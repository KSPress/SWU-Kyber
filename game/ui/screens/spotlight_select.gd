extends ScreenBase
## Spotlight Campaign hub: one tile per Spotlight deck with its record
## (runs, best sector, most wins, bosses, recent runs) and either
## "Continue run" or "Start run".

var _scroll: ScrollContainer
var _box: VBoxContainer


func build() -> void:
	set_header("Spotlight Campaign")
	bg.backdrop = Art.ui_texture("swu_background")
	bg.backdrop_alpha = 0.2
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_scroll)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 14)
	_scroll.add_child(_box)
	var intro := UIKit.label("Pick a Spotlight deck. You start with its leader, base and part of its list; win battles to earn the rest, buy and upgrade cards, and push through ever-harder sectors until your base falls. Each deck keeps its own record.", 17, Kyber.C_DIM)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(intro)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 14)
	flow.add_theme_constant_override("v_separation", 14)
	_box.add_child(flow)
	var i := 0
	for d in SpotlightFlow.spots():
		flow.add_child(_entry(d, i))
		i += 1


func _entry(d: Dictionary, i: int) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.custom_minimum_size.x = DeckTile.SIZE.x
	var r := SpotlightFlow.run(d["id"])
	var rec := SpotlightFlow.record(d["id"])
	var tile := DeckTile.make(d, d.get("set_label", "") + " Spotlight")
	tile.selected = not r.is_empty()
	tile.long_pressed.connect(func(_t): InspectOverlay.open(self, d["leader"], tile.get_global_rect()))
	tile.pressed.connect(func(_t): _open(d))
	v.add_child(tile)
	var line := ""
	if rec.is_empty():
		line = "No runs yet"
	else:
		line = "Runs %d · Best sector %d · Most wins %d · Bosses %d" % [int(rec.get("runs", 0)), int(rec.get("best_sector", 0)), int(rec.get("best_wins", 0)), int(rec.get("bosses", 0))]
	var l := UIKit.label(line, 14, Kyber.C_GOLD if not rec.is_empty() else Kyber.C_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)
	var b := KyberButton.make("Continue · Sector %d" % int(r.get("sector", 1)) if not r.is_empty() else "Start run", KyberButton.Style.PRIMARY if not r.is_empty() else KyberButton.Style.REBEL, "play", not r.is_empty())
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func(): _open(d))
	v.add_child(b)
	UIKit.pop_in(v, i * 0.04)
	return v


func _open(d: Dictionary) -> void:
	var r := SpotlightFlow.run(d["id"])
	if not r.is_empty():
		Router.go("spotlight_run", {"deck_id": d["id"]})
		return
	var rec := SpotlightFlow.record(d["id"])
	var mp := ModalPanel.open(self, 620.0, Kyber.C_KYBER)
	mp.dismiss_on_backdrop = true
	var t := mp.text(CardDB.card(d["leader"]).get("name", "").to_upper(), 30, Kyber.C_KYBER)
	t.add_theme_font_override("font", Kyber.font_title)
	mp.text(d.get("full_name", d["name"]), 16, Kyber.C_DIM)
	var row := AspectIcon.row_for(d["leader"], d["base"], 34.0)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	mp.add(row)
	var st: Dictionary = SpotlightRun.cfg().get("start", {})
	mp.text("Start with %d of the deck's %d cards, a %d-HP base and %d credits." % [int(st.get("cards", 20)), Save.deck_size(d), int(st.get("base_hp", 20)), int(st.get("credits", 20))], 17)
	if not rec.is_empty():
		mp.text("RECORD", 18, Kyber.C_GOLD)
		mp.text("Runs %d · Best sector %d · Most wins in a run %d · Bosses defeated %d" % [int(rec.get("runs", 0)), int(rec.get("best_sector", 0)), int(rec.get("best_wins", 0)), int(rec.get("bosses", 0))], 16, Kyber.C_GOLD)
		for h in rec.get("history", []).slice(0, 5):
			mp.text("• Sector %d — %d wins, %d bosses, %d cards earned, deck %d" % [int(h.get("sector", 0)), int(h.get("wins", 0)), int(h.get("bosses", 0)), int(h.get("cards", 0)), int(h.get("deck", 0))], 14, Kyber.C_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	var go := KyberButton.make("Begin run", KyberButton.Style.PRIMARY, "play", true)
	go.pressed.connect(func():
		mp.close()
		SpotlightFlow.start(d["id"])
		Router.go("spotlight_run", {"deck_id": d["id"]}))
	mp.add(go)
	var cancel := KyberButton.make("Back", KyberButton.Style.GHOST)
	cancel.pressed.connect(mp.close)
	mp.add(cancel)


func relayout(_p: bool, r: Rect2) -> void:
	_scroll.position = Vector2.ZERO
	_scroll.size = r.size
	_box.custom_minimum_size.x = r.size.x - 16
