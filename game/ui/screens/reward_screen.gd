extends ScreenBase
## Post-victory rewards: pick 1 of 3 cards (flipped in face-down), optionally a
## treasure after elite/objective fights; chapter-clear screen after a boss.

var res: Dictionary
var chapter: Dictionary
var _row: HBoxContainer
var _box: VBoxContainer
var _picked := false


func build() -> void:
	res = Router.params
	chapter = CardDB.chapter(res.get("chapter_id", ""))
	set_header("Victory", "")
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 14)
	body.add_child(_box)
	if res.get("boss", false):
		_build_clear()
		return
	if res.has("pickup"):
		var pl := UIKit.label("%s joins your deck!" % CardDB.card(res["pickup"]).get("name", ""), 22, Kyber.C_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
		_box.add_child(pl)
	_box.add_child(UIKit.title("Choose a card", 34, Kyber.C_KYBER))
	_box.add_child(UIKit.label("Tap to take it · long-press to inspect", 16, Kyber.C_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 14)
	_box.add_child(_row)
	var i := 0
	for id in res.get("rewards", []):
		_row.add_child(_reward_card(id, i))
		i += 1
	var tre: Array = res.get("treasures", [])
	if not tre.is_empty():
		_box.add_child(UIKit.title("…or a treasure", 26, Kyber.C_GOLD))
		var tdefs := CampaignFlow.treasures_for(chapter)
		for t in tre:
			var td: Dictionary = tdefs.get(t, {})
			var b := KyberButton.make("%s — %s" % [td.get("name", t), td.get("desc", "")], KyberButton.Style.GOLD, "star")
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.pressed.connect(func(): _take({"treasure": t}))
			_box.add_child(b)
	var skip := KyberButton.make("Skip reward", KyberButton.Style.GHOST)
	skip.pressed.connect(func(): _take({}))
	_box.add_child(skip)


func _reward_card(id: String, i: int) -> Control:
	var slot := Control.new()
	var sc := _scale()
	slot.custom_minimum_size = CardView.PORTRAIT * sc
	var cv := CardView.create(id)
	cv.pivot_offset = CardView.PORTRAIT / 2.0
	cv.home_scale = Vector2(sc, sc)
	cv.scale = cv.home_scale
	cv.position = (CardView.PORTRAIT * sc - CardView.PORTRAIT) / 2.0
	cv.home_pos = cv.position
	cv.hover_lift = false
	cv.face_down = true
	cv.drag_released.connect(func(c, _p): c.spring_home())
	cv.tapped.connect(func(_c): _take({"add_cards": [id]}))
	cv.inspect_requested.connect(func(c): InspectOverlay.open(self, c.card_id, c.get_global_rect()))
	slot.add_child(cv)
	get_tree().create_timer(Kyber.anim(0.4 + i * 0.25)).timeout.connect(func():
		Sfx.play("draw")
		cv.flip_to(true))
	return slot


func _scale() -> float:
	var vs := get_viewport_rect().size
	return clampf(minf(vs.x / 3.5, vs.y * 0.38 / 1.39) / CardView.PORTRAIT.x, 0.4, 1.0)


func _take(effect: Dictionary) -> void:
	if _picked:
		return
	_picked = true
	var run := Save.run()
	CampaignRun.apply_effect(run, chapter, effect)
	Save.set_run(run)
	Sfx.play("win", 1.5)
	Router.go("chapter", {"chapter_id": chapter["id"]})


func _build_clear() -> void:
	_box.add_child(UIKit.aurebesh("chapter complete", 26))
	_box.add_child(UIKit.title("%s cleared!" % chapter.get("title", ""), 44, Kyber.C_GOLD))
	var unlocked: Array = res.get("unlocked", [])
	_box.add_child(UIKit.label("%d new card(s) added to your Collection Vault." % unlocked.size(), 20, Kyber.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = CardView.PORTRAIT.y * 0.5 + 20
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	scroll.add_child(row)
	_box.add_child(scroll)
	var i := 0
	for id in unlocked:
		var slot := Control.new()
		slot.custom_minimum_size = CardView.PORTRAIT * 0.5
		if CardDB.card(id).get("type", "") in ["leader", "base"]:
			slot.custom_minimum_size = CardView.LANDSCAPE * 0.5
		var cv := CardView.create(id)
		cv.pivot_offset = Vector2.ZERO
		cv.home_scale = Vector2(0.5, 0.5)
		cv.scale = cv.home_scale
		cv.hover_lift = false
		cv.draggable = false
		cv.tapped.connect(func(c): InspectOverlay.open(self, c.card_id, c.get_global_rect()))
		slot.add_child(cv)
		row.add_child(slot)
		UIKit.pop_in(cv, i * 0.05)
		i += 1
	var next: String = chapter.get("next_chapter", "")
	if next != "":
		var b := KyberButton.make("Next chapter", KyberButton.Style.PRIMARY, "play", true)
		b.pressed.connect(func(): Router.go("chapter", {"chapter_id": next}))
		_box.add_child(b)
	var back := KyberButton.make("Campaign", KyberButton.Style.GHOST, "back")
	back.pressed.connect(func(): Router.go("episodes"))
	_box.add_child(back)


func relayout(_p: bool, r: Rect2) -> void:
	_box.position = Vector2(r.size.x * 0.04, 0)
	_box.size = Vector2(r.size.x * 0.92, r.size.y)
