/// Tray-only additions. Order: English, Japanese, Korean.
const Map<String, List<String>> uiCatalogTray = {
  '托盘菜单高斯模糊': ['Tray menu Gaussian blur', 'トレイメニューのガウスぼかし', '트레이 메뉴 가우시안 흐림'],
  '模糊半径：{0} 逻辑像素': [
    'Blur radius: {0} logical pixels',
    'ぼかし半径：{0} 論理ピクセル',
    '흐림 반경: {0} 논리 픽셀'
  ],
  '调整真实高斯模糊半径，不改变透明度。0 表示关闭；下次打开菜单时生效。': [
    'Adjusts the actual Gaussian blur radius, not transparency. 0 means off; applies the next time the menu opens.',
    '透明度ではなく、実際のガウスぼかし半径を調整します。0 は無効です。次にメニューを開いたときに適用されます。',
    '투명도가 아닌 실제 가우시안 흐림 반경을 조절합니다. 0은 끄기이며, 다음에 메뉴를 열 때 적용됩니다.'
  ],
  '仅使用打开菜单时该菜单范围内的静态背景，关闭即释放，不保存图像。高对比度、透明效果关闭、节能或不可用时自动使用纯色。': [
    'Uses a static background from only the menu area when opened, released on close and never saved. Falls back to a solid color for high contrast, disabled transparency, energy saver, or unavailable effects.',
    'メニューを開いた瞬間のメニュー範囲内の背景のみを使用し、閉じると解放します。画像は保存しません。ハイコントラスト、透明効果の無効、省エネ、または利用不可の場合は単色に切り替わります。',
    '메뉴를 열 때 메뉴 영역의 정적 배경만 사용하며, 닫으면 해제하고 이미지를 저장하지 않습니다. 고대비, 투명 효과 끄기, 절전 또는 효과 사용 불가 시 단색으로 표시합니다.'
  ],
};
