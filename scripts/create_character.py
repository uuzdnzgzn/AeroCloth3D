"""Build AeroCloth3D's original recovery mannequin with Blender 4.3+.

Run: blender --background --python scripts/create_character.py
No external assets are used. Native Blender Z-up/front -Y becomes glTF Y-up/front +Z.
"""
from pathlib import Path
import math
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "demo/assets/recovery_character"
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

def material(name, color, metallic=0.0, roughness=0.75):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Metallic'].default_value = metallic
    p.inputs['Roughness'].default_value = roughness
    return m

mats = {
    'skin': material('Warm skin', (0.56, 0.32, 0.23)),
    'hair': material('Midnight hair', (0.025, 0.045, 0.075)),
    'shirt': material('Base shirt - graphite', (0.11, 0.15, 0.20)),
    'pants': material('Base trousers', (0.045, 0.065, 0.095)),
    'boot': material('Boots and gloves', (0.024, 0.032, 0.045), 0.1),
    'teal': material('Teal seam', (0.045, 0.63, 0.56), 0.25, 0.4),
    'white': material('Eye whites', (0.79, 0.88, 0.88)),
    'iris': material('Teal iris', (0.025, 0.29, 0.26)),
    'dark': material('Face details', (0.03, 0.022, 0.025)),
    'metal': material('Belt buckle', (0.38, 0.45, 0.51), 0.7, 0.35),
}
parts = []

def finish(obj, name, mat, bone):
    obj.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.data.materials.append(mats[mat])
    obj.vertex_groups.new(name=bone).add(list(range(len(obj.data.vertices))), 1.0, 'REPLACE')
    parts.append(obj)
    return obj

def sphere(name, center, scale, mat, bone, segments=12, rings=8):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=center)
    obj = bpy.context.object
    obj.scale = scale
    return finish(obj, name, mat, bone)

def box(name, center, scale, mat, bone, bevel=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center)
    obj = bpy.context.object
    obj.scale = scale
    if bevel:
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        mod = obj.modifiers.new('Low-poly bevel', 'BEVEL')
        mod.width = bevel
        mod.segments = 1
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return finish(obj, name, mat, bone)

def segment(name, start, end, r1, r2, mat, bone, vertices=10):
    a, b = Vector(start), Vector(end)
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=r1, radius2=r2,
                                  depth=(b-a).length, location=(a+b)/2)
    obj = bpy.context.object
    obj.rotation_euler = (b-a).to_track_quat('Z', 'Y').to_euler()
    return finish(obj, name, mat, bone)

def ring_shell(name, rings, mat, bone, n=12):
    verts = [(math.cos(i*2*math.pi/n)*rx, math.sin(i*2*math.pi/n)*ry, z)
             for z, rx, ry in rings for i in range(n)]
    faces=[]
    for r in range(len(rings)-1):
        for i in range(n):
            a = r*n+i
            b = r*n+(i+1)%n
            faces.append((a,b,b+n,a+n))
    faces.extend([tuple(reversed(range(n))), tuple((len(rings)-1)*n+i for i in range(n))])
    mesh=bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj=bpy.data.objects.new(name,mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active=obj
    obj.select_set(True)
    return finish(obj,name,mat,bone)

# Main body and existing outfit. Added damage test layers are separate runtime assets.
ring_shell('Torso base shirt', [(0.96,.151,.09),(1.07,.163,.10),(1.27,.208,.115),
                              (1.41,.218,.112),(1.46,.174,.09)], 'shirt','Chest')
ring_shell('Waist belt',[(.953,.159,.096),(.999,.159,.096)],'boot','Hips')
box('Belt buckle',(0,-.102,.977),(.06,.017,.037),'metal','Hips',.008)
ring_shell('Shirt neck collar',[(1.43,.075,.066),(1.483,.067,.06)],'teal','Chest')
segment('Neck',(0,0,1.43),(0,0,1.59),.062,.064,'skin','Neck')
sphere('Head',(0,-.006,1.668),(.126,.108,.158),'skin','Head',16,10)
sphere('Jaw',(0,-.018,1.585),(.094,.084,.067),'skin','Head',12,8)
sphere('Hair cap',(0,.013,1.722),(.134,.112,.112),'hair','Head',16,8)
sphere('Back hair',(0,.066,1.667),(.126,.075,.126),'hair','Head',12,8)
# Swept wedges make the face readable without textures.
for i, x in enumerate([-.105,-.067,-.025,.025,.068,.106]):
    length = [.09,.10,.115,.091,.071,.068][i]
    sphere('Fringe %d'%i,(x,-.085,1.754-length*.45),(.036,.032,length*.62),'hair','Head',6,5)
for sign in [-1,1]:
    sphere('Ear',(sign*.127,.005,1.657),(.023,.027,.044),'skin','Head',8,6)
    sphere('Eye white',(sign*.051,-.102,1.679),(.036,.012,.021),'white','Head',12,6)
    sphere('Iris',(sign*.052,-.113,1.68),(.013,.004,.017),'iris','Head',10,6)
    sphere('Pupil',(sign*.052,-.117,1.68),(.006,.002,.011),'dark','Head',8,4)
    box('Eyebrow',(sign*.051,-.107,1.711),(.06,.009,.009),'hair','Head',.002)
sphere('Nose',(0,-.113,1.645),(.014,.018,.024),'skin','Head',6,4)
box('Mouth',(0,-.100,1.605),(.041,.006,.005),'dark','Head',.001)

for suffix, sign in [('R',-1),('L',1)]:
    shoulder=(sign*.213,0,1.411)
    elbow=(sign*.333,-.009,1.147)
    wrist=(sign*.385,-.038,.925)
    sphere('Shirt shoulder '+suffix,shoulder,(.105,.101,.097),'shirt','UpperArm_'+suffix)
    segment('Short sleeve '+suffix,shoulder,(sign*.262,-.002,1.309),.095,.085,'shirt','UpperArm_'+suffix)
    segment('Upper arm '+suffix,(sign*.252,-.003,1.334),elbow,.069,.054,'skin','UpperArm_'+suffix)
    sphere('Elbow '+suffix,elbow,(.055,.055,.055),'skin','Forearm_'+suffix)
    segment('Forearm '+suffix,elbow,wrist,.056,.039,'skin','Forearm_'+suffix)
    segment('Wrist cuff '+suffix,(sign*.369,-.03,.989),wrist,.045,.044,'boot','Forearm_'+suffix)
    sphere('Hand '+suffix,(sign*.394,-.048,.879),(.044,.035,.068),'skin','Hand_'+suffix)
    hip=(sign*.097,0,.94)
    knee=(sign*.106,-.007,.535)
    ankle=(sign*.108,.012,.135)
    segment('Trousers upper '+suffix,hip,knee,.102,.078,'pants','Thigh_'+suffix)
    sphere('Trouser knee '+suffix,knee,(.078,.077,.087),'pants','Shin_'+suffix)
    segment('Trousers lower '+suffix,knee,ankle,.076,.048,'pants','Shin_'+suffix)
    segment('Boot cuff '+suffix,(sign*.108,.012,.25),ankle,.066,.058,'boot','Shin_'+suffix)
    box('Boot '+suffix,(sign*.108,-.048,.082),(.136,.24,.146),'boot','Foot_'+suffix,.026)
    box('Shin detail '+suffix,(sign*.108,-.057,.325),(.025,.014,.12),'teal','Shin_'+suffix,.004)

# Flat shading is deliberate: the test actor stays inexpensive and clearly procedural.
bpy.ops.object.select_all(action='DESELECT')
for p in parts:
    p.select_set(True)
bpy.context.view_layer.objects.active=parts[0]
bpy.ops.object.join()
skin=bpy.context.object
skin.name='RecoveryCharacterMesh'

arm=bpy.data.armatures.new('RecoveryRig')
rig=bpy.data.objects.new('RecoveryRig',arm)
bpy.context.collection.objects.link(rig)
bpy.context.view_layer.objects.active=rig
bpy.ops.object.mode_set(mode='EDIT')

def bone(name,head,tail,parent=None):
    b=arm.edit_bones.new(name)
    b.head=head
    b.tail=tail
    if parent:
        b.parent=arm.edit_bones[parent]
    return b

bone('Root',(0,0,0),(0,0,.15))
bone('Hips',(0,0,.91),(0,0,1.05),'Root')
bone('Spine',(0,0,1.05),(0,0,1.25),'Hips')
bone('Chest',(0,0,1.25),(0,0,1.45),'Spine')
bone('Neck',(0,0,1.45),(0,0,1.565),'Chest')
bone('Head',(0,0,1.565),(0,0,1.80),'Neck')
for suffix,sign in [('R',-1),('L',1)]:
    bone('Shoulder_'+suffix,(0,0,1.412),(sign*.213,0,1.411),'Chest')
    bone('UpperArm_'+suffix,(sign*.213,0,1.411),(sign*.333,-.009,1.147),'Shoulder_'+suffix)
    bone('Forearm_'+suffix,(sign*.333,-.009,1.147),(sign*.385,-.038,.925),'UpperArm_'+suffix)
    bone('Hand_'+suffix,(sign*.385,-.038,.925),(sign*.405,-.05,.825),'Forearm_'+suffix)
    bone('Thigh_'+suffix,(sign*.097,0,.94),(sign*.106,-.007,.535),'Hips')
    bone('Shin_'+suffix,(sign*.106,-.007,.535),(sign*.108,.012,.135),'Thigh_'+suffix)
    bone('Foot_'+suffix,(sign*.108,.012,.135),(sign*.108,-.15,.08),'Shin_'+suffix)
bpy.ops.object.mode_set(mode='OBJECT')
skin.parent=rig
mod=skin.modifiers.new('Skeleton skin','ARMATURE')
mod.object=rig

scene=bpy.context.scene
scene.render.fps=24
scene.frame_start=1
scene.frame_end=48
rig.animation_data_create()
for name,end in [('Idle',48),('Walk',32)]:
    action=bpy.data.actions.new(name)
    rig.animation_data.action=action
    for f in range(1,end+1):
        t=(f-1)/(end-1)*2*math.pi
        for p in rig.pose.bones:
            p.rotation_mode='XYZ'
            p.rotation_euler=(0,0,0)
            p.location=(0,0,0)
        if name=='Idle':
            rig.pose.bones['Chest'].rotation_euler.x=math.sin(t)*.014
            rig.pose.bones['Head'].rotation_euler.y=math.sin(t)*.018
            rig.pose.bones['Hips'].location.y=math.sin(t)*.006
        else:
            rig.pose.bones['Hips'].location.y=abs(math.sin(t))*.018
            rig.pose.bones['Chest'].rotation_euler.y=math.sin(t)*.035
            for suffix,phase in [('R',1),('L',-1)]:
                v=math.sin(t)*phase
                rig.pose.bones['Thigh_'+suffix].rotation_euler.x=v*.33
                rig.pose.bones['Shin_'+suffix].rotation_euler.x=max(0,-v)*.43
                rig.pose.bones['Foot_'+suffix].rotation_euler.x=-v*.12
                rig.pose.bones['UpperArm_'+suffix].rotation_euler.x=-v*.22
                rig.pose.bones['Forearm_'+suffix].rotation_euler.x=-.07-max(0,v)*.15
        for p in rig.pose.bones:
            p.keyframe_insert(data_path='rotation_euler',frame=f,group=p.name)
            if p.name=='Hips':
                p.keyframe_insert(data_path='location',frame=f,group=p.name)
    for fc in action.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation='LINEAR'
    # A distinct NLA track preserves both actions in glTF and in the source .blend.
    track=rig.animation_data.nla_tracks.new()
    track.name=name
    strip=track.strips.new(name,1,action)
    strip.action_frame_end=end
rig.animation_data.action=None
for tr in rig.animation_data.nla_tracks:
    tr.mute=True
scene.frame_set(1)
for p in rig.pose.bones:
    p.rotation_euler=(0,0,0)
    p.location=(0,0,0)

bpy.ops.object.select_all(action='DESELECT')
skin.select_set(True)
rig.select_set(True)
bpy.context.view_layer.objects.active=rig
opts=dict(filepath=str(OUT/'character.glb'),export_format='GLB',use_selection=True,
          export_yup=True,export_skins=True,export_animations=True,export_materials='EXPORT',
          export_animation_mode='NLA_TRACKS',export_force_sampling=True)
# Unmute tracks only for export (Blender exporter processes each NLA track independently).
for tr in rig.animation_data.nla_tracks:
    tr.mute=False
bpy.ops.export_scene.gltf(**opts)
for tr in rig.animation_data.nla_tracks:
    tr.mute=True
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'character.blend'))
print('AEROCLOTH_CHARACTER_EXPORTED', OUT/'character.glb', 'bones',len(arm.bones), 'vertices',len(skin.data.vertices))
