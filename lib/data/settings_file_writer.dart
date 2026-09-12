import 'dart:io';

/// Small settings documents are flushed beside their destination, then renamed
/// over it. Windows' Dart File.rename uses MoveFileExW(REPLACE_EXISTING |
/// WRITE_THROUGH); a failed write must never truncate the recovery checkpoint.
void writeSettingsFile(File target, String contents) {
  target.parent.createSync(recursive: true);
  final temporary = File('${target.path}.pending');
  try {
    temporary.writeAsStringSync(contents, flush: true);
    temporary.renameSync(target.path);
  } finally {
    try {
      if (temporary.existsSync()) temporary.deleteSync();
    } on FileSystemException {
      // Cleanup cannot turn a committed settings write into a false failure.
    }
  }
}
