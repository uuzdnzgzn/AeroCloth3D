extends Control
## Runtime test workspace. The EditorPlugin opens this scene from Godot's Tools menu.

const Actor = preload("res://demo/scenario_character.gd")
const Geometry = preload("res://demo/scenario_meshes.gd")
const Profile = preload("res://demo/wardrobe_profile.gd")
const PROFILE_PATH := "user://wearable-profile.json"
const TEAL := Color("48dfca")
const TEXT := Color("d8e3f0")
const MUTED := Color("8697b0")
const IDS: Array[String] = ["bag", "shoulder", "chest", "cloth", "inner"]
const NAMES := {"bag":"Bağlı çanta", "shoulder":"Omuz zırhı", "chest":"Göğüslük", "cloth":"Sarkan kumaş", "inner":"İç katman"}
const SECTIONS: Array[String] = ["Hazırlama", "Boyama", "Çarpışma", "Katmanlar", "Hasar", "Hareket"]

var actors: Array[Node3D] = []
var viewport: SubViewport
var preview: SubViewportContainer
var world: Node3D
var camera: Camera3D
var tools_panel: VBoxContainer
var rows: Dictionary = {}
var section_buttons: Array[Button] = []
var selected := "shoulder"
var section := 4
var count := 1
var history := UndoRedo.new()
var orbit := Vector2(-0.48, 0.13)
var distance := 3.15
var focus := Vector3(0, 0.98, 0)
var status: Label
var preview_title: Label
var metric_label: Label
var state_label: Label
var undo_button: Button
var redo_button: Button
var frame_samples: Array[float] = []
var last_tick := 0
var paint_value := 0.0
var paint_before: Array = []
var painting := false
var benchmark_active := false
var benchmark_frame := 0
var benchmark_frames: Array[float] = []
var benchmark_events: Array[Dictionary] = []
var benchmark_pending := -1
var benchmark_last_frame := 0
var benchmark_result: Dictionary = {}
var benchmark_output := "res://artifacts/benchmark.json"
var benchmark_characters := 3
var benchmark_process_ms: Array[float] = []
var benchmark_physics_ms: Array[float] = []
var benchmark_cloth_ms: Array[float] = []
var screenshot_frame := -1
var automation_mode := ""

func _ready() -> void:
	_build_theme()
	_build_layout()
	_build_world()
	_build_tools()
	_refresh()
	last_tick = Time.get_ticks_usec()
	for argument in OS.get_cmdline_user_args():
		if argument == "--benchmark":
			automation_mode = "benchmark"
			call_deferred("_start_benchmark")
		elif argument.begins_with("--report="):
			benchmark_output = argument.trim_prefix("--report=")
		elif argument.begins_with("--characters="):
			benchmark_characters = clampi(argument.trim_prefix("--characters=").to_int(), 1, 3)
		elif argument.begins_with("--capture="):
			automation_mode = argument.trim_prefix("--capture=")
			screenshot_frame = 100
			if automation_mode == "lab-three":
				_set_count(3)

func _build_theme() -> void:
	var custom := Theme.new()
	custom.default_font_size = 14
	custom.set_color("font_color", "Label", TEXT)
	custom.set_color("font_color", "Button", TEXT)
	custom.set_color("font_hover_color", "Button", TEAL)
	custom.set_color("font_pressed_color", "Button", TEAL)
	custom.set_color("font_color", "CheckButton", TEXT)
	custom.set_color("font_color", "CheckBox", TEXT)
	for type_name in ["Button", "OptionButton"]:
		custom.set_stylebox("normal", type_name, _style(Color("1b293b"), Color("2b3b50"), 6))
		custom.set_stylebox("hover", type_name, _style(Color("233e4b"), TEAL, 6))
		custom.set_stylebox("pressed", type_name, _style(Color("153e40"), TEAL, 6))
		custom.set_stylebox("focus", type_name, _style(Color(0,0,0,0), TEAL, 6))
	custom.set_stylebox("panel", "PanelContainer", _style(Color("111c2b"), Color("233347"), 8))
	theme = custom
	var background := ColorRect.new()
	background.color = Color("0a111c")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

func _style(fill: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	return style

func _label(value: String, size: int = 14, color: Color = TEXT) -> Label:
	var node := Label.new()
	node.text = value
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	return node

func _text(parent: Node, value: String, color: Color = MUTED) -> Label:
	var label: Label = _label(value, 13, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _button(parent: Node, title: String, action: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size.y = 38
	button.pressed.connect(action)
	if primary:
		button.add_theme_stylebox_override("normal", _style(Color("16463f"), Color("3baf9f"), 6))
		button.add_theme_color_override("font_color", TEAL)
	parent.add_child(button)
	return button

func _build_layout() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 14)
	margin.add_child(stack)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 18)
	stack.add_child(header)
	var brand := VBoxContainer.new()
	header.add_child(brand)
	brand.add_child(_label("AERO / CLOTH 3D", 25, TEAL))
	brand.add_child(_label("Giyilebilir eşya laboratuvarı", 13, MUTED))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var recovery := _label("YENİ KURULUM  /  ANİMASYONLU TEST KARAKTERİ", 11, MUTED)
	header.add_child(recovery)
	undo_button = _button(header, "↶ Geri al", _undo)
	redo_button = _button(header, "↷ Yinele", _redo)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	stack.add_child(tabs)
	for i in range(SECTIONS.size()):
		var tab: Button = _button(tabs, "%02d  %s" % [i + 1, SECTIONS[i]], _select_section.bind(i))
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		section_buttons.append(tab)
	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 12)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(main)
	var left := PanelContainer.new()
	left.custom_minimum_size.x = 230
	main.add_child(left)
	var left_stack := VBoxContainer.new()
	left_stack.add_theme_constant_override("separation", 9)
	left.add_child(left_stack)
	left_stack.add_child(_label("GİYİLEN PARÇALAR", 12, MUTED))
	_text(left_stack, "Dıştan içe · bir parça seç", MUTED)
	for id in IDS:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 1)
		left_stack.add_child(row)
		var button: Button = _button(row, NAMES[id], _select_item.bind(id))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var sub: Label = _label("", 11, MUTED)
		row.add_child(sub)
		rows[id] = {"button":button,"sub":sub}
	var left_spacer := Control.new()
	left_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_stack.add_child(left_spacer)
	_text(left_stack, "Temel beden ve giysi\n20 kemik · Idle / Walk", MUTED)
	_text(left_stack, "Seç → bağlantıları yerleştir → alt katmanı kontrol et → darbe uygula.", TEXT)
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 8)
	main.add_child(center)
	var preview_header := HBoxContainer.new()
	center.add_child(preview_header)
	preview_title = _label("KARAKTER ÖNİZLEMESİ", 12, MUTED)
	preview_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_header.add_child(preview_title)
	_button(preview_header, "Odakla", _focus_selected)
	_button(preview_header, "Tümünü gör", _reset_camera)
	preview = SubViewportContainer.new()
	preview.stretch = true
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.custom_minimum_size = Vector2(380, 370)
	preview.gui_input.connect(_preview_input)
	center.add_child(preview)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.handle_input_locally = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	preview.add_child(viewport)
	var transport := HBoxContainer.new()
	transport.add_theme_constant_override("separation", 8)
	center.add_child(transport)
	_button(transport, "▶ Oynat", _play.bind(true))
	_button(transport, "Ⅱ Duraklat", _play.bind(false))
	var animation_select := OptionButton.new()
	animation_select.add_item("Idle")
	animation_select.add_item("Walk")
	animation_select.item_selected.connect(func(index: int) -> void:
		for actor in actors:
			actor.set_animation("Idle" if index == 0 else "Walk")
	)
	transport.add_child(animation_select)
	_button(transport, "↺ Sıfırla", func() -> void: _record("İlk duruma dön", _reset_all))
	var details := HBoxContainer.new()
	center.add_child(details)
	state_label = _label("", 12, TEAL)
	state_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_child(state_label)
	details.add_child(_label("Sağ sürükle: döndür · Tekerlek: yaklaş", 11, MUTED))
	var right := PanelContainer.new()
	right.custom_minimum_size.x = 310
	main.add_child(right)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	tools_panel = VBoxContainer.new()
	tools_panel.custom_minimum_size.x = 278
	tools_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools_panel.add_theme_constant_override("separation", 13)
	scroll.add_child(tools_panel)
	var footer := PanelContainer.new()
	stack.add_child(footer)
	var footer_stack := VBoxContainer.new()
	footer.add_child(footer_stack)
	metric_label = _label("Kare süreleri ölçülüyor…", 12, TEXT)
	footer_stack.add_child(metric_label)
	status = _label("Hazır. Omuz zırhına iki darbe uygulayarak senaryoyu deneyin.", 12, MUTED)
	footer_stack.add_child(status)

func _build_world() -> void:
	world = Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("101c2b")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("a2b9d3")
	settings.ambient_light_energy = 0.4
	environment.environment = settings
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-38, -35, 0)
	light.light_energy = 1.15
	light.shadow_enabled = true
	world.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 140, 0)
	fill.light_color = Color("51c5cf")
	fill.light_energy = 0.25
	world.add_child(fill)
	var floor_visual: MeshInstance3D = Geometry.box(Vector3(20, 0.1, 20), Color("152334"))
	floor_visual.position.y = -0.065
	world.add_child(floor_visual)
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(20, 0.1, 20)
	collision.shape = floor_shape
	floor_body.add_child(collision)
	floor_body.position.y = -0.065
	world.add_child(floor_body)
	var lines := PackedVector3Array()
	for i in range(-12, 13):
		var offset: float = i * 0.25
		lines.append_array(PackedVector3Array([Vector3(offset,-0.009,-3),Vector3(offset,-0.009,3),Vector3(-3,-0.009,offset),Vector3(3,-0.009,offset)]))
	world.add_child(Geometry.line(lines, Color("253a4b")))
	for i in range(3):
		var actor := Actor.new()
		actor.position.x = i * 1.15
		world.add_child(actor)
		actor.set_active(i == 0)
		actor.changed.connect(_refresh)
		actors.append(actor)
	camera = Camera3D.new()
	camera.fov = 35
	camera.near = 0.02
	world.add_child(camera)
	_update_camera()

func _clear_tools() -> void:
	for child in tools_panel.get_children():
		tools_panel.remove_child(child)
		child.queue_free()

func _build_tools() -> void:
	_clear_tools()
	tools_panel.add_child(_label(SECTIONS[section].to_upper(), 12, TEAL))
	tools_panel.add_child(_label(NAMES[selected], 23, TEXT))
	var toggle := CheckButton.new()
	toggle.text = "Giyili"
	toggle.button_pressed = actors[0].is_equipped(selected)
	toggle.toggled.connect(func(value: bool) -> void: _record("Giysi ekle / çıkar", func() -> void:
		for actor in actors: actor.set_equipped(selected, value)
	))
	tools_panel.add_child(toggle)
	match section:
		0: _preparation_tools()
		1: _paint_tools()
		2: _collision_tools()
		3: _layer_tools()
		4: _damage_tools()
		5: _motion_tools()
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 12
	tools_panel.add_child(spacer)
	tools_panel.add_child(_label("GEOMETRİ GÖRÜNÜMÜ", 11, MUTED))
	var views := HBoxContainer.new()
	tools_panel.add_child(views)
	for i in range(3):
		var title: String = ["Yüzey", "Kenar", "Vertex"][i]
		_button(views, title, func() -> void:
			for actor in actors: actor.set_debug(i)
		)
	_text(tools_panel, "Hazır kopma bölgeleri kullanılır. Serbest kesme ve beden morph zinciri henüz yok.")

func _preparation_tools() -> void:
	var saves := HBoxContainer.new()
	tools_panel.add_child(saves)
	_button(saves, "Ayarı kaydet", _save_profile)
	if FileAccess.file_exists(PROFILE_PATH): _button(saves, "Kaydı yükle", _load_profile)
	if selected not in ["shoulder", "bag"]:
		_text(tools_panel, "Bu test parçası hazır olarak yerleştirildi. Bağlantı düzenlemek için omuz zırhını veya çantayı seç.")
		_button(tools_panel, "Omuz zırhını seç", _select_item.bind("shoulder"))
		return
	_text(tools_panel, "Bağlantılar animasyon kemiğine göre tanımlıdır. Turkuaz noktalar sağlam, kırmızı noktalar kopuktur.")
	if selected == "shoulder":
		tools_panel.add_child(_label("Altındaki bölge", 12, MUTED))
		var region := OptionButton.new()
		region.add_item("İç omuz bölgesi")
		region.add_item("Örtme kuralı yok")
		region.selected = 0 if actors[0].shoulder_covers_inner else 1
		region.item_selected.connect(func(index: int) -> void:
			_record("Alt bölge ilişkisi", func() -> void:
				for actor in actors:
					actor.shoulder_covers_inner = index == 0
					actor.refresh_coverage()
			)
		)
		tools_panel.add_child(region)
	var piece: Node3D = actors[0].shoulder if selected == "shoulder" else actors[0].bag
	for index in range(piece.connection_points.size()):
		tools_panel.add_child(_label("Bağlantı %d · yerel metre" % [index + 1], 13, TEXT))
		for axis in range(3):
			var row := HBoxContainer.new()
			tools_panel.add_child(row)
			row.add_child(_label(["X", "Y", "Z"][axis], 12, MUTED))
			var value := SpinBox.new()
			value.min_value = -0.35
			value.max_value = 0.35
			value.step = 0.005
			value.value = piece.connection_points[index][axis]
			value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			value.value_changed.connect(_edit_connection.bind(index, axis))
			row.add_child(value)
	_text(tools_panel, "Çanta tek vertex yerine zırhın yerel socket çerçevesini izler. Deforme kumaşa üçgen/barycentric socket bağlama sonraki adımdır.")

func _edit_connection(value: float, index: int, axis: int) -> void:
	_record("Bağlantı yerleştir", func() -> void:
		for actor in actors:
			var piece: Node3D = actor.shoulder if selected == "shoulder" else actor.bag
			var point: Vector3 = piece.connection_points[index]
			point[axis] = value
			piece.set_connection_point(index, point)
			if selected == "shoulder": actor.connection_markers[index].position = point
	)

func _save_profile() -> void:
	var file := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	if not file:
		status.text = "Ayar kaydedilemedi: %s" % FileAccess.get_open_error()
		return
	file.store_string(JSON.stringify(Profile.encode(actors[0]), "\t"))
	status.text = "Bağlantılar, örtme kuralı ve kumaş ağırlıkları kaydedildi: " + ProjectSettings.globalize_path(PROFILE_PATH)
	call_deferred("_build_tools")

func _load_profile() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	if not Profile.validate(data):
		status.text = "Ayar dosyası bu örneğin biçimine uymuyor; değişiklik uygulanmadı."
		return
	_record("Hazırlama ayarını yükle", func() -> void:
		for actor in actors: Profile.apply(actor, data)
	)
	status.text = "Hazırlama ayarı yüklendi. Mevcut hasar korunuyor."
	call_deferred("_build_tools")

func _paint_tools() -> void:
	if selected != "cloth":
		_text(tools_panel, "Bu parça rijit veya iskelete bağlı. Serbestlik boyaması düşük çözünürlüklü kumaşta kullanılabilir.")
		_button(tools_panel, "Sarkan kumaşı seç", _select_item.bind("cloth"))
		return
	for actor in actors: actor.cloth.paint_visible = true
	_text(tools_panel, "Önizlemede sol tuşla boya. Renkler hareket serbestliğini gösterir; üst sırayı sabit bırakarak başla.")
	for choice in [["● Sabit · 0", 0.0], ["● Kısmi · 0.5", 0.5], ["● Serbest · 1", 1.0]]:
		_button(tools_panel, choice[0], func() -> void: paint_value = choice[1], choice[1] == paint_value)
	_button(tools_panel, "Kumaşa odakla", _focus_selected)
	_text(tools_panel, "99 simülasyon noktası · fırça 35 px\nHer fırça hareketi tek Geri al adımıdır.")

func _collision_tools() -> void:
	if selected == "cloth":
		var toggle := CheckButton.new()
		toggle.text = "Ucuz kalça çarpışma proxy’si"
		toggle.button_pressed = actors[0].cloth.collision_enabled
		toggle.toggled.connect(func(value: bool) -> void:
			for actor in actors: actor.cloth.collision_enabled = value
		)
		tools_panel.add_child(toggle)
		_text(tools_panel, "Kumaş, elipsoid kalça proxy’si ve zeminle çözülür. Genel giysi/beden teması garantisi vermez.")
	else:
		_text(tools_panel, "Kopan rijit parçalar hazırlanmış kutu çarpışma şekliyle zemine düşer. Askıda salınma kontrollüdür; bedene kuvvet uygulamaz.")
	_text(tools_panel, "Gizlenen iç yüzeyin çizimi durur. Ucuz çarpışma proxy’si korunur; şeffaf malzeme ile gizleme kullanılmaz.")

func _layer_tools() -> void:
	tools_panel.add_child(_label("ÖRTME İLİŞKİSİ", 11, MUTED))
	var description: String = {"shoulder":"Omuz zırhı → iç omuz bölgesi\nİki sağlam bağlantıda kapalı; ilk kopmada görünür.","chest":"Göğüslük → iç ön gövde\nGöğüslük çıkarılınca geri görünür.","inner":"İç katman → ön / arka / omuz\nYalnız kesin örtülen bölge gizlenir.","bag":"Çanta → omuz zırhı socket’i\nAlt katman örtme kuralı yok.","cloth":"Kumaş → kalça kemiği\nHareket sınırlarında alt katman korunur."}[selected]
	_text(tools_panel, description, TEXT)
	_text(tools_panel, "Sıralama listesi dıştan içe ilişkiyi gösterir. Bu örnekte örtme bölgeleri hazırlanmıştır; sırayı sürüklemek otomatik bir örtme kuralı üretmez.")
	_text(tools_panel, "Bölge gizleme: çizim azalır. Kaynak mesh/bellek korunur. Bedenin skinning maliyeti devam eder; vertex sıkıştırma uygulanmadı.")
	_button(tools_panel, "Göğüslüğü çıkar / tak", func() -> void:
		_record("Göğüslük değiştir", func() -> void:
			var value: bool = not actors[0].chest_equipped
			for actor in actors: actor.set_equipped("chest", value)
		)
	)

func _damage_tools() -> void:
	if selected not in ["shoulder", "bag", "cloth"]:
		_text(tools_panel, "Bu parçada hazırlanmış hasar bağlantısı yok. Senaryo için iki bağlantılı omuz zırhını seç.")
		_button(tools_panel, "Omuz zırhını seç", _select_item.bind("shoulder"))
		return
	_text(tools_panel, "1. darbe → kalan bağlantıda salınma\n2. darbe → fiziksel düşüş\nAçılan iç bölge hemen geri görünür.", TEXT)
	_button(tools_panel, "⚡ Seçili parçaya darbe", _hit, true)
	if selected == "shoulder":
		var rule := OptionButton.new()
		rule.add_item("Çanta zırhı takip etsin")
		rule.add_item("Zırh düşünce çanta da ayrılsın")
		rule.selected = actors[0].accessory_rule
		rule.item_selected.connect(func(index: int) -> void:
			_record("Çanta bağlantı kuralı", func() -> void:
				for actor in actors: actor.accessory_rule = index
			)
		)
		tools_panel.add_child(rule)
		_button(tools_panel, "Yalnız çantayı kopar", func() -> void:
			_record("Çanta darbesi", func() -> void:
				for i in range(count): actors[i].bag.apply_hit()
			)
		)
	_text(tools_panel, "Çıkarma / tekrar takma hasarı korur. Sıfırla tüm başlangıç durumunu geri kurar. Geri al hasar ve giysi değişikliklerini geri getirir.")
	_text(tools_panel, "Çanta takibi tek yönlüdür; çantanın ağırlığı kumaşı veya iskeleti çekmez.")

func _motion_tools() -> void:
	_text(tools_panel, "Karakter sayısı", TEXT)
	var counts := HBoxContainer.new()
	tools_panel.add_child(counts)
	_button(counts, "1 karakter", _set_count.bind(1), count == 1)
	_button(counts, "3 karakter", _set_count.bind(3), count == 3)
	_button(tools_panel, "Üç karakterde kopma ölçümü", _start_benchmark, true)
	_text(tools_panel, "Ölçüm: ısıtma → üç karaktere aynı karede ilk darbe → ikinci kopma → tekrar. Kare ortalaması, p99, tepe ve olay çevresi kaydedilir.")
	_text(tools_panel, "CPU kumaş: 99 nokta × 5 çözüm adımı. Görünmeyen karakterler ve çıkarılan kumaş hesaplanmaz. Gizli iç bölgeler saklanır, tekrar açılırken mesh üretilmez.")
	_text(tools_panel, "Bu ortamın sonuçları donanım hedefi değildir. Hedef FPS ve en düşük cihaz belirlenmeden performans garantisi verilmez.")

func _select_item(id: String) -> void:
	selected = id
	for actor in actors: actor.set_selected(id)
	_build_tools()
	_refresh()

func _select_section(index: int) -> void:
	section = index
	for actor in actors: actor.cloth.paint_visible = false
	_build_tools()
	_refresh()

func _refresh() -> void:
	if actors.is_empty() or not is_instance_valid(state_label): return
	for id in IDS:
		var button: Button = rows[id]["button"]
		button.add_theme_stylebox_override("normal", _style(Color("153d3c") if id == selected else Color("172537"), TEAL if id == selected else Color("2a3b50"), 6))
		button.add_theme_color_override("font_color", TEAL if id == selected else TEXT)
		var label: Label = rows[id]["sub"]
		label.text = "  " + ("Giyili" if actors[0].is_equipped(id) else "Çıkarıldı · durum saklanıyor")
		if id == "bag" and actors[0].bag.equipped and not actors[0].shoulder.equipped:
			label.text = "  Ana zırh çıkarıldı · bekliyor"
	for i in range(section_buttons.size()):
		section_buttons[i].add_theme_stylebox_override("normal", _style(Color("16423f") if i == section else Color("132033"), TEAL if i == section else Color("26364a"), 6))
	var shoulder_status: String = actors[0].shoulder.get_state_label()
	state_label.text = "Omuz: " + shoulder_status + ("  /  İç omuz açık" if actors[0].under_shoulder.visible else "  /  İç omuz örtülü")
	preview_title.text = "%s  /  %d KARAKTER" % [NAMES[selected].to_upper(), count]
	undo_button.disabled = not history.has_undo()
	redo_button.disabled = not history.has_redo()

func _snapshots() -> Array:
	var data: Array = []
	for actor in actors: data.append(actor.snapshot())
	return data

func _restore_all(data: Array) -> void:
	for i in range(actors.size()): actors[i].restore(data[i])
	_refresh()
	call_deferred("_build_tools")

func _commit(title: String, before: Array, after: Array) -> void:
	history.create_action(title)
	history.add_do_method(_restore_all.bind(after))
	history.add_undo_method(_restore_all.bind(before))
	history.commit_action(false)
	_refresh()

func _record(title: String, operation: Callable) -> void:
	var before: Array = _snapshots()
	operation.call()
	_commit(title, before, _snapshots())

func _undo() -> void:
	if history.has_undo(): history.undo()
	_refresh()

func _redo() -> void:
	if history.has_redo(): history.redo()
	_refresh()

func _hit() -> void:
	var hit_count := 0
	var begin: int = Time.get_ticks_usec()
	var before: Array = _snapshots()
	for i in range(count):
		if actors[i].hit_selected(): hit_count += 1
	var duration: int = Time.get_ticks_usec() - begin
	if hit_count:
		_commit("Bağlantıya darbe", before, _snapshots())
		status.text = "%d parça hasar aldı · çağrı %.3f ms · kare etkisi ölçüm testinde kaydedilir." % [hit_count, duration / 1000.0]
	else:
		status.text = "Sağlam bağlantı kalmadı veya seçili parça çıkarılmış. Sıfırla ya da Geri al ile geri dön."
	_refresh()

func _reset_all() -> void:
	for actor in actors:
		for id in IDS: actor.set_equipped(id, true)
		actor.reset_damage()
		actor.set_animation("Idle")
		if actor.animation: actor.animation.seek(0.0, true)
		actor.set_playing(true)
	status.text = "Giysiler onarıldı ve animasyon başa alındı. Hazırlama ayarları korunuyor."
	call_deferred("_build_tools")

func _play(value: bool) -> void:
	for actor in actors: actor.set_playing(value)
	status.text = "Animasyon oynuyor." if value else "Animasyon duraklatıldı; kumaş ve kopan parçaların fiziği devam ediyor."

func _set_count(value: int) -> void:
	count = value
	for i in range(actors.size()):
		actors[i].set_active(i < count)
	_reset_camera()
	_refresh()

func _reset_camera() -> void:
	focus = Vector3((count - 1) * 0.575, 0.98, 0)
	distance = 3.15 if count == 1 else 5.9
	_update_camera()

func _focus_selected() -> void:
	focus = actors[0].selected_world_position()
	distance = 1.35
	_update_camera()

func _update_camera() -> void:
	if not camera: return
	camera.position = focus + Vector3(sin(orbit.x) * cos(orbit.y), sin(orbit.y), cos(orbit.x) * cos(orbit.y)) * distance
	camera.look_at(focus)

func _preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			distance = maxf(0.5, distance * 0.9)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			distance = minf(10, distance * 1.1)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_LEFT and section == 1 and selected == "cloth":
			if event.pressed:
				paint_before = _snapshots()
				painting = true
				_paint_at(event.position)
			elif painting:
				painting = false
				_commit("Kumaş serbestliği boya", paint_before, _snapshots())
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			orbit += Vector2(-event.relative.x, event.relative.y) * 0.006
			orbit.y = clampf(orbit.y, -0.2, 1.1)
			_update_camera()
		elif painting: _paint_at(event.position)

func _paint_at(position_value: Vector2) -> void:
	var hits: int = actors[0].cloth.paint(camera, position_value, paint_value)
	for i in range(1, actors.size()): actors[i].cloth.weights = actors[0].cloth.weights.duplicate()
	status.text = "%d nokta boyandı · serbestlik %.1f" % [hits, paint_value]

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.ctrl_pressed:
		if event.keycode == KEY_Z:
			if event.shift_pressed: _redo()
			else: _undo()
		elif event.keycode == KEY_Y: _redo()

func _process(_delta: float) -> void:
	var tick: int = Time.get_ticks_usec()
	var milliseconds: float = (tick - last_tick) / 1000.0
	last_tick = tick
	frame_samples.append(milliseconds)
	if frame_samples.size() > 180: frame_samples.pop_front()
	if Engine.get_process_frames() % 30 == 0:
		var average: float = _mean(frame_samples)
		var simulation := 0
		for i in range(count): simulation += actors[i].cloth.update_usec
		metric_label.text = "%d karakter  |  Kare ort. %.2f ms  ·  p99 %.2f ms  |  Kumaş CPU %.2f ms  |  Godot %s" % [count, average, _percentile(frame_samples, 0.99), simulation / 1000.0, Engine.get_version_info()["string"]]
	if benchmark_active: _benchmark_step(tick)
	if screenshot_frame >= 0:
		screenshot_frame -= 1
		if screenshot_frame == 55 and automation_mode in ["lab-hanging", "lab-detached", "lab-three"]:
			for i in range(count): actors[i].shoulder.apply_hit(-1, Vector3(-0.7,0.25,0.8))
		if screenshot_frame == 8 and automation_mode == "lab-detached":
			for i in range(count): actors[i].shoulder.apply_hit(-1, Vector3(-0.7,0.25,0.8))
		if screenshot_frame == 0: call_deferred("_capture")

func _mean(values: Array[float]) -> float:
	var total := 0.0
	for value in values: total += value
	return total / maxf(values.size(), 1)

func _percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty(): return 0.0
	var ordered: Array[float] = values.duplicate()
	ordered.sort()
	return ordered[mini(ordered.size() - 1, int(ceil(ordered.size() * fraction)) - 1)]

func _start_benchmark() -> void:
	if benchmark_active: return
	_set_count(benchmark_characters)
	_select_item("shoulder")
	_reset_all()
	for actor in actors: actor.set_animation("Walk")
	benchmark_frame = 0
	benchmark_frames.clear()
	benchmark_process_ms.clear()
	benchmark_physics_ms.clear()
	benchmark_cloth_ms.clear()
	benchmark_events.clear()
	benchmark_pending = -1
	benchmark_last_frame = Time.get_ticks_usec()
	benchmark_active = true
	status.text = "Ölçüm çalışıyor: 120 kare ısıtma + 600 kare, %d karakter aynı anda hasar alıyor." % count

func _benchmark_step(tick: int) -> void:
	benchmark_frame += 1
	var duration: float = (tick - benchmark_last_frame) / 1000.0
	benchmark_last_frame = tick
	if benchmark_frame > 120:
		benchmark_frames.append(duration)
		benchmark_process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		benchmark_physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		var cloth_ms := 0.0
		for i in range(count): cloth_ms += actors[i].cloth.update_usec / 1000.0
		benchmark_cloth_ms.append(cloth_ms)
		if benchmark_pending >= 0:
			benchmark_events[benchmark_pending]["following_frame_ms"] = duration
			benchmark_pending = -1
	if benchmark_frame >= 150 and benchmark_frame < 660 and (benchmark_frame - 150) % 180 == 0:
		for i in range(count): actors[i].reset_damage()
	if benchmark_frame >= 180 and benchmark_frame < 660 and ((benchmark_frame - 180) % 180 == 0 or (benchmark_frame - 210) % 180 == 0):
		var start: int = Time.get_ticks_usec()
		for i in range(count): actors[i].shoulder.apply_hit(-1, Vector3(-0.7,0.25,0.8))
		var call_ms: float = (Time.get_ticks_usec() - start) / 1000.0
		benchmark_events.append({"frame":benchmark_frame,"kind":"detach" if actors[0].shoulder.get_active_connection_count() == 0 else "first_break","characters":count,"call_ms":call_ms,"preceding_frame_ms":duration})
		benchmark_pending = benchmark_events.size() - 1
	if benchmark_frame >= 720: _finish_benchmark()

func _finish_benchmark() -> void:
	benchmark_active = false
	var max_value := 0.0
	for value in benchmark_frames: max_value = maxf(max_value, value)
	for event in benchmark_events:
		var window: Array[float] = []
		var center: int = int(event["frame"]) - 121
		for index in range(maxi(0,center - 2), mini(benchmark_frames.size(),center + 6)):
			window.append(benchmark_frames[index])
		event["window_ms_minus2_plus5"] = window
		event["window_max_ms"] = window.max()
	benchmark_result = {"engine":Engine.get_version_info(),"os":OS.get_name(),"cpu":OS.get_processor_name(),"renderer":RenderingServer.get_video_adapter_name(),"rendering_method":RenderingServer.get_current_rendering_method(),"headless":DisplayServer.get_name() == "headless","viewport":str(viewport.size),"characters":count,"warmup_frames":120,"sample_frames":benchmark_frames.size(),"mean_frame_ms":_mean(benchmark_frames),"p99_frame_ms":_percentile(benchmark_frames,0.99),"max_frame_ms":max_value,"mean_process_monitor_ms":_mean(benchmark_process_ms),"mean_physics_monitor_ms":_mean(benchmark_physics_ms),"mean_cloth_script_ms":_mean(benchmark_cloth_ms),"events":benchmark_events,"raw_frame_ms":benchmark_frames,"limitations":"Container CPU/software renderer or headless result only; not target hardware FPS. Headless excludes drawing/GPU skinning. Wall frames include limiter/scheduler/UI; process and physics monitors are separately recorded. call_ms includes UI state signals. Event windows include preceding 2 and following 5 wall frames."}
	var file := FileAccess.open(benchmark_output, FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(benchmark_result, "\t"))
	status.text = "Ölçüm bitti · ort. %.2f / p99 %.2f / tepe %.2f ms · %s" % [benchmark_result["mean_frame_ms"],benchmark_result["p99_frame_ms"],max_value,benchmark_output]
	var brief: Dictionary = benchmark_result.duplicate()
	brief.erase("raw_frame_ms")
	print("AEROCLOTH_BENCHMARK ", JSON.stringify(brief))
	if automation_mode == "benchmark": get_tree().quit()

func _capture() -> void:
	await RenderingServer.frame_post_draw
	var output: String = "res://artifacts/" + automation_mode + ".png"
	var error: Error = get_viewport().get_texture().get_image().save_png(output)
	print("AEROCLOTH_CAPTURE ", output, " ", error)
	get_tree().quit()

func _exit_tree() -> void:
	history.clear_history()
	history.free()
