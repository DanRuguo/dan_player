/// The selected provider has no usable lyrics for this exact recording.
/// This is distinct from transport, response-format and local-save failures.
class LyricUnavailableException implements Exception {
  const LyricUnavailableException();

  @override
  String toString() => 'No usable lyrics for the selected source recording';
}
