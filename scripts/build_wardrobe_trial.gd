extends SceneTree
func _initialize() -> void:
 var catalog={'version':1,'body_channels':{'chest':{'name':'Göğüs','min':0,'max':1,'default':0.5}},'slots':['torso','waist','neck'],'regions':['torso'],'body':{'scene':'','skeleton':'','morphs':{},'regions':{}},'garments':[]}
 for id in ['shirt','corset','collar']:
  var path='Armature/Skeleton3D/'+id
  var g={'id':id,'name':{'shirt':'Veyra · deneme gömleği','corset':'Veyra · kuşak korse','collar':'Veyra · boyunluk'}[id],'slot':{'shirt':'torso','corset':'waist','collar':'neck'}[id],'layer':10 if id=='shirt' else 20,'occupies':[id],'tags':[id],'fit_mode':'deform','default_variant':'default','variants':{'default':{'scene':'res://demo/wardrobe_trial/'+id+'.glb','skinning':'shared','part_nodes':{}}},'parts':{'main':{'node':path,'covers':[]}},'morph_limits':{},'bindings':[],'rules':[]}
  if id=='shirt':
   var n=load(g.variants.default.scene).instantiate()
   var mesh=n.get_node(path).mesh
   var a=mesh.surface_get_arrays(0)
   var ids:PackedInt32Array=a[Mesh.ARRAY_INDEX]
   var verts:PackedVector3Array=a[Mesh.ARRAY_VERTEX]
   var miny=INF;var maxy=-INF
   for v in verts:miny=minf(miny,v.y);maxy=maxf(maxy,v.y)
   var hem=[]
   for face in range(ids.size()/3):
    var top=maxf(verts[ids[face*3]].y,maxf(verts[ids[face*3+1]].y,verts[ids[face*3+2]].y))
    if top<miny+(maxy-miny)*.30:hem.append(face)
   print('HEM faces=',hem.size(),' bounds=',miny,',',maxy)
   g.parts['hem']={'node':path,'covers':[],'faces':{'surface':0,'triangles':hem}}
   g.morph_limits={'Tucked':[0,1],'NeckFit':[0,1]}
   g.rules=[{'id':'corset-tuck','priority':10,'when':{'all_items':['corset']},'actions':{'morphs':{'Tucked':1},'hide_parts':['hem']}},{'id':'collar-fit','priority':20,'when':{'all_items':['collar']},'actions':{'morphs':{'NeckFit':1}}}]
   n.free()
  catalog.garments.append(g)
 var f=FileAccess.open('res://demo/wardrobe_trial/catalog.json',FileAccess.WRITE)
 f.store_string(JSON.stringify(catalog,'\t'));f.close()
 quit()
