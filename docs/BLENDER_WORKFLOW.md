# Blender preparation and export bridge

Implemented Blender addon source: `blender_addon/aerocloth_export/__init__.py`.
Tested on Blender 4.3.2. Blender 5.2.3 compatibility is not verified.

## Installation and operation

Install the `aerocloth_export` folder as a conventional Blender addon, or package
that folder into a ZIP with `aerocloth_export/__init__.py` at its root. Enable
**AeroCloth Preparation** in preferences. Open 3D View → Sidebar → AeroCloth.

1. Select the character/garment meshes. Needed armatures are included automatically.
2. **Prepare stable IDs** creates persistent `ac_id` UUID custom properties.
   Existing unique IDs are kept; duplicate IDs inside the export set get new IDs.
   This explicit operator supports Blender Undo and does not change geometry.
3. Mark optional regions with vertex groups named `ac_region_<region_id>`.
   Use `ac_role=proxy` for simulation surfaces or `ac_role=rigid` for unskinned
   rigid pieces. Default mesh role is `garment`.
4. Provide a second UV layer for local damage. It must be inside 0..1 and have
   no positive-area triangle overlap. Material UV0 and damage UV2 are separate.
5. Connection empties use `ac_role=connection`, `ac_source_item`,
   `ac_source_region` and optional `ac_bone` custom properties. Existing
   `ac_item_id` / `ac_region_id` are accepted aliases; explicit source names win.
6. **Validate preparation** reports missing/duplicate IDs, missing rigs, missing
   or non-normalized bone weights, region absence and damage UV issues.
7. Choose directory/asset name and **Export GLB + AeroCloth metadata**.

**Prepare damage UV on garment copies** creates separate mesh data, keeps UV0
and shape keys, and runs Smart UV Project into the second UV channel. Inspect
islands and padding; validation reports any remaining positive-area overlap.

**Suggest rest-pose fit on garment copies** projects toward the chosen body's
basis surface. Defaults: search 0.10 m, movement clamp 0.02 m, clearance 0.003 m.
An optional region group limits the displacement. The same displacement is
applied to all copied shape keys so their relative deltas survive. This is a
bounded rest-pose suggestion, not cloth simulation or guaranteed animation fit.

Missing IDs, invalid rigging and weights block export before any export output is
written. Missing/invalid damage UV or absent regions produce warnings: the GLB
can still be useful, but local damage painting must be prepared/fixed in Godot.
UV validation triangulates the source mesh and tests triangle intersection area;
shared UV edges are allowed. It is not a texel padding or mip-bleed validator.

The exporter preserves original geometry, weights, selection, active object and
NLA track mute settings. It temporarily unmutes NLA tracks for GLB animation
export. Exported source mesh vertex/face/UV fingerprints are recorded so Godot
can detect stale bindings after re-export. They are hashes of Blender source
data, **not** of glTF's reordered/split vertices. Modifiers that change topology
require explicit baking/rebinding; a hash match is not a universal fit guarantee.

## Weight transfer

Choose a rigged **Weight source body**, select one or more garments, optionally
name an existing target **region group**, then use **Transfer weights to garment
copies**. It creates separate objects and mesh data, transfers deform-bone weights
by Blender's nearest-face interpolation, and assigns the source armature.

With a region group, original and transferred weights are blended by that group's
weight. Region masks themselves are not transferred from the body. Shape keys
on the garment copy are retained. Original source and garment geometry/weights
are untouched. The copies are selected for inspection and the operation supports
Undo. The operation transfers skinning weights; it does not shrinkwrap the garment,
create new shape keys, or guarantee fit around intersecting body parts.

Always validate afterward and inspect representative animations. A copied garment
with no original weights outside a masked region may still need those areas rigged.

## Metadata contract

`<name>.aerocloth.json` contains:

- `schema: "AeroCloth3D.blender"`, `version: 1`, `source_glb`, `glb_sha256`.
- Object `id`, `name`, `type`, `role`, source-space `matrix_world`.
- Armature bone names, parent names, deform flags and source-space rest matrices.
- Mesh source `topology_fingerprint`, vertex/polygon counts, armature ID,
  sparse region weights, shape key names and detailed damage UV report.
- Connection item/region/bone references.

Matrices are **Blender Z-up**; the GLB exporter changes GLB coordinates to Y-up.
Importers must convert metadata coordinates once. Stable IDs are also stored in
GLB extras. Name and vertex ordering are not stable identifiers across exports.
`glb_sha256` hashes the exact exported GLB bytes after export, so importers can
reject an outdated metadata/GLB pair before using binding metadata.

## Tests and example

```sh
blender --background --python-exit-code 1 --python scripts/add_example_morphs.py
blender --background --python-exit-code 1 --python scripts/test_blender_bridge.py
```

The new `demo/assets/authoring_character` contains an editable `.blend`, GLB and
metadata. `ChestCompression` changes a covered skin torso; `FitCompression`
changes its shirt. Godot 4.6.3 reads both channels and the Idle/Walk animations.

The Blender smoke test passed **40 checks** on Blender 4.3.2. It exercises registration/unregistration, actual GLB/JSON
export, source fingerprint preservation, morph and animation export, real UV
overlap primitives, invalid-export rejection, and copied weight transfer with
region restriction and preserved morphs. The optional missing Draco library
warning is unrelated to this uncompressed export path.
