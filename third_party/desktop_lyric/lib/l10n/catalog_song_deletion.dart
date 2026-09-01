const Map<String, List<String>> uiCatalogSongDeletion = {
  '删除歌曲…': ['Delete track…', '曲を削除…', '곡 삭제…'],
  '永久删除歌曲？': [
    'Permanently delete this track?',
    '曲を完全に削除しますか？',
    '곡을 영구 삭제할까요?',
  ],
  '将从磁盘永久删除“{0}”，并从总乐库、播放队列及所有歌单中移除。此操作不可撤销。': [
    '“{0}” will be permanently deleted from disk and removed from the library, playback queue, and every playlist. This cannot be undone.',
    '「{0}」をディスクから完全に削除し、ライブラリ、再生キュー、すべてのプレイリストから取り除きます。この操作は元に戻せません。',
    '“{0}”을(를) 디스크에서 영구 삭제하고 전체 보관함, 재생 대기열 및 모든 재생목록에서 제거합니다. 이 작업은 되돌릴 수 없습니다.',
  ],
  '文件位置': ['File location', 'ファイルの場所', '파일 위치'],
  '删除文件': ['Delete file', 'ファイルを削除', '파일 삭제'],
  '已删除歌曲“{0}”': [
    'Deleted “{0}”',
    '「{0}」を削除しました',
    '“{0}”을(를) 삭제했습니다',
  ],
  '歌曲文件已删除，但部分列表状态尚未保存；刷新后可重试同步。': [
    'The track file was deleted, but some list changes could not be saved. Refresh to retry synchronization.',
    '曲のファイルは削除されましたが、一部のリスト状態を保存できませんでした。更新して同期を再試行できます。',
    '곡 파일은 삭제되었지만 일부 목록 상태를 저장하지 못했습니다. 새로 고친 후 동기화를 다시 시도할 수 있습니다.',
  ],
  '曲库正在刷新或保存，请稍后再删除歌曲。': [
    'The library is being refreshed or saved. Delete the track after it finishes.',
    'ライブラリを更新または保存しています。完了してから曲を削除してください。',
    '보관함을 새로 고치거나 저장하는 중입니다. 완료된 후 곡을 삭제해 주세요.',
  ],
  '联网歌曲没有可删除的本地文件。': [
    'Online tracks do not have a local file to delete.',
    'オンライン曲には削除できるローカルファイルがありません。',
    '온라인 곡에는 삭제할 로컬 파일이 없습니다.',
  ],
  '歌单尚未完整读取。为避免留下无法恢复的引用，暂时不能删除歌曲。': [
    'Playlists have not loaded completely. The track cannot be deleted yet because that could leave unrecoverable references.',
    'プレイリストの読み込みが完了していません。復元できない参照が残るのを防ぐため、現在は曲を削除できません。',
    '재생목록을 완전히 읽지 못했습니다. 복구할 수 없는 참조가 남지 않도록 지금은 곡을 삭제할 수 없습니다.',
  ],
  '这首歌曲已不在本地曲库中，请刷新曲库后重试。': [
    'This track is no longer in the local library. Refresh the library and try again.',
    'この曲はローカルライブラリにありません。ライブラリを更新してから再試行してください。',
    '이 곡은 더 이상 로컬 보관함에 없습니다. 보관함을 새로 고친 후 다시 시도해 주세요.',
  ],
  '歌曲文件路径无效，未执行删除。': [
    'The track file path is invalid. Nothing was deleted.',
    '曲のファイルパスが無効です。削除は行われませんでした。',
    '곡 파일 경로가 잘못되었습니다. 아무것도 삭제하지 않았습니다.',
  ],
  '歌曲文件已经不存在，请刷新曲库。': [
    'The track file no longer exists. Refresh the library.',
    '曲のファイルは既に存在しません。ライブラリを更新してください。',
    '곡 파일이 이미 존재하지 않습니다. 보관함을 새로 고쳐 주세요.',
  ],
  '该来源不是可安全删除的本地音乐文件。': [
    'This source is not a local music file that can be deleted safely.',
    'このソースは安全に削除できるローカル音楽ファイルではありません。',
    '이 소스는 안전하게 삭제할 수 있는 로컬 음악 파일이 아닙니다.',
  ],
  '歌曲文件在确认期间已被其他程序更改。请刷新曲库并重新确认后再删除。': [
    'Another program changed the track file after confirmation. Refresh the library and confirm deletion again.',
    '確認後に別のプログラムが曲のファイルを変更しました。ライブラリを更新し、もう一度削除を確認してください。',
    '확인 후 다른 프로그램에서 곡 파일을 변경했습니다. 보관함을 새로 고친 후 삭제를 다시 확인해 주세요.',
  ],
  '无法删除歌曲文件。请确认文件未被其他程序占用，并检查文件夹写入权限。': [
    'Could not delete the track file. Make sure another program is not using it and check write permission for the folder.',
    '曲のファイルを削除できませんでした。他のプログラムが使用していないことと、フォルダーの書き込み権限を確認してください。',
    '곡 파일을 삭제하지 못했습니다. 다른 프로그램에서 사용 중인지와 폴더 쓰기 권한을 확인해 주세요.',
  ],
  '删除歌曲文件失败，请稍后重试。': [
    'Could not delete the track file. Try again later.',
    '曲のファイルを削除できませんでした。後でもう一度お試しください。',
    '곡 파일을 삭제하지 못했습니다. 잠시 후 다시 시도해 주세요.',
  ],
  '删除歌曲失败：{0}': [
    'Could not delete track: {0}',
    '曲を削除できませんでした：{0}',
    '곡을 삭제하지 못했습니다: {0}',
  ],
};
