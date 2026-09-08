//! Per-request cooperative cancellation. The commit CAS is the cancellation
//! boundary; a cancelled discovery can never begin an index replacement.
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicU8, Ordering};
use std::sync::{Arc, LazyLock, Mutex};

const SCANNING: u8 = 0;
const CANCELLING: u8 = 1;
const COMMITTING: u8 = 2;
const FINISHED: u8 = 3;
static NEXT_ID: AtomicU64 = AtomicU64::new(1);
static REQUESTS: LazyLock<Mutex<HashMap<String, Arc<ScanControl>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

#[derive(Default)]
pub(crate) struct ScanControl {
    phase: AtomicU8,
    claimed: AtomicBool,
}

impl ScanControl {
    pub(crate) fn check(&self) -> anyhow::Result<()> {
        anyhow::ensure!(
            self.phase.load(Ordering::Acquire) != CANCELLING,
            "INDEX_SCAN_CANCELLED|扫描已取消，旧索引未覆盖"
        );
        Ok(())
    }

    pub(crate) fn begin_commit(&self) -> anyhow::Result<()> {
        match self
            .phase
            .compare_exchange(SCANNING, COMMITTING, Ordering::AcqRel, Ordering::Acquire)
        {
            Ok(_) => Ok(()),
            Err(CANCELLING) => self.check(),
            Err(_) => anyhow::bail!("INDEX_SCAN_STATE|扫描已进入提交或结束阶段"),
        }
    }

    fn cancel(&self) -> &'static str {
        match self
            .phase
            .compare_exchange(SCANNING, CANCELLING, Ordering::AcqRel, Ordering::Acquire)
        {
            Ok(_) | Err(CANCELLING) => "cancelling",
            Err(COMMITTING) => "committing",
            Err(_) => "finished",
        }
    }
}

pub(crate) fn create() -> anyhow::Result<String> {
    let mut requests = REQUESTS.lock().unwrap_or_else(|e| e.into_inner());
    anyhow::ensure!(requests.len() < 16, "INDEX_SCAN_BUSY|扫描任务数量已达上限");
    let id = format!(
        "{}-{}",
        std::process::id(),
        NEXT_ID.fetch_add(1, Ordering::Relaxed)
    );
    requests.insert(id.clone(), Arc::new(ScanControl::default()));
    Ok(id)
}

pub(crate) fn cancel(id: &str) -> String {
    REQUESTS
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .get(id)
        .map_or("finished", |request| request.cancel())
        .to_owned()
}

/// Only a prepared, unclaimed request may be abandoned by its Dart owner.
/// A running request remains registered until its RAII lease has exited.
pub(crate) fn release(id: &str) {
    let mut requests = REQUESTS.lock().unwrap_or_else(|e| e.into_inner());
    if requests
        .get(id)
        .is_some_and(|request| !request.claimed.load(Ordering::Acquire))
    {
        requests.remove(id);
    }
}

pub(crate) struct ScanLease {
    id: Option<String>,
    pub(crate) control: Arc<ScanControl>,
}

impl ScanLease {
    pub(crate) fn begin(id: Option<String>) -> anyhow::Result<Self> {
        let control = if let Some(id) = id.as_ref() {
            let requests = REQUESTS.lock().unwrap_or_else(|e| e.into_inner());
            let control = requests
                .get(id)
                .ok_or_else(|| anyhow::anyhow!("INDEX_SCAN_STATE|扫描任务不存在"))?
                .clone();
            anyhow::ensure!(
                !control.claimed.swap(true, Ordering::AcqRel),
                "INDEX_SCAN_STATE|扫描任务不能重复启动"
            );
            control
        } else {
            Arc::new(ScanControl::default())
        };
        Ok(Self { id, control })
    }
}

impl Drop for ScanLease {
    fn drop(&mut self) {
        self.control.phase.store(FINISHED, Ordering::Release);
        if let Some(id) = &self.id {
            let mut requests = REQUESTS.lock().unwrap_or_else(|e| e.into_inner());
            if requests
                .get(id)
                .is_some_and(|request| Arc::ptr_eq(request, &self.control))
            {
                requests.remove(id);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cancellation_is_owned_and_survives_until_safe_exit() {
        let first_id = create().unwrap();
        let second_id = create().unwrap();
        let first = ScanLease::begin(Some(first_id.clone())).unwrap();
        let second = ScanLease::begin(Some(second_id.clone())).unwrap();
        assert_eq!(cancel(&first_id), "cancelling");
        assert_eq!(cancel(&first_id), "cancelling");
        release(&first_id);
        assert!(first.control.check().is_err());
        assert!(first.control.begin_commit().is_err());
        assert!(second.control.check().is_ok());
        drop(first);
        assert_eq!(cancel(&first_id), "finished");
        second.control.begin_commit().unwrap();
        assert_eq!(cancel(&second_id), "committing");
        assert!(second.control.check().is_ok());
    }

    #[test]
    fn cancellation_before_start_and_duplicate_start_are_safe() {
        let id = create().unwrap();
        assert_eq!(cancel(&id), "cancelling");
        let task = ScanLease::begin(Some(id.clone())).unwrap();
        assert!(task.control.check().is_err());
        assert!(ScanLease::begin(Some(id.clone())).is_err());
        drop(task);
        assert!(ScanLease::begin(Some(id)).is_err());
        let abandoned = create().unwrap();
        release(&abandoned);
        assert_eq!(cancel(&abandoned), "finished");
    }

    #[test]
    fn cancel_and_commit_race_has_one_winner() {
        for _ in 0..64 {
            let control = Arc::new(ScanControl::default());
            let worker = control.clone();
            let barrier = Arc::new(std::sync::Barrier::new(2));
            let worker_barrier = barrier.clone();
            let handle = std::thread::spawn(move || {
                worker_barrier.wait();
                worker.cancel()
            });
            barrier.wait();
            let committed = control.begin_commit().is_ok();
            let cancel_state = handle.join().unwrap();
            assert_eq!(committed, cancel_state == "committing");
            assert_eq!(control.check().is_ok(), committed);
        }
    }
}
