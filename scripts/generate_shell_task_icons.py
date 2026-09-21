"""Generate neutral Jump List ICOs from the same Material Symbols as the tray.
Requires Pillow and the restored material_symbols_icons dependency (Apache-2.0).
Ordinary builds use the committed ICOs and do not require Python.
"""
import json
import re
from pathlib import Path
from urllib.parse import unquote, urlparse
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / ".dart_tool/package_config.json"
entry = next(p for p in json.loads(CONFIG.read_text())["packages"]
             if p["name"] == "material_symbols_icons")
uri = urlparse(entry["rootUri"])
package = Path(unquote(uri.path).lstrip("/") if uri.scheme == "file" else CONFIG.parent / entry["rootUri"])
source = (package / "lib/symbols.dart").read_text(encoding="utf-8")
font = ImageFont.truetype(str(package / "lib/fonts/MaterialSymbolsOutlined.ttf"), 160)
for task, name in {"window": "open_in_new", "mini": "picture_in_picture_alt",
                   "play": "play_arrow", "previous": "skip_previous", "next": "skip_next"}.items():
    code = re.search(r"static const IconData " + name + r"\s*=\s*IconData\((0x[0-9a-fA-F]+)", source)
    glyph = chr(int(code[1], 16))
    image = Image.new("RGBA", (192, 192))
    draw = ImageDraw.Draw(image)
    left, top, right, bottom = draw.textbbox((0, 0), glyph, font=font)
    draw.text(((192-right+left)/2-left, (192-bottom+top)/2-top), glyph, font=font, fill=(85,85,85,255))
    image.save(ROOT / f"windows/runner/resources/task_{task}.ico", sizes=[(n,n) for n in (16,24,32,48,64)])
