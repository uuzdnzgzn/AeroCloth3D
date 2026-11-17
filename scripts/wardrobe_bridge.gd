extends Control
## Small catalog bridge; the destination game's catalog/resolver remains authoritative.
const DEFAULT_CATALOG := "res://demo/wardrobe_trial/catalog.json"
var catalog: Dictionary = {}
var catalog_path := DEFAULT_CATALOG
var export_name := "aero_trial"
var export_asset_folder := ""
var garments: OptionButton
var rules: OptionButton
var all_items: LineEdit
var morphs: OptionButton
var amount: SpinBox
var hide_parts: LineEdit
var destination: LineEdit
var status: Label

static func load_catalog(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 4 * 1024 * 1024: return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}

static func validate_catalog(data: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	if data.get("version") != 1 or not data.get("garments") is Array:
		return ["Katalog v1 / garments gerekli."]
	var ids := {}
	for garment: Variant in data["garments"]:
		if not garment is Dictionary or not garment.get("id") is String or str(garment["id"]).is_empty() or ids.has(garment["id"]):
			return ["Giysi kimliği eksik veya tekrarlı."]
		ids[garment["id"]] = true
	for garment: Dictionary in data["garments"]:
		if not garment.get("variants") is Dictionary or not garment.get("parts") is Dictionary or not garment.get("morph_limits", {}) is Dictionary or not garment.get("rules", []) is Array:
			return ["Varyant, parça, morph veya kural yapısı geçersiz."]
		for part: Variant in garment["parts"].values():
			if not part is Dictionary: return ["Parça nesne olmalı."]
			if part.has("faces"):
				var face: Variant = part["faces"]
				if not face is Dictionary or not face.get("surface") is int and not face.get("surface") is float or not face.get("triangles") is Array:
					return ["Yüz grubu yüzey/üçgen listesi geçersiz."]
				if float(face["surface"]) < 0 or float(face["surface"]) != floorf(float(face["surface"])) or face["triangles"].is_empty(): return ["Yüz grubu boş veya yüzeyi geçersiz."]
				for triangle: Variant in face["triangles"]:
					if not (triangle is int or triangle is float) or float(triangle) < 0 or float(triangle) != floorf(float(triangle)): return ["Üçgen kimliği geçersiz."]
		var rule_ids := {}
		for rule: Variant in garment.get("rules", []):
			if not rule is Dictionary or not rule.get("id") is String or str(rule["id"]).is_empty() or rule_ids.has(rule["id"]) or not rule.get("when", {}) is Dictionary or not rule.get("actions", {}) is Dictionary:
				return ["Kural kimliği/yapısı geçersiz."]
			rule_ids[rule["id"]] = true
			var required: Variant = rule.get("when", {}).get("all_items", [])
			if not required is Array: return ["all_items liste olmalı."]
			for id: Variant in required:
				if not id is String or not ids.has(id): problems.append("Koşulda giysi bulunamadı: " + str(id))
			var hidden: Variant = rule.get("actions", {}).get("hide_parts", [])
			if not hidden is Array: return ["hide_parts liste olmalı."]
			for part: Variant in hidden:
				if not part is String or not garment["parts"].has(part): problems.append("Parça bulunamadı: " + str(part))
			var values: Variant = rule.get("actions", {}).get("morphs", {})
			if not values is Dictionary: return ["morphs nesne olmalı."]
			for name: String in values:
				if not garment.get("morph_limits", {}).has(name): problems.append("Morph bulunamadı: " + name)
				var value: Variant = values[name]
				if not value is Dictionary and (not (value is int or value is float) or not is_finite(float(value))): problems.append("Morph değeri geçersiz: " + name)
	return problems

static func update_rule(data: Dictionary, garment_id: String, rule_id: String, required: Array, morph: String, value: float, hidden: Array) -> Dictionary:
	var candidate := data.duplicate(true)
	for garment: Dictionary in candidate.get("garments", []):
		if garment.get("id") != garment_id: continue
		for rule: Dictionary in garment.get("rules", []):
			if rule.get("id") != rule_id: continue
			rule.get_or_add("when", {})["all_items"] = required.duplicate()
			rule.get_or_add("actions", {})["hide_parts"] = hidden.duplicate()
			if not morph.is_empty(): rule["actions"].get_or_add("morphs", {})[morph] = value
			var errors := validate_catalog(candidate)
			return {"catalog": candidate if errors.is_empty() else data, "errors": errors}
	return {"catalog": data, "errors": ["Düzenlenecek giysi/kural bulunamadı."]}

static func save_catalog(data: Dictionary, path: String) -> Error:
	if not validate_catalog(data).is_empty(): return ERR_INVALID_DATA
	var absolute := ProjectSettings.globalize_path(path)
	var error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if error != OK: return error
	var file := FileAccess.open(absolute + ".tmp", FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t") + "\n")
	file.flush()
	error = file.get_error()
	file.close()
	if error != OK: return error
	return DirAccess.rename_absolute(absolute + ".tmp", absolute)

static func export_catalog(data: Dictionary, target_project: String, source_root: String = "res://", output_name: String = "aero_trial", asset_folder: String = "") -> Dictionary:
	var errors := validate_catalog(data)
	if not errors.is_empty(): return {"error": ERR_INVALID_DATA, "message": "; ".join(errors)}
	var target := ProjectSettings.globalize_path(target_project).simplify_path()
	if not FileAccess.file_exists(target.path_join("project.godot")): return {"error": ERR_INVALID_PARAMETER, "message": "Hedef Godot proje klasörü olmalı."}
	var candidate := data.duplicate(true)
	if output_name.is_empty() or output_name.validate_filename() != output_name or "." in output_name:
		return {"error": ERR_INVALID_PARAMETER, "message": "Çıktı adı yalnız dosya kimliği olmalı."}
	if asset_folder.is_empty(): asset_folder = output_name
	if asset_folder.validate_filename() != asset_folder or "." in asset_folder: return {"error": ERR_INVALID_PARAMETER, "message": "Varlık klasörü geçersiz."}
	var copies := {}
	var references: Array = []
	if not str(candidate.get("body", {}).get("scene", "")).is_empty(): references.append(candidate["body"])
	for garment: Dictionary in candidate["garments"]:
		for variant: Dictionary in garment["variants"].values(): references.append(variant)
	for reference: Dictionary in references:
		var source := str(reference.get("scene", ""))
		if not source.begins_with("res://") or ".." in source.split("/") or source.get_extension().to_lower() != "glb":
			return {"error": ERR_INVALID_DATA, "message": "Varyant bağımsız res:// GLB olmalı: " + source}
		var relative := "assets/" + asset_folder + "/" + source.get_file()
		var input := ProjectSettings.globalize_path(source_root.path_join(source.trim_prefix("res://")))
		if not FileAccess.file_exists(input): return {"error": ERR_FILE_NOT_FOUND, "message": input}
		if copies.has(relative) and copies[relative] != input: return {"error": ERR_ALREADY_EXISTS, "message": "GLB dosya adı çakışması: " + relative}
		var fingerprint := FileAccess.get_sha256(input)
		if reference.has("source_sha256") and reference["source_sha256"] != fingerprint:
			return {"error": ERR_INVALID_DATA, "message": "Kaynak GLB değişmiş; yüz gruplarını yeniden doğrulayın: " + input}
		reference["source_sha256"] = fingerprint
		copies[relative] = input
		reference["scene"] = "res://" + relative
	for relative: String in copies:
		var output := target.path_join(relative)
		var error := DirAccess.make_dir_recursive_absolute(output.get_base_dir())
		if error == OK and copies[relative].simplify_path() != output.simplify_path(): error = DirAccess.copy_absolute(copies[relative], output)
		if error == OK: error = _configure_import(output, "res://" + relative)
		if error != OK: return {"error": error, "message": output}
	var path := target.path_join("data/wardrobe/" + output_name + ".json")
	var error := save_catalog(candidate, path)
	return {"error": error, "path": path, "message": "Aktarıldı: " + path if error == OK else "Katalog yazılamadı."}

static func _configure_import(asset_path: String, resource_path: String) -> Error:
	var config := ConfigFile.new()
	var sidecar := asset_path + ".import"
	if FileAccess.file_exists(sidecar):
		var error := config.load(sidecar)
		if error != OK: return error
	else:
		config.set_value("remap", "importer", "scene")
		config.set_value("remap", "type", "PackedScene")
		config.set_value("deps", "source_file", resource_path)
	# Face groups address source triangles; generated LODs change that topology.
	config.set_value("params", "meshes/generate_lods", false)
	return config.save(sidecar)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := VBoxContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_constant_override("separation", 8)
	add_child(panel)
	_label(panel, "Aero → Godot giysi kataloğu · koşul / morph / parça")
	garments = OptionButton.new(); panel.add_child(garments)
	rules = OptionButton.new(); panel.add_child(rules)
	all_items = _line(panel, "when.all_items · giysi kimlikleri, virgülle")
	_label(panel, "Sabit değer uygulanacak morph · diğer morph eylemleri korunur")
	morphs = OptionButton.new(); panel.add_child(morphs)
	amount = SpinBox.new(); amount.min_value = -100000; amount.max_value = 100000; amount.step = 0.01; panel.add_child(amount)
	hide_parts = _line(panel, "actions.hide_parts · kendi parça kimlikleri, virgülle")
	_button(panel, "Kuralı uygula", _apply)
	_button(panel, "Kaynak kataloğu kaydet", func():
		if _apply(): status.text = "Kaydetme: " + error_string(save_catalog(catalog, catalog_path)))
	destination = _line(panel, "Hedef Godot proje klasörü · project.godot içeren mutlak yol")
	destination.text = ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("prototype")
	_button(panel, "Body Lab · örtülen yüzleri düzenle", func(): get_tree().change_scene_to_file("res://demo/AdventureAuthoring.tscn"))
	_button(panel, "3B Aero çalışma alanını aç", func(): get_tree().change_scene_to_file("res://demo/AuthoringLab.tscn"))
	_button(panel, "GLB + kataloğu hedef projeye aktar", func():
		if _apply(): status.text = str(export_catalog(catalog, destination.text.strip_edges(), "res://", export_name, export_asset_folder).get("message", "Aktarım başarısız.")))
	status = _label(panel, "")
	garments.item_selected.connect(func(_index: int): _show_garment())
	rules.item_selected.connect(func(_index: int): _show_rule())
	morphs.item_selected.connect(func(_index: int): _show_morph())
	catalog = load_catalog(catalog_path)
	var errors := validate_catalog(catalog)
	if not errors.is_empty(): status.text = "; ".join(errors); return
	for garment: Dictionary in catalog["garments"]: garments.add_item(garment["id"])
	_show_garment()

func _garment() -> Dictionary:
	return catalog["garments"][garments.selected] if garments.selected >= 0 else {}

func _rule() -> Dictionary:
	return _garment().get("rules", [])[rules.selected] if rules.selected >= 0 else {}

func _show_garment() -> void:
	rules.clear(); morphs.clear(); morphs.add_item("— koru —")
	for rule: Dictionary in _garment().get("rules", []): rules.add_item(rule["id"])
	for name: String in _garment().get("morph_limits", {}): morphs.add_item(name)
	_show_rule()

func _show_rule() -> void:
	all_items.text = ", ".join(_rule().get("when", {}).get("all_items", []))
	hide_parts.text = ", ".join(_rule().get("actions", {}).get("hide_parts", []))
	morphs.select(0)
	_show_morph()

func _show_morph() -> void:
	var value: Variant = _rule().get("actions", {}).get("morphs", {}).get(morphs.get_item_text(morphs.selected), 0)
	amount.value = float(value) if value is int or value is float else 0.0

func _apply() -> bool:
	if rules.selected < 0:
		var errors := validate_catalog(catalog)
		status.text = "Katalog doğrulandı." if errors.is_empty() else "; ".join(errors)
		return errors.is_empty()
	var result := update_rule(catalog, str(_garment().get("id", "")), str(_rule().get("id", "")), _csv(all_items.text), morphs.get_item_text(morphs.selected) if morphs.selected > 0 else "", amount.value, _csv(hide_parts.text))
	if not result["errors"].is_empty(): status.text = "; ".join(result["errors"]); return false
	catalog = result["catalog"]
	status.text = "Kural doğrulandı; kaydet veya aktar. Tam şema kontrolü hedef oyunda yapılır."
	return true

func _csv(text: String) -> Array:
	var result: Array = []
	for part: String in text.split(",", false):
		var clean := part.strip_edges()
		if not clean.is_empty() and clean not in result: result.append(clean)
	return result

func _label(parent: Node, text: String) -> Label:
	var label := Label.new(); label.text = text; parent.add_child(label); return label

func _line(parent: Node, text: String) -> LineEdit:
	_label(parent, text)
	var field := LineEdit.new(); parent.add_child(field); return field

func _button(parent: Node, text: String, callback: Callable) -> void:
	var button := Button.new(); button.text = text; button.pressed.connect(callback); parent.add_child(button)
