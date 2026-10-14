"""Assemble the pinned optional dictionary data without a player build."""
import hashlib
import json
import pathlib
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
STEM = "DanPlayer-JapaneseReadings-IPADIC-6.2.0"


def build(destination: pathlib.Path):
    catalog = json.loads((ROOT / "scripts/support/bundled_japanese_readings.json").read_text())
    resource = catalog["resource"]
    data = (ROOT / resource["path"]).read_bytes()
    if len(data) != resource["bytes"] or hashlib.sha256(data).hexdigest() != resource["sha256"]:
        raise ValueError("Dictionary differs from pinned source")
    files = {"ipadic-reading.bin.gz": data}
    supplements = []
    for extra in catalog['supplements']:
        name = pathlib.PurePosixPath(extra['path']).name
        if name not in ('supplemental-reading-v1.json.gz', 'kanji-reading-v1.json.gz') or name in files:
            raise ValueError('Unsafe or duplicate supplemental resource')
        original = (ROOT / extra['path']).read_bytes()
        if extra['embedded'] or len(original) != extra['bytes'] or hashlib.sha256(original).hexdigest() != extra['sha256']:
            raise ValueError('Supplemental readings differ from pinned source')
        files[name] = original
        supplements.append(dict(name=name, bytes=len(original), sha256=extra['sha256'], entries=extra['entries']))
    for notice in catalog["notices"]:
        original = (ROOT / notice["path"]).read_bytes()
        if hashlib.sha256(original).hexdigest() != notice["sha256"]:
            raise ValueError("License differs from pinned original")
        files[notice["path"]] = original
    files["licenses/IPADIC/PROVENANCE.md"] = (ROOT / "licenses/IPADIC/PROVENANCE.md").read_bytes()
    files["licenses/EDRDG/PROVENANCE.md"] = (ROOT / "licenses/EDRDG/PROVENANCE.md").read_bytes()
    files["MODULE.json"] = (json.dumps({"schemaVersion": 2, "engine": catalog["engine"],
        "resource": {"name": "ipadic-reading.bin.gz", "bytes": len(data), "sha256": resource["sha256"]},
        "supplements": supplements},
        ensure_ascii=False, indent=2) + "\n").encode()
    files["README.txt"] = ("Dan Player optional offline Japanese reading dictionary\n\n"
        "Install using the player's Japanese reading component prompt, or extract\n"
        "this entire ZIP into tool/japanese_readings beside Dan Player.exe and click\n"
        "the installed-component check. No executable is included.\n\n"
        "IPADIC, JMdict/KANJIDIC2 readings and license notices stay separate from the player.\n"
        "The updated data module needs a player supporting EDRDG reading 2026-10-14.\n"
        "Generated readings are cached separately and do not edit source lyrics.\n").encode()
    destination.mkdir(parents=True, exist_ok=True)
    archive = destination / (STEM + ".zip")
    if archive.exists() or (destination / (STEM + '.sha256')).exists():
        raise ValueError('Use a new destination; previous module artifacts are retained')
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_STORED) as output:
        for name, content in sorted(files.items()):
            entry = zipfile.ZipInfo(name, date_time=(2000, 1, 1, 0, 0, 0))
            entry.external_attr = 0o100644 << 16
            output.writestr(entry, content)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    (destination / (STEM + ".sha256")).write_text(f"{digest} *{archive.name}\n", encoding="ascii")
    with zipfile.ZipFile(archive) as check:
        if check.testzip() is not None or set(check.namelist()) != set(files):
            raise ValueError('Module ZIP integrity mismatch')
        for name, content in files.items():
            if check.read(name) != content:
                raise ValueError('Module ZIP source bytes mismatch')
    print(json.dumps({"path": str(archive), "bytes": archive.stat().st_size,
        "sha256": digest, "entries": len(files), "dataOnly": True,
        "files": {name: dict(bytes=len(content), sha256=hashlib.sha256(content).hexdigest())
                  for name, content in files.items()}}, ensure_ascii=False))


if __name__ == "__main__":
    build(pathlib.Path(sys.argv[1]))
