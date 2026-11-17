extends Control
## Source-safe clothing face authoring. Triangle IDs address imported GLB surfaces.
const Bridge = preload("res://scripts/wardrobe_bridge.gd")
const WORK_CATALOG := "res://data/wardrobe/adventure_work.json"
var catalog: Dictionary = {}
var source_project: LineEdit
var target_project: LineEdit
var garments: OptionButton
var meshes: OptionButton
var surface: SpinBox
var group_name: LineEdit
var conditions: ItemList
var groups: OptionButton
var status: Label
var viewport: SubViewport
var camera: Camera3D
var assembly: Node3D
var overlay: MeshInstance3D
var target_mesh: MeshInstance3D
var originals: Dictionary = {}
var garment_roots: Dictionary = {}
var selected: Array = []
var orbit := Vector2(0.0, 0.08)
var distance := 2.8
var preview_hidden := false
var isolated := false
var dirty := false
var selection_dirty := false
var busy := false
var brush_radius: SpinBox

static func write_face_rule(data: Dictionary, garment_id: String, part_id: String, node_path: String, surface_id: int, triangles: Array, outer_ids: Array) -> Dictionary:
	if garment_id=="__body__":
		var proxy:=data.duplicate(true);var mask:Dictionary=proxy.get("body",{}).get("masking",{"parts":{},"rules":[]}).duplicate(true)
		mask.merge({"id":"__body_proxy__","variants":{"default":{"scene":""}},"morph_limits":{}},true)
		proxy.garments.append(mask);proxy.body.erase("masking")
		var result:=write_face_rule(proxy,"__body_proxy__",part_id,node_path,surface_id,triangles,outer_ids)
		if not result.get("errors",[]).is_empty():return result
		var saved:Dictionary=result.catalog.garments.pop_back();result.catalog.body["masking"]={"id":"__body__","parts":saved.parts,"rules":saved.rules}
		return result
	var candidate := data.duplicate(true)
	if part_id.strip_edges().is_empty() or node_path.is_empty() or triangles.is_empty() or outer_ids.is_empty() or surface_id < 0:
		return {"errors": ["Grup adı, mesh, seçili yüz ve en az bir dış giysi gerekli."]}
	for garment: Dictionary in candidate.get("garments", []):
		if garment.get("id") != garment_id: continue
		if garment.get("parts", {}).has(part_id) and not garment["parts"][part_id].has("faces"):
			return {"errors": ["Bu ad tam mesh parçasına ait; yeni grup adı kullanın."]}
		garment["parts"][part_id] = {"node": node_path, "covers": [], "faces": {"surface": surface_id, "triangles": triangles.duplicate()}}
		var rule_id := "hide-" + part_id
		var found := false
		for rule: Dictionary in garment["rules"]:
			if rule["id"] != rule_id: continue
			rule.get_or_add("when", {})["all_items"] = outer_ids.duplicate()
			var hidden: Array = rule.get_or_add("actions", {}).get_or_add("hide_parts", [])
			if part_id not in hidden: hidden.append(part_id)
			found = true
		if not found: garment["rules"].append({"id": rule_id, "priority": 20, "when": {"all_items": outer_ids.duplicate()}, "actions": {"hide_parts": [part_id]}})
		var errors := Bridge.validate_catalog(candidate)
		return {"catalog": candidate, "errors": errors}
	return {"errors": ["Giysi bulunamadı."]}

static func topology_sha256(mesh: Mesh, surface_id: int) -> String:
	var arrays := mesh.surface_get_arrays(surface_id)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(str(vertices.size()).to_utf8_buffer())
	hashing.update(indices.to_byte_array())
	return hashing.finish().hex_encode()

static func filtered_mesh(source: Mesh, surface_id: int, triangles: Array) -> ArrayMesh:
	var result := ArrayMesh.new()
	for index in source.get_blend_shape_count(): result.add_blend_shape(source.get_blend_shape_name(index))
	result.blend_shape_mode = source.blend_shape_mode
	for index in source.get_surface_count():
		var arrays := source.surface_get_arrays(index).duplicate(true)
		if index == surface_id:
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if indices.is_empty():
				for vertex in arrays[Mesh.ARRAY_VERTEX].size(): indices.append(vertex)
			var kept := PackedInt32Array()
			for triangle in indices.size() / 3:
				if triangle not in triangles:
					for offset in 3: kept.append(indices[triangle * 3 + offset])
			if kept.is_empty(): kept = PackedInt32Array([0, 0, 0])
			arrays[Mesh.ARRAY_INDEX] = kept
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, source.surface_get_blend_shape_arrays(index), {}, source.surface_get_format(index))
		result.surface_set_material(index, source.surface_get_material(index))
	return result

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(margin)
	var row := HBoxContainer.new(); margin.add_child(row)
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size.x = 380; scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; row.add_child(scroll)
	var panel := VBoxContainer.new(); panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL; panel.add_theme_constant_override("separation", 6); scroll.add_child(panel)
	_label(panel, "BODY LAB → AERO → GODOT")
	_label(panel, "Örtülen yüzleri gizle · kaynak mesh silinmez")
	source_project = _directory(panel, "1. Body Lab çıktılarını içeren Godot projesi", true)
	var sibling := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("prototype")
	if FileAccess.file_exists(sibling.path_join("project.godot")): source_project.text = sibling
	_button(panel, "Adventure setini kopyala / aç", _import_set)
	_label(panel, "2. Beden/giysi ve mesh seç; sol tuşla yüzlere tıkla")
	garments = OptionButton.new(); garments.fit_to_longest_item = false; garments.clip_text = true; panel.add_child(garments); garments.item_selected.connect(func(_i: int): _show_garment())
	meshes = OptionButton.new(); meshes.fit_to_longest_item = false; meshes.clip_text = true; panel.add_child(meshes); meshes.item_selected.connect(func(_i: int): _choose_mesh())
	_label(panel, "Yüzey (malzeme bölümü; üçgen kimliği bu yüzeye aittir)")
	surface = SpinBox.new(); surface.min_value = 0; surface.max_value = 0; panel.add_child(surface)
	surface.value_changed.connect(func(_value: float): _clear_selection())
	groups = OptionButton.new(); groups.fit_to_longest_item = false; groups.clip_text = true; panel.add_child(groups); groups.item_selected.connect(_load_group)
	group_name = _line(panel, "3. Yüz grubu adı (örn. bluz_korse_alti)")
	group_name.text = "covered_faces"
	_label(panel, "4. Gizlemeyi etkinleştiren dış giysiler (hepsi giyilince)")
	conditions = ItemList.new(); conditions.select_mode = ItemList.SELECT_MULTI; conditions.custom_minimum_size.y = 120; panel.add_child(conditions)
	_button(panel, "İç giysiyi göster / tüm set", _isolate)
	_label(panel, "Fırça yarıçapı (piksel; 0 = tek yüz) · Shift: seçimden çıkar")
	brush_radius = SpinBox.new(); brush_radius.min_value = 0; brush_radius.max_value = 60; brush_radius.value = 12; panel.add_child(brush_radius)
	_button(panel, "Yüzeyi tamamen seç", _select_surface)
	_button(panel, "Seçimi temizle", _clear_selection)
	_button(panel, "Seçimi gizle / göster (önizleme)", _toggle_preview)
	_button(panel, "Yüz grubu + gizleme kuralını uygula", _apply_group)
	_button(panel, "Çalışma kataloğunu kaydet", _save)
	target_project = _directory(panel, "5. Hedef Godot projesi (GLB + adventure.json)", false)
	target_project.text = source_project.text
	_button(panel, "Godot'a aktar", _export)
	_button(panel, "Koşul ve morph kuralları", _open_rules)
	status = _label(panel, "Sağ sürükle: dön · Tekerlek: yaklaş · Sol sürükle: seç · Shift: çıkar")
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var view := SubViewportContainer.new(); view.stretch = true; view.size_flags_horizontal = Control.SIZE_EXPAND_FILL; view.size_flags_vertical = Control.SIZE_EXPAND_FILL; row.add_child(view)
	view.gui_input.connect(_input_view)
	viewport = SubViewport.new(); viewport.own_world_3d = true; view.add_child(viewport)
	var world := Node3D.new(); viewport.add_child(world)
	assembly = Node3D.new(); world.add_child(assembly)
	overlay = MeshInstance3D.new(); world.add_child(overlay)
	camera = Camera3D.new(); camera.fov = 38; world.add_child(camera); camera.current = true; _camera()
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-35, -35, 0); sun.light_energy = 1.7; world.add_child(sun)
	var environment := WorldEnvironment.new(); environment.environment = Environment.new(); environment.environment.background_mode = Environment.BG_COLOR; environment.environment.background_color = Color("293340"); environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_color = Color.WHITE; environment.environment.ambient_light_energy = 0.7; world.add_child(environment)
	if FileAccess.file_exists(WORK_CATALOG): _load_work()

func _import_set() -> void:
	if busy: return
	if dirty or selection_dirty:
		status.text = "Kaydet/aktar: yeniden içe aktarma hazırlığı değiştirecek. Önce yüz grubunu uygula ve Aero kataloğunu kaydet veya oyuna aktar."
		return
	var source := source_project.text.strip_edges()
	var data := Bridge.load_catalog(source.path_join("data/wardrobe/adventure.json"))
	var result := Bridge.export_catalog(data, "res://", source, "adventure_work")
	status.text = str(result.get("message", ""))
	if result["error"] != OK: return
	# Author actual editor-imported triangle order; raw GLTFDocument meshes
	# differ after Godot's mesh optimization during editor import.
	_set_busy(true)
	status.text = "Godot GLB içe aktarımı sürüyor… Hazırlık tamamlanınca set açılacak."
	var process := OS.create_process(OS.get_executable_path(), ["--headless", "--quiet", "--path", ProjectSettings.globalize_path("res://"), "--editor", "--import"], false)
	if process < 0:
		_set_busy(false)
		status.text = "Godot içe aktarma işlemi başlatılamadı."
		return
	var started := Time.get_ticks_msec()
	while OS.is_process_running(process):
		await get_tree().create_timer(0.2).timeout
		status.text = "Godot GLB içe aktarımı sürüyor… %d sn" % ((Time.get_ticks_msec() - started) / 1000)
	var code := OS.get_process_exit_code(process)
	_set_busy(false)
	if code != 0:
		status.text = "Godot içe aktarımı başarısız (çıkış %d). Çalışma kaydı diskte korundu; tekrar deneyin." % code
		return
	_load_work()

func _set_busy(value: bool) -> void:
	busy = value
	for button in find_children("*", "BaseButton", true, false): button.disabled = value
	for field: LineEdit in [source_project, target_project, group_name]: field.editable = not value
	surface.editable = not value
	conditions.mouse_filter = Control.MOUSE_FILTER_IGNORE if value else Control.MOUSE_FILTER_STOP

func _load_glb(path: String) -> Node3D:
	var scene := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	return scene.instantiate() if scene != null else null

func _load_work() -> void:
	catalog = Bridge.load_catalog(WORK_CATALOG)
	var errors := Bridge.validate_catalog(catalog)
	if not errors.is_empty(): status.text = "; ".join(errors); return
	for child in assembly.get_children(): child.free()
	garment_roots.clear(); originals.clear(); garments.clear()
	var body_path := str(catalog.get("body", {}).get("scene", ""))
	if not body_path.is_empty():
		var body := _load_glb(body_path)
		if body:
			assembly.add_child(body)
			_freeze_rest_meshes(body)
			garment_roots["__body__"]=body;_remember_meshes(body)
	for garment: Dictionary in catalog["garments"]:
		var variant: Dictionary = garment["variants"][garment.get("default_variant", "default")]
		var model := _load_glb(variant["scene"])
		if model == null: status.text = "GLB açılamadı: " + variant["scene"]; return
		assembly.add_child(model)
		_freeze_rest_meshes(model)
		garment_roots[garment["id"]] = model
		garments.add_item(str(garment.get("name", garment["id"])))
		_remember_meshes(model)
	if garment_roots.has("__body__"):garments.add_item("BEDEN · giysi altında kalan yüzler")
	dirty = false; selection_dirty = false
	_show_garment()
	status.text = "Adventure seti hazır. Kaynaklar Aero'ya kopyalandı; bedeni veya bir iç giysi seçin."

func _freeze_rest_meshes(node: Node) -> void:
	# Bind/rest products share one transform in this exported rest pose. Detach
	# preview skins so rendering, picking and overlay use identical coordinates.
	# Imported mesh arrays (and exported GLBs) stay unchanged.
	if node is MeshInstance3D and node.skin != null and node.skin.get_bind_count() > 0:
		var skeleton := node.get_node_or_null(node.skeleton) as Skeleton3D
		if skeleton != null:
			var bone := skeleton.find_bone(node.skin.get_bind_name(0))
			if bone < 0: bone = node.skin.get_bind_bone(0)
			if bone >= 0:
				var rest: Transform3D = skeleton.global_transform * skeleton.get_bone_global_rest(bone) * node.skin.get_bind_pose(0)
				node.skin = null
				node.skeleton = NodePath("")
				node.global_transform = rest
	for child in node.get_children(): _freeze_rest_meshes(child)

func _remember_meshes(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null: originals[node] = node.mesh
	for child in node.get_children(): _remember_meshes(child)

func _garment() -> Dictionary:
	if garments.selected==catalog.get("garments",[]).size():return catalog.body.get_or_add("masking",{"id":"__body__","parts":{},"rules":[]})
	return catalog["garments"][garments.selected] if garments.selected >= 0 else {}

func _show_garment() -> void:
	_restore_mesh()
	meshes.clear(); groups.clear(); conditions.clear()
	var root: Node3D = garment_roots.get(_garment().get("id"))
	if root == null: return
	for node: MeshInstance3D in originals:
		if root.is_ancestor_of(node): meshes.add_item(str(root.get_path_to(node)))
	groups.add_item("— yeni yüz grubu —")
	for id: String in _garment().get("parts", {}):
		if _garment()["parts"][id].has("faces"): groups.add_item(id)
	for garment: Dictionary in catalog["garments"]:
		if garment["id"] == _garment()["id"]: continue
		conditions.add_item(str(garment.get("name", garment["id"]))); conditions.set_item_metadata(conditions.item_count - 1, garment["id"])
	_choose_mesh()
	_update_isolation()

func _choose_mesh() -> void:
	_restore_mesh()
	target_mesh = null
	if meshes.selected < 0: return
	var root: Node3D = garment_roots[_garment()["id"]]
	target_mesh = root.get_node_or_null(meshes.get_item_text(meshes.selected))
	if target_mesh == null: return
	surface.max_value = target_mesh.mesh.get_surface_count() - 1
	surface.value = 0
	_clear_selection()

func _restore_mesh() -> void:
	if is_instance_valid(target_mesh) and originals.has(target_mesh): target_mesh.mesh = originals[target_mesh]
	preview_hidden = false

func _clear_selection() -> void:
	_restore_mesh(); selected.clear(); selection_dirty = false; _draw_selection()

func _load_group(index: int) -> void:
	if index == 0: return
	var id := groups.get_item_text(index)
	var part: Dictionary = _garment()["parts"][id]
	_clear_selection()
	var found := false
	for mesh_index in meshes.item_count:
		if meshes.get_item_text(mesh_index) == part["node"]: meshes.select(mesh_index); _choose_mesh(); found = true; break
	if not found: status.text = "Grup mesh düğümü artık bulunamıyor."; return
	if int(part["faces"]["surface"]) > surface.max_value: status.text = "Grup yüzeyi artık bulunamıyor."; return
	surface.value = part["faces"]["surface"]
	if part["faces"].has("topology_sha256") and part["faces"]["topology_sha256"] != topology_sha256(originals[target_mesh], int(surface.value)):
		status.text = "Bu grubun mesh topolojisi değişmiş. Yüzleri yeniden seçip uygulayın."
		return
	selected = part["faces"]["triangles"].duplicate()
	group_name.text = id
	conditions.deselect_all()
	for rule: Dictionary in _garment()["rules"]:
		if rule["id"] != "hide-" + id: continue
		for condition in conditions.item_count:
			if conditions.get_item_metadata(condition) in rule.get("when", {}).get("all_items", []): conditions.select(condition, false)
	_draw_selection()

func _apply_group() -> void:
	if busy: return
	if target_mesh == null: return
	var outer_ids: Array = []
	for index in conditions.get_selected_items(): outer_ids.append(conditions.get_item_metadata(index))
	var result := write_face_rule(catalog, _garment()["id"], group_name.text.strip_edges(), meshes.get_item_text(meshes.selected), int(surface.value), selected, outer_ids)
	if not result["errors"].is_empty(): status.text = "; ".join(result["errors"]); return
	catalog = result["catalog"]
	var id := group_name.text.strip_edges()
	_garment()["parts"][id]["faces"]["topology_sha256"] = topology_sha256(originals[target_mesh], int(surface.value))
	dirty = true; selection_dirty = false
	var known := false
	for index in groups.item_count:
		if groups.get_item_text(index) == id: known = true
	if not known: groups.add_item(id)
	status.text = "%d yüz için kural hazır; kaydedin veya aktarın. Kaynak mesh korunur." % selected.size()

func _save() -> void:
	if busy: return
	if selection_dirty: status.text = "Önce seçilen yüz grubunu ve kuralını uygula."; return
	var error := Bridge.save_catalog(catalog, WORK_CATALOG)
	if error == OK: dirty = false
	status.text = "Kaydetme: " + error_string(error)

func _export() -> void:
	if busy: return
	if selection_dirty: status.text = "Önce seçilen yüz grubunu ve kuralını uygula."; return
	var problems := _topology_errors()
	if not problems.is_empty(): status.text = "; ".join(problems); return
	var error := Bridge.save_catalog(catalog, WORK_CATALOG)
	if error != OK: status.text = error_string(error); return
	var result := Bridge.export_catalog(catalog, target_project.text.strip_edges(), "res://", "adventure", "body_lab")
	status.text = str(result.get("message", ""))
	if result["error"] == OK: dirty = false

func _topology_errors() -> Array[String]:
	var problems: Array[String] = []
	var entries:Array=catalog.get("garments", []).duplicate()
	if catalog.get("body",{}).has("masking"):entries.append(catalog.body.masking)
	for garment: Dictionary in entries:
		var model: Node3D = garment_roots.get(garment["id"])
		if model == null: problems.append("Giysi yüklenemedi: " + garment["id"]); continue
		for id: String in garment["parts"]:
			var part: Dictionary = garment["parts"][id]
			if not part.has("faces"): continue
			var node := model.get_node_or_null(str(part.get("node", id))) as MeshInstance3D
			var face: Dictionary = part["faces"]
			if node == null or not originals.has(node) or int(face["surface"]) >= originals[node].get_surface_count():
				problems.append("Grup mesh/yüzeyi bulunamadı: " + id); continue
			if face.has("topology_sha256") and face["topology_sha256"] != topology_sha256(originals[node], int(face["surface"])):
				problems.append("Topoloji değişmiş; grubu yeniden seçin: " + id); continue
			var arrays: Array = originals[node].surface_get_arrays(int(face["surface"]))
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var count: int = indices.size() / 3 if not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size() / 3
			for triangle: Variant in face["triangles"]:
				if int(triangle) >= count: problems.append("Üçgen modelle eşleşmiyor: " + id); break
	return problems

func _toggle_preview() -> void:
	if target_mesh == null or selected.is_empty(): return
	preview_hidden = not preview_hidden
	target_mesh.mesh = filtered_mesh(originals[target_mesh], int(surface.value), selected) if preview_hidden else originals[target_mesh]
	overlay.visible = not preview_hidden

func _triangles() -> Array:
	if target_mesh == null: return []
	var arrays: Array = originals[target_mesh].surface_get_arrays(int(surface.value))
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty():
		for index in vertices.size(): indices.append(index)
	return [vertices, indices]

func _isolate() -> void:
	isolated = not isolated
	_update_isolation()

func _update_isolation() -> void:
	for child in assembly.get_children(): child.visible = not isolated or child == garment_roots.get(_garment().get("id"))

func _select_surface() -> void:
	var geometry := _triangles()
	if geometry.is_empty(): return
	_restore_mesh(); selected.clear(); selection_dirty = true
	for index in geometry[1].size() / 3: selected.append(index)
	_draw_selection()
	status.text = "%d yüz seçildi." % selected.size()

func _input_view(event: InputEvent) -> void:
	if busy: return
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_paint_selection(event.position, event.shift_pressed)
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		orbit += event.relative * 0.008; orbit.y = clampf(orbit.y, -1.3, 1.3); _camera()
	if not event is InputEventMouseButton or not event.pressed: return
	if event.button_index == MOUSE_BUTTON_WHEEL_UP: distance = maxf(0.4, distance * 0.9); _camera()
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: distance = minf(12, distance * 1.1); _camera()
	elif event.button_index == MOUSE_BUTTON_LEFT: _paint_selection(event.position, event.shift_pressed)

func _paint_selection(position: Vector2, remove: bool) -> void:
	selection_dirty = true
	_restore_mesh()
	var offsets: Array[Vector2] = [Vector2.ZERO]
	if brush_radius.value > 0:
		for offset in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]: offsets.append(offset * brush_radius.value)
	for offset in offsets:
		var hit := _pick(position + offset)
		if hit < 0: continue
		if remove: selected.erase(hit)
		elif hit not in selected: selected.append(hit)
	selected.sort(); _draw_selection()
	status.text = "%d yüz seçildi. Shift: seçimden çıkar. Fırça yalnız seçili mesh'in en yakın yüzünü seçer." % selected.size()

func _pick(position: Vector2) -> int:
	var geometry := _triangles()
	if geometry.is_empty(): return -1
	var inverse := target_mesh.global_transform.affine_inverse()
	var origin := inverse * camera.project_ray_origin(position)
	var end := inverse * (camera.project_ray_origin(position) + camera.project_ray_normal(position) * 100)
	var closest := INF
	var hit := -1
	var vertices: PackedVector3Array = geometry[0]
	var indices: PackedInt32Array = geometry[1]
	for triangle in indices.size() / 3:
		var point: Variant = Geometry3D.ray_intersects_triangle(origin, (end - origin).normalized(), vertices[indices[triangle * 3]], vertices[indices[triangle * 3 + 1]], vertices[indices[triangle * 3 + 2]])
		if point != null and origin.distance_squared_to(point) < closest:
			closest = origin.distance_squared_to(point); hit = triangle
	return hit

func _draw_selection() -> void:
	if overlay == null: return
	overlay.mesh = null; overlay.visible = true
	var geometry := _triangles()
	if geometry.is_empty() or selected.is_empty(): return
	var material := StandardMaterial3D.new(); material.albedo_color = Color(1, 0.22, 0.08, 0.8); material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; material.cull_mode = BaseMaterial3D.CULL_DISABLED; material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; material.no_depth_test = true
	var mesh := ImmediateMesh.new(); mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	var vertices: PackedVector3Array = geometry[0]
	var indices: PackedInt32Array = geometry[1]
	for triangle: Variant in selected:
		if int(triangle) * 3 + 2 >= indices.size(): continue
		for offset in 3: mesh.surface_add_vertex(target_mesh.global_transform * vertices[indices[int(triangle) * 3 + offset]])
	mesh.surface_end(); overlay.mesh = mesh

func _camera() -> void:
	var focus := Vector3(0, 0.86, 0)
	camera.position = focus + Vector3(sin(orbit.x) * cos(orbit.y), sin(orbit.y), cos(orbit.x) * cos(orbit.y)) * distance
	camera.look_at(focus)

func _label(parent: Node, value: String) -> Label:
	var label := Label.new(); label.text = value; label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; parent.add_child(label); return label

func _line(parent: Node, title: String) -> LineEdit:
	_label(parent, title); var line := LineEdit.new(); parent.add_child(line); return line

func _button(parent: Node, title: String, callback: Callable) -> void:
	var button := Button.new(); button.text = title; button.tooltip_text = title; button.clip_text = true; button.add_theme_font_size_override("font_size", 14); button.custom_minimum_size.y = 30; button.pressed.connect(callback); parent.add_child(button)
	if parent is HBoxContainer: button.custom_minimum_size.x = 96

func _open_rules() -> void:
	if busy: return
	if Bridge.save_catalog(catalog, WORK_CATALOG) != OK: return
	var bridge := Bridge.new()
	bridge.catalog_path = WORK_CATALOG
	bridge.export_name = "adventure"
	bridge.export_asset_folder = "body_lab"
	get_tree().root.add_child(bridge)
	get_tree().current_scene = bridge
	queue_free()

func _directory(parent: Node, title: String, source: bool) -> LineEdit:
	_label(parent, title)
	var row := HBoxContainer.new(); parent.add_child(row)
	var field := LineEdit.new(); field.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(field)
	_button(row, "Klasör seç…", func():
		var dialog := FileDialog.new()
		dialog.use_native_dialog = true
		dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		dialog.access = FileDialog.ACCESS_FILESYSTEM
		dialog.title = title
		if DirAccess.dir_exists_absolute(field.text): dialog.current_dir = field.text
		add_child(dialog)
		dialog.dir_selected.connect(func(path: String):
			if source and (target_project.text.is_empty() or target_project.text == field.text): target_project.text = path
			field.text = path
			dialog.queue_free())
		dialog.canceled.connect(dialog.queue_free)
		dialog.popup_centered_ratio(0.7))
	return field
