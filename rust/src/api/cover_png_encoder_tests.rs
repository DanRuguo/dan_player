use super::resize_picture;
use image::{DynamicImage, ImageFormat, RgbaImage};
use std::io::Cursor;

fn original_png_writer(pixels: &RgbaImage) -> Vec<u8> {
    // Preserve the previous writer only as a byte-level compatibility oracle.
    // Release builds do not include this generic encoding dispatch.
    let mut output = Cursor::new(Vec::new());
    pixels.write_to(&mut output, ImageFormat::Png).unwrap();
    output.into_inner()
}

fn assert_native_thumbnail_matches_original_writer(source: DynamicImage, format: ImageFormat) {
    let mut input = Cursor::new(Vec::new());
    source.write_to(&mut input, format).unwrap();
    let pixels = image::load_from_memory(input.get_ref()).unwrap().to_rgba8();
    let expected = original_png_writer(&pixels);
    let actual = resize_picture(input.get_ref(), 100, 100).expect("valid native-size thumbnail");
    assert_eq!(actual, expected, "default PNG bytes must remain identical");
    assert_eq!(image::guess_format(&actual).unwrap(), ImageFormat::Png);
    let decoded = image::load_from_memory(&actual).unwrap().to_rgba8();
    assert_eq!(decoded.dimensions(), pixels.dimensions());
    assert_eq!(
        decoded, pixels,
        "color and alpha bytes must remain identical"
    );
}

#[test]
fn native_rgba_thumbnail_keeps_exact_png_and_alpha_bytes() {
    let source = RgbaImage::from_fn(37, 23, |x, y| {
        image::Rgba([
            (x * 7) as u8,
            (y * 11) as u8,
            (x ^ y) as u8,
            (x * 13 + y * 3) as u8,
        ])
    });
    assert_native_thumbnail_matches_original_writer(
        DynamicImage::ImageRgba8(source),
        ImageFormat::Png,
    );
}

#[test]
fn native_color_conversions_keep_exact_png_bytes() {
    let png_sources = [
        DynamicImage::ImageRgb8(image::RgbImage::from_pixel(
            31,
            17,
            image::Rgb([0, 127, 255]),
        )),
        DynamicImage::ImageLuma8(image::GrayImage::from_pixel(31, 17, image::Luma([127]))),
        DynamicImage::ImageLumaA8(image::GrayAlphaImage::from_pixel(
            31,
            17,
            image::LumaA([127, 254]),
        )),
        DynamicImage::ImageRgb16(image::ImageBuffer::from_pixel(
            31,
            17,
            image::Rgb([0u16, 32768, 65535]),
        )),
        DynamicImage::ImageRgba16(image::ImageBuffer::from_pixel(
            31,
            17,
            image::Rgba([0u16, 32768, 65535, 65534]),
        )),
        DynamicImage::ImageLuma16(image::ImageBuffer::from_pixel(
            31,
            17,
            image::Luma([32768u16]),
        )),
        DynamicImage::ImageLumaA16(image::ImageBuffer::from_pixel(
            31,
            17,
            image::LumaA([32768u16, 65534]),
        )),
    ];
    for source in png_sources {
        assert_native_thumbnail_matches_original_writer(source, ImageFormat::Png);
    }
    let float_sources = [
        DynamicImage::ImageRgb32F(image::ImageBuffer::from_pixel(
            31,
            17,
            image::Rgb([0.0f32, 0.5, 1.0]),
        )),
        DynamicImage::ImageRgba32F(image::ImageBuffer::from_pixel(
            31,
            17,
            image::Rgba([0.0f32, 0.5, 1.0, 0.9999]),
        )),
    ];
    for source in float_sources {
        assert_native_thumbnail_matches_original_writer(source, ImageFormat::OpenExr);
    }
}
