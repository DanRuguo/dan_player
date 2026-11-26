"""Assemble the pinned slim audio FFmpeg optional component archive deterministically."""
import hashlib
import json
import pathlib
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
STEM = "DanPlayer-FFmpeg-7.1.1-audio-windows-x64"


def build(destination: pathlib.Path, runtime_dir: pathlib.Path | None = None):
    manifest = json.loads((ROOT / "scripts/ffmpeg_runtime_manifest.json").read_text(encoding="utf-8"))
    source_dir = runtime_dir or (ROOT.parent / "tool/ffmpeg-7.1.1/runtime")
    if not source_dir.is_dir():
        raise FileNotFoundError(f"Missing pinned FFmpeg runtime directory: {source_dir}")

    files: dict[str, bytes] = {}
    manifest_entries = manifest["Files"]
    for entry in manifest_entries:
        name = entry["Name"]
        if pathlib.PurePosixPath(name).name != name or name in files:
            raise ValueError(f"Unsafe or duplicate FFmpeg entry: {name}")
        file_path = source_dir / name
        if not file_path.is_file() or file_path.is_symlink():
            raise ValueError(f"Invalid FFmpeg runtime file: {file_path}")
        content = file_path.read_bytes()
        digest = hashlib.sha256(content).hexdigest()
        if len(content) != entry["Size"] or digest.lower() != entry["Sha256"].lower():
            raise ValueError(f"FFmpeg runtime hash/size mismatch for {name}")
        files[name] = content

    destination.mkdir(parents=True, exist_ok=True)
    archive = destination / f"{STEM}.zip"
    checksum_file = destination / f"{STEM}.zip.sha256"
    if archive.exists() or checksum_file.exists():
        raise ValueError("Use a new destination; previous FFmpeg module artifacts are retained")

    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for name in sorted(files):
            info = zipfile.ZipInfo(name, date_time=(2000, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            zf.writestr(info, files[name], compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)

    archive_bytes = archive.read_bytes()
    archive_sha256 = hashlib.sha256(archive_bytes).hexdigest()
    checksum_file.write_text(f"{archive_sha256}  {archive.name}\n", encoding="ascii")

    with zipfile.ZipFile(archive, "r") as check:
        if check.testzip() is not None or set(check.namelist()) != set(files):
            raise ValueError("FFmpeg module ZIP integrity check failed")
        for name, content in files.items():
            if check.read(name) != content:
                raise ValueError(f"FFmpeg module ZIP content mismatch: {name}")

    print(json.dumps({
        "path": str(archive),
        "checksumPath": str(checksum_file),
        "bytes": len(archive_bytes),
        "sha256": archive_sha256,
        "entries": len(files),
        "version": manifest["Version"],
    }, ensure_ascii=False))


if __name__ == "__main__":
    dest = pathlib.Path(sys.argv[1])
    rt = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else None
    build(dest, rt)
