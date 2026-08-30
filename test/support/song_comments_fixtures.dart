import 'dart:async';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/online/song_comments.dart';

Audio commentAudio(
        {String provider = 'netease',
        String id = '123',
        int? numericId = 456,
        String title = '测试歌曲'}) =>
    Audio.online(
        provider: provider,
        id: id,
        numericId: numericId,
        title: title,
        artist: '测试艺术家',
        album: '测试专辑',
        duration: 180,
        created: 1700000000);

Audio localCommentAudio() => Audio('本地歌曲', '本地艺术家', '本地专辑', 0, 180, null, null,
    r'D:\isolated-fixture\not-a-user-song.flac', 0, 0, null);

Map<String, dynamic> neteaseComment(int id, {String? content}) => {
      'commentId': id,
      'content': content ?? '测试评论 $id',
      'time': 1700000000000,
      'likedCount': 5,
      'user': {
        'nickname': '测试用户 $id',
        'avatarUrl': 'https://unused.invalid/avatar.png'
      },
      'beReplied': <Object>[],
    };

Map<String, dynamic> neteaseComments(List<Map<String, dynamic>> rows,
        {SongCommentSort sort = SongCommentSort.hot,
        bool more = false,
        int? total}) =>
    {
      'code': 200,
      sort == SongCommentSort.hot ? 'hotComments' : 'comments': rows,
      sort == SongCommentSort.hot ? 'hasMore' : 'more': more,
      'total': total ?? rows.length,
    };

Map<String, dynamic> qqLatestComment(int id, {int? rootId, String? content}) =>
    {
      'commentid': '$id',
      'rootcommentid': '${rootId ?? id}',
      'rootcommentcontent': content ?? 'QQ 测试评论 $id',
      'rootcommentnick': '完整昵称 $id',
      'time': '1700000000',
      'praisenum': 3,
      'middlecommentcontent': <Object>[],
    };

Map<String, dynamic> qqLatestComments(List<Map<String, dynamic>> rows,
        {bool more = false, int? total}) =>
    {
      'code': 0,
      'morecomment': more ? 1 : 0,
      'comment': {'commentlist': rows, 'commenttotal': total ?? rows.length},
    };

Map<String, dynamic> qqHotComment(int id, {String? content}) => {
      'CmId': '$id',
      'SeqNo': '${id + 1000}',
      'Content': content ?? 'QQ 热门评论 $id',
      'Nick': '热门用户 $id',
      'PubTime': '1700000000',
      'PraiseNum': 7,
      'SubComments': <Object>[],
    };

Map<String, dynamic> qqHotComments(List<Map<String, dynamic>> rows,
        {bool more = false, int? total}) =>
    {
      'code': 0,
      'req': {
        'code': 0,
        'data': {
          'CommentList': {
            'Comments': rows,
            'HasMore': more,
            'Total': total ?? rows.length,
          }
        }
      },
    };

class CommentRequestRecord {
  const CommentRequestRecord(
      this.target, this.sort, this.page, this.cancellation);
  final SongCommentsTarget target;
  final SongCommentSort sort;
  final int page;
  final SongCommentsCancellation cancellation;
}

typedef CommentResponseHandler = FutureOr<Map<String, dynamic>> Function(
    CommentRequestRecord request);

class FakeCommentsTransport implements SongCommentsTransport {
  FakeCommentsTransport(this.handler);
  CommentResponseHandler handler;
  final requests = <CommentRequestRecord>[];

  @override
  Future<Map<String, dynamic>> fetch(
    SongCommentsTarget target, {
    required SongCommentSort sort,
    required int page,
    required SongCommentsCancellation cancellation,
  }) async {
    final request = CommentRequestRecord(target, sort, page, cancellation);
    requests.add(request);
    return handler(request);
  }
}
