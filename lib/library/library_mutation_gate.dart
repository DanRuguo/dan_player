/// Reject concurrent work instead of queueing an old Audio after a reload.
class LibraryMutationBusy implements Exception {
  const LibraryMutationBusy();
}

class LibraryMutationGate {
  static final shared = LibraryMutationGate();
  bool _busy = false;
  bool get isBusy => _busy;

  Future<T> run<T>(Future<T> Function() operation) async {
    if (_busy) throw const LibraryMutationBusy();
    _busy = true;
    try {
      return await operation();
    } finally {
      _busy = false;
    }
  }
}
