import 'dart:io';
import 'package:path/path.dart' as p;

Future<void> browseFolderInExplorer(Directory directory,
    {Future<void> Function(String executable, List<String> arguments)?
        launch}) async {
  if (!await directory.exists()) {
    throw FileSystemException('Folder is unavailable', directory.path);
  }
  final explorer = p.join(
      Platform.environment['SystemRoot'] ?? r'C:\Windows', 'explorer.exe');
  final arguments = [p.normalize(directory.absolute.path)];
  if (launch != null) {
    await launch(explorer, arguments);
  } else {
    await Process.start(explorer, arguments, mode: ProcessStartMode.detached);
  }
}
