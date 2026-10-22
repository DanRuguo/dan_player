import 'package:dan_player/library/audio_library.dart';

/// Presentation indexes into the live queue. No audio, order or edit history is
/// duplicated. Only adjacent occurrences from the same known release group.
class QueueAlbumBlock {
  const QueueAlbumBlock(
      {required this.id,
      required this.start,
      required this.end,
      required this.title,
      required this.owner});
  final int id, start, end;
  final String title, owner;
  int get count => end - start;
  bool contains(int index) => index >= start && index < end;
}

class QueueAlbumRow {
  const QueueAlbumRow.track(this.queueIndex) : block = null;
  const QueueAlbumRow.header(this.block) : queueIndex = null;
  final int? queueIndex;
  final QueueAlbumBlock? block;
}

List<QueueAlbumBlock> queueAlbumBlocks(
    List<Audio> queue, int? Function(int) occurrenceAt) {
  final blocks = <QueueAlbumBlock>[];
  var start = 0;
  while (start < queue.length) {
    final album = queue[start].albumIdentity;
    var end = start + 1;
    if (album.title != null) {
      while (end < queue.length && queue[end].albumIdentity.id == album.id) {
        end++;
      }
    }
    final id = occurrenceAt(start);
    if (end - start > 1 && id != null) {
      blocks.add(QueueAlbumBlock(
          id: id,
          start: start,
          end: end,
          title: album.displayTitle,
          owner: album.displayOwner));
    }
    start = end;
  }
  return List.unmodifiable(blocks);
}

List<QueueAlbumRow> queueAlbumRows(
    List<int> visibleIndices, List<QueueAlbumBlock> blocks, Set<int> collapsed,
    {required bool grouping, required bool searching}) {
  if (!grouping || searching) {
    return [for (final index in visibleIndices) QueueAlbumRow.track(index)];
  }
  final rows = <QueueAlbumRow>[];
  var blockIndex = 0;
  for (final index in visibleIndices) {
    while (blockIndex < blocks.length && blocks[blockIndex].end <= index) {
      blockIndex++;
    }
    final block =
        blockIndex < blocks.length && blocks[blockIndex].contains(index)
            ? blocks[blockIndex]
            : null;
    if (block != null && index == block.start)
      rows.add(QueueAlbumRow.header(block));
    if (block == null || !collapsed.contains(block.id))
      rows.add(QueueAlbumRow.track(index));
  }
  return rows;
}
