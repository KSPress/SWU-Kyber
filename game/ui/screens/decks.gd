extends ScreenBase
## Deck Builder home: every saved deck as a tile (marked decks first), plus
## "New deck". Tap a deck to edit; long-press / right-click for actions.

var _scroll: ScrollContainer
var _grid: GridContainer


func build() -> void:
	set_header("Deck Builder")
	bg.backdrop = Art.ui_texture("swu_background")
	bg.backdrop_alpha = 0.2
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 14)
	_scroll.add_child(_grid)
	_fill()


func _fill() -> void:
	for c in _grid.get_children():
		c.queue_free()
	var new_btn := KyberButton.make("New deck", KyberButton.Style.PRIMARY, "play", true)
	new_btn.custom_minimum_size = DeckTile.SIZE
	new_btn.add_theme_font_size_override("font_size", 24)
	new_btn.pressed.connect(_new_deck)
	_grid.add_child(new_btn)
	var list: Array = Save.decks().duplicate()
	list.sort_custom(func(a, b):
		if a.get("marked", false) != b.get("marked", false):
			return a.get("marked", false)
		return float(a.get("updated", 0)) > float(b.get("updated", 0)))
	var i := 0
	for d in list:
		var t := DeckTile.make(d)
		t.pressed.connect(func(_t): Router.go("deck_editor", {"deck_id": d["id"]}))
		t.long_pressed.connect(func(_t): _actions(d))
		_grid.add_child(t)
		UIKit.pop_in(t, i * 0.04)
		i += 1


func _new_deck() -> void:
	var mp := ModalPanel.open(self, 560.0, Kyber.C_KYBER)
	mp.dismiss_on_backdrop = true
	mp.text("NEW DECK", 28, Kyber.C_KYBER)
	var blank := KyberButton.make("Blank deck", KyberButton.Style.PRIMARY, "play")
	blank.pressed.connect(func():
		mp.close()
		Router.go("deck_editor", {"deck_id": ""}))
	mp.add(blank)
	mp.text("…or start from a Spotlight deck", 16, Kyber.C_DIM)
	for sd in CardDB.spotlight_for_mode("traditional") + CardDB.spotlight_for_mode("space"):
		var b := KyberButton.make(sd["name"], KyberButton.Style.GHOST, sd.get("icon", "star"))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(func():
			var d := {"id": "", "name": CardDB.card(sd["leader"]).get("name", "Deck"), "icon": "star", "marked": false,
				"leader": sd["leader"], "base": sd["base"], "cards": sd["cards"].duplicate()}
			Save.save_deck(d)
			mp.close()
			Router.go("deck_editor", {"deck_id": d["id"]}))
		mp.add(b)
	var cancel := KyberButton.make("Cancel", KyberButton.Style.GHOST)
	cancel.pressed.connect(mp.close)
	mp.add(cancel)


func _actions(d: Dictionary) -> void:
	var mp := ModalPanel.open(self, 520.0, Kyber.C_GOLD)
	mp.dismiss_on_backdrop = true
	mp.text(d.get("name", "Deck").to_upper(), 26, Kyber.C_GOLD)
	var row := AspectIcon.row_for(d.get("leader", ""), d.get("base", ""), 34.0)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	mp.add(row)
	var edit := KyberButton.make("Edit", KyberButton.Style.PRIMARY, "gear")
	edit.pressed.connect(func():
		mp.close()
		Router.go("deck_editor", {"deck_id": d["id"]}))
	mp.add(edit)
	var mark := KyberButton.make("Unmark" if d.get("marked", false) else "Mark as favourite", KyberButton.Style.GOLD, "star")
	mark.pressed.connect(func():
		d["marked"] = not d.get("marked", false)
		Save.save_deck(d)
		mp.close()
		_fill())
	mp.add(mark)
	var dup := KyberButton.make("Duplicate", KyberButton.Style.REBEL, "deck")
	dup.pressed.connect(func():
		var c := d.duplicate(true)
		c["id"] = ""
		c["name"] = d.get("name", "Deck") + " (copy)"
		Save.save_deck(c)
		mp.close()
		_fill())
	mp.add(dup)
	var del := KyberButton.make("Delete", KyberButton.Style.EMPIRE)
	del.pressed.connect(func():
		if del.text != "Tap again to delete":
			del.text = "Tap again to delete"
			return
		Save.delete_deck(d["id"])
		mp.close()
		_fill())
	mp.add(del)
	var cancel := KyberButton.make("Close", KyberButton.Style.GHOST)
	cancel.pressed.connect(mp.close)
	mp.add(cancel)


func relayout(_p: bool, r: Rect2) -> void:
	_scroll.position = Vector2.ZERO
	_scroll.size = r.size
	_grid.columns = maxi(1, int((r.size.x + 14) / (DeckTile.SIZE.x + 14)))
