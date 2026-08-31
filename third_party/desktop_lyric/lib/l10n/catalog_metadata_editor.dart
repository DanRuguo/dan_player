// Application status messages only; never music/tag contents.
const Map<String, List<String>> catalogMetadataEditor = {
  '歌曲文件已保存，但曲库同步未完成。再次点击保存将先重试同步，不会重复写入相同修改。': [
    'The audio file was saved, but library sync is incomplete. Save again to retry sync without rewriting the same changes.',
    '音声ファイルは保存されましたが、ライブラリの同期は未完了です。再度保存すると、同じ変更を書き直さずに同期を再試行します。',
    '오디오 파일은 저장되었지만 라이브러리 동기화가 완료되지 않았습니다. 다시 저장하면 같은 변경을 다시 쓰지 않고 동기화를 재시도합니다.',
  ],
  '文件正在被占用。请先切换当前歌曲并关闭其他占用程序后重试。': [
    'The file is in use. Switch tracks and close other programs using it, then try again.',
    'ファイルは使用中です。再生する曲を切り替え、使用中の他のアプリを閉じてから再試行してください。',
    '파일이 사용 중입니다. 재생 곡을 전환하고 파일을 사용하는 다른 프로그램을 닫은 후 다시 시도하세요.',
  ],
  '文件为只读。播放器不会自动修改文件属性。': [
    'The file is read-only. The player will not change its attributes automatically.',
    'ファイルは読み取り専用です。プレーヤーはファイル属性を自動で変更しません。',
    '읽기 전용 파일입니다. 플레이어는 파일 속성을 자동으로 변경하지 않습니다.',
  ],
  '没有文件或所在文件夹的写入权限。播放器不会自动修改权限。': [
    'Write permission is missing for the file or its folder. The player will not change permissions automatically.',
    'ファイルまたはフォルダーへの書き込み権限がありません。プレーヤーは権限を自動で変更しません。',
    '파일 또는 폴더에 쓰기 권한이 없습니다. 플레이어는 권한을 자동으로 변경하지 않습니다.',
  ],
  '磁盘空间不足，无法创建安全写入副本。': [
    'There is not enough disk space to create a safe working copy.',
    '安全な作業用コピーを作成するためのディスク容量が不足しています。',
    '안전한 작업용 복사본을 만들 디스크 공간이 부족합니다.',
  ],
  '当前实际音频容器暂不支持安全编辑标签；这不代表文件无法播放。原文件未被修改。': [
    'Safe tag editing is not yet supported for this audio container. This does not mean it cannot play. The original file was not changed.',
    'この音声コンテナーの安全なタグ編集には未対応です。再生できないことを意味するものではありません。元のファイルは変更されていません。',
    '이 오디오 컨테이너의 안전한 태그 편집은 아직 지원되지 않습니다. 재생할 수 없다는 뜻은 아닙니다. 원본 파일은 변경되지 않았습니다.',
  ],
  '当前标签编辑器无法完整读取此容器或标签组合，已保留原文件。': [
    'The tag editor cannot fully read this container or tag layout. The original file has been preserved.',
    'タグエディターはこのコンテナーまたはタグ構成を完全に読み取れません。元のファイルは保持されています。',
    '태그 편집기가 이 컨테이너 또는 태그 구성을 완전히 읽을 수 없습니다. 원본 파일은 보존되었습니다.',
  ],
  '这首歌曲的信息正在保存，请等待完成。': [
    'This track is already being saved. Please wait for it to finish.',
    'この曲の情報を保存中です。完了するまでお待ちください。',
    '이 곡의 정보를 저장 중입니다. 완료될 때까지 기다려 주세요.',
  ],
};
