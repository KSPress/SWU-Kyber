class_name ModalPanel
extends Control
## Centred modal panel that always fits the screen: fixed readable width,
## scrolls when content is taller than the screen, re-fits on rotation.
## Add content to `box`. Word-wrapped labels get a real width, so they wrap
## instead of stretching the panel.

signal closed

var box: VBoxContainer
var max_width := 640.0
var full := false             # use (almost) the whole screen
var dismiss_on_backdrop := false
var _panel: PanelContainer
var _scroll: ScrollContainer
var _layer: CanvasLayer


static func open(host: Node, p_max_width := 640.0, border := Kyber.C_GOLD, p_full := false) -> ModalPanel:
	var m := ModalPanel.new()
	m.max_width = p_max_width
	m.full = p_full
	m._layer = CanvasLayer.new()
	m._layer.layer = 30
	host.add_child(m._layer)
	m._layer.add_child(m)
	m._build(border)
	return m


func _build(border: Color) -> void:
	UIKit.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0.01, 0.03, 0.82)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.fill_rect(dim)
	add_child(dim)
	_panel = UIKit.panel(Color(0.02, 0.05, 0.09, 0.97), border, 14, 12)
	add_child(_panel)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(_scroll)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(box)
	box.minimum_size_changed.connect(_fit)
	get_viewport().size_changed.connect(_fit)
	_fit.call_deferred()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, Kyber.anim(0.18))


func _fit() -> void:
	if not is_inside_tree():
		return
	var vs := get_viewport_rect().size
	var w := vs.x * 0.94 if full else minf(vs.x * 0.92, max_width)
	var margin := 28.0
	box.custom_minimum_size.x = w - margin - 12
	var content_h := box.get_combined_minimum_size().y
	var max_h := vs.y * (0.94 if full else 0.86)
	var h := max_h if full else minf(content_h + margin, max_h)
	_scroll.custom_minimum_size = Vector2(w - margin, h - margin)
	_panel.size = Vector2(w, h)
	_panel.position = (vs - _panel.size) / 2.0


## Word-wrapped label helper sized for this panel.
func text(t: String, size := 18, color := Kyber.C_TEXT, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := UIKit.label(t, size, color, align)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(l)
	return l


func add(c: Control) -> Control:
	if c is Button:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(c)
	return c


func _gui_input(ev: InputEvent) -> void:
	if dismiss_on_backdrop and ev is InputEventMouseButton and ev.pressed:
		if not _panel.get_global_rect().has_point(ev.global_position):
			close()


func close() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, Kyber.anim(0.12))
	await tw.finished
	closed.emit()
	if is_instance_valid(_layer):
		_layer.queue_free()
