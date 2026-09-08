//! Read-only media discovery; only the caller commits a complete index result.
use super::*;
use crate::index_scan::ScanControl;
use std::collections::{BTreeMap, HashMap};

#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) struct Fingerprint {
    size: u64,
    modified_ns: String,
    modified: u64,
}

impl Fingerprint {
    fn read(path: &Path) -> anyhow::Result<Self> {
        let metadata = fs::metadata(path)?;
        anyhow::ensure!(
            metadata.is_file(),
            "INDEX_SCAN_INCOMPLETE|歌曲路径已不再是文件"
        );
        let modified = metadata
            .modified()?
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default();
        Ok(Self {
            size: metadata.len(),
            modified_ns: modified.as_nanos().to_string(),
            modified: modified.as_secs(),
        })
    }

    fn matches(&self, value: &serde_json::Value) -> bool {
        value["file_size"].as_u64() == Some(self.size)
            && value["modified_ns"].as_str() == Some(self.modified_ns.as_str())
    }

    fn apply(&self, value: &mut serde_json::Value) {
        value["file_size"] = self.size.into();
        value["modified"] = self.modified.into();
        value["modified_ns"] = self.modified_ns.clone().into();
    }
}

fn path_key(path: &Path) -> String {
    let value = path.to_string_lossy();
    if cfg!(windows) {
        value.replace('/', "\\").to_lowercase()
    } else {
        value.into_owned()
    }
}

pub(super) fn roots(index: &serde_json::Value) -> anyhow::Result<Vec<String>> {
    let values = if let Some(values) = index.get("roots") {
        values
            .as_array()
            .ok_or_else(|| anyhow::anyhow!("INDEX_SCHEMA_INVALID|音乐根目录必须是列表"))?
            .iter()
            .map(|value| value.as_str().map(str::to_owned))
            .collect::<Option<Vec<_>>>()
    } else {
        index["folders"].as_array().and_then(|values| {
            values
                .iter()
                .map(|value| value["path"].as_str().map(str::to_owned))
                .collect::<Option<Vec<_>>>()
        })
    }
    .ok_or_else(|| anyhow::anyhow!("INDEX_SCHEMA_INVALID|音乐根目录记录缺少路径"))?;
    let mut unique = Vec::<String>::new();
    for value in values {
        anyhow::ensure!(
            !value.is_empty() && Path::new(&value).is_absolute(),
            "INDEX_SCHEMA_INVALID|音乐根目录路径无效"
        );
        let key = path_key(Path::new(&value));
        if !unique.iter().any(|old| path_key(Path::new(old)) == key) {
            unique.push(value);
        }
    }
    // Overlapping roots need one traversal, and a deleted nested folder must
    // not be mistaken for a missing separately-mounted root.
    let candidates = unique.clone();
    unique.retain(|value| {
        !candidates.iter().any(|other| {
            let child = PathBuf::from(path_key(Path::new(value)));
            let parent = PathBuf::from(path_key(Path::new(other)));
            child != parent && child.starts_with(parent)
        })
    });
    Ok(unique)
}

struct DiscoveredFile {
    path: PathBuf,
    fingerprint: Fingerprint,
}

fn collect(
    directory: &Path,
    visited: &mut HashSet<PathBuf>,
    directories: &mut BTreeMap<String, u64>,
    files: &mut Vec<DiscoveredFile>,
    control: &ScanControl,
    progress: &mut impl FnMut(f64),
) -> anyhow::Result<()> {
    control.check()?;
    // Canonical identity prevents overlapping roots/junction loops. Persist
    // the user's original path spelling, not a device-path alias.
    let canonical = directory.canonicalize()?;
    if !visited.insert(canonical) {
        return Ok(());
    }
    let mut entries = Vec::new();
    for entry in fs::read_dir(directory)? {
        control.check()?;
        entries.push(entry?);
    }
    if visited.len() == 1 || visited.len() % 64 == 0 {
        progress(0.0);
        control.check()?;
    }
    entries.sort_by_key(|entry| entry.file_name());
    let modified = fs::metadata(directory)?
        .modified()?
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    directories.insert(directory.to_string_lossy().into_owned(), modified);
    for entry in entries {
        control.check()?;
        let kind = entry.file_type()?;
        if kind.is_dir() {
            collect(
                &entry.path(),
                visited,
                directories,
                files,
                control,
                progress,
            )?;
        } else if kind.is_file() && is_supported_audio_path(&entry.path()) {
            files.push(DiscoveredFile {
                fingerprint: Fingerprint::read(&entry.path())?,
                path: entry.path(),
            });
        }
    }
    Ok(())
}

/// Exact unchanged JSON is reused. All directory enumeration/stat errors abort
/// before the caller writes anything; only successfully enumerated absence
/// removes songs. Roots themselves remain registered even when empty.
#[cfg(test)]
pub(super) fn refresh(
    previous: Option<&serde_json::Value>,
    selected_roots: &[String],
    force: bool,
    reader: &(impl Fn(&Path) -> Option<serde_json::Value> + Sync),
    progress: impl FnMut(f64),
) -> anyhow::Result<serde_json::Value> {
    refresh_cancellable(
        previous,
        selected_roots,
        force,
        reader,
        &ScanControl::default(),
        progress,
    )
}

pub(super) fn refresh_cancellable(
    previous: Option<&serde_json::Value>,
    selected_roots: &[String],
    force: bool,
    reader: &(impl Fn(&Path) -> Option<serde_json::Value> + Sync),
    control: &ScanControl,
    mut progress: impl FnMut(f64),
) -> anyhow::Result<serde_json::Value> {
    control.check()?;
    let roots = roots(&serde_json::json!({"roots": selected_roots}))?;
    let mut old = HashMap::<String, &serde_json::Value>::new();
    let mut old_order = HashMap::<String, usize>::new();
    let mut old_folders = HashMap::<String, (&serde_json::Value, usize)>::new();
    if let Some(previous) = previous {
        let folders = previous["folders"]
            .as_array()
            .ok_or_else(|| anyhow::anyhow!("INDEX_SCHEMA_INVALID|曲库文件夹记录无效"))?;
        for (folder_index, folder) in folders.iter().enumerate() {
            control.check()?;
            let path = folder["path"]
                .as_str()
                .ok_or_else(|| anyhow::anyhow!("INDEX_SCHEMA_INVALID|曲库文件夹缺少路径"))?;
            old_folders.insert(path_key(Path::new(path)), (folder, folder_index));
            let audios = folder["audios"]
                .as_array()
                .ok_or_else(|| anyhow::anyhow!("INDEX_SCHEMA_INVALID|曲库歌曲记录无效"))?;
            for (audio_index, audio) in audios.iter().enumerate() {
                control.check()?;
                let path = audio["path"]
                    .as_str()
                    .ok_or_else(|| anyhow::anyhow!("INDEX_SCHEMA_INVALID|曲库歌曲缺少路径"))?;
                old.entry(path_key(Path::new(path))).or_insert(audio);
                old_order
                    .entry(path_key(Path::new(path)))
                    .or_insert(audio_index);
            }
        }
    }
    let mut files = Vec::new();
    let mut directories = BTreeMap::new();
    let mut visited = HashSet::new();
    for root in &roots {
        control.check()?;
        collect(
            Path::new(root),
            &mut visited,
            &mut directories,
            &mut files,
            control,
            &mut progress,
        )
        .map_err(|error| {
            if error.to_string().contains("INDEX_SCAN_CANCELLED|") {
                return error;
            }
            anyhow::anyhow!(
                "INDEX_SCAN_INCOMPLETE|未能完整读取音乐文件夹；旧索引未覆盖：{}",
                error
            )
        })?;
    }
    progress(0.15);
    control.check()?;
    let results: Vec<anyhow::Result<serde_json::Value>> = files.par_iter().map(|file| {
        control.check()?;
        let previous = old.get(&path_key(&file.path)).copied();
        if !force && previous.is_some_and(|value| file.fingerprint.matches(value)
            && value["metadata_pending"] != true
            && !needs_classification_backfill(value)
            && !needs_duration_backfill(value)) {
            let mut value = previous.unwrap().clone();
            value["path"] = file.path.to_string_lossy().into_owned().into();
            return Ok(value);
        }
        // Readability failures are not missing/bad metadata. Fail the entire
        // refresh; a metadata parser miss itself preserves the prior record.
        fs::File::open(&file.path).map_err(|error| anyhow::anyhow!("INDEX_SCAN_INCOMPLETE|歌曲暂时不可读取；旧索引未覆盖：{}", error))?;
        control.check()?;
        let read = reader(&file.path);
        control.check()?;
        anyhow::ensure!(Fingerprint::read(&file.path)? == file.fingerprint,
            "INDEX_SCAN_INCOMPLETE|扫描期间歌曲发生变化，请重试；旧索引未覆盖");
        let reliable = read.as_ref().is_some_and(|value| value["by"].is_string());
        if !reliable {
            if let Some(previous) = previous {
                let mut retained = previous.clone();
                retained["path"] = file.path.to_string_lossy().into_owned().into();
                retained["metadata_pending"] = true.into();
                return Ok(retained);
            }
        }
        let read = read.unwrap_or_else(|| serde_json::json!({
            "path": file.path.to_string_lossy(), "title": file.path.file_name().unwrap_or_default().to_string_lossy(),
            "artist": "UNKNOWN", "album": "UNKNOWN", "created": 0, "classification_version": 0,
        }));
        let mut value = previous.cloned().unwrap_or_else(|| serde_json::json!({}));
        value.as_object_mut().unwrap().extend(read.as_object().ok_or_else(||
            anyhow::anyhow!("INDEX_SCHEMA_INVALID|歌曲元数据记录无效"))?.clone());
        file.fingerprint.apply(&mut value);
        value["metadata_pending"] = (!reliable).into();
        Ok(value)
    }).collect();
    let mut grouped = BTreeMap::<String, Vec<serde_json::Value>>::new();
    for (index, (file, result)) in files.iter().zip(results).enumerate() {
        control.check()?;
        let audio = result?;
        let folder = file.path.parent().unwrap().to_string_lossy().into_owned();
        grouped.entry(folder).or_default().push(audio);
        progress(0.15 + 0.8 * (index + 1) as f64 / files.len().max(1) as f64);
    }
    let mut folders: Vec<_> = directories
        .into_iter()
        .filter_map(|(path, modified)| {
            let mut audios = grouped.remove(&path).unwrap_or_default();
            if audios.is_empty() {
                return None;
            }
            audios.sort_by_key(|audio| {
                old_order
                    .get(&path_key(Path::new(audio["path"].as_str().unwrap())))
                    .copied()
                    .unwrap_or(usize::MAX)
            });
            let latest = audios
                .iter()
                .filter_map(|audio| audio["created"].as_u64())
                .max()
                .unwrap_or(0);
            let mut folder = old_folders
                .get(&path_key(Path::new(&path)))
                .map(|(folder, _)| (*folder).clone())
                .unwrap_or_else(|| serde_json::json!({}));
            folder["path"] = path.into();
            folder["modified"] = modified.into();
            folder["latest"] = latest.into();
            folder["audios"] = serde_json::json!(audios);
            Some(folder)
        })
        .collect();
    folders.sort_by_key(|folder| {
        old_folders
            .get(&path_key(Path::new(folder["path"].as_str().unwrap())))
            .map(|(_, order)| *order)
            .unwrap_or(usize::MAX)
    });
    let mut output = previous.cloned().unwrap_or_else(|| serde_json::json!({}));
    output["version"] = INDEX_VERSION.into();
    output["roots"] = serde_json::json!(roots);
    output["folders"] = serde_json::json!(folders);
    progress(1.0);
    control.check()?;
    Ok(output)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::AtomicUsize;
    use std::time::SystemTime;

    #[test]
    fn cancel_during_directory_enumeration_never_reads_tags_or_changes_index() {
        let f = Fixture::new();
        for i in 0..128 {
            f.file(&format!("dir-{i:03}/song.mp3"));
        }
        let old_index = f.0.join("index.json");
        fs::write(&old_index, b"previous complete index").unwrap();
        let id = crate::index_scan::create().unwrap();
        let task = crate::index_scan::ScanLease::begin(Some(id.clone())).unwrap();
        let mut batches = 0;
        let result = refresh_cancellable(
            None,
            &f.roots(),
            true,
            &|_| panic!("cancelled enumeration must not dispatch tag reads"),
            &task.control,
            |progress| {
                if progress == 0.0 {
                    batches += 1;
                    if batches == 2 {
                        crate::index_scan::cancel(&id);
                    }
                }
            },
        );
        assert_eq!(batches, 2);
        assert!(result
            .unwrap_err()
            .to_string()
            .starts_with("INDEX_SCAN_CANCELLED|"));
        assert!(task.control.begin_commit().is_err());
        assert_eq!(fs::read(old_index).unwrap(), b"previous complete index");
    }

    #[test]
    fn cancel_during_tag_read_or_final_progress_prevents_commit() {
        for final_progress in [false, true] {
            let f = Fixture::new();
            f.file("song.mp3");
            let id = crate::index_scan::create().unwrap();
            let task = crate::index_scan::ScanLease::begin(Some(id.clone())).unwrap();
            let reads = AtomicUsize::new(0);
            let result = refresh_cancellable(
                None,
                &f.roots(),
                true,
                &|path| {
                    reads.fetch_add(1, Ordering::Relaxed);
                    if !final_progress {
                        crate::index_scan::cancel(&id);
                    }
                    Some(tags(path))
                },
                &task.control,
                |progress| {
                    if final_progress && progress == 1.0 {
                        crate::index_scan::cancel(&id);
                    }
                },
            );
            assert_eq!(reads.load(Ordering::Relaxed), 1);
            assert!(result
                .unwrap_err()
                .to_string()
                .starts_with("INDEX_SCAN_CANCELLED|"));
            assert!(task.control.begin_commit().is_err());
            drop(task);
            assert_eq!(cancelled_task_state(&id), "finished");
            assert_eq!(
                f.scan(None, true, &AtomicUsize::new(0))["folders"]
                    .as_array()
                    .unwrap()
                    .len(),
                1
            );
        }
    }

    fn cancelled_task_state(id: &str) -> String {
        crate::index_scan::cancel(id)
    }

    struct Fixture(PathBuf);
    impl Fixture {
        fn new() -> Self {
            static NEXT: AtomicUsize = AtomicUsize::new(0);
            let root = std::env::temp_dir().join(format!(
                "incremental-index-{}-{}-{}",
                std::process::id(),
                SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .unwrap()
                    .as_nanos(),
                NEXT.fetch_add(1, Ordering::Relaxed)
            ));
            fs::create_dir(&root).unwrap();
            Self(root)
        }
        fn roots(&self) -> Vec<String> {
            vec![self.0.to_string_lossy().into_owned()]
        }
        fn file(&self, name: &str) -> PathBuf {
            let path = self.0.join(name);
            fs::create_dir_all(path.parent().unwrap()).unwrap();
            fs::write(&path, b"synthetic; not actual audio").unwrap();
            path
        }
        fn scan(
            &self,
            old: Option<&serde_json::Value>,
            force: bool,
            calls: &AtomicUsize,
        ) -> serde_json::Value {
            refresh(
                old,
                &self.roots(),
                force,
                &|path| {
                    calls.fetch_add(1, Ordering::Relaxed);
                    Some(tags(path))
                },
                |_| {},
            )
            .unwrap()
        }
    }
    impl Drop for Fixture {
        fn drop(&mut self) {
            fs::remove_dir_all(&self.0).unwrap();
        }
    }
    fn tags(path: &Path) -> serde_json::Value {
        serde_json::json!({"path": path.to_string_lossy(), "title": "Synthetic title",
            "artist": "Fixture", "album": "Synthetic", "by": "Test", "created": 0,
            "classification_version": CLASSIFICATION_VERSION,
            "duration_version": DURATION_VERSION})
    }
    fn songs(index: &serde_json::Value) -> Vec<&serde_json::Value> {
        index["folders"]
            .as_array()
            .unwrap()
            .iter()
            .flat_map(|folder| folder["audios"].as_array().unwrap())
            .collect()
    }
    #[test]
    fn unchanged_refresh_reuses_exact_json_without_metadata_reads() {
        let f = Fixture::new();
        f.file("a.mp3");
        let calls = AtomicUsize::new(0);
        let mut first = f.scan(None, true, &calls);
        first["folders"][0]["audios"][0]["extension_field"] = "keep".into();
        first["extension_root"] = "keep".into();
        calls.store(0, Ordering::Relaxed);
        let second = f.scan(Some(&first), false, &calls);
        assert_eq!(second, first);
        assert_eq!(calls.load(Ordering::Relaxed), 0);
    }
    #[test]
    fn old_duration_reader_marker_is_backfilled_once_then_reused() {
        let f = Fixture::new();
        f.file("a.mp3");
        let calls = AtomicUsize::new(0);
        let mut first = f.scan(None, true, &calls);
        first["folders"][0]["audios"][0]
            .as_object_mut()
            .unwrap()
            .remove("duration_version");
        calls.store(0, Ordering::Relaxed);

        let migrated = f.scan(Some(&first), false, &calls);
        assert_eq!(calls.load(Ordering::Relaxed), 1);
        assert_eq!(songs(&migrated)[0]["duration_version"], DURATION_VERSION);

        f.scan(Some(&migrated), false, &calls);
        assert_eq!(calls.load(Ordering::Relaxed), 1);
    }
    #[test]
    fn full_refresh_force_reads_every_song_and_preserves_extension_fields() {
        let f = Fixture::new();
        f.file("a.mp3");
        f.file("b.flac");
        let calls = AtomicUsize::new(0);
        let mut first = f.scan(None, true, &calls);
        first["folders"][0]["audios"][0]["custom"] = 42.into();
        calls.store(0, Ordering::Relaxed);
        let second = f.scan(Some(&first), true, &calls);
        assert_eq!(calls.load(Ordering::Relaxed), 2);
        assert_eq!(songs(&second)[0]["custom"], 42);
    }
    #[test]
    fn changed_size_with_preserved_timestamp_is_reread() {
        let f = Fixture::new();
        let path = f.file("a.mp3");
        let calls = AtomicUsize::new(0);
        let before = fs::metadata(&path).unwrap().modified().unwrap();
        let first = f.scan(None, true, &calls);
        fs::write(&path, b"different byte count").unwrap();
        fs::File::options()
            .write(true)
            .open(&path)
            .unwrap()
            .set_modified(before)
            .unwrap();
        calls.store(0, Ordering::Relaxed);
        f.scan(Some(&first), false, &calls);
        assert_eq!(calls.load(Ordering::Relaxed), 1);
    }
    #[test]
    fn same_second_nanoseconds_and_backwards_times_are_changes() {
        let f = Fixture::new();
        let path = f.file("a.mp3");
        let calls = AtomicUsize::new(0);
        let file = fs::File::options().write(true).open(&path).unwrap();
        file.set_modified(UNIX_EPOCH + Duration::new(1_700_000_000, 100_000))
            .unwrap();
        let mut first = f.scan(None, true, &calls);
        for timestamp in [
            Duration::new(1_700_000_000, 200_000),
            Duration::new(1_600_000_000, 0),
        ] {
            file.set_modified(UNIX_EPOCH + timestamp).unwrap();
            calls.store(0, Ordering::Relaxed);
            first = f.scan(Some(&first), false, &calls);
            assert_eq!(calls.load(Ordering::Relaxed), 1);
        }
    }
    #[test]
    fn added_nested_song_with_old_creation_time_is_discovered_and_deletion_removed() {
        let f = Fixture::new();
        let old_path = f.file("old.mp3");
        let calls = AtomicUsize::new(0);
        let first = f.scan(None, true, &calls);
        fs::remove_file(old_path).unwrap();
        let new_path = f.file("new/sub/added.mp3");
        calls.store(0, Ordering::Relaxed);
        let second = f.scan(Some(&first), false, &calls);
        assert_eq!(songs(&second).len(), 1);
        assert_eq!(
            path_key(Path::new(songs(&second)[0]["path"].as_str().unwrap())),
            path_key(&new_path)
        );
        assert_eq!(calls.load(Ordering::Relaxed), 1);
    }
    #[test]
    fn empty_roots_survive_and_later_additions_are_found() {
        let f = Fixture::new();
        let calls = AtomicUsize::new(0);
        let first = f.scan(None, true, &calls);
        assert!(songs(&first).is_empty());
        assert_eq!(roots(&first).unwrap(), f.roots());
        f.file("later/song.mp3");
        let second = f.scan(Some(&first), false, &calls);
        assert_eq!(songs(&second).len(), 1);
    }
    #[test]
    fn missing_root_aborts_incremental_and_full_without_mutating_previous() {
        let f = Fixture::new();
        f.file("a.mp3");
        let calls = AtomicUsize::new(0);
        let first = f.scan(None, true, &calls);
        let snapshot = first.clone();
        let mut selected = f.roots();
        selected.push(f.0.join("unavailable").to_string_lossy().into_owned());
        // A separately registered (non-overlapping) unavailable root cannot be pruned.
        selected[1] = format!("{}-offline", f.0.to_string_lossy());
        for force in [false, true] {
            let result = refresh(
                Some(&first),
                &selected,
                force,
                &|path| Some(tags(path)),
                |_| {},
            );
            assert!(result
                .unwrap_err()
                .to_string()
                .starts_with("INDEX_SCAN_INCOMPLETE"));
            assert_eq!(first, snapshot);
        }
    }
    #[test]
    fn not_a_directory_aborts_instead_of_emptying_library() {
        let f = Fixture::new();
        let path = f.file("a.mp3");
        assert!(refresh(
            None,
            &[path.to_string_lossy().into_owned()],
            true,
            &|path| Some(tags(path)),
            |_| {}
        )
        .is_err());
    }
    #[test]
    fn metadata_failure_preserves_previous_fields_and_retries_next_scan() {
        let f = Fixture::new();
        f.file("a.mp3");
        let calls = AtomicUsize::new(0);
        let first = f.scan(None, true, &calls);
        let pending = refresh(Some(&first), &f.roots(), true, &|_| None, |_| {}).unwrap();
        assert_eq!(songs(&pending)[0]["title"], songs(&first)[0]["title"]);
        assert_eq!(songs(&pending)[0]["metadata_pending"], true);
        calls.store(0, Ordering::Relaxed);
        let recovered = f.scan(Some(&pending), false, &calls);
        assert_eq!(calls.load(Ordering::Relaxed), 1);
        assert_eq!(songs(&recovered)[0]["metadata_pending"], false);
    }
    #[test]
    fn new_unrecognized_audio_is_retained_as_pending_not_silently_dropped() {
        let f = Fixture::new();
        f.file("a.mp3");
        let index = refresh(None, &f.roots(), false, &|_| None, |_| {}).unwrap();
        assert_eq!(songs(&index).len(), 1);
        assert_eq!(songs(&index)[0]["metadata_pending"], true);
    }
    #[test]
    fn file_changes_during_tag_read_abort_commit() {
        let f = Fixture::new();
        let path = f.file("a.mp3");
        let result = refresh(
            None,
            &f.roots(),
            true,
            &|path| {
                fs::write(path, b"changed while reading").unwrap();
                Some(tags(path))
            },
            |_| {},
        );
        assert!(result
            .unwrap_err()
            .to_string()
            .starts_with("INDEX_SCAN_INCOMPLETE"));
        assert!(path.exists());
    }
    #[test]
    fn old_index_without_fingerprint_gets_one_read_then_reuses() {
        let f = Fixture::new();
        f.file("a.mp3");
        let calls = AtomicUsize::new(0);
        let mut first = f.scan(None, true, &calls);
        first.as_object_mut().unwrap().remove("roots");
        first["folders"][0]["audios"][0]
            .as_object_mut()
            .unwrap()
            .remove("modified_ns");
        assert_eq!(roots(&first).unwrap(), f.roots());
        calls.store(0, Ordering::Relaxed);
        let second = f.scan(Some(&first), false, &calls);
        assert_eq!(calls.load(Ordering::Relaxed), 1);
        f.scan(Some(&second), false, &calls);
        assert_eq!(calls.load(Ordering::Relaxed), 1);
    }
    #[test]
    fn overlapping_roots_are_deduplicated_and_empty_selection_is_explicit_clear() {
        let f = Fixture::new();
        let path = f.file("nested/a.mp3");
        let selected = vec![
            path.parent().unwrap().to_string_lossy().into_owned(),
            f.roots()[0].clone(),
        ];
        let index = refresh(None, &selected, true, &|path| Some(tags(path)), |_| {}).unwrap();
        assert_eq!(songs(&index).len(), 1);
        assert_eq!(roots(&index).unwrap(), f.roots());
        let cleared = refresh(Some(&index), &[], true, &|path| Some(tags(path)), |_| {}).unwrap();
        assert!(songs(&cleared).is_empty());
        assert!(roots(&cleared).unwrap().is_empty());
    }
    #[test]
    fn relative_or_malformed_roots_are_rejected() {
        for index in [
            serde_json::json!({"roots":["relative"]}),
            serde_json::json!({"roots":[null]}),
            serde_json::json!({"roots":"bad"}),
            serde_json::json!({"folders":[{}]}),
        ] {
            assert!(roots(&index).is_err());
        }
    }

    #[cfg(windows)]
    #[test]
    fn case_only_filename_change_refreshes_spelling_without_rereading_tags() {
        let f = Fixture::new();
        let path = f.file("actual.mp3");
        let calls = AtomicUsize::new(0);
        let mut first = f.scan(None, true, &calls);
        first["folders"][0]["audios"][0]["path"] = path
            .with_file_name("ACTUAL.mp3")
            .to_string_lossy()
            .into_owned()
            .into();
        calls.store(0, Ordering::Relaxed);
        let second = f.scan(Some(&first), false, &calls);
        assert_eq!(songs(&second)[0]["path"], path.to_string_lossy().as_ref());
        assert_eq!(calls.load(Ordering::Relaxed), 0);
    }

    #[test]
    fn unchanged_incremental_preserves_old_folder_and_song_order() {
        let f = Fixture::new();
        f.file("a.mp3");
        f.file("z.mp3");
        f.file("b/song.mp3");
        let calls = AtomicUsize::new(0);
        let mut first = f.scan(None, true, &calls);
        first["folders"][0]["audios"]
            .as_array_mut()
            .unwrap()
            .reverse();
        first["folders"].as_array_mut().unwrap().reverse();
        first["folders"][0]["custom"] = "preserve".into();
        calls.store(0, Ordering::Relaxed);
        assert_eq!(f.scan(Some(&first), false, &calls), first);
        assert_eq!(calls.load(Ordering::Relaxed), 0);
    }
}
