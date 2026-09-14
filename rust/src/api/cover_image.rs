use std::io::{Cursor, Read};
use std::sync::Mutex;

use anyhow::{bail, ensure, Context};
use image::codecs::jpeg::JpegEncoder;
use image::codecs::png::{CompressionType, FilterType, PngEncoder};
use image::{DynamicImage, ImageDecoder, ImageEncoder, ImageFormat, ImageReader};

const MAX_INPUT_BYTES: usize = 20 * 1024 * 1024;
const MAX_INPUT_PIXELS: u64 = 40_000_000;
const MAX_OUTPUT_BYTES: usize = 2 * 1024 * 1024;
const MAX_OUTPUT_EDGE: u32 = 1600;
// User imports are infrequent. Serial decoding bounds peak allocations even
// when multiple dialogs/metadata jobs request a cover concurrently.
static COVER_WORKER: Mutex<()> = Mutex::new(());

#[derive(Debug)]
pub struct ImportedCoverImage {
    pub bytes: Vec<u8>,
    pub extension: String,
    pub width: u32,
    pub height: u32,
}

/// Validate and prepare an import copy; never write to the selected source.
/// FRB runs this ordinary function on its native worker pool, not the UI thread.
pub fn normalize_cover_image(data: Vec<u8>) -> anyhow::Result<ImportedCoverImage> {
    let _guard = COVER_WORKER
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    normalize(&data)
}

pub(crate) fn read_cover_file(source: &str) -> anyhow::Result<ImportedCoverImage> {
    let file = std::fs::File::open(source).context("无法读取封面图片。")?;
    ensure!(
        file.metadata()?.len() <= MAX_INPUT_BYTES as u64,
        "封面图片不能超过 20 MiB，请先缩小原图后重试。"
    );
    let mut bytes = Vec::new();
    file.take(MAX_INPUT_BYTES as u64 + 1)
        .read_to_end(&mut bytes)?;
    normalize_cover_image(bytes)
}

fn normalize(data: &[u8]) -> anyhow::Result<ImportedCoverImage> {
    ensure!(!data.is_empty(), "封面图片为空或无法读取。");
    ensure!(
        data.len() <= MAX_INPUT_BYTES,
        "封面图片不能超过 20 MiB，请先缩小原图后重试。"
    );
    let format = image::guess_format(data).context("封面图片已损坏或格式不受支持。")?;
    let extension = match format {
        ImageFormat::Jpeg => "jpg",
        ImageFormat::Png => "png",
        ImageFormat::WebP => "webp",
        ImageFormat::Bmp => "bmp",
        _ => bail!("封面仅支持静态 PNG、JPEG、WebP 和 BMP 图片。"),
    };
    ensure!(
        !animated(data, format)?,
        "封面暂不支持动图，请选择静态图片。"
    );
    let mut limits = image::Limits::default();
    limits.max_image_width = Some(32768);
    limits.max_image_height = Some(32768);
    limits.max_alloc = Some(192 * 1024 * 1024);
    let mut header = ImageReader::with_format(Cursor::new(data), format);
    header.limits(limits.clone());
    let dimensions = header
        .into_dimensions()
        .context("封面图片已损坏或无法解码。")?;
    ensure!(
        dimensions.0 > 0
            && dimensions.1 > 0
            && dimensions.0 as u64 * dimensions.1 as u64 <= MAX_INPUT_PIXELS
            && dimensions.0 <= 32768
            && dimensions.1 <= 32768,
        "封面图片最多支持 4000 万像素，请先缩小原图后重试。"
    );
    let mut reader = ImageReader::with_format(Cursor::new(data), format);
    reader.limits(limits);
    let mut decoder = reader
        .into_decoder()
        .context("封面图片已损坏或无法解码。")?;
    let orientation = decoder.orientation().ok();
    let mut decoded = DynamicImage::from_decoder(decoder).context("封面图片已损坏或无法解码。")?;
    // Decode even a small image before preserving its original bytes, so a
    // plausible header with truncated/corrupt pixels is never accepted.
    if dimensions.0.max(dimensions.1) <= MAX_OUTPUT_EDGE
        && data.len() <= MAX_OUTPUT_BYTES
        && format != ImageFormat::Bmp
    {
        return Ok(ImportedCoverImage {
            bytes: data.to_vec(),
            extension: extension.into(),
            width: dimensions.0,
            height: dimensions.1,
        });
    }
    if let Some(orientation) = orientation {
        decoded.apply_orientation(orientation);
    }
    let mut image = if decoded.width().max(decoded.height()) > MAX_OUTPUT_EDGE {
        decoded.resize(
            MAX_OUTPUT_EDGE,
            MAX_OUTPUT_EDGE,
            image::imageops::FilterType::Triangle,
        )
    } else {
        decoded
    };
    // Preserve real transparency, not merely the presence of an alpha channel.
    let transparent =
        image.color().has_alpha() && image.to_rgba8().pixels().any(|pixel| pixel.0[3] != 255);
    for _ in 0..8 {
        let width = image.width();
        let height = image.height();
        if transparent || format == ImageFormat::Bmp {
            let rgba = image.to_rgba8();
            let mut bytes = Vec::new();
            PngEncoder::new_with_quality(
                &mut bytes,
                CompressionType::Default,
                FilterType::Adaptive,
            )
            .write_image(&rgba, width, height, image::ExtendedColorType::Rgba8)?;
            if bytes.len() <= MAX_OUTPUT_BYTES {
                return Ok(ImportedCoverImage {
                    bytes,
                    extension: "png".into(),
                    width,
                    height,
                });
            }
        }
        if !transparent {
            let rgb = image.to_rgb8();
            for quality in [92, 84, 76, 68] {
                let mut bytes = Vec::new();
                JpegEncoder::new_with_quality(&mut bytes, quality).encode(
                    &rgb,
                    width,
                    height,
                    image::ExtendedColorType::Rgb8,
                )?;
                if bytes.len() <= MAX_OUTPUT_BYTES {
                    return Ok(ImportedCoverImage {
                        bytes,
                        extension: "jpg".into(),
                        width,
                        height,
                    });
                }
            }
        }
        image = image.resize(
            (width * 3 / 4).max(1),
            (height * 3 / 4).max(1),
            image::imageops::FilterType::Triangle,
        );
    }
    bail!("无法将封面压缩到 2 MiB，请选择其他图片。")
}

fn animated(data: &[u8], format: ImageFormat) -> anyhow::Result<bool> {
    if format != ImageFormat::Png && format != ImageFormat::WebP {
        return Ok(false);
    }
    let png = format == ImageFormat::Png;
    let mut offset = if png { 8usize } else { 12usize };
    let mut chunks = 0;
    while offset + 8 <= data.len() {
        chunks += 1;
        ensure!(chunks <= 4096, "封面图片已损坏或无法解码。");
        let type_at = if png { offset + 4 } else { offset };
        let size_at = if png { offset } else { offset + 4 };
        let word: [u8; 4] = data[size_at..size_at + 4].try_into().unwrap();
        let size = if png {
            u32::from_be_bytes(word)
        } else {
            u32::from_le_bytes(word)
        } as usize;
        let kind = &data[type_at..type_at + 4];
        if kind == b"acTL" || kind == b"ANIM" || kind == b"ANMF" {
            return Ok(true);
        }
        if !png && kind == b"VP8X" && size > 0 && data.get(offset + 8).is_some_and(|v| v & 2 != 0) {
            return Ok(true);
        }
        let end = offset
            .checked_add(size)
            .and_then(|v| v.checked_add(if png { 12 } else { 8 + (size & 1) }))
            .context("封面图片已损坏或无法解码。")?;
        ensure!(end <= data.len(), "封面图片已损坏或无法解码。");
        offset = end;
        if png && kind == b"IEND" {
            break;
        }
    }
    Ok(false)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn encoded(image: &DynamicImage, format: ImageFormat) -> Vec<u8> {
        let mut output = Cursor::new(Vec::new());
        image.write_to(&mut output, format).unwrap();
        output.into_inner()
    }
    #[test]
    fn small_static_images_are_validated_without_reencoding() {
        for format in [ImageFormat::Png, ImageFormat::Jpeg, ImageFormat::WebP] {
            let bytes = encoded(&DynamicImage::new_rgb8(64, 40), format);
            let result = normalize_cover_image(bytes.clone()).unwrap();
            assert_eq!(result.bytes, bytes);
            assert_eq!((result.width, result.height), (64, 40));
        }
    }
    #[test]
    fn large_opaque_cover_has_bounded_dimensions_and_bytes() {
        let result = normalize_cover_image(encoded(
            &DynamicImage::new_rgb8(3200, 1800),
            ImageFormat::Png,
        ))
        .unwrap();
        assert_eq!((result.width, result.height), (1600, 900));
        assert!(result.bytes.len() <= MAX_OUTPUT_BYTES);
        assert_eq!(result.extension, "jpg");
        assert_eq!(
            image::load_from_memory(&result.bytes).unwrap().width(),
            1600
        );
    }
    #[test]
    fn noisy_transparent_cover_shrinks_until_within_budget() {
        let mut rgba = image::RgbaImage::new(1600, 1600);
        let mut seed = 21u32;
        for pixel in rgba.pixels_mut() {
            for channel in &mut pixel.0 {
                seed ^= seed << 13;
                seed ^= seed >> 17;
                seed ^= seed << 5;
                *channel = seed as u8;
            }
        }
        let original = encoded(&DynamicImage::ImageRgba8(rgba), ImageFormat::Png);
        assert!(original.len() > MAX_OUTPUT_BYTES);
        let result = normalize_cover_image(original).unwrap();
        assert_eq!(result.extension, "png");
        assert!(result.bytes.len() <= MAX_OUTPUT_BYTES);
        assert!(result.width < 1600);
        let decoded = image::load_from_memory(&result.bytes).unwrap().to_rgba8();
        assert!(decoded.pixels().any(|pixel| pixel.0[3] != 255));
    }
    #[test]
    fn rejects_truncation_animation_and_input_bombs() {
        assert!(normalize_cover_image(vec![0; MAX_INPUT_BYTES + 1]).is_err());
        let valid = encoded(&DynamicImage::new_rgb8(10, 10), ImageFormat::Png);
        assert!(normalize_cover_image(valid[..32].to_vec()).is_err());
        let mut animated = valid.clone();
        animated.splice(33..33, [0, 0, 0, 0, b'a', b'c', b'T', b'L', 0, 0, 0, 0]);
        assert!(normalize_cover_image(animated)
            .unwrap_err()
            .to_string()
            .contains("动图"));
        let mut fragmented = valid[..33].to_vec();
        for _ in 0..4097 {
            fragmented.extend_from_slice(&[0, 0, 0, 0, b't', b'E', b'X', b't', 0, 0, 0, 0]);
        }
        fragmented.extend_from_slice(&valid[33..]);
        assert!(normalize_cover_image(fragmented).is_err());
        let mut bomb = valid;
        bomb[16..20].copy_from_slice(&40000u32.to_be_bytes());
        assert!(normalize_cover_image(bomb).is_err());
    }
}
