"""Test the addon in isolation, then save and load a gameplay scene in another process.

Copies only addons/aero_cloth_3d. Generated projects/logs remain outside the repo.
No working-tree artifacts, Godot imports, or resource files are modified.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

PROJECT = """config_version=5
[application]
config/name="AeroCloth Clean Install QA"
[rendering]
renderer/rendering_method="gl_compatibility"
[editor_plugins]
enabled=PackedStringArray("res://addons/aero_cloth_3d/plugin.cfg")
[filesystem]
import/blender/enabled=false
"""

SAVE_SCRIPT = """extends SceneTree
const Factory=preload("res://addons/aero_cloth_3d/core/aero_example_factory.gd")
const Rig=preload("res://addons/aero_cloth_3d/core/aero_wearable_rig.gd")
func _initialize()->void:call_deferred("_run")
func _run()->void:
 var outfit:Resource=Factory.create()
 if outfit.character_scene!=null:
  push_error("Isolation fixture unexpectedly acquired a demo character")
  quit(1)
  return
 var scene_root:=Node3D.new()
 scene_root.name="GameplayRoot"
 root.add_child(scene_root)
 var rig:=Rig.new()
 rig.name="Wearables"
 scene_root.add_child(rig)
 var errors:PackedStringArray=rig.load_outfit(outfit)
 if not errors.is_empty():
  push_error("Clean standalone rig failed: "+"; ".join(errors))
  scene_root.queue_free()
  await process_frame
  quit(1)
  return
 if rig.slots.size()!=5:
  push_error("Standalone recipe did not register five wearable items")
  quit(1)
  return
 rig.outfit=outfit
 rig.owner=scene_root
 var packed:=PackedScene.new()
 var error:Error=packed.pack(scene_root)
 if error==OK:error=ResourceSaver.save(packed,"user://clean_gameplay.tscn")
 if error!=OK:
  push_error("Could not export gameplay scene: "+str(error))
  quit(1)
  return
 print("CLEAN_EXPORT_OK items=",rig.slots.size()," scene=",ProjectSettings.globalize_path("user://clean_gameplay.tscn"))
 scene_root.queue_free()
 await process_frame
 quit()
"""

LOAD_SCRIPT = """extends SceneTree
func _initialize()->void:call_deferred("_run")
func _run()->void:
 if Engine.is_editor_hint():
  push_error("Gameplay verification must run outside the editor")
  quit(1)
  return
 var packed:PackedScene=load("user://clean_gameplay.tscn")
 if packed==null:
  push_error("Exported scene was not readable in the gameplay process")
  quit(1)
  return
 var scene:Node=packed.instantiate()
 root.add_child(scene)
 var rig:Node=scene.get_node("Wearables")
 if not rig.errors.is_empty() or rig.slots.size()!=5:
  push_error("Exported gameplay rig did not initialize")
  quit(1)
  return
 var result:Dictionary=rig.controller.apply_hit({"hit_id":"clean-install-contact","item_id":"jacket","region_id":"body","uv":[.4,.4],"amount":15.0,"type":"slash","seed":71})
 if not result.get("accepted",false):
  push_error("Gameplay contact was rejected: "+str(result))
  quit(1)
  return
 var state:Dictionary=rig.controller.get_item_state(&"jacket")
 if state["regions"][&"body"]["stage"]!=1:
  push_error("Gameplay contact did not advance the persisted stage rules")
  quit(1)
  return
 if not rig.slots[&"jacket"]["visual"].material_override==null:
  push_error("Unexpected material override bypasses damage surfaces")
  quit(1)
  return
 var materials:Array=rig.slots[&"jacket"]["materials"]
 if materials.is_empty() or materials[0].get_shader_parameter("mask_texture")==null or float(materials[0].get_shader_parameter("cut_strength"))<=0:
  push_error("Gameplay stage did not reach the runtime damage material")
  quit(1)
  return
 print("CLEAN_GAMEPLAY_OK items=",rig.slots.size()," stage=",state["regions"][&"body"]["stage"]," editor_hint=",Engine.is_editor_hint())
 scene.queue_free()
 await process_frame
 quit()
"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--keep", action="store_true", help="Keep the isolated fixture after success")
    parser.add_argument("--addon", type=Path, help="Test an extracted release addon instead of the working tree")
    options = parser.parse_args()
    repository = Path(__file__).resolve().parents[1]
    temporary = Path(tempfile.mkdtemp(prefix="aerocloth-clean-install-"))
    project = temporary / "project"
    project.mkdir()
    addon = project / "addons/aero_cloth_3d"
    shutil.copytree(options.addon or repository / "addons/aero_cloth_3d", addon, ignore=shutil.ignore_patterns("__pycache__"))
    (project / "project.godot").write_text(PROJECT)
    (project / "save_gameplay.gd").write_text(SAVE_SCRIPT)
    (project / "load_gameplay.gd").write_text(LOAD_SCRIPT)
    environment = os.environ.copy()
    for name, folder in [("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")]:
        environment[name] = str(temporary / folder)
        (temporary / folder).mkdir()
    success = False
    try:
        # Runtime dependencies must not contain editor-only classes or demo files.
        forbidden = re.compile(r"\b(?:EditorInterface|EditorPlugin|EditorUndoRedoManager)\b")
        for directory in ("core", "resources"):
            for path in (addon / directory).glob("*.gd"):
                if forbidden.search(path.read_text()):
                    raise RuntimeError(f"Editor-only class in runtime dependency: {path.relative_to(addon)}")
        phases = [
            ("editor-import", ["--headless", "--editor", "--path", str(project), "--import", "--quit"], None),
            ("export", ["--headless", "--path", str(project), "--script", "save_gameplay.gd"], "CLEAN_EXPORT_OK"),
            ("gameplay", ["--headless", "--path", str(project), "--script", "load_gameplay.gd"], "CLEAN_GAMEPLAY_OK"),
        ]
        for name, arguments, expected in phases:
            result = subprocess.run([options.godot, *arguments], env=environment,
                                    capture_output=True, text=True, timeout=90)
            output = result.stdout + result.stderr
            (temporary / f"{name}.log").write_text(output)
            if result.returncode or re.search(r"(?m)^(?:SCRIPT ERROR|ERROR:)", output):
                raise RuntimeError(f"{name} failed (exit {result.returncode})\n{output[-18000:]}")
            if expected and expected not in output:
                raise RuntimeError(f"{name} did not confirm success\n{output[-18000:]}")
            print(f"CLEAN_INSTALL {name}: passed")
            if expected:
                print("\n".join(line for line in output.splitlines() if expected in line))
        success = True
        print("CLEAN_INSTALL_TESTS: addon-only editor import, scene export and separate gameplay process passed")
        return 0
    except (RuntimeError, subprocess.TimeoutExpired) as error:
        print(str(error))
        print(f"Clean-install diagnostics retained at {temporary}")
        return 1
    finally:
        if success and not options.keep:
            shutil.rmtree(temporary)
        elif success:
            print(f"Clean-install fixture retained at {temporary}")


if __name__ == "__main__":
    raise SystemExit(main())
