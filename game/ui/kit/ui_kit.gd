class_name UIKit
extends RefCounted
## Shared look: chamfered octagon panels with soft glow (the "SW HUD" icon style
## from the reference sheet), built from StyleBoxFlat with corner_detail = 1.


static func chamfer(bg: Color, border: Color, cut := 10, border_w := 2, glow := 0.0, glow_col := Color.TRANSPARENT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(cut)
	s.corner_detail = 1
	s.anti_aliasing = true
	if glow > 0.0:
		s.shadow_size = int(glow)
		s.shadow_color = glow_col if glow_col.a > 0 else Color(border, 0.45)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


static func build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = Kyber.font_title
	t.default_font_size = 22
	var base := chamfer(Color(Kyber.C_PANEL, 0.92), Kyber.C_LINE, 10, 2)
	t.set_stylebox("panel", "Panel", base)
	t.set_stylebox("panel", "PanelContainer", base)
	t.set_color("font_color", "Label", Kyber.C_TEXT)
	t.set_color("font_color", "Button", Kyber.C_TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Kyber.C_KYBER)
	t.set_color("font_disabled_color", "Button", Color(Kyber.C_DIM, 0.6))
	t.set_stylebox("normal", "Button", chamfer(Color(Kyber.C_PANEL, 0.95), Kyber.C_REBEL, 10, 2, 6))
	t.set_stylebox("hover", "Button", chamfer(Kyber.C_PANEL_HI, Kyber.C_KYBER, 10, 2, 12))
	t.set_stylebox("pressed", "Button", chamfer(Color("0a2233"), Kyber.C_KYBER, 10, 3, 16))
	t.set_stylebox("disabled", "Button", chamfer(Color(Kyber.C_PANEL, 0.6), Color(Kyber.C_LINE, 0.6), 10, 2))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	var le := chamfer(Color("070d14"), Kyber.C_LINE, 8, 2)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", chamfer(Color("070d14"), Kyber.C_KYBER, 8, 2, 6))
	t.set_color("font_color", "LineEdit", Kyber.C_TEXT)
	t.set_stylebox("panel", "PopupMenu", base)
	t.set_stylebox("grabber", "VScrollBar", chamfer(Kyber.C_LINE, Kyber.C_LINE, 3, 0))
	t.set_stylebox("scroll", "VScrollBar", StyleBoxEmpty.new())
	t.set_color("font_color", "RichTextLabel", Kyber.C_TEXT)
	t.set_color("default_color", "RichTextLabel", Kyber.C_TEXT)
	t.set_font_size("normal_font_size", "RichTextLabel", 20)
	t.set_font("normal_font", "RichTextLabel", Kyber.font_body)
	t.set_stylebox("slider", "HSlider", chamfer(Color("070d14"), Kyber.C_LINE, 4, 1))
	return t


static func label(text: String, size := 22, color := Kyber.C_TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func title(text: String, size := 40, color := Kyber.C_TEXT) -> Label:
	var l := label(text.to_upper(), size, color, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_font_override("font", Kyber.font_title)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	return l


## Decorative Aurebesh line (never used for rules text).
static func aurebesh(text: String, size := 18, color := Color(Kyber.C_KYBER, 0.55)) -> Label:
	var l := label(text, size, color, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_font_override("font", Kyber.font_aurebesh)
	l.visible = Kyber.settings.get("show_aurebesh", true)
	return l


static func panel(bg := Color(Kyber.C_PANEL, 0.94), border := Kyber.C_LINE, cut := 12, glow := 0.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", chamfer(bg, border, cut, 2, glow))
	return p


static func spacer(h := 8) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func fill_rect(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Pop-in for any control (grow from 60% of its current scale + fade).
## Keeps the control's pivot so laid-out positions don't shift.
static func pop_in(c: Control, delay := 0.0) -> void:
	var target := c.scale if c.scale.x > 0.01 else Vector2.ONE
	c.scale = target * 0.6
	c.modulate.a = 0.0
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "scale", target, Kyber.anim(0.35)).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, Kyber.anim(0.2)).set_delay(delay)


static func type_label(t: String) -> String:
	return {"unit": "Unit", "event": "Event", "upgrade": "Upgrade", "leader": "Leader", "base": "Base"}.get(t, t.capitalize())


const KEYWORD_HELP := {
	"sentinel": "Enemy units in this arena must attack a Sentinel unit if able.",
	"shielded": "When played, gets a Shield token (prevents the next damage).",
	"grit": "+1 power for each damage on it.",
	"saboteur": "When attacking, ignores Sentinel and defeats the defender's Shields.",
	"ambush": "When played, may ready and attack an enemy unit.",
	"overwhelm": "Excess combat damage to a unit is dealt to its controller's base.",
	"raid": "+X power while attacking.",
	"restore": "When attacking, heal X damage from your base.",
	"hidden": "Can't be attacked the phase it was played.",
	"smuggle": "May be played from your resources at its Smuggle cost.",
	"exploit": "May defeat friendly units to reduce cost (not yet automated).",
	"coordinate": "Bonus while you control 3+ units (shown, not yet automated).",
	"piloting": "May be played as a pilot upgrade on a Vehicle (not yet automated).",
	"bounty": "Reward when this unit is defeated or captured (not yet automated).",
	"support": "When played, may attack with another unit (not yet automated).",
	"plot": "May be deployed from resources with your leader (not yet automated).",
	"fortify": "Attaches to your base (not yet automated).",
}


## draw_string that never spills out of its box: shrinks the font until the
## text fits `width` (down to 60%), then trims with an ellipsis.
static func draw_fit(ci: CanvasItem, font: Font, pos: Vector2, text: String, align: HorizontalAlignment, width: float, size: int, color: Color) -> void:
	if width <= 0.0 or text == "":
		ci.draw_string(font, pos, text, align, width, size, color)
		return
	var fs := size
	var min_fs := maxi(8, int(size * 0.6))
	while fs > min_fs and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
		fs -= 1
	var t := text
	while t.length() > 1 and font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
		t = t.substr(0, t.length() - 2) + "…"
	ci.draw_string(font, pos, t, align, width, fs, color)


## Label that trims with "…" instead of overflowing its box.
static func fit_label(l: Label) -> Label:
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.clip_text = true
	return l
