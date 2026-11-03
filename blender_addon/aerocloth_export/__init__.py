"""AeroCloth preparation metadata and GLB exporter. No network or live bridge."""
bl_info = {"name": "AeroCloth Preparation", "author": "AeroCloth3D contributors",
           "version": (0, 3, 0), "blender": (4, 3, 0), "location": "3D View > Sidebar > AeroCloth",
           "description": "Validate rig/regions/damage UV, copy weight transfer, export GLB + JSON", "category": "Import-Export"}

import bpy
import hashlib
import json
import math
import uuid
from pathlib import Path
from bpy.props import PointerProperty, StringProperty, FloatProperty
from mathutils.bvhtree import BVHTree

SCHEMA_VERSION = 1


def selected_export_objects(context):
    result = set(context.selected_objects)
    for obj in tuple(result):
        if obj.type == 'MESH':
            for modifier in obj.modifiers:
                if modifier.type == 'ARMATURE' and modifier.object:
                    result.add(modifier.object)
    return sorted(result, key=lambda obj: (str(obj.get('ac_id', '')), obj.name))


def topology_fingerprint(obj):
    """Source binding fingerprint; geometry/UV edits require rebinding in Godot."""
    if obj.type != 'MESH':
        return None
    payload = {"vertices": [[round(float(c), 7) for c in v.co] for v in obj.data.vertices],
               "faces": [list(p.vertices) for p in obj.data.polygons],
               "uv": {layer.name: [[round(float(c), 7) for c in loop.uv] for loop in layer.data]
                      for layer in obj.data.uv_layers}}
    return hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def _area(poly):
    return abs(sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1]
                   for i in range(len(poly)))) * 0.5 if len(poly) >= 3 else 0.0


def _intersection_area(subject, clip):
    signed = sum(clip[i][0] * clip[(i + 1) % 3][1] - clip[(i + 1) % 3][0] * clip[i][1] for i in range(3))
    sign = 1 if signed > 0 else -1
    output = list(subject)
    for i in range(3):
        a, b = clip[i], clip[(i + 1) % 3]
        def side(p):
            return sign * ((b[0]-a[0])*(p[1]-a[1]) - (b[1]-a[1])*(p[0]-a[0]))
        source, output = output, []
        if not source:
            break
        previous = source[-1]
        sp = side(previous)
        for current in source:
            sc = side(current)
            if (sp >= -1e-10) != (sc >= -1e-10):
                t = sp / (sp - sc)
                output.append((previous[0] + (current[0]-previous[0])*t,
                               previous[1] + (current[1]-previous[1])*t))
            if sc >= -1e-10:
                output.append(current)
            previous, sp = current, sc
    return _area(output)


def damage_uv_report(obj):
    if len(obj.data.uv_layers) < 2:
        return {"status": "missing", "overlaps": [], "degenerate_triangles": 0,
                "note": "UV2 is required for local damage painting; base UV is preserved."}
    layer = obj.data.uv_layers[1]
    obj.data.calc_loop_triangles()
    triangles, grid, tested, overlaps = [], {}, set(), []
    degenerate = 0
    outside = False
    for triangle in obj.data.loop_triangles:
        uv = [tuple(float(c) for c in layer.data[index].uv) for index in triangle.loops]
        if not all(math.isfinite(c) for p in uv for c in p):
            outside = True
            triangles.append(uv)
            degenerate += 1
            continue
        if not all(-1e-6 <= c <= 1+1e-6 for p in uv for c in p):
            outside = True
        triangles.append(uv)
        if _area(uv) < 1e-12:
            degenerate += 1
            continue
        lo = [max(0, min(31, int(min(p[k] for p in uv)*32))) for k in (0, 1)]
        hi = [max(0, min(31, int(max(p[k] for p in uv)*32))) for k in (0, 1)]
        index = len(triangles)-1
        for x in range(lo[0], hi[0]+1):
            for y in range(lo[1], hi[1]+1):
                bucket = grid.setdefault((x,y), [])
                for other in bucket:
                    pair = (other,index)
                    if pair not in tested:
                        tested.add(pair)
                        if _intersection_area(triangles[other],uv) > 1e-9:
                            overlaps.append(list(pair))
                bucket.append(index)
    return {"status": "invalid" if outside or overlaps or degenerate else "valid",
            "layer": layer.name, "outside_unit_square": outside,
            "overlaps": overlaps[:32], "overlap_count": len(overlaps),
            "degenerate_triangles": degenerate,
            "note": "Positive-area overlap test, triangulated source UV2; shared edges are allowed."}


def validate_objects(objects):
    errors, warnings, seen = [], [], set()
    meshes = [obj for obj in objects if obj.type == 'MESH']
    if not meshes:
        errors.append("Select at least one mesh.")
    for obj in objects:
        identity = str(obj.get('ac_id', ''))
        if not identity:
            errors.append(f"{obj.name}: missing ac_id; run Prepare IDs.")
        elif identity in seen:
            errors.append(f"{obj.name}: duplicate ac_id; copied objects need their own ID.")
        seen.add(identity)
        if obj.type != 'MESH':
            continue
        role = str(obj.get('ac_role', 'garment'))
        rigs = [m.object for m in obj.modifiers if m.type == 'ARMATURE' and m.object]
        if role not in {'proxy', 'rigid'} and not rigs:
            errors.append(f"{obj.name}: no armature; assign a rig or mark ac_role=rigid/proxy.")
        if rigs:
            bone_names = {b.name for b in rigs[0].data.bones if b.use_deform}
            group_indices = {g.index for g in obj.vertex_groups if g.name in bone_names}
            zero, unnormalized = [], []
            for vertex in obj.data.vertices:
                total = sum(g.weight for g in vertex.groups if g.group in group_indices)
                if total < 1e-6:
                    zero.append(vertex.index)
                elif abs(total-1) > 0.01:
                    unnormalized.append(vertex.index)
            if zero:
                errors.append(f"{obj.name}: {len(zero)} vertices have no bone weight (first {zero[:8]}).")
            if unnormalized:
                errors.append(f"{obj.name}: {len(unnormalized)} vertices have unnormalized bone weights.")
        uv = damage_uv_report(obj)
        if uv['status'] != 'valid':
            warnings.append(f"{obj.name}: damage UV2 {uv['status']}; local damage painting needs repair.")
        if not any(g.name.startswith('ac_region_') for g in obj.vertex_groups):
            warnings.append(f"{obj.name}: no ac_region_* groups; regions must be authored in Godot.")
    return {"valid": not errors, "errors": errors, "warnings": warnings}


def build_metadata(objects, glb_name):
    report = validate_objects(objects)
    if not report['valid']:
        raise ValueError('; '.join(report['errors']))
    records = []
    for obj in objects:
        record = {"id": str(obj['ac_id']), "name": obj.name, "type": obj.type,
                  "role": str(obj.get('ac_role','garment' if obj.type == 'MESH' else obj.type.lower())),
                  "matrix_world": [list(row) for row in obj.matrix_world]}
        if obj.type == 'ARMATURE':
            record['bones'] = [{"name": b.name, "parent": b.parent.name if b.parent else None,
                                "deform": b.use_deform, "rest_matrix": [list(row) for row in b.matrix_local]}
                               for b in obj.data.bones]
        if obj.type == 'MESH':
            record.update(topology_fingerprint=topology_fingerprint(obj), vertex_count=len(obj.data.vertices),
                          polygon_count=len(obj.data.polygons), damage_uv=damage_uv_report(obj))
            record['regions'] = [{"id": group.name[len('ac_region_'):],
                                  "weights": [[v.index, next((g.weight for g in v.groups if g.group==group.index),0.0)]
                                              for v in obj.data.vertices if any(g.group==group.index and g.weight>0 for g in v.groups)]}
                                 for group in obj.vertex_groups if group.name.startswith('ac_region_')]
            record['shape_keys'] = [k.name for k in obj.data.shape_keys.key_blocks if k.name != 'Basis'] if obj.data.shape_keys else []
            record['armature_id'] = next((str(m.object.get('ac_id','')) for m in obj.modifiers if m.type=='ARMATURE' and m.object), None)
        if obj.type == 'EMPTY' and obj.get('ac_role') == 'connection':
            # ac_source_* is explicit for links; retain ac_item_id/ac_region_id
            # as accepted authoring aliases for existing prepared files.
            record['connection'] = {"item_id": str(obj.get('ac_source_item',obj.get('ac_item_id',''))),
                                    "region_id": str(obj.get('ac_source_region',obj.get('ac_region_id',''))),
                                    "bone": str(obj.get('ac_bone',''))}
        records.append(record)
    return {"schema": "AeroCloth3D.blender", "version": SCHEMA_VERSION, "source_glb": glb_name,
            "source_coordinates": "Blender Z-up, right-handed", "glb_coordinates": "glTF Y-up, right-handed",
            "coordinate_note": "GLB exporter converts basis; metadata matrices remain Blender source space.",
            "objects": records, "validation": report}


def export_bundle(context, directory, stem='character'):
    if not stem or Path(stem).name != stem:
        raise ValueError('Asset name must be a filename without directories')
    objects = selected_export_objects(context)
    metadata = build_metadata(objects, stem+'.glb')
    directory = Path(bpy.path.abspath(directory))
    directory.mkdir(parents=True, exist_ok=True)
    selected = list(context.selected_objects)
    active = context.view_layer.objects.active
    muted = [(track,track.mute) for obj in objects if obj.animation_data for track in obj.animation_data.nla_tracks]
    try:
        bpy.ops.object.select_all(action='DESELECT')
        for obj in objects:
            obj.select_set(True)
        for track,_ in muted:
            track.mute = False
        bpy.ops.export_scene.gltf(filepath=str(directory/(stem+'.glb')), export_format='GLB',use_selection=True,
                                  export_yup=True, export_skins=True, export_animations=True, export_morph=True,
                                  export_materials='EXPORT', export_extras=True, export_animation_mode='NLA_TRACKS',
                                  export_force_sampling=True)
        metadata['glb_sha256'] = hashlib.sha256((directory/(stem+'.glb')).read_bytes()).hexdigest()
        (directory/(stem+'.aerocloth.json')).write_text(json.dumps(metadata, indent=2), encoding='utf8')
    finally:
        for track,value in muted:
            track.mute = value
        bpy.ops.object.select_all(action='DESELECT')
        for obj in selected:
            obj.select_set(True)
        context.view_layer.objects.active = active
    return metadata


class AEROCLOTH_Settings(bpy.types.PropertyGroup):
    body: PointerProperty(name="Weight source body", type=bpy.types.Object, poll=lambda _,o:o.type=='MESH')
    region_mask: StringProperty(name="Target region group", description="Optional target vertex group; transfer only changes its weighted region")
    directory: StringProperty(name="Export directory", subtype='DIR_PATH', default='//aerocloth_export/')
    stem: StringProperty(name="Asset name", default='character')
    fit_distance: FloatProperty(name="Fit search distance", default=.10, min=.001, max=1, unit='LENGTH')
    fit_limit: FloatProperty(name="Maximum vertex movement", default=.02, min=.001, max=.2, unit='LENGTH')
    fit_offset: FloatProperty(name="Body clearance", default=.003, min=0, max=.1, unit='LENGTH')


def _garment_copies(context, suffix):
    body=context.scene.aerocloth_settings.body
    sources=[o for o in context.selected_objects if o.type=='MESH' and o!=body]
    copies=[]
    for source in sources:
        copy=source.copy()
        copy.data=source.data.copy()
        context.collection.objects.link(copy)
        copy.name=source.name+suffix
        copy['ac_id']=str(uuid.uuid4())
        copies.append(copy)
    return copies


def _select_copies(context, copies):
    bpy.ops.object.select_all(action='DESELECT')
    for copy in copies:copy.select_set(True)
    if copies:context.view_layer.objects.active=copies[0]


class AEROCLOTH_OT_uv_copy(bpy.types.Operator):
    bl_idname='aerocloth.damage_uv_copies'
    bl_label='Prepare damage UV on garment copies'
    bl_options={'REGISTER','UNDO'}
    def execute(self,context):
        if context.mode!='OBJECT':
            self.report({'ERROR'},'Switch to Object Mode before preparing copies')
            return {'CANCELLED'}
        copies=_garment_copies(context,'_AC_UV')
        if not copies:
            self.report({'ERROR'},'Select garment meshes (the selected body is excluded)')
            return {'CANCELLED'}
        for copy in copies:
            _select_copies(context,[copy])
            if not copy.data.uv_layers:copy.data.uv_layers.new(name='UVMap')
            if len(copy.data.uv_layers)<2:copy.data.uv_layers.new(name='AeroDamageUV')
            copy.data.uv_layers.active_index=1
            bpy.ops.object.mode_set(mode='EDIT')
            try:
                bpy.ops.mesh.select_all(action='SELECT')
                bpy.ops.uv.smart_project(angle_limit=math.radians(66),island_margin=.02,scale_to_bounds=True)
            finally:bpy.ops.object.mode_set(mode='OBJECT')
        _select_copies(context,copies)
        invalid=[copy.name for copy in copies if damage_uv_report(copy)['status']!='valid']
        self.report({'WARNING'} if invalid else {'INFO'},'UV2 prepared on copies; inspect islands/padding'+(': '+', '.join(invalid) if invalid else ''))
        return {'FINISHED'}


class AEROCLOTH_OT_fit_copy(bpy.types.Operator):
    bl_idname='aerocloth.fit_copies'
    bl_label='Suggest rest-pose fit on garment copies'
    bl_options={'REGISTER','UNDO'}
    def execute(self,context):
        settings=context.scene.aerocloth_settings
        body=settings.body
        sources=[o for o in context.selected_objects if o.type=='MESH' and o!=body]
        if context.mode!='OBJECT' or body is None or not sources or not body.data.polygons:
            self.report({'ERROR'},'Choose a mesh body and garments in Object Mode')
            return {'CANCELLED'}
        if any(settings.region_mask and settings.region_mask not in o.vertex_groups for o in sources):
            self.report({'ERROR'},'Target region group is missing; nothing changed')
            return {'CANCELLED'}
        tree=BVHTree.FromPolygons([v.co for v in body.data.vertices],[tuple(p.vertices) for p in body.data.polygons])
        inverse_body=body.matrix_world.inverted()
        normal_matrix=body.matrix_world.to_3x3().inverted().transposed()
        copies=_garment_copies(context,'_AC_Fit')
        moved=0
        for copy in copies:
            inverse_copy=copy.matrix_world.to_3x3().inverted()
            group=copy.vertex_groups.get(settings.region_mask) if settings.region_mask else None
            for vertex in copy.data.vertices:
                weight=next((g.weight for g in vertex.groups if group and g.group==group.index),0) if group else 1
                if weight<=0:continue
                world=copy.matrix_world@vertex.co
                hit,normal,_,_=tree.find_nearest(inverse_body@world)
                if hit is None:continue
                target=body.matrix_world@hit+(normal_matrix@normal).normalized()*settings.fit_offset
                delta=target-world
                if delta.length>settings.fit_distance:continue
                if delta.length>settings.fit_limit:delta=delta.normalized()*settings.fit_limit
                local=inverse_copy@(delta*weight)
                if local.length<1e-9:continue
                if copy.data.shape_keys:
                    for block in copy.data.shape_keys.key_blocks:block.data[vertex.index].co+=local
                vertex.co+=local
                moved+=1
            copy.data.update()
        _select_copies(context,copies)
        self.report({'INFO'},f'Fit suggestion: {moved} vertices on copies; base/rest geometry only. Check animations and clearance.')
        return {'FINISHED'}


class AEROCLOTH_OT_prepare_ids(bpy.types.Operator):
    bl_idname='aerocloth.prepare_ids'
    bl_label='Prepare stable IDs'
    bl_options={'REGISTER','UNDO'}
    def execute(self,context):
        selected = selected_export_objects(context)
        identities = set()
        for obj in selected:
            value = str(obj.get('ac_id',''))
            if not value or value in identities:
                value = str(uuid.uuid4())
                obj['ac_id'] = value
            identities.add(value)
        self.report({'INFO'},f"Prepared IDs for {len(selected)} objects; geometry unchanged")
        return {'FINISHED'}


class AEROCLOTH_OT_validate(bpy.types.Operator):
    bl_idname='aerocloth.validate'
    bl_label='Validate preparation'
    def execute(self,context):
        report = validate_objects(selected_export_objects(context))
        for warning in report['warnings']:
            self.report({'WARNING'},warning)
        for error in report['errors']:
            self.report({'ERROR'},error)
        if report['valid']:
            self.report({'INFO'},'Rig/weights/IDs valid; inspect any UV/region warnings')
        return {'FINISHED'} if report['valid'] else {'CANCELLED'}


class AEROCLOTH_OT_transfer_copy(bpy.types.Operator):
    bl_idname='aerocloth.transfer_weights_copy'
    bl_label='Transfer weights to garment copies'
    bl_options={'REGISTER','UNDO'}
    def execute(self,context):
        settings=context.scene.aerocloth_settings
        body=settings.body
        targets=[o for o in context.selected_objects if o.type=='MESH' and o!=body]
        if body is None or not targets:
            self.report({'ERROR'},'Choose a body and select at least one garment')
            return {'CANCELLED'}
        if not body.find_armature():
            self.report({'ERROR'},'Source body needs an armature')
            return {'CANCELLED'}
        missing=[o.name for o in targets if settings.region_mask and settings.region_mask not in o.vertex_groups]
        if missing:
            self.report({'ERROR'},'Target region group missing: '+', '.join(missing))
            return {'CANCELLED'}
        copies=[]
        for source in targets:
            copy=source.copy()
            copy.data=source.data.copy()
            context.collection.objects.link(copy)
            copy.name=source.name+'_AC_Weights'
            copy['ac_id']=str(uuid.uuid4())
            copies.append(copy)
            bones={b.name for b in body.find_armature().data.bones if b.use_deform}
            old={g.name:{v.index:next((w.weight for w in v.groups if w.group==g.index),0.0) for v in copy.data.vertices}
                 for g in copy.vertex_groups if g.name in bones}
            mask=copy.vertex_groups.get(settings.region_mask) if settings.region_mask else None
            limits={v.index:next((w.weight for w in v.groups if mask and w.group==mask.index),0.0) for v in copy.data.vertices} if mask else None
            bpy.ops.object.select_all(action='DESELECT')
            body.select_set(True)
            copy.select_set(True)
            context.view_layer.objects.active=body
            # Blender's operator accepts concrete group names, not the modifier's
            # BONE_DEFORM enum. Transfer only deform-bone groups so authored region
            # masks are never copied from the body onto the garment.
            for group_name in sorted(bones):
                if group_name in body.vertex_groups:
                    bpy.ops.object.data_transfer(data_type='VGROUP_WEIGHTS',use_create=True,vert_mapping='POLYINTERP_NEAREST',
                                                layers_select_src=group_name,layers_select_dst='NAME',mix_mode='REPLACE')
            if limits is not None:
                for group in copy.vertex_groups:
                    if group.name not in bones:
                        continue
                    for vertex in copy.data.vertices:
                        current=next((w.weight for w in vertex.groups if w.group==group.index),0.0)
                        strength=limits[vertex.index]
                        weight=old.get(group.name,{}).get(vertex.index,0)*(1-strength)+current*strength
                        group.add([vertex.index],weight,'REPLACE')
            modifier=next((m for m in copy.modifiers if m.type=='ARMATURE'),None)
            if modifier is None:
                modifier=copy.modifiers.new('AeroCloth rig','ARMATURE')
            modifier.object=body.find_armature()
        bpy.ops.object.select_all(action='DESELECT')
        for obj in copies:
            obj.select_set(True)
        context.view_layer.objects.active=copies[0]
        self.report({'INFO'},f"Transferred to {len(copies)} copies; originals untouched. Validate and inspect animation.")
        return {'FINISHED'}


class AEROCLOTH_OT_export(bpy.types.Operator):
    bl_idname='aerocloth.export_bundle'
    bl_label='Export GLB + AeroCloth metadata'
    def execute(self,context):
        settings=context.scene.aerocloth_settings
        if not settings.stem or Path(settings.stem).name != settings.stem:
            self.report({'ERROR'},'Asset name must be a filename without directories')
            return {'CANCELLED'}
        try:
            metadata=export_bundle(context,settings.directory,settings.stem)
        except (ValueError,OSError,RuntimeError) as error:
            self.report({'ERROR'},str(error))
            return {'CANCELLED'}
        self.report({'INFO'},f"Exported {len(metadata['objects'])} objects; source geometry unchanged")
        return {'FINISHED'}


class AEROCLOTH_PT_panel(bpy.types.Panel):
    bl_label='AeroCloth Preparation'
    bl_space_type='VIEW_3D'
    bl_region_type='UI'
    bl_category='AeroCloth'
    def draw(self,context):
        layout=self.layout
        settings=context.scene.aerocloth_settings
        layout.operator('aerocloth.prepare_ids')
        layout.operator('aerocloth.validate')
        layout.separator()
        layout.prop(settings,'body')
        layout.prop(settings,'region_mask')
        layout.operator('aerocloth.transfer_weights_copy')
        layout.operator('aerocloth.damage_uv_copies')
        layout.prop(settings,'fit_distance')
        layout.prop(settings,'fit_limit')
        layout.prop(settings,'fit_offset')
        layout.operator('aerocloth.fit_copies')
        layout.label(text='Suggestions on copies; inspect animations.')
        layout.separator()
        layout.prop(settings,'directory')
        layout.prop(settings,'stem')
        layout.operator('aerocloth.export_bundle')


CLASSES=(AEROCLOTH_Settings,AEROCLOTH_OT_prepare_ids,AEROCLOTH_OT_validate,AEROCLOTH_OT_transfer_copy,AEROCLOTH_OT_uv_copy,AEROCLOTH_OT_fit_copy,AEROCLOTH_OT_export,AEROCLOTH_PT_panel)
def register():
    for cls in CLASSES:
        bpy.utils.register_class(cls)
    bpy.types.Scene.aerocloth_settings=PointerProperty(type=AEROCLOTH_Settings)

def unregister():
    del bpy.types.Scene.aerocloth_settings
    for cls in reversed(CLASSES):
        bpy.utils.unregister_class(cls)

if __name__=='__main__':
    register()
