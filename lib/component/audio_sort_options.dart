import 'package:dan_player/library/audio_sort.dart';
import 'package:flutter/material.dart';

IconData audioSortIcon(AudioSortField field) => switch (field) {
      AudioSortField.original => Icons.drag_indicator,
      AudioSortField.name => Icons.sort_by_alpha,
      AudioSortField.artist => Icons.person_outline,
      AudioSortField.album => Icons.album_outlined,
      AudioSortField.composer => Icons.edit_note,
      AudioSortField.duration => Icons.timer_outlined,
      AudioSortField.added => Icons.schedule,
      AudioSortField.modified => Icons.edit_calendar_outlined,
      AudioSortField.track => Icons.format_list_numbered,
      AudioSortField.albumArtist => Icons.people_outline,
      AudioSortField.bitrate => Icons.speed,
      AudioSortField.sampleRate => Icons.graphic_eq,
      AudioSortField.fileSize => Icons.storage_outlined,
      AudioSortField.format => Icons.audio_file_outlined,
      AudioSortField.language => Icons.language,
      AudioSortField.source => Icons.cloud_outlined,
    };
