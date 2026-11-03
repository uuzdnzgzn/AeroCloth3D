"""Build a clean source project ZIP. No import cache, credentials or repo metadata."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
import hashlib

root = Path(__file__).resolve().parents[1]
output = root / "artifacts/AeroCloth3D-0.3-authoring.zip"
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

def package_folder(folder, target, prefix, skip=()):
    with ZipFile(target, "w", ZIP_DEFLATED) as archive:
        for path in sorted(folder.rglob("*")):
            if not path.is_file() or "__pycache__" in path.parts or path.name in skip:
                continue
            archive.write(path, Path(prefix) / path.relative_to(folder))
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    target.with_suffix(".zip.sha256").write_text(f"{digest}  {target.name}\n")
    print(target, target.stat().st_size, "bytes", digest)

package_folder(root / "addons/aero_cloth_3d", root / "artifacts/AeroCloth3D-0.3-godot-addon.zip",
               "addons/aero_cloth_3d", ("aero_cloth_workspace.gd", "aero_cloth_workspace.gd.uid"))
package_folder(root / "blender_addon/aerocloth_export", root / "artifacts/AeroCloth3D-0.3-blender-addon.zip",
               "aerocloth_export", (".gitignore",))
