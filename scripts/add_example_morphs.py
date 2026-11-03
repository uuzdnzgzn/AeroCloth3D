"""Generate a separate authoring example; never edits the recovery asset.

Run: blender --background --python scripts/add_example_morphs.py
"""
from pathlib import Path
import math
import sys
import uuid
import bpy

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'demo/assets/authoring_character'
OUT.mkdir(parents=True,exist_ok=True)
sys.path.insert(0,str(ROOT/'blender_addon'))
import aerocloth_export as bridge

bpy.ops.wm.open_mainfile(filepath=str(ROOT/'demo/assets/recovery_character/character.blend'))
rig=next(o for o in bpy.data.objects if o.type=='ARMATURE')
skin=next(o for o in bpy.data.objects if o.type=='MESH' and o.find_armature()==rig)
for track in rig.animation_data.nla_tracks:
    track.mute=True
for pose in rig.pose.bones:
    pose.rotation_euler=(0,0,0)
    pose.location=(0,0,0)

# Add an actual covered skin torso so compression and garment fitting have
# independent morph targets. Existing shirt remains outside this skin surface.
rings=[(.97,.135,.077),(1.08,.145,.085),(1.27,.188,.095),(1.40,.196,.090),(1.445,.150,.074)]
vertices=[(math.cos(i*math.tau/12)*rx,math.sin(i*math.tau/12)*ry,z)
          for z,rx,ry in rings for i in range(12)]
faces=[]
for row in range(len(rings)-1):
    for i in range(12):
        a=row*12+i
        b=row*12+(i+1)%12
        faces.append((a,b,b+12,a+12))
faces.extend([tuple(reversed(range(12))),tuple((len(rings)-1)*12+i for i in range(12))])
mesh=bpy.data.meshes.new('CompressionBodySurface')
mesh.from_pydata(vertices,[],faces)
mesh.update()
body=bpy.data.objects.new('CompressionBodySurface',mesh)
bpy.context.collection.objects.link(body)
material=next(m for m in bpy.data.materials if m.name.startswith('Warm skin')).copy()
material.name='Compression body'
body.data.materials.append(material)
body.vertex_groups.new(name='Chest').add(list(range(len(vertices))),1.0,'REPLACE')
bpy.ops.object.select_all(action='DESELECT')
skin.select_set(True)
body.select_set(True)
bpy.context.view_layer.objects.active=skin
bpy.ops.object.join()
skin.name='AuthoringCharacterMesh'

body_vertices=set()
shirt_vertices=set()
for polygon in skin.data.polygons:
    name=skin.data.materials[polygon.material_index].name
    if name=='Compression body':
        body_vertices.update(polygon.vertices)
    if name.startswith('Base shirt'):
        shirt_vertices.update(polygon.vertices)
skin.shape_key_add(name='Basis')
compression=skin.shape_key_add(name='ChestCompression')
fit=skin.shape_key_add(name='FitCompression')
for vertex in skin.data.vertices:
    x,y,z=vertex.co
    envelope=max(0.0,1.0-abs(z-1.25)/.29)
    if vertex.index in body_vertices:
        compression.data[vertex.index].co.x=x*(1-.10*envelope)
        compression.data[vertex.index].co.y=y*(1-.28*envelope)
    if vertex.index in shirt_vertices and abs(x)<.235 and .96<z<1.46:
        fit.data[vertex.index].co.x=x*(1-.10*envelope)
        fit.data[vertex.index].co.y=y*(1-.28*envelope)

for group_name,indices in [('ac_region_body',body_vertices),('ac_region_torso',body_vertices|shirt_vertices),('ac_region_garment',shirt_vertices)]:
    skin.vertex_groups.new(name=group_name).add(sorted(indices),1.0,'REPLACE')
skin['ac_role']='body_outfit'
skin['ac_id']=str(uuid.uuid5(uuid.NAMESPACE_URL,'AeroCloth3D/authoring/character_mesh'))
rig['ac_id']=str(uuid.uuid5(uuid.NAMESPACE_URL,'AeroCloth3D/authoring/rig'))

if not skin.data.uv_layers:
    skin.data.uv_layers.new(name='BaseUV')
while len(skin.data.uv_layers)>1:
    skin.data.uv_layers.remove(skin.data.uv_layers[-1])
damage_uv=skin.data.uv_layers.new(name='DamageUV')
skin.data.uv_layers.active=damage_uv
bpy.context.view_layer.objects.active=skin
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=math.radians(66),island_margin=.006)
bpy.ops.object.mode_set(mode='OBJECT')
skin.data.uv_layers.active_index=0

for index,point in enumerate([(-.11,-.13,1.40),(.11,-.13,1.40)]):
    empty=bpy.data.objects.new(f'ChestConnection{index+1}',None)
    bpy.context.collection.objects.link(empty)
    empty.location=point
    empty.empty_display_size=.025
    empty['ac_id']=str(uuid.uuid5(uuid.NAMESPACE_URL,f'AeroCloth3D/authoring/connection/{index}'))
    empty['ac_role']='connection'
    empty['ac_item_id']=skin['ac_id']
    empty['ac_region_id']='torso'
    empty['ac_bone']='Chest'

bpy.ops.object.select_all(action='DESELECT')
for obj in bpy.context.scene.objects:
    if obj.type in {'MESH','ARMATURE','EMPTY'}:
        obj.select_set(True)
bpy.context.view_layer.objects.active=rig
metadata=bridge.export_bundle(bpy.context,str(OUT),'character')
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'character.blend'))
print('AEROCLOTH_AUTHORING_EXAMPLE',len(skin.data.vertices),'vertices',list(skin.data.shape_keys.key_blocks.keys()),'UV2',bridge.damage_uv_report(skin)['status'])
