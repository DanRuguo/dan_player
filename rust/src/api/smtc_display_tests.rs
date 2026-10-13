use super::*;
#[cfg(windows)]
use std::os::windows::process::CommandExt;
use std::{
    io::Cursor,
    process::{Command, Stdio},
    sync::{mpsc, Arc},
    thread,
    time::Instant,
};
use windows::Win32::System::Com::{CoInitializeEx, CoUninitialize, COINIT_MULTITHREADED};

struct Apartment;
impl Apartment {
    fn new() -> Self {
        unsafe { CoInitializeEx(None, COINIT_MULTITHREADED).ok().unwrap() };
        Self
    }
}
impl Drop for Apartment {
    fn drop(&mut self) {
        unsafe { CoUninitialize() };
    }
}

fn run_in_native_process(case: &str) -> bool {
    const MARKER: &str = "DAN_PLAYER_SMTC_NATIVE_CASE";
    if std::env::var(MARKER).as_deref() == Ok(case) {
        return false;
    }
    // MediaPlayer has a process-wide cached WinRT activation factory. Ending
    // the last MTA between libtest worker threads can leave that factory in
    // APP_EXITING. Each case owns a fresh native process/apartment lifecycle.
    let mut command = Command::new(std::env::current_exe().unwrap());
    command
        .args([
            "--exact",
            &format!("api::smtc_flutter::display_tests::{case}"),
            "--nocapture",
        ])
        .env(MARKER, case)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    #[cfg(windows)]
    command.creation_flags(0x08000000); // CREATE_NO_WINDOW
    let mut child = command.spawn().unwrap();
    let started = Instant::now();
    while child.try_wait().unwrap().is_none() {
        if started.elapsed() > Duration::from_secs(15) {
            child.kill().unwrap();
            let output = child.wait_with_output().unwrap();
            panic!(
                "native SMTC case timed out: {case}\n{}\n{}",
                String::from_utf8_lossy(&output.stdout),
                String::from_utf8_lossy(&output.stderr)
            );
        }
        thread::sleep(Duration::from_millis(10));
    }
    let output = child.wait_with_output().unwrap();
    println!("{}", String::from_utf8_lossy(&output.stdout));
    eprintln!("{}", String::from_utf8_lossy(&output.stderr));
    assert!(output.status.success(), "native SMTC case failed: {case}");
    true
}

fn artwork() -> RandomAccessStreamReference {
    let image = image::RgbaImage::from_pixel(1, 1, image::Rgba([200, 50, 90, 255]));
    let mut png = Cursor::new(Vec::new());
    image::DynamicImage::ImageRgba8(image)
        .write_to(&mut png, image::ImageFormat::Png)
        .unwrap();
    SMTCFlutter::_ras_ref_from_pic_data(png.get_ref()).unwrap()
}

#[test]
fn online_track_replaces_local_artwork_without_reusing_previous_thumbnail() {
    if run_in_native_process(
        "online_track_replaces_local_artwork_without_reusing_previous_thumbnail",
    ) {
        return;
    }
    let _apartment = Apartment::new();
    let player = SMTCFlutter::_new().unwrap();
    let updater = player._smtc.DisplayUpdater().unwrap();
    updater.SetType(MediaPlaybackType::Music).unwrap();
    updater.SetThumbnail(&artwork()).unwrap();
    updater.Update().unwrap();
    assert!(updater.Thumbnail().is_ok(), "fixture must own real artwork");

    player
        ._update_display(
            HSTRING::from("new online title"),
            HSTRING::from("new artist"),
            HSTRING::from("new album"),
            180000,
            HSTRING::from("online://test/new-track"),
        )
        .unwrap();
    let music = updater.MusicProperties().unwrap();
    assert_eq!(music.Title().unwrap(), HSTRING::from("new online title"));
    assert_eq!(music.Artist().unwrap(), HSTRING::from("new artist"));
    assert_eq!(music.AlbumTitle().unwrap(), HSTRING::from("new album"));
    assert!(
        updater.Thumbnail().is_err(),
        "an online track without artwork must retire the previous local cover"
    );
    player.close();
}

#[test]
fn thumbnail_failure_still_commits_complete_new_metadata() {
    if run_in_native_process("thumbnail_failure_still_commits_complete_new_metadata") {
        return;
    }
    let _apartment = Apartment::new();
    let player = SMTCFlutter::_new().unwrap();
    let updater = player._smtc.DisplayUpdater().unwrap();
    updater.SetThumbnail(&artwork()).unwrap();
    player
        ._update_display_with_thumbnail(
            HSTRING::from("without cover"),
            HSTRING::from("current artist"),
            HSTRING::from("current album"),
            120000,
            || {
                Err(windows::core::Error::from_hresult(windows::core::HRESULT(
                    0x80004005u32 as i32,
                )))
            },
        )
        .unwrap();
    let music = updater.MusicProperties().unwrap();
    assert_eq!(music.Title().unwrap(), HSTRING::from("without cover"));
    assert_eq!(music.Artist().unwrap(), HSTRING::from("current artist"));
    assert_eq!(music.AlbumTitle().unwrap(), HSTRING::from("current album"));
    assert!(updater.Thumbnail().is_err());
    assert_eq!(updater.Type().unwrap(), MediaPlaybackType::Music);
    assert!(player._smtc.IsEnabled().unwrap());
    player.close();
}

#[test]
fn late_previous_artwork_cannot_clear_or_publish_over_current_metadata() {
    if run_in_native_process("late_previous_artwork_cannot_clear_or_publish_over_current_metadata")
    {
        return;
    }
    let _apartment = Apartment::new();
    let player = Arc::new(SMTCFlutter::_new().unwrap());
    let (entered, waiting) = mpsc::sync_channel(1);
    let (release, released) = mpsc::sync_channel(1);
    let old = Arc::clone(&player);
    let worker = thread::spawn(move || {
        let _apartment = Apartment::new();
        old._update_display_with_thumbnail(
            HSTRING::from("late old title"),
            HSTRING::from("old artist"),
            HSTRING::from("old album"),
            30000,
            || {
                let picture = artwork();
                entered.send(()).unwrap();
                released.recv_timeout(Duration::from_secs(5)).unwrap();
                Ok(Some(picture))
            },
        )
        .unwrap();
    });
    waiting.recv_timeout(Duration::from_secs(5)).unwrap();
    player
        ._update_display(
            HSTRING::from("current title"),
            HSTRING::from("current artist"),
            HSTRING::from("current album"),
            180000,
            HSTRING::from("online://test/current"),
        )
        .unwrap();
    release.send(()).unwrap();
    worker.join().unwrap();

    let updater = player._smtc.DisplayUpdater().unwrap();
    let music = updater.MusicProperties().unwrap();
    assert_eq!(music.Title().unwrap(), HSTRING::from("current title"));
    assert_eq!(music.Artist().unwrap(), HSTRING::from("current artist"));
    assert_eq!(music.AlbumTitle().unwrap(), HSTRING::from("current album"));
    assert!(
        updater.Thumbnail().is_err(),
        "old cover must not be republished"
    );
    assert!(player._smtc.IsEnabled().unwrap());
    Arc::try_unwrap(player).ok().unwrap().close();
}

#[test]
fn closing_controls_revokes_waiting_artwork_and_future_display_requests() {
    if run_in_native_process("closing_controls_revokes_waiting_artwork_and_future_display_requests")
    {
        return;
    }
    let _apartment = Apartment::new();
    let player = Arc::new(SMTCFlutter::_new().unwrap());
    let controls = player._smtc.clone();
    controls.SetIsEnabled(true).unwrap();
    let (entered, waiting) = mpsc::sync_channel(1);
    let (release, released) = mpsc::sync_channel(1);
    let old = Arc::clone(&player);
    let worker = thread::spawn(move || {
        let _apartment = Apartment::new();
        old._update_display_with_thumbnail(
            HSTRING::from("must never revive"),
            HSTRING::new(),
            HSTRING::new(),
            30000,
            || {
                let picture = artwork();
                entered.send(()).unwrap();
                released.recv_timeout(Duration::from_secs(5)).unwrap();
                Ok(Some(picture))
            },
        )
        .unwrap();
    });
    waiting.recv_timeout(Duration::from_secs(5)).unwrap();
    player._close();
    release.send(()).unwrap();
    worker.join().unwrap();
    assert!(
        !controls.IsEnabled().unwrap(),
        "late cover cannot enable closed SMTC"
    );
    player
        ._update_display_with_thumbnail(
            HSTRING::from("after close"),
            HSTRING::new(),
            HSTRING::new(),
            1000,
            || panic!("a closed controller must not start more artwork I/O"),
        )
        .unwrap();
    assert!(!controls.IsEnabled().unwrap());
}

#[test]
fn bridge_shared_close_retires_an_inflight_opaque_display_borrow() {
    if run_in_native_process("bridge_shared_close_retires_an_inflight_opaque_display_borrow") {
        return;
    }
    use flutter_rust_bridge::for_generated::{
        rust_auto_opaque_decode_owned, rust_auto_opaque_encode, Lockable, RustAutoOpaqueInner,
    };

    let _apartment = Apartment::new();
    // These are the same MOI opaque and shared decoder used by the generated
    // update_display/close handlers, including their native reference counts.
    let opaque: crate::frb_generated::RustOpaqueMoi<RustAutoOpaqueInner<SMTCFlutter>> =
        rust_auto_opaque_encode(SMTCFlutter::_new().unwrap());
    let (entered, waiting) = mpsc::sync_channel(1);
    let (release, released) = mpsc::sync_channel(1);
    let display = opaque.clone();
    let worker = thread::spawn(move || {
        let _apartment = Apartment::new();
        let borrowed = display.lockable_decode_sync_ref();
        borrowed
            ._update_display_with_thumbnail(
                HSTRING::from("slow opaque display"),
                HSTRING::new(),
                HSTRING::new(),
                30000,
                || {
                    let picture = artwork();
                    entered.send(()).unwrap();
                    released.recv_timeout(Duration::from_secs(5)).unwrap();
                    Ok(Some(picture))
                },
            )
            .unwrap();
    });
    waiting.recv_timeout(Duration::from_secs(5)).unwrap();
    // Negative control exercises the former generated owned decoder against
    // the live reference count, proving the shutdown failure before close().
    let owned = opaque.clone();
    assert!(std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let _: SMTCFlutter = rust_auto_opaque_decode_owned(owned);
    }))
    .is_err());
    let closing = opaque.lockable_decode_sync_ref();
    let controls = closing._smtc.clone();
    closing.close(); // Public API must work while another opaque ref is held.
    closing.close(); // A shared close remains idempotent.
    let callback = TypedEventHandler::<
        SystemMediaTransportControls,
        SystemMediaTransportControlsButtonPressedEventArgs,
    >::new(|_, _| Ok(()));
    closing._register_button_handler(&callback).unwrap();
    assert!(closing.button_pressed_token.lock().unwrap().is_none());
    assert!(!controls.IsEnabled().unwrap());
    drop(closing);
    release.send(()).unwrap();
    worker.join().unwrap();
    assert!(
        !controls.IsEnabled().unwrap(),
        "late opaque cover cannot revive SMTC"
    );

    // Couple the actual ref-lifetime test to the generated dispatcher's wire
    // mode. An owned decoder would panic before entering the public close.
    let generated = include_str!("../frb_generated.rs");
    let start = generated
        .find("fn wire__crate__api__smtc_flutter__SmtcFlutter_close_impl(")
        .unwrap();
    let end = generated[start..]
        .find("fn wire__crate__api__smtc_flutter__SmtcFlutter_new_impl(")
        .unwrap()
        + start;
    let close_handler = &generated[start..end];
    assert!(close_handler.contains("lockable_decode_sync_ref()"));
    assert!(!close_handler.contains("<SMTCFlutter>::sse_decode"));
    // Once the worker/guards finish, the real MOI decoder must again observe a
    // unique owner. This also rules out leaked exported reference counts.
    let released: SMTCFlutter = rust_auto_opaque_decode_owned(opaque);
    assert!(released.display_revision.lock().unwrap().is_none());
}
