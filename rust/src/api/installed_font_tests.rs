use super::_read_fonts_in_folder;
use std::{
    fs,
    path::PathBuf,
    sync::atomic::{AtomicU64, Ordering},
};

static NEXT: AtomicU64 = AtomicU64::new(0);

struct Fixture(PathBuf);
impl Fixture {
    fn new() -> Self {
        let path = std::env::temp_dir().join(format!(
            "dan-font-collection-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&path).unwrap();
        Self(path)
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn font(name: &str) -> Vec<u8> {
    fs::read(
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../third_party/desktop_lyric/assets/fonts")
            .join(name),
    )
    .unwrap()
}

fn collection(faces: &[Vec<u8>]) -> Vec<u8> {
    let header = (12 + faces.len() * 4 + 3) & !3;
    let mut result = vec![
        0;
        header
            + faces
                .iter()
                .map(|face| (face.len() + 3) & !3)
                .sum::<usize>()
    ];
    result[..4].copy_from_slice(b"ttcf");
    result[4..8].copy_from_slice(&0x00010000u32.to_be_bytes());
    result[8..12].copy_from_slice(&(faces.len() as u32).to_be_bytes());
    let mut offset = header;
    for (index, face) in faces.iter().enumerate() {
        result[offset..offset + face.len()].copy_from_slice(face);
        result[12 + index * 4..16 + index * 4].copy_from_slice(&(offset as u32).to_be_bytes());
        let count = u16::from_be_bytes(face[4..6].try_into().unwrap());
        for table in 0..count as usize {
            let record = 12 + table * 16 + 8;
            let start = u32::from_be_bytes(face[record..record + 4].try_into().unwrap());
            result[offset + record..offset + record + 4]
                .copy_from_slice(&(start + offset as u32).to_be_bytes());
        }
        offset += (face.len() + 3) & !3;
    }
    result
}

#[test]
fn enumerates_collection_siblings_and_preserves_standalone_fonts() {
    let fixture = Fixture::new();
    let first = font("GoogleSans-VF.ttf");
    let second = font("Pretendard-Regular.otf");
    fs::write(
        fixture.0.join("siblings.ttc"),
        collection(&[first, second.clone()]),
    )
    .unwrap();
    fs::write(fixture.0.join("single.otf"), second).unwrap();
    let mut fonts = vec![];
    _read_fonts_in_folder(&fixture.0, &mut fonts).unwrap();
    let mut names: Vec<_> = fonts.iter().map(|font| font.full_name.as_str()).collect();
    names.sort_unstable();
    assert_eq!(
        names,
        [
            "Google Sans Regular",
            "Pretendard Regular",
            "Pretendard Regular"
        ]
    );
    assert_eq!(
        fonts
            .iter()
            .filter(|font| font.path.ends_with("siblings.ttc"))
            .count(),
        2
    );
}

#[test]
fn duplicate_collection_names_do_not_duplicate_a_selection_identity() {
    let fixture = Fixture::new();
    let face = font("Pretendard-Regular.otf");
    fs::write(
        fixture.0.join("duplicate.ttc"),
        collection(&[face.clone(), face]),
    )
    .unwrap();
    let mut fonts = vec![];
    _read_fonts_in_folder(&fixture.0, &mut fonts).unwrap();
    assert_eq!(fonts.len(), 1);
    assert_eq!(fonts[0].full_name, "Pretendard Regular");
}
