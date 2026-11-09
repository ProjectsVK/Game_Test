extends CanvasLayer
## Interface : horloge, capacités, journal, dialogues, écrans de récit et carnet d'enquête.

const PAPER := Color(0.94, 0.89, 0.8)
const INK := Color(0.16, 0.13, 0.09)
const PANEL := Color(0.05, 0.07, 0.1, 0.86)
const LINE := Color(0.23, 0.28, 0.36)
const AMBER := Color(0.94, 0.65, 0.29)
const TEAL := Color(0.31, 0.76, 0.7)
const MUTED := Color(0.6, 0.64, 0.7)

var main
var f_display: Font
var f_body: Font
var f_bold: Font

var _root: Control
var _day: Label
var _time: Label
var _status: Label
var _toasts: VBoxContainer
var _prompt: Label
var _dialog: PanelContainer
var _dialog_name: Label
var _dialog_text: Label
var _dialog_timer := 0.0
var _target: PanelContainer
var _target_name: Label
var _target_role: Label
var _target_task: Label
var _target_ref = null
var _pause: Control
var _abilities: HBoxContainer
var _slots: Array = []
var _screen: Control
var _screen_eyebrow: Label
var _screen_title: Label
var _screen_body: RichTextLabel
var _screen_btn: Button
var _screen_cb: Callable
var _notebook: Control
var _nb_grid: GridContainer
var _nb_clues: RichTextLabel
var _nb_title: Label


func build(m) -> void:
	main = m
	f_display = load("res://assets/fonts/AlegreyaSC-Bold.woff2")
	f_body = load("res://assets/fonts/AlegreyaSans-Regular.woff2")
	f_bold = load("res://assets/fonts/AlegreyaSans-Bold.woff2")
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_top()
	_build_bottom()
	_build_dialog()
	_build_crosshair()
	_build_target()
	_build_notebook()
	_build_pause()
	_build_screen()


# ---------------------------------------------------------------- utilitaires

func _label(text: String, size: int, color: Color, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if font == null:
		font = f_body
	if font:
		l.add_theme_font_override("font", font)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Ancre un contrôle et fixe ses marges ; il grandit vers le haut et des deux côtés si besoin.
func _anchor(c: Control, preset: int, l: float, t: float, r: float, b: float) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = l
	c.offset_top = t
	c.offset_right = r
	c.offset_bottom = b
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH if preset in [Control.PRESET_CENTER_BOTTOM, Control.PRESET_CENTER] else Control.GROW_DIRECTION_BEGIN
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN if preset == Control.PRESET_CENTER_BOTTOM else Control.GROW_DIRECTION_END


func _box(bg: Color, border: Color = Color(0, 0, 0, 0), radius: int = 8, pad: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1 if border.a > 0.0 else 0)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(pad)
	return sb


func _panel(bg: Color = PANEL, border: Color = LINE, radius: int = 8, pad: int = 10) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(bg, border, radius, pad))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 20)
	if f_bold:
		b.add_theme_font_override("font", f_bold)
	b.add_theme_color_override("font_color", PAPER)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_stylebox_override("normal", _box(INK, INK, 4, 12))
	b.add_theme_stylebox_override("hover", _box(Color(0.32, 0.23, 0.14), INK, 4, 12))
	b.add_theme_stylebox_override("pressed", _box(Color(0.1, 0.08, 0.05), INK, 4, 12))
	b.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), AMBER, 4, 12))
	b.pressed.connect(func(): Sfx.ui("ui_click", -4.0, 1.0, "SFX"))
	return b


# ---------------------------------------------------------------- haut

func _build_top() -> void:
	var clock := _panel()
	clock.position = Vector2(20, 18)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	clock.add_child(hb)
	_day = _label("Jour 1/5", 22, AMBER, f_display)
	_time = _label("06:00", 32, PAPER, f_display)
	hb.add_child(_day)
	hb.add_child(_time)
	_root.add_child(clock)

	var st := _panel()
	st.position = Vector2(270, 24)
	_status = _label("", 18, MUTED)
	st.add_child(_status)
	_root.add_child(st)

	var keys := _label("E interagir   ·   C carnet   ·   F accélérer   ·   N ×2 finir la journée   ·   Échap pause", 15, MUTED)
	_anchor(keys, Control.PRESET_TOP_RIGHT, -600, 28, -20, 52)
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root.add_child(keys)

	_toasts = VBoxContainer.new()
	_anchor(_toasts, Control.PRESET_TOP_RIGHT, -440, 70, -20, 80)
	_toasts.add_theme_constant_override("separation", 6)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toasts)


func toast(text: String, kind: String = "") -> void:
	var p := _panel(PANEL, TEAL if kind == "clue" else AMBER, 6, 10)
	var l := _label(text, 17, PAPER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(400, 0)
	p.add_child(l)
	_toasts.add_child(p)
	_toasts.move_child(p, 0)
	while _toasts.get_child_count() > 5:
		var last := _toasts.get_child(_toasts.get_child_count() - 1)
		_toasts.remove_child(last)
		last.queue_free()
	var tw := create_tween()
	tw.tween_interval(7.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.8)
	tw.tween_callback(p.queue_free)


# ---------------------------------------------------------------- bas

func _build_bottom() -> void:
	var bar := HBoxContainer.new()
	_anchor(bar, Control.PRESET_CENTER_BOTTOM, 0, -20, 0, -20)
	bar.add_theme_constant_override("separation", 18)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bar)
	_abilities = HBoxContainer.new()
	_abilities.add_theme_constant_override("separation", 8)
	bar.add_child(_abilities)

	_prompt = _label("", 19, PAPER, f_bold)
	_anchor(_prompt, Control.PRESET_CENTER_BOTTOM, 0, -150, 0, -150)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_prompt.add_theme_constant_override("outline_size", 8)
	_root.add_child(_prompt)


func refresh_abilities() -> void:
	for c in _abilities.get_children():
		c.queue_free()
	_slots.clear()
	for i in 4:
		var a: Dictionary = GameData.PLAYER["abilities"][i]
		var slot := Panel.new()
		slot.custom_minimum_size = Vector2(190, 92)
		slot.add_theme_stylebox_override("panel", _box(PANEL, LINE, 8, 0))
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var key := _label(str(i + 1), 15, AMBER, f_bold)
		key.position = Vector2(10, 6)
		var nm := _label(a["name"], 19, PAPER, f_bold)
		nm.position = Vector2(10, 28)
		var ds := _label(a["desc"], 13, MUTED)
		ds.position = Vector2(10, 52)
		ds.size = Vector2(172, 38)
		ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ds.clip_text = true
		var cdr := ColorRect.new()
		cdr.color = Color(0.0, 0.0, 0.0, 0.65)
		cdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cdr.position = Vector2(0, 92)
		cdr.size = Vector2(190, 0)
		var cdn := _label("", 16, AMBER, f_bold)
		cdn.position = Vector2(160, 6)
		slot.add_child(key)
		slot.add_child(nm)
		slot.add_child(ds)
		slot.add_child(cdr)
		slot.add_child(cdn)
		_abilities.add_child(slot)
		_slots.append({"panel": slot, "cd": cdr, "num": cdn, "max": float(a["cd"])})


func flash_ability(i: int) -> void:
	if i >= _slots.size():
		return
	var p: Panel = _slots[i]["panel"]
	p.add_theme_stylebox_override("panel", _box(PANEL, TEAL, 8, 0))
	get_tree().create_timer(0.25).timeout.connect(func():
		if is_instance_valid(p):
			p.add_theme_stylebox_override("panel", _box(PANEL, LINE, 8, 0)))


func set_prompt(t: String) -> void:
	if _prompt.text != t:
		_prompt.text = t


func update_hud() -> void:
	_day.text = "Jour %d/%d" % [Game.day, GameData.CONFIG["days"]]
	_time.text = Game.hhmm(Game.minute) + ("  »" if Input.is_action_pressed("fast_time") and not Game.paused else "")
	var dead := 0
	for n in main.npcs:
		if not n.alive:
			dead += 1
	var st := "Victimes %d   ·   Accusations restantes %d   ·   Crochetages %d" % [dead, GameData.CONFIG["max_wrong"] - Game.wrong, main.crochet_left]
	_status.text = st
	var f = main.player
	for i in _slots.size():
		var c: float = f.cd[i]
		var frac := clampf(c / _slots[i]["max"], 0.0, 1.0)
		var r: ColorRect = _slots[i]["cd"]
		r.size = Vector2(190, 92 * frac)
		r.position = Vector2(0, 92 - 92 * frac)
		_slots[i]["num"].text = str(ceili(c)) if c > 0.0 else ""
	if _dialog.visible and not Game.paused:
		_dialog_timer -= get_process_delta_time()
		if _dialog_timer <= 0.0:
			_dialog.visible = false


# ---------------------------------------------------------------- dialogue

func _build_dialog() -> void:
	_dialog = _panel(Color(PAPER, 0.97), INK, 4, 18)
	_anchor(_dialog, Control.PRESET_CENTER_BOTTOM, 0, -190, 0, -190)
	_dialog.custom_minimum_size = Vector2(680, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	_dialog.add_child(vb)
	_dialog_name = _label("", 24, INK, f_display)
	_dialog_text = _label("", 20, INK)
	_dialog_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog_text.custom_minimum_size = Vector2(640, 0)
	var hint := _label("Échap pour fermer", 14, Color(0.45, 0.38, 0.3))
	vb.add_child(_dialog_name)
	vb.add_child(_dialog_text)
	vb.add_child(hint)
	_dialog.visible = false
	_root.add_child(_dialog)


func show_dialog(who: String, color: Color, text: String) -> void:
	_dialog_name.text = who
	_dialog_name.add_theme_color_override("font_color", color.darkened(0.35))
	_dialog_text.text = "« " + text + " »"
	_dialog.visible = true
	_dialog_timer = 12.0


func hide_dialog() -> void:
	_dialog.visible = false


func dialog_visible() -> bool:
	return _dialog.visible


func _build_crosshair() -> void:
	var dot := ColorRect.new()
	dot.color = Color(1, 1, 1, 0.7)
	_anchor(dot, Control.PRESET_CENTER, -2, -2, 2, 2)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dot)


# ---------------------------------------------------------------- écrans de récit

func _overlay() -> Control:
	var o := Control.new()
	o.set_anchors_preset(Control.PRESET_FULL_RECT)
	o.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	o.add_child(dim)
	return o


func _build_screen() -> void:
	_screen = _overlay()
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen.add_child(cc)
	var sheet := _panel(PAPER, Color(0, 0, 0, 0), 4, 34)
	sheet.custom_minimum_size = Vector2(760, 0)
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	cc.add_child(sheet)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	sheet.add_child(vb)
	_screen_eyebrow = _label("", 15, Color(0.48, 0.4, 0.3), f_bold)
	_screen_title = _label("", 40, INK, f_display)
	_screen_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_screen_title.custom_minimum_size = Vector2(690, 0)
	_screen_body = RichTextLabel.new()
	_screen_body.bbcode_enabled = true
	_screen_body.fit_content = true
	_screen_body.scroll_active = false
	_screen_body.custom_minimum_size = Vector2(690, 0)
	_screen_body.add_theme_color_override("default_color", INK)
	_screen_body.add_theme_font_size_override("normal_font_size", 20)
	_screen_body.add_theme_font_size_override("bold_font_size", 20)
	if f_body:
		_screen_body.add_theme_font_override("normal_font", f_body)
	if f_bold:
		_screen_body.add_theme_font_override("bold_font", f_bold)
	_screen_btn = _button("Continuer")
	_screen_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_screen_btn.pressed.connect(_on_screen_btn)
	vb.add_child(_screen_eyebrow)
	vb.add_child(_screen_title)
	vb.add_child(_screen_body)
	vb.add_child(_screen_btn)
	_screen.visible = false
	_root.add_child(_screen)


func show_screen(eyebrow: String, title: String, body: String, button: String, cb: Callable) -> void:
	Game.paused = true
	main.set_capture(false)
	_screen_eyebrow.text = eyebrow.to_upper()
	_screen_title.text = title
	_screen_body.text = body
	_screen_btn.text = button
	_screen_btn.visible = button != ""
	_screen_cb = cb
	_screen.visible = true
	Sfx.ui("ui_open", -6.0)
	if button != "":
		_screen_btn.grab_focus.call_deferred()


func _on_screen_btn() -> void:
	_screen.visible = false
	Game.paused = false
	if _screen_cb.is_valid():
		_screen_cb.call()


func screen_visible() -> bool:
	return _screen.visible


## Ferme l'écran de récit sans rappeler l'action du bouton (test automatique).
func dismiss_screen() -> void:
	_screen.visible = false
	Game.paused = false


func show_title(cb: Callable) -> void:
	var p: Dictionary = GameData.PLAYER
	var lines: Array = []
	for i in p["abilities"].size():
		var ab: Dictionary = p["abilities"][i]
		lines.append("[b]%d · %s[/b] : %s" % [i + 1, ab["name"], ab["desc"]])
	var body: String = GameData.INTRO + "\n\n[b]%s[/b], %s.\n" % [p["name"], p["role"].to_lower()] + "\n".join(PackedStringArray(lines)) + \
		"\n\n[b]Commandes[/b]  Z Q S D pour marcher, souris pour viser, Maj pour courir, 1 à 4 pour les capacités, E pour parler ou fouiller, C pour le carnet et l'accusation, Échap pour la pause (volumes, Débloquer)."
	show_screen("Secteur C", "Bunker 1013", body, "Entrer dans le Secteur C", cb)


# ---------------------------------------------------------------- personne visée

func _build_target() -> void:
	_target = _panel(PANEL, LINE, 8, 12)
	_anchor(_target, Control.PRESET_CENTER_TOP, -170, 18, 170, 18)
	_target.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_target.custom_minimum_size = Vector2(340, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	_target.add_child(vb)
	_target_name = _label("", 28, PAPER, f_display)
	_target_role = _label("", 16, MUTED, f_bold)
	_target_task = _label("", 17, PAPER)
	for l in [_target_name, _target_role, _target_task]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(l)
	_target.visible = false
	_root.add_child(_target)


func set_target(n) -> void:
	var on: bool = n != null and not Game.paused
	_target.visible = on
	if not on:
		_target_ref = null
		return
	if n != _target_ref:
		_target_ref = n
		var c: Color = n.color()
		_target_name.text = n.display_name
		_target_name.add_theme_color_override("font_color", c.lightened(0.35))
		_target_role.text = "%s · équipe %s" % [n.role, GameData.TEAMS[n.team]["name"]]
		_target.add_theme_stylebox_override("panel", _box(PANEL, c.lightened(0.1), 8, 12))
	_target_task.text = n.task_label


# ---------------------------------------------------------------- pause

func _build_pause() -> void:
	_pause = _overlay()
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause.add_child(cc)
	var sheet := _panel(PAPER, Color(0, 0, 0, 0), 4, 30)
	sheet.custom_minimum_size = Vector2(480, 0)
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	cc.add_child(sheet)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	sheet.add_child(vb)
	vb.add_child(_label("Pause", 40, INK, f_display))
	var resume := _button("Reprendre")
	resume.pressed.connect(hide_pause)
	vb.add_child(resume)
	var unstuck := _button("Débloquer")
	unstuck.pressed.connect(func():
		hide_pause()
		main.unstuck())
	vb.add_child(unstuck)
	var hint := _label("Coincé·e ? « Débloquer » replace Lina au centre de la salle la plus proche.", 14, Color(0.45, 0.38, 0.3))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(420, 0)
	vb.add_child(hint)
	vb.add_child(_label("Volumes", 22, INK, f_display))
	for row in [["Master", "Général"], ["Music", "Musique"], ["SFX", "Effets"], ["Ambience", "Ambiance"]]:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		var l := _label(row[1], 18, INK, f_bold)
		l.custom_minimum_size = Vector2(110, 0)
		hb.add_child(l)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.value = Game.volumes[row[0]]
		sl.custom_minimum_size = Vector2(280, 24)
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var bus: String = row[0]
		sl.value_changed.connect(func(v: float):
			Game.set_volume(bus, v)
			if bus != "Music":
				Sfx.ui("ui_click", -6.0, 1.0, bus if bus != "Master" else "SFX"))
		hb.add_child(sl)
		vb.add_child(hb)
	var paint := CheckButton.new()
	paint.text = "Filtre peinture (touche P)"
	paint.button_pressed = Game.paint_filter
	paint.add_theme_color_override("font_color", INK)
	paint.add_theme_color_override("font_pressed_color", INK)
	paint.add_theme_color_override("font_hover_color", INK)
	paint.add_theme_font_size_override("font_size", 18)
	if f_bold:
		paint.add_theme_font_override("font", f_bold)
	paint.toggled.connect(func(on: bool): main.set_paint(on))
	vb.add_child(paint)
	var hb2 := HBoxContainer.new()
	hb2.add_theme_constant_override("separation", 10)
	var restart := _button("Recommencer")
	restart.pressed.connect(func():
		hide_pause()
		main._restart())
	var quit := _button("Quitter le jeu")
	quit.pressed.connect(func(): get_tree().quit())
	hb2.add_child(restart)
	hb2.add_child(quit)
	vb.add_child(hb2)
	_pause.visible = false
	_root.add_child(_pause)
	_pause.set_meta("paint", paint)


func pause_visible() -> bool:
	return _pause.visible


func show_pause() -> void:
	Game.paused = true
	main.set_capture(false)
	(_pause.get_meta("paint") as CheckButton).set_pressed_no_signal(Game.paint_filter)
	_pause.visible = true
	Sfx.ui("ui_open", -6.0)


func hide_pause() -> void:
	if not _pause.visible:
		return
	_pause.visible = false
	if not _screen.visible and not _notebook.visible:
		Game.paused = false
		main.set_capture(true)


# ---------------------------------------------------------------- carnet

func _build_notebook() -> void:
	_notebook = _overlay()
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_notebook.add_child(cc)
	var sheet := _panel(PAPER, Color(0, 0, 0, 0), 4, 30)
	sheet.custom_minimum_size = Vector2(1100, 600)
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	cc.add_child(sheet)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	sheet.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_child(_label("CARNET DE LINA · SECTEUR C", 14, Color(0.48, 0.4, 0.3), f_bold))
	_nb_title = _label("Jour 1", 32, INK, f_display)
	hv.add_child(_nb_title)
	head.add_child(hv)
	var close := _button("Fermer (C)")
	close.pressed.connect(toggle_notebook)
	head.add_child(close)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 26)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(cols)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(560, 0)
	left.add_child(_label("Suspects", 22, INK, f_display))
	_nb_grid = GridContainer.new()
	_nb_grid.columns = 3
	_nb_grid.add_theme_constant_override("h_separation", 8)
	_nb_grid.add_theme_constant_override("v_separation", 8)
	left.add_child(_nb_grid)
	var note := _label("Chaque combinaison équipe + pointure est unique. Une accusation fausse enferme un innocent.", 15, Color(0.4, 0.33, 0.24))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(540, 0)
	left.add_child(note)
	cols.add_child(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(_label("Indices", 22, INK, f_display))
	_nb_clues = RichTextLabel.new()
	_nb_clues.bbcode_enabled = true
	_nb_clues.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_nb_clues.custom_minimum_size = Vector2(440, 420)
	_nb_clues.add_theme_color_override("default_color", INK)
	_nb_clues.add_theme_font_size_override("normal_font_size", 17)
	_nb_clues.add_theme_font_size_override("bold_font_size", 18)
	if f_body:
		_nb_clues.add_theme_font_override("normal_font", f_body)
	if f_bold:
		_nb_clues.add_theme_font_override("bold_font", f_bold)
	right.add_child(_nb_clues)
	cols.add_child(right)
	_notebook.visible = false
	_root.add_child(_notebook)


func notebook_visible() -> bool:
	return _notebook.visible


func toggle_notebook() -> void:
	if Game.over:
		return
	if _notebook.visible:
		_notebook.visible = false
		main.acc_arm = ""
		if not _screen.visible:
			Game.paused = false
			main.set_capture(true)
	else:
		Game.paused = true
		main.set_capture(false)
		refresh_notebook()
		_notebook.visible = true
		Sfx.ui("ui_open", -6.0)


func refresh_notebook() -> void:
	_nb_title.text = "Jour %d sur %d" % [Game.day, GameData.CONFIG["days"]]
	for c in _nb_grid.get_children():
		c.queue_free()
	for n in main.npcs:
		_nb_grid.add_child(_card(n))
	var by_day := {}
	for c in Game.clues:
		if not by_day.has(c["day"]):
			by_day[c["day"]] = []
		by_day[c["day"]].append(c["text"])
	var days: Array = by_day.keys()
	days.sort()
	days.reverse()
	var txt := ""
	for d in days:
		txt += "[b]Jour %d[/b]\n" % d
		for t in by_day[d]:
			txt += "•  %s\n" % t
		txt += "\n"
	if txt == "":
		txt = "Aucun indice pour l'instant. Commence par la scène du crime."
	_nb_clues.text = txt


func _card(n) -> Control:
	var gone: bool = not n.is_present()
	var struck: bool = Game.struck.has(n.id)
	var p := _panel(Color(0.97, 0.93, 0.86) if not gone else Color(0.88, 0.83, 0.74), Color(0.78, 0.7, 0.56), 4, 10)
	p.custom_minimum_size = Vector2(178, 0)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	p.add_child(vb)
	var team: Dictionary = GameData.TEAMS[n.team]
	var nm := _label(("✕ " if struck else "") + n.display_name, 21, team["color"].darkened(0.3) if not gone else Color(0.5, 0.44, 0.36), f_display)
	vb.add_child(nm)
	var k: Dictionary = Game.know_of(n.id)
	var shoe_parts: Array = []
	if k.has("seen"):
		shoe_parts.append("vue %s" % k["seen"])
	if k.has("claim"):
		shoe_parts.append("dite %s" % k["claim"])
	var shoe := " · ".join(PackedStringArray(shoe_parts)) if shoe_parts.size() > 0 else "?"
	vb.add_child(_label("Équipe %s\nPointure : %s" % [team["name"], shoe], 14, Color(0.4, 0.33, 0.24)))
	if not n.alive:
		vb.add_child(_label("MORT·E", 13, Color(0.55, 0.16, 0.13), f_bold))
	elif n.confined:
		vb.add_child(_label("ENFERMÉ·E", 13, INK, f_bold))
	else:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 4)
		var b1 := _small_btn("Remettre" if struck else "Écarter", INK)
		b1.pressed.connect(func():
			if Game.struck.has(n.id):
				Game.struck.erase(n.id)
			else:
				Game.struck[n.id] = true
			refresh_notebook())
		var armed: bool = main.acc_arm == n.id
		var b2 := _small_btn("Confirmer ?" if armed else "Accuser", Color(0.55, 0.16, 0.13), armed)
		b2.pressed.connect(func():
			if main.acc_arm != n.id:
				main.acc_arm = n.id
				refresh_notebook()
			else:
				main.accuse(n))
		hb.add_child(b1)
		hb.add_child(b2)
		vb.add_child(hb)
	return p


func _small_btn(text: String, color: Color, filled: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 14)
	if f_bold:
		b.add_theme_font_override("font", f_bold)
	b.add_theme_color_override("font_color", PAPER if filled else color)
	b.add_theme_color_override("font_hover_color", PAPER)
	b.add_theme_stylebox_override("normal", _box(color if filled else Color(0, 0, 0, 0), color, 3, 5))
	b.add_theme_stylebox_override("hover", _box(color, color, 3, 5))
	b.add_theme_stylebox_override("pressed", _box(color.darkened(0.3), color, 3, 5))
	b.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), AMBER, 3, 5))
	return b
