"""Build small fitted/weighted trial garments on Neutral_F. Originals untouched."""
import bpy, math, json, sys
from pathlib import Path
from mathutils import Vector
from mathutils.kdtree import KDTree
root=Path(__file__).resolve().parents[1]; out=root/'demo/wardrobe_trial'
source=Path(sys.argv[sys.argv.index('--')+1]) if '--' in sys.argv else Path('/workspace/art/characters/reallusion_neutral_f/Neutral_F_sword_trial.blend')
bpy.ops.wm.open_mainfile(filepath=str(source))
rig=next(o for o in bpy.data.objects if o.type=='ARMATURE'); body=bpy.data.objects['CC_Base_Body']
rig.animation_data_clear()
for p in rig.pose.bones: p.matrix_basis.identity()
bpy.context.view_layer.update()
kdt=KDTree(len(body.data.vertices))
for v in body.data.vertices:kdt.insert(body.matrix_world@v.co,v.index)
kdt.balance()
garments=[]; report={}
for name,zs,rx,ry,color in [('shirt',[.97,1.10,1.25,1.38,1.46],[.235,.21,.245,.26,.215],[.165,.16,.185,.195,.16],(.18,.48,.48,1)),('corset',[1.0,1.1,1.23],[.245,.22,.25],[.175,.17,.195],(.36,.15,.08,1)),('collar',[1.44,1.49,1.53],[.225,.15,.10],[.17,.12,.095],(.55,.32,.12,1))]:
 verts=[]; faces=[]; n=24
 for j,z in enumerate(zs):
  for i in range(n):
   a=2*math.pi*i/n; verts.append((rx[j]*math.cos(a)*100,ry[j]*math.sin(a)*100,z*100))
 for j in range(len(zs)-1):
  for i in range(n):
   a=j*n+i;b=j*n+(i+1)%n;c=(j+1)*n+i;d=(j+1)*n+(i+1)%n
   faces.extend([(a,b,c),(b,d,c)])
 mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
 obj=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(obj);obj.parent=rig
 obj.modifiers.new('Armature','ARMATURE').object=rig
 for vg in body.vertex_groups:obj.vertex_groups.new(name=vg.name)
 for v in mesh.vertices:
  _,idx,_=kdt.find(rig.matrix_world@v.co)
  for group in body.data.vertices[idx].groups:obj.vertex_groups[group.group].add([v.index],group.weight,'REPLACE')
 obj.shape_key_add(name='Basis')
 if name=='shirt':
  for key_name in ['Tucked','NeckFit']:
   key=obj.shape_key_add(name=key_name)
   for v in mesh.vertices:
    z=v.co.z/100
    if key_name=='Tucked' and z<=1.1: key.data[v.index].co.x*=.87;key.data[v.index].co.y*=.87
    if key_name=='NeckFit' and z>=1.38:key.data[v.index].co.x*=.90;key.data[v.index].co.y*=.90
 mat=bpy.data.materials.new(name);mat.diffuse_color=color;obj.data.materials.append(mat)
 garments.append(obj);report[name]={'vertices':len(verts),'triangles':len(faces),'weighted_vertices':sum(bool(v.groups) for v in mesh.vertices),'morphs':[k.name for k in obj.data.shape_keys.key_blocks]}
 bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);rig.select_set(True);bpy.context.view_layer.objects.active=obj
 bpy.ops.export_scene.gltf(filepath=str(out/(name+'.glb')),use_selection=True,export_format='GLB',export_animations=False,export_morph=True,export_skins=True)
# Keep an inspectable scene, including the original rigged character.
bpy.ops.object.select_all(action='DESELECT')
for obj in garments:obj.select_set(True)
bpy.context.view_layer.objects.active=garments[0]
bpy.ops.wm.save_as_mainfile(filepath=str(out/'wardrobe_trial.blend'))
(out/'blender_report.json').write_text(json.dumps(report,indent=2))
print('WARDROBE_TRIAL',report)
