extends ScreenBase
## Saga select: nine episodes (I–IX). Episodes with authored data are playable;
## the rest show as locked holo-tiles. Selecting one lists its chapters.

const EPISODES := [
	[1, "I", "The Phantom Menace"], [2, "II", "Attack of the Clones"], [3, "III", "Revenge of the Sith"],
	[4, "IV", "A New Hope"], [5, "V", "The Empire Strikes Back"], [6, "VI", "Return of the Jedi"],
	[7, "VII", "The Force Awakens"], [8, "VIII", "The Last Jedi"], [9, "IX", "The Rise of Skywalker"],
]

var _grid: GridContainer
var _detail: PanelContainer
var _detail_box: VBoxContainer
var _selected := 4


func build() -> void:
	set_header("Campaign", "menu")
	bg.backdrop = Art.ui_texture("swu_background")
	bg.backdrop_alpha = 0.25
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)
	var i := 0
	for e in EPISODES:
		var tile := _tile(e)
		_grid.add_child(tile)
		UIKit.pop_in(tile, i * 0.04)
		i += 1
	_detail = UIKit.panel(Color(Kyber.C_PANEL, 0.95), Kyber.C_KYBER, 14, 8)
	_detail_box = VBoxContainer.new()
	_detail_box.add_theme_constant_override("separation", 10)
	_detail.add_child(_detail_box)
	body.add_child(_detail)
	_show_episode(_selected)


func _tile(e: Array) -> Control:
	var playable := CardDB.episodes.has(e[0])
	var b := KyberButton.make("", KyberButton.Style.PRIMARY if playable else KyberButton.Style.GHOST, "" if playable else "lock")
	b.custom_minimum_size = Vector2(0, 92)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.text = "EPISODE %s\n%s" % [e[1], e[2]]
	b.add_theme_font_size_override("font_size", 18)
	b.disabled = not playable
	b.pressed.connect(func(): _show_episode(e[0]))
	return b


func _show_episode(ep: int) -> void:
	_selected = ep
	for c in _detail_box.get_children():
		c.queue_free()
	var data := CampaignFlow.episode_data(ep)
	if data.is_empty():
		return
	var t := UIKit.title("Episode %s: %s" % [data.get("roman", ""), data.get("title", "")], 28, Kyber.C_GOLD)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_box.add_child(t)
	var crawl := UIKit.label(data.get("crawl", ""), 17, Kyber.C_GOLD.darkened(0.15), HORIZONTAL_ALIGNMENT_CENTER)
	crawl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_box.add_child(crawl)
	var run := Save.run()
	for ch in data.get("chapters", []):
		var unlocked := CampaignFlow.chapter_unlocked(ch)
		var cleared := Save.is_cleared(ch["id"])
		var active: bool = run.get("chapter", "") == ch["id"] and run.get("status", "") == "active"
		var label := "Chapter %d · %s%s%s" % [int(ch["number"]), ch["title"], "  ✓" if cleared else "", "  (run in progress)" if active else ""]
		var b := KyberButton.make(label, KyberButton.Style.REBEL if unlocked else KyberButton.Style.GHOST, "play" if unlocked else "lock", active)
		b.disabled = not unlocked
		b.add_theme_font_size_override("font_size", 20)
		var cid: String = ch["id"]
		b.pressed.connect(func(): Router.go("chapter", {"chapter_id": cid}))
		_detail_box.add_child(b)
	UIKit.pop_in(_detail)


func relayout(p: bool, r: Rect2) -> void:
	var scroll: ScrollContainer = body.get_node("Scroll")
	_grid.columns = 3
	if p:
		scroll.position = Vector2.ZERO
		scroll.size = Vector2(r.size.x, r.size.y * 0.42)
		_detail.position = Vector2(0, r.size.y * 0.44)
		_detail.size = Vector2(r.size.x, r.size.y * 0.56)
	else:
		scroll.position = Vector2.ZERO
		scroll.size = Vector2(r.size.x * 0.5, r.size.y)
		_detail.position = Vector2(r.size.x * 0.52, 0)
		_detail.size = Vector2(r.size.x * 0.48, r.size.y)
	_grid.custom_minimum_size.x = scroll.size.x - 10
