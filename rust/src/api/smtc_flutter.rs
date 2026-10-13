use std::{sync::Mutex, time::Duration};

use flutter_rust_bridge::frb;
use windows::{
    core::HSTRING,
    Foundation::{EventRegistrationToken, TimeSpan, TypedEventHandler},
    Media::{
        MediaPlaybackStatus, MediaPlaybackType, Playback::MediaPlayer,
        SystemMediaTransportControls, SystemMediaTransportControlsButton,
        SystemMediaTransportControlsButtonPressedEventArgs,
        SystemMediaTransportControlsTimelineProperties,
    },
    Storage::{
        FileProperties::ThumbnailMode,
        StorageFile,
        Streams::{DataWriter, InMemoryRandomAccessStream, RandomAccessStreamReference},
    },
};

use crate::frb_generated::StreamSink;

use super::{logger::log_to_dart, tag_reader, utils::windows_storage_path};

pub struct SMTCFlutter {
    _smtc: SystemMediaTransportControls,
    _player: MediaPlayer,
    button_pressed_token: Mutex<Option<EventRegistrationToken>>,
    // The same short lock registers requests, commits metadata and closes the
    // controls. Cover I/O happens outside it; None permanently revokes display.
    display_revision: Mutex<Option<u64>>,
}

pub enum SMTCControlEvent {
    Play,
    Pause,
    Previous,
    Next,
    Unknown,
}

pub enum SMTCState {
    Paused,
    Playing,
}

/// Apis for Flutter
impl SMTCFlutter {
    #[frb(sync)]
    pub fn new() -> Self {
        Self::_new().unwrap()
    }

    pub fn subscribe_to_control_events(&self, sink: StreamSink<SMTCControlEvent>) {
        let callback = TypedEventHandler::<
            SystemMediaTransportControls,
            SystemMediaTransportControlsButtonPressedEventArgs,
        >::new(move |_, event| {
            let Some(event) = event else {
                return Ok(());
            };
            let Ok(button) = event.Button() else {
                return Ok(());
            };
            let event = match button {
                SystemMediaTransportControlsButton::Play => SMTCControlEvent::Play,
                SystemMediaTransportControlsButton::Pause => SMTCControlEvent::Pause,
                SystemMediaTransportControlsButton::Next => SMTCControlEvent::Next,
                SystemMediaTransportControlsButton::Previous => SMTCControlEvent::Previous,
                _ => SMTCControlEvent::Unknown,
            };
            let _ = sink.add(event);

            Ok(())
        });
        if let Err(error) = self._register_button_handler(&callback) {
            log_to_dart(format!("fail to subscribe SMTC controls: {}", error));
        }
    }

    pub fn update_state(&self, state: SMTCState) {
        if let Err(err) = self._update_state(state) {
            log_to_dart(format!("fail to update state: {}", err));
        }
    }

    /// progress, duration: ms
    pub fn update_time_properties(&self, progress: u32) {
        if let Err(err) = self._update_time_properties(progress) {
            log_to_dart(format!("fail to update state: {}", err));
        }
    }

    pub fn update_display(
        &self,
        title: String,
        artist: String,
        album: String,
        duration: u32,
        path: String,
    ) {
        if let Err(err) = self._update_display(
            HSTRING::from(title),
            HSTRING::from(artist),
            HSTRING::from(album),
            duration,
            HSTRING::from(path),
        ) {
            log_to_dart(format!("fail to update display: {}", err));
        }
    }

    pub fn close(&self) {
        self._close();
    }
}

#[cfg(test)]
#[path = "smtc_display_tests.rs"]
mod display_tests;

impl SMTCFlutter {
    fn _close(&self) {
        let mut revision = self
            .display_revision
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        if revision.is_none() {
            return;
        }
        *revision = None;
        if let Ok(mut stored_token) = self.button_pressed_token.lock() {
            if let Some(token) = stored_token.take() {
                let _ = self._smtc.RemoveButtonPressed(token);
            }
        }
        let _ = self._smtc.SetIsEnabled(false);
        if let Err(err) = self._player.Close() {
            log_to_dart(format!("fail to close SMTC media player: {}", err));
        }
    }

    fn _register_button_handler(
        &self,
        callback: &TypedEventHandler<
            SystemMediaTransportControls,
            SystemMediaTransportControlsButtonPressedEventArgs,
        >,
    ) -> Result<(), windows::core::Error> {
        let current = self
            .display_revision
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        if current.is_none() {
            return Ok(());
        }
        let token = self._smtc.ButtonPressed(callback)?;
        match self.button_pressed_token.lock() {
            Ok(mut stored_token) => {
                if let Some(previous_token) = stored_token.replace(token) {
                    let _ = self._smtc.RemoveButtonPressed(previous_token);
                }
            }
            Err(_) => {
                let _ = self._smtc.RemoveButtonPressed(token);
                log_to_dart("fail to retain SMTC button event token".to_string());
            }
        }
        Ok(())
    }

    fn _init_controls(smtc: &SystemMediaTransportControls) -> Result<(), windows::core::Error> {
        // 下一首
        smtc.SetIsNextEnabled(true)?;
        // 暂停
        smtc.SetIsPauseEnabled(true)?;
        // 播放（恢复）
        smtc.SetIsPlayEnabled(true)?;
        // 上一首
        smtc.SetIsPreviousEnabled(true)?;

        Ok(())
    }

    fn _new() -> Result<Self, windows::core::Error> {
        let _player = MediaPlayer::new()?;
        _player.CommandManager()?.SetIsEnabled(false)?;

        let _smtc = _player.SystemMediaTransportControls()?;
        Self::_init_controls(&_smtc)?;

        Ok(Self {
            _smtc,
            _player,
            button_pressed_token: Mutex::new(None),
            display_revision: Mutex::new(Some(0)),
        })
    }

    fn _update_state(&self, state: SMTCState) -> Result<(), windows::core::Error> {
        let state = match state {
            SMTCState::Playing => MediaPlaybackStatus::Playing,
            SMTCState::Paused => MediaPlaybackStatus::Paused,
        };
        self._smtc.SetPlaybackStatus(state)?;

        Ok(())
    }

    /// progress, duration: ms
    fn _update_time_properties(&self, progress: u32) -> Result<(), windows::core::Error> {
        let time_properties = SystemMediaTransportControlsTimelineProperties::new()?;
        time_properties.SetPosition(TimeSpan::from(Duration::from_millis(progress.into())))?;
        self._smtc.UpdateTimelineProperties(&time_properties)?;

        Ok(())
    }

    fn _ras_ref_from_pic_data(
        picture_data: &[u8],
    ) -> Result<RandomAccessStreamReference, windows::core::Error> {
        let stream = InMemoryRandomAccessStream::new()?;

        let writer = DataWriter::CreateDataWriter(&stream)?;
        writer.WriteBytes(picture_data)?;
        writer.StoreAsync()?.get()?;

        // 调用 DetachStream() 的意义在于“把流从 DataWriter 脱附”，
        // 这样可以安全地释放/关闭 DataWriter 而不影响流的生命周期。
        // stream 不会因为 writer drop 而被销毁
        writer.DetachStream()?;

        stream.Seek(0)?;

        RandomAccessStreamReference::CreateFromStream(&stream)
    }

    fn _update_display(
        &self,
        title: HSTRING,
        artist: HSTRING,
        album: HSTRING,
        duration: u32,
        path: HSTRING,
    ) -> Result<(), windows::core::Error> {
        self._update_display_with_thumbnail(title, artist, album, duration, || {
            Self::_thumbnail_for_path(&path)
        })
    }

    fn _thumbnail_for_path(
        path: &HSTRING,
    ) -> Result<Option<RandomAccessStreamReference>, windows::core::Error> {
        // Remote tracks have an online:// identity. A missing file or optional
        // thumbnail must never leave another track's artwork or block its text.
        if !std::path::Path::new(&path.to_string()).exists() {
            return Ok(None);
        }
        let picture =
            if let Some(pic_data) = tag_reader::get_picture_from_path(path.to_string(), 256, 256) {
                Self::_ras_ref_from_pic_data(&pic_data)?
            } else {
                let file = StorageFile::GetFileFromPathAsync(&windows_storage_path(
                    std::path::Path::new(&path.to_os_string()),
                )?)?
                .get()?;
                let thumbnail = file
                    .GetThumbnailAsyncOverloadDefaultSizeDefaultOptions(ThumbnailMode::MusicView)?
                    .get()?;
                RandomAccessStreamReference::CreateFromStream(&thumbnail)?
            };
        Ok(Some(picture))
    }

    fn _update_display_with_thumbnail(
        &self,
        title: HSTRING,
        artist: HSTRING,
        album: HSTRING,
        duration: u32,
        thumbnail: impl FnOnce() -> Result<Option<RandomAccessStreamReference>, windows::core::Error>,
    ) -> Result<(), windows::core::Error> {
        let requested = {
            let mut owner = self
                .display_revision
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            let Some(revision) = owner.as_mut() else {
                return Ok(());
            };
            *revision = revision.wrapping_add(1);
            *revision
        };
        // Reading a cloud-backed file, decoder or Shell thumbnail can finish
        // after a newer track. No shared updater is changed during that wait.
        let picture = match thumbnail() {
            Ok(picture) => picture,
            Err(error) => {
                log_to_dart(format!("fail to read SMTC artwork: {}", error));
                None
            }
        };
        let current = self
            .display_revision
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        if *current != Some(requested) {
            return Ok(());
        }

        let updater = self._smtc.DisplayUpdater()?;
        // ClearAll also resets Type. Restore Music and the complete current
        // metadata under the ownership lock before publishing a single update.
        updater.ClearAll()?;
        updater.SetType(MediaPlaybackType::Music)?;

        let time_properties = SystemMediaTransportControlsTimelineProperties::new()?;
        time_properties.SetStartTime(TimeSpan { Duration: 0 })?;
        time_properties.SetEndTime(TimeSpan::from(Duration::from_millis(duration.into())))?;
        time_properties.SetMinSeekTime(TimeSpan { Duration: 0 })?;
        time_properties.SetMaxSeekTime(TimeSpan::from(Duration::from_millis(duration.into())))?;
        self._smtc.UpdateTimelineProperties(&time_properties)?;

        let music_properties = updater.MusicProperties()?;
        music_properties.SetTitle(&title)?;
        music_properties.SetArtist(&artist)?;
        music_properties.SetAlbumTitle(&album)?;

        if let Some(picture) = picture {
            // Artwork is optional; a rejected thumbnail still publishes the
            // new title/artist/album after the old cover has been retired.
            if let Err(error) = updater.SetThumbnail(&picture) {
                log_to_dart(format!("fail to set SMTC artwork: {}", error));
            }
        }

        updater.Update()?;

        if !(self._smtc.IsEnabled()?) {
            self._smtc.SetIsEnabled(true)?;
        }

        Ok(())
    }
}
