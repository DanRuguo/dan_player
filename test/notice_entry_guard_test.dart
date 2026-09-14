import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('player notices cannot bypass the shared notice bubble', () {
    final bypasses = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) =>
            file.path.endsWith('.dart') &&
            RegExp(r'\.showSnackBar\s*\(').hasMatch(file.readAsStringSync()))
        .map((file) => file.path)
        .toList();
    expect(bypasses, isEmpty,
        reason: 'Use showAppNotice; the shared library owns presentation.');
  });
}
