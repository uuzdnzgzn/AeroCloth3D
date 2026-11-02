# Recovery test character

This is an original procedural **test asset**, generated for AeroCloth3D. It is
not the Cyberstyle character by DanlyVostok and is not a recovered copy of that
character. No third-party mesh, texture, or animation is included in this folder.

The previous session's `lowpoly_anime_character_cyberstyle.zip` was unavailable in
the replacement workspace. On 2026-11-02, Sketchfab's official model-download API
for `9c284506f1e247348acd0de4151974d6` returned HTTP 401 (authentication required).
No viewer assets were scraped. The user's original CC BY 4.0 model attribution
must be restored alongside the model when the original archive becomes available:

> “Lowpoly Anime Character Cyberstyle” by DanlyVostok, CC BY 4.0.
> https://sketchfab.com/3d-models/lowpoly-anime-character-cyberstyle-9c284506f1e247348acd0de4151974d6

## Rebuild

Run from the project directory:

```sh
blender --background --python scripts/create_character.py
```

The script writes `character.glb` and editable `character.blend` without downloads,
textures, plugins, or other dependencies. Generated and tested with Blender 4.3.2;
Blender 5.2.3 compatibility has not been tested. The optional Blender Draco
compression library is not required; the exported GLB is uncompressed.

## Runtime contract

- Godot / glTF coordinates: Y up, front **+Z**, feet at ground level.
- Mesh AABB: position `(-0.438, 0.009, -0.141)`, size `(0.876, 1.825, 0.309)` metres.
- One skinned mesh, 2,260 source vertices, 10 material surfaces, 20 bones.
- AnimationPlayer actions: `Idle` (48 frames / 24 fps), `Walk` (32 frames / 24 fps).
  Runtime code should set `loop_mode = Animation.LOOP_LINEAR` for looping playback.
- No root motion. The fitted shirt, trousers, belt, boots, hair and facial details
  are part of the base mesh. Additional damage-test wearables are separate assets.
- No morphs or automatic garment fitting are present.

Bone names:

```text
Root
  Hips
    Spine
      Chest
        Neck
          Head
        Shoulder_R
          UpperArm_R
            Forearm_R
              Hand_R
        Shoulder_L
          UpperArm_L
            Forearm_L
              Hand_L
    Thigh_R
      Shin_R
        Foot_R
    Thigh_L
      Shin_L
        Foot_L
```

Important rest origins in character space: `Chest = (0, 1.25, 0)`,
`Shoulder_R = (0, 1.412, 0)`, `UpperArm_R = (-0.213, 1.411, 0)`.
Chest has an identity rest basis. Arm and shoulder bases follow their bone axes;
their local offsets are not character-space offsets. To animate an anchor authored
in character space, apply `current_pose * inverse(global_rest) * anchor`.

Imported and instantiated in **Godot 4.6.3**: skeleton, bounds and both animation
names verified. Godot 4.7.2 compatibility remains untested.

## License

The procedural character geometry, materials and animations in this folder are
dedicated to the public domain under CC0 1.0, to the extent possible under law.
https://creativecommons.org/publicdomain/zero/1.0/

The generator source is `scripts/create_character.py`; project code licensing
is separate from the asset dedication above. No attribution to DanlyVostok is required for this new
procedural asset; the separate attribution above describes only the missing
original Cyberstyle model.
