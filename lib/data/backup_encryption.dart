import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

class BackupEncryptionLimitException implements Exception {
  const BackupEncryptionLimitException();
}

/// Versioned authenticated envelope around a compressed backup. Decryption
/// produces only a private temporary ZIP, never an extracted file. Callers may
/// read that ZIP only after doFinal has authenticated the entire stream.
class BackupEncryption {
  static final _magic = ascii.encode('DANBAK2E');
  static const iterations = 600000;
  static const _headerLength = 8 + 4 + 16 + 12;
  // GCM permits at most 2^39 - 256 plaintext bits for a single invocation.
  static const maximumBytes = (1 << 36) - 32;

  static Future<bool> isEncrypted(File file) async {
    final input = await file.open();
    try {
      final bytes = await input.read(_magic.length);
      return _equal(bytes, _magic);
    } finally {
      await input.close();
    }
  }

  static Future<void> encrypt(File source, File destination, String password,
      {Future<void> Function(int, int)? checkpoint}) async {
    if (password.isEmpty) throw const FormatException('A password is required');
    final length = await source.length();
    if (length > maximumBytes) throw const BackupEncryptionLimitException();
    final random = Random.secure();
    final header = Uint8List(_headerLength)..setAll(0, _magic);
    ByteData.sublistView(header).setUint32(8, iterations, Endian.big);
    for (var index = 12; index < header.length; index++) {
      header[index] = random.nextInt(256);
    }
    await _transform(source, destination, password, header, true,
        checkpoint: checkpoint);
  }

  static Future<void> decrypt(File source, File destination, String password,
      {Future<void> Function(int, int)? checkpoint}) async {
    final input = await source.open();
    late Uint8List header;
    try {
      header = await input.read(_headerLength);
    } finally {
      await input.close();
    }
    if (header.length != _headerLength ||
        !_equal(header.sublist(0, 8), _magic) ||
        ByteData.sublistView(header).getUint32(8, Endian.big) != iterations ||
        await source.length() < _headerLength + 16 ||
        await source.length() > maximumBytes + _headerLength + 16) {
      throw const FormatException('Invalid encrypted backup');
    }
    await _transform(source, destination, password, header, false,
        checkpoint: checkpoint);
  }

  static Future<void> _transform(File source, File destination, String password,
      Uint8List header, bool encrypting,
      {Future<void> Function(int, int)? checkpoint}) async {
    await checkpoint?.call(0, await source.length());
    final passwordBytes = Uint8List.fromList(utf8.encode(password));
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(header.sublist(12, 28), iterations, 32));
    final key = derivator.process(passwordBytes);
    passwordBytes.fillRange(0, passwordBytes.length, 0);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
          encrypting,
          AEADParameters(
              KeyParameter(key), 128, header.sublist(28, 40), header));
    final output = await destination.open(mode: FileMode.write);
    final total = await source.length();
    var completed = 0;
    var succeeded = false;
    try {
      if (encrypting) await output.writeFrom(header);
      // Both file IO and cipher output stay bounded even for multi-GB music.
      final input = await source.open();
      try {
        if (!encrypting) await input.setPosition(_headerLength);
        while (true) {
          await checkpoint?.call(completed, total);
          final bytes = await input.read(256 * 1024);
          if (bytes.isEmpty) break;
          // The streaming decryptor may release the previous chunk's held
          // block too. getOutputSize(n) does not include that buffered block.
          final buffer = Uint8List(bytes.length + cipher.blockSize + 32);
          final count = cipher.processBytes(bytes, 0, bytes.length, buffer, 0);
          if (count > 0) await output.writeFrom(buffer, 0, count);
          completed += bytes.length;
        }
        // PointyCastle's getOutputSize(0) excludes the partial block already
        // buffered by processBytes; reserve that block plus the 16-byte tag.
        final last = Uint8List(cipher.blockSize + 32);
        final count = cipher.doFinal(last, 0);
        if (count > 0) await output.writeFrom(last, 0, count);
        await output.flush();
        succeeded = true;
      } finally {
        await input.close();
      }
    } finally {
      key.fillRange(0, key.length, 0);
      await output.close();
      if (!succeeded && await destination.exists()) await destination.delete();
    }
  }

  static bool _equal(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var index = 0; index < a.length; index++) {
      difference |= a[index] ^ b[index];
    }
    return difference == 0;
  }
}
