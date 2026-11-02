"""Build a clean source project ZIP. No import cache, credentials or repo metadata."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
import hashlib

root = Path(__file__).resolve().parents[1]
output = root / "artifacts/AeroCloth3D-0.2-hybrid.zip"
with ZipFile(output, "w", ZIP_DEFLATED) as archive:
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root)
        if not path.is_file() or any(p in {".git", ".godot", "__pycache__"} for p in relative.parts):
            continue
        if path.suffix in {".zip", ".log", ".tmp"} or path.name.endswith((".blend1", ".zip.sha256")):
            continue
        archive.write(path, Path("AeroCloth3D") / relative)
checksum = hashlib.sha256(output.read_bytes()).hexdigest()
(output.with_suffix(".zip.sha256")).write_text(f"{checksum}  {output.name}\n")
print(output, output.stat().st_size, "bytes", checksum)
