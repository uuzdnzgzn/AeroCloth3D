# Authoring character: compression and fit example

Original procedural test asset, derived from this repository's CC0 recovery
character. It is **not** the missing DanlyVostok Cyberstyle character. Geometry,
materials and animations here are CC0 1.0, to the extent possible under law.

Reproduce with Blender:

```sh
blender --background --python scripts/add_example_morphs.py
```

The script opens the recovery `.blend` read-only in memory and writes this new
folder; it never saves over the recovery source. It adds a covered skin torso,
regions, non-overlapping damage UV2 and two independent shape keys:

- `ChestCompression`: compresses the covered skin torso, leaving shirt vertices
  unchanged. The shape is intentionally stylized and modest.
- `FitCompression`: the matching prepared compression of the chest shirt,
  leaving skin vertices unchanged.

At full compression, drive **both** channels to 1. At rest both are 0. Derive
weights from currently equipped effects, rather than accumulating deltas when
items are added and removed. These are a single prepared fit example, not an
automatic fitting algorithm. Damage topology and cloth tearing are not part of
this character mesh; those belong to the separate garment preparation resources.

Runtime contract:

- Godot/glTF Y up, front +Z; source Blender Z up, front -Y.
- One skinned mesh, 2,320 source vertices, 20 bones, 11 material surfaces.
- Godot mesh path relative to character root:
  `RecoveryRig/Skeleton3D/AuthoringCharacterMesh`.
- Blend shape names are exactly `ChestCompression` and `FitCompression`.
- Imported Idle and Walk animations are preserved.
- `ac_region_body`, `ac_region_torso`, `ac_region_garment` vertex groups are
  exported in the JSON metadata as sparse per-vertex weights.
- Two authored Chest connection empties are examples; they are not physical
  joints until the Godot runtime attaches them to prepared item definitions.
- `character.aerocloth.json` is schema version 1. Its matrices remain Blender
  source-space matrices; GLB data is converted to glTF space by Blender.
- `glb_sha256` in the JSON matches the exact companion GLB bytes; stale pairs
  must be rejected before bindings are used.
- Stable object IDs are also present in glTF node extras, imported by Godot
  under the `extras` metadata dictionary.

Verified with Blender **4.3.2** and Godot **4.6.3**. The target Blender 5.2.3 and
Godot 4.7.2 have not been tested here. A missing optional Draco library warning
is emitted by the distro Blender exporter, but export uses uncompressed GLB.
