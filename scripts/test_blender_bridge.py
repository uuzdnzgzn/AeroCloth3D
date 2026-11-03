"""Blender-side meaningful bridge smoke tests. Run with Blender --background --python."""
from pathlib import Path
import json
import sys
import tempfile
import struct
import hashlib
import bpy

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'blender_addon'))
import aerocloth_export as addon

checks=0
def check(value,message):
    global checks
    checks+=1
    if not value:
        raise AssertionError(message)

addon.register()
check(hasattr(bpy.context.scene,'aerocloth_settings'),'Addon registers scene settings')
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'demo/assets/authoring_character/character.blend'))
mesh=next(o for o in bpy.context.scene.objects if o.type=='MESH')
rig=mesh.find_armature()
check(rig is not None,'Example is rigged')
check({'ChestCompression','FitCompression'}<=set(mesh.data.shape_keys.key_blocks.keys()),'Both morph channels exist')
for name in ['ChestCompression','FitCompression']:
    check(any((v.co-mesh.data.vertices[i].co).length>1e-6 for i,v in enumerate(mesh.data.shape_keys.key_blocks[name].data)),name+' changes geometry')
check(addon.damage_uv_report(mesh)['status']=='valid','Damage UV2 passes real overlap test')
objects=addon.selected_export_objects(bpy.context)
check(addon.validate_objects(objects)['valid'],'Example preparation validates')
before=addon.topology_fingerprint(mesh)
with tempfile.TemporaryDirectory(prefix='aerocloth-bridge-') as directory:
    metadata=addon.export_bundle(bpy.context,directory,'smoke')
    check(addon.topology_fingerprint(mesh)==before,'Export does not change source topology/UV')
    saved=json.loads((Path(directory)/'smoke.aerocloth.json').read_text())
    check(saved['version']==1 and saved['schema']=='AeroCloth3D.blender','Metadata schema version')
    check(saved['source_glb']=='smoke.glb','Metadata names exported GLB')
    records=[o for o in saved['objects'] if o['type']=='MESH']
    check(records[0]['topology_fingerprint']==before,'Stable source fingerprint serialized')
    check(len(records[0]['regions'])>=3,'Prepared regions serialize vertex weights')
    check(len([o for o in saved['objects'] if o.get('connection')])==2,'Connection empties serialize metadata')
    connection=next(o for o in objects if o.type=='EMPTY' and o.get('ac_role')=='connection')
    legacy_item=connection['ac_item_id']
    connection['ac_item_id']='legacy-value-must-not-win'
    connection['ac_source_item']=mesh['ac_id']
    connection['ac_source_region']='body'
    explicit=next(o['connection'] for o in addon.build_metadata(objects,'smoke.glb')['objects'] if o['id']==connection['ac_id'])
    check(explicit['item_id']==mesh['ac_id'] and explicit['region_id']=='body','Explicit connection source fields override legacy aliases')
    connection['ac_item_id']=legacy_item
    del connection['ac_source_item']
    del connection['ac_source_region']
    blob=(Path(directory)/'smoke.glb').read_bytes()
    check(saved['glb_sha256']==hashlib.sha256(blob).hexdigest(),'Metadata matches exact exported GLB content')
    length,kind=struct.unpack_from('<II',blob,12)
    gltf=json.loads(blob[20:20+length])
    check(gltf['asset']['version']=='2.0','GLB is valid glTF2')
    targets={name for m in gltf['meshes'] for name in m.get('extras',{}).get('targetNames',[])}
    check({'ChestCompression','FitCompression'}<=targets,'Morph channels reach GLB')
    check({'Idle','Walk'}<={a['name'] for a in gltf.get('animations',[])},'Animations reach GLB')
    old_id=mesh['ac_id']
    del mesh['ac_id']
    check(not addon.validate_objects(objects)['valid'],'Missing IDs rejected')
    invalid_output=Path(directory)/'invalid'
    try:
        addon.export_bundle(bpy.context,str(invalid_output),'invalid')
        check(False,'Invalid export should throw')
    except ValueError:
        check(not invalid_output.exists(),'Invalid preparation writes no export files')
    mesh['ac_id']=old_id

# Overlapping UV triangles must be detected; shared edge contact is not overlap.
check(addon._intersection_area([(0,0),(1,0),(0,1)],[(0,0),(1,0),(0,1)])>.49,'UV overlap geometric check')
check(addon._intersection_area([(0,0),(1,0),(0,1)],[(1,0),(1,1),(0,1)])<1e-9,'Shared UV edge allowed')

# Explicit transfer creates a new garment mesh; source and target originals survive.
bpy.ops.object.select_all(action='DESELECT')
target=mesh.copy()
target.data=mesh.data.copy()
bpy.context.collection.objects.link(target)
target.name='TransferSmokeGarment'
target.select_set(True)
target['ac_id']='temporary-target'
settings=bpy.context.scene.aerocloth_settings
settings.body=mesh
settings.region_mask='ac_region_garment'
mask=target.vertex_groups[settings.region_mask]
def region_weight(vertex):
    return next((w.weight for w in vertex.groups if w.group==mask.index),0.0)
inside=next(v.index for v in target.data.vertices if region_weight(v)>.99 and .96<v.co.z<1.42 and abs(v.co.x)<.2)
outside=next(v.index for v in target.data.vertices if region_weight(v)<.01)
bone_names={b.name for b in rig.data.bones if b.use_deform}
for group in target.vertex_groups:
    if group.name in bone_names:
        group.remove([inside,outside])
target.vertex_groups['Head'].add([inside],1.0,'REPLACE')
target.vertex_groups.new(name='Root').add([outside],1.0,'REPLACE')
original_groups={g.name:[next((w.weight for w in v.groups if w.group==g.index),0.0) for v in target.data.vertices] for g in target.vertex_groups}
result=bpy.ops.aerocloth.transfer_weights_copy()
check(result=={'FINISHED'},'Weight transfer operator succeeds with morph-bearing garment')
copy=bpy.context.view_layer.objects.active
check(copy is not target and copy.data is not target.data,'Transfer uses separate object and mesh')
check(addon.topology_fingerprint(target)==before,'Original target topology unchanged')
check(all(original_groups[g.name]==[next((w.weight for w in v.groups if w.group==g.index),0.0) for v in target.data.vertices] for g in target.vertex_groups),'Original target weights unchanged')
check(copy.get('ac_id')!=target.get('ac_id'),'Transferred copy has its own identity')
check(copy.data.shape_keys and 'FitCompression' in copy.data.shape_keys.key_blocks,'Transfer preserves copied morphs')
check(copy.vertex_groups['Head'].weight(inside)<.01,'Inside region receives body weights rather than old Head weight')
check(copy.vertex_groups['Root'].weight(outside)>.99,'Outside region retains its original Root weight')
# UV generation works on a new copy and preserves material UV0 and morphs.
source=copy
source_uv0=[tuple(loop.uv) for loop in source.data.uv_layers[0].data]
source_hash=addon.topology_fingerprint(source)
result=bpy.ops.aerocloth.damage_uv_copies()
uv_copy=bpy.context.view_layer.objects.active
check(result=={'FINISHED'} and uv_copy is not source,'Damage UV operator creates a new copy')
check(source_hash==addon.topology_fingerprint(source),'UV preparation leaves original data unchanged')
check(source_uv0==[tuple(loop.uv) for loop in uv_copy.data.uv_layers[0].data],'UV0 material coordinates survive automatic UV2 generation')
check(addon.damage_uv_report(uv_copy)['status']=='valid','Generated damage UV has no positive-area overlap')
check('FitCompression' in uv_copy.data.shape_keys.key_blocks,'UV copy keeps shape keys')
# Bounded fit keeps the source and relative shape-key deltas intact.
fit_source=uv_copy
fit_before=[v.co.copy() for v in fit_source.data.vertices]
relative=[v.co-fit_source.data.shape_keys.key_blocks[0].data[i].co for i,v in enumerate(fit_source.data.shape_keys.key_blocks['FitCompression'].data)]
settings.region_mask=''
result=bpy.ops.aerocloth.fit_copies()
fitted=bpy.context.view_layer.objects.active
check(result=={'FINISHED'} and fitted is not fit_source,'Fit operates on a new garment')
check(all((v.co-fit_before[i]).length<1e-7 for i,v in enumerate(fit_source.data.vertices)),'Fit leaves original garment unchanged')
check(all((v.co-fit_before[i]).length<=settings.fit_limit+1e-6 for i,v in enumerate(fitted.data.vertices)),'Fit displacement is bounded')
check(all(((v.co-fitted.data.shape_keys.key_blocks[0].data[i].co)-relative[i]).length<1e-6 for i,v in enumerate(fitted.data.shape_keys.key_blocks['FitCompression'].data)),'Fit preserves relative morph offsets')
addon.unregister()
check(not hasattr(bpy.context.scene,'aerocloth_settings'),'Addon unregisters cleanly')
print(f'BLENDER_BRIDGE_TESTS: {checks} checks, 0 failures')
