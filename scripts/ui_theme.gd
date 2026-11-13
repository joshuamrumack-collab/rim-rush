extends RefCounted
## Shared look for all menus and HUD panels.


static func panel_style(bg := Color(0.04, 0.05, 0.08, 0.86), border := Color(1, 1, 1, 0.08), radius := 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 10
	return s


static func make(accent := Color(0.25, 0.6, 1.0)) -> Theme:
	var t := Theme.new()
	t.default_font_size = 22
	var normal := panel_style(Color(0.1, 0.12, 0.17, 0.92), Color(1, 1, 1, 0.07), 10)
	var hover := panel_style(Color(0.16, 0.2, 0.3, 0.95), accent.darkened(0.2), 10)
	var focus := panel_style(Color(0.18, 0.26, 0.42, 0.97), accent, 10)
	focus.set_border_width_all(3)
	var pressed := panel_style(accent.darkened(0.3), accent, 10)
	var disabled := panel_style(Color(0.08, 0.08, 0.1, 0.7), Color(1, 1, 1, 0.03), 10)
	for st in [normal, hover, focus, pressed, disabled]:
		st.shadow_size = 0
		st.content_margin_top = 10
		st.content_margin_bottom = 10
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("focus", "Button", focus)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_color("font_color", "Button", Color(0.92, 0.94, 1.0))
	t.set_color("font_focus_color", "Button", Color(1, 1, 1))
	t.set_color("font_hover_color", "Button", Color(1, 1, 1))
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.35))
	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("panel", "Panel", panel_style())
	t.set_color("font_color", "Label", Color(0.93, 0.95, 1.0))
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.85))
	t.set_constant("outline_size", "Label", 4)
	var grab := StyleBoxFlat.new()
	grab.bg_color = accent
	grab.set_corner_radius_all(8)
	t.set_stylebox("grabber_area", "HSlider", grab)
	t.set_stylebox("grabber_area_highlight", "HSlider", grab)
	var sl := StyleBoxFlat.new()
	sl.bg_color = Color(1, 1, 1, 0.12)
	sl.set_corner_radius_all(8)
	sl.content_margin_top = 4
	sl.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", sl)
	var pb_bg := StyleBoxFlat.new()
	pb_bg.bg_color = Color(1, 1, 1, 0.1)
	pb_bg.set_corner_radius_all(6)
	var pb_fill := StyleBoxFlat.new()
	pb_fill.bg_color = accent
	pb_fill.set_corner_radius_all(6)
	t.set_stylebox("background", "ProgressBar", pb_bg)
	t.set_stylebox("fill", "ProgressBar", pb_fill)
	return t


static func label(text: String, size := 22, col := Color(0.93, 0.95, 1.0)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l
