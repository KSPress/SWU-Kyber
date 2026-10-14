extends ScreenBase
## A Spotlight Campaign run: sector map, run HUD, every node type, rewards,
## run deck editing and the end-of-run summary.

const NodeButton := preload("res://ui/screens/chapter_map.gd").NodeButton
const GLYPH := {"fight": "fight", "elite": "elite", "objective": "objective", "boss": "boss", "event": "event",
	"rest": "rest", "shop": "resource", "treasure": "star"}

var deck_id := ""
var run: Dictionary
var _hud: HFlowContainer
var _map: Control
var _nodes: Dictionary = {}
var _panel: ModalPanel


func build() -> void:
	deck_id = Router.params.get("deck_id", "")
	run = SpotlightFlow.run(deck_id)
	var res: Dictionary = Router.params.get("result", {})
	set_header("Spotlight · " + CardDB.card(SpotlightFlow.spot(deck_id).get("leader", "")).get("name", ""), "spotlight")
	bg.backdrop = Art.ui_texture("planets/" + ["kessel", "felucia", "nar_shaddaa", "kamino", "mustafar"][int(run.get("sector", 1)) % 5]) if not run.is_empty() else null
	bg.backdrop_alpha = 0.3
	if run.is_empty():
		_death(res)
		return
	_hud = HFlowContainer.new()
	_hud.add_theme_constant_override("h_separation", 10)
	_hud.add_theme_constant_override("v_separation", 6)
	body.add_child(_hud)
	_map = Control.new()
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.draw.connect(_draw_links)
	body.add_child(_map)
	_refresh()
	if not run.get("pending_reward", {}).is_empty():
		_reward.call_deferred()


func _save() -> void:
	SpotlightFlow.save_run(run)


func _refresh() -> void:
	for c in _hud.get_children():
		c.queue_free()
	var hp := int(run["base_max"]) - int(run["base_damage"])
	_hud.add_child(_chip("Sector %d" % int(run["sector"]), Kyber.C_KYBER))
	_hud.add_child(_chip("Base %d / %d" % [hp, int(run["base_max"])], Kyber.C_GOOD if hp > int(run["base_max"]) / 2 else Kyber.C_EMPIRE))
	_hud.add_child(_chip("Credits %d" % int(run["credits"]), Kyber.C_COST))
	var locked := 0
	for id in run["locked"]:
		locked += int(run["locked"][id])
	_hud.add_child(_chip("Spotlight cards left %d" % locked, Kyber.C_DIM))
	var deck_b := KyberButton.make("Deck %d" % SpotlightRun.deck_size(run), KyberButton.Style.GOLD, "deck")
	deck_b.pressed.connect(_edit_deck)
	_hud.add_child(deck_b)
	var perk_b := KyberButton.make("Perks %d" % run["perks"].size(), KyberButton.Style.GHOST, "star")
	perk_b.pressed.connect(_show_perks)
	_hud.add_child(perk_b)
	var ab := KyberButton.make("Abandon", KyberButton.Style.EMPIRE)
	ab.pressed.connect(func():
		if ab.text != "Tap again to abandon":
			ab.text = "Tap again to abandon"
			return
		run["status"] = "abandoned"
		SpotlightFlow.finish(run)
		Router.go("spotlight"))
	_hud.add_child(ab)
	for c in _map.get_children():
		c.queue_free()
	_nodes.clear()
	var avail := SpotlightRun.available_nodes(run)
	for id in run["map"]["nodes"]:
		var n: Dictionary = run["map"]["nodes"][id].duplicate()
		n["glyph"] = GLYPH.get(n["type"], "fight")
		var nb := NodeButton.new()
		nb.node_def = n
		nb.state = "visited" if id in run["visited"] else ("available" if id in avail else "locked")
		var nid: String = id
		nb.pressed.connect(func(): _open_node(nid))
		_map.add_child(nb)
		_nodes[id] = nb
	_on_resize()
	# the HUD wraps onto a second row on narrow screens: lay the map out again once it has
	_on_resize.call_deferred()


func _chip(text: String, col: Color) -> Control:
	var p := UIKit.panel(Color(0.02, 0.05, 0.09, 0.9), Color(col, 0.6), 8)
	p.add_child(UIKit.label(text, 18, col))
	return p


func _draw_links() -> void:
	var edges: Dictionary = run.get("map", {}).get("edges", {})
	for a in edges:
		for b in edges[a]:
			if not (_nodes.has(a) and _nodes.has(b)):
				continue
			var pa: Vector2 = _nodes[a].position + _nodes[a].size / 2.0
			var pb: Vector2 = _nodes[b].position + _nodes[b].size / 2.0
			var lit: bool = a in run["visited"] and (b in run["visited"] or a == run["current"])
			var col := Color(Kyber.C_KYBER, 0.8) if lit else Color(1, 1, 1, 0.16)
			var d := pb - pa
			var n := int(d.length() / 14.0)
			for i in n:
				if i % 2 == 0:
					_map.draw_line(pa + d * (i / float(n)), pa + d * ((i + 1) / float(n)), col, 3.0, true)


func relayout(p: bool, r: Rect2) -> void:
	if _hud == null:
		return
	_hud.position = Vector2.ZERO
	_hud.size = Vector2(r.size.x, 0)
	var top := maxf(_hud.get_combined_minimum_size().y, _hud.size.y) + 14
	_map.position = Vector2(0, top)
	_map.size = Vector2(r.size.x, r.size.y - top)
	var rows: Array = run["map"]["rows"]
	var n := rows.size()
	for ri in n:
		var row: Array = rows[ri]
		for ci in row.size():
			var nb: Control = _nodes.get(row[ci])
			if nb == null:
				continue
			var s := clampf(minf(_map.size.x, _map.size.y) * 0.11, 60, 104)
			nb.size = Vector2(s, s)
			var along := (ci + 1.0) / (row.size() + 1.0)
			var step := (ri + 0.5) / float(n)
			if p:
				nb.position = Vector2(_map.size.x * along - s / 2.0, _map.size.y * (1.0 - step) - s / 2.0 - 8)
			else:
				nb.position = Vector2(_map.size.x * step - s / 2.0, _map.size.y * along - s / 2.0)
	_map.queue_redraw()


# ---------------------------------------------------------------- nodes

func _complete(id: String) -> void:
	run["current"] = id
	run["visited"].append(id)
	run["stats"]["nodes"] = int(run["stats"]["nodes"]) + 1
	_save()
	_refresh()


func _open_node(id: String) -> void:
	if not (id in SpotlightRun.available_nodes(run)) or id in run["visited"]:
		return
	var n := SpotlightRun.node(run, id)
	if _panel and is_instance_valid(_panel):
		_panel.close()
	var t: String = n["type"]
	var mp := ModalPanel.open(self, 640.0, Kyber.C_EMPIRE if t == "boss" else Kyber.C_GOLD)
	mp.dismiss_on_backdrop = true
	_panel = mp
	mp.add(UIKit.aurebesh(t, 18))
	var title := mp.text(str(n["title"]).to_upper(), 28, Kyber.C_GOLD)
	title.add_theme_font_override("font", Kyber.font_title)
	match t:
		"fight", "elite", "objective", "boss":
			_battle_panel(mp, id, n)
		"event":
			_event_panel(mp, id, n)
		"rest":
			_rest_panel(mp, id)
		"shop":
			_shop_panel(mp, id)
		"treasure":
			_treasure_panel(mp, id)
	var back := KyberButton.make("Back", KyberButton.Style.GHOST)
	back.pressed.connect(mp.close)
	mp.add(back)


func _battle_panel(mp: ModalPanel, id: String, n: Dictionary) -> void:
	var en: Dictionary = n["enemy"]
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var slot := Control.new()
	slot.custom_minimum_size = CardView.LANDSCAPE * 0.6
	var cv := CardView.create(en["leader"])
	cv.pivot_offset = Vector2.ZERO
	cv.scale = Vector2(0.6, 0.6)
	cv.home_scale = cv.scale
	cv.hover_lift = false
	cv.draggable = false
	cv.tapped.connect(func(c): InspectOverlay.open(self, c.card_id, c.get_global_rect()))
	slot.add_child(cv)
	row.add_child(slot)
	mp.add(row)
	mp.text("%s · base %d HP · %d-card deck%s" % [en.get("name", "Enemy"), int(en["hp"]), en["deck"].size(),
		(" · +%d resources" % int(en["extra_resources"])) if int(en.get("extra_resources", 0)) > 0 else ""], 17)
	mp.text("Objective: " + Objective.create(n.get("objective", {})).describe(), 17, Kyber.C_KYBER)
	if not en.get("preplaced", []).is_empty():
		var names: Array = []
		for p in en["preplaced"]:
			names.append(CardDB.card(p["id"]).get("name", ""))
		mp.text("Already on the field: " + ", ".join(names), 15, Kyber.C_EMPIRE)
	var reward_txt: String = {"fight": "a card", "objective": "a card, maybe a perk", "elite": "a rare card + a perk", "boss": "2 cards, a perk, repairs — then the next sector"}[n["type"]]
	mp.text("Reward: credits and " + reward_txt, 15, Kyber.C_DIM)
	if SpotlightRun.deck_size(run) < int(SpotlightRun.cfg().get("start", {}).get("deck_min", 20)):
		mp.text("Your deck needs at least %d cards — edit your deck first." % int(SpotlightRun.cfg()["start"]["deck_min"]), 16, Kyber.C_EMPIRE)
		return
	var go := KyberButton.make("Engage", KyberButton.Style.EMPIRE if n["type"] == "boss" else KyberButton.Style.PRIMARY, "fight", true)
	go.custom_minimum_size.y = 66
	go.pressed.connect(func():
		mp.close()
		SpotlightFlow.start_node(run, id))
	mp.add(go)


func _event_panel(mp: ModalPanel, id: String, n: Dictionary) -> void:
	var ev := {}
	for e in SpotlightRun.cfg().get("events", []):
		if e["id"] == n.get("event", ""):
			ev = e
	mp.text(ev.get("desc", ""), 17)
	for ch in ev.get("choices", []):
		var eff: Dictionary = ch.get("effect", {})
		var b := KyberButton.make(ch.get("label", ""), KyberButton.Style.PRIMARY, "event")
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.disabled = int(eff.get("credits", 0)) < 0 and int(run["credits"]) < -int(eff["credits"])
		b.pressed.connect(func():
			mp.close()
			if eff.has("remove_card"):
				_pick_owned("Choose a card to trade away", func(cid):
					SpotlightRun.remove_card(run, cid)
					_finish_effect(id, eff))
				return
			if eff.has("upgrade_card"):
				_pick_owned("Choose a card to upgrade (every copy gains it)", func(cid):
					SpotlightRun.upgrade_card(run, cid, eff["upgrade_card"])
					_finish_effect(id, eff))
				return
			_finish_effect(id, eff))
		mp.add(b)


func _finish_effect(id: String, eff: Dictionary) -> void:
	var e := eff.duplicate()
	e.erase("remove_card")
	e.erase("upgrade_card")
	var msg := SpotlightRun.apply_effect(run, e, CardDB.lib, SpotlightRun.rng_for(run, hash(id)))
	_complete(id)
	if msg != "":
		Fx.banner(self, "Done", Kyber.C_GOLD, msg)


func _rest_panel(mp: ModalPanel, id: String) -> void:
	mp.text("A safe house. Choose one:", 17)
	var heal := maxi(4, int(run["base_max"]) * 3 / 10)
	var h := KyberButton.make("Repair: heal %d base damage" % heal, KyberButton.Style.PRIMARY, "heal")
	h.pressed.connect(func():
		mp.close()
		_finish_effect(id, {"heal": heal}))
	mp.add(h)
	var u := KyberButton.make("Train: a card gains a permanent Experience token", KyberButton.Style.GOLD, "star")
	u.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	u.pressed.connect(func():
		mp.close()
		_pick_owned("Choose a card to train", func(cid):
			SpotlightRun.upgrade_card(run, cid, "experience")
			_finish_effect(id, {})))
	mp.add(u)
	var s := KyberButton.make("Fortify: a card gains a permanent Shield token", KyberButton.Style.REBEL, "shield")
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	s.pressed.connect(func():
		mp.close()
		_pick_owned("Choose a card to shield", func(cid):
			SpotlightRun.upgrade_card(run, cid, "shield")
			_finish_effect(id, {})))
	mp.add(s)


func _shop_panel(mp: ModalPanel, id: String) -> void:
	var prices: Dictionary = SpotlightRun.cfg().get("prices", {})
	mp.text("Credits: %d" % int(run["credits"]), 18, Kyber.C_COST)
	var stock := SpotlightRun.shop_stock(run, CardDB.lib, id)
	var bought: Array = run.get("shop_bought", {}).get(id, [])
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	mp.add(grid)
	for cid in stock:
		var col := VBoxContainer.new()
		var slot := Control.new()
		slot.custom_minimum_size = CardView.PORTRAIT * 0.45
		var cv := CardView.create(cid)
		cv.pivot_offset = Vector2.ZERO
		cv.scale = Vector2(0.45, 0.45)
		cv.home_scale = cv.scale
		cv.hover_lift = false
		cv.draggable = false
		cv.tapped.connect(func(c): InspectOverlay.open(self, c.card_id, c.get_global_rect()))
		slot.add_child(cv)
		col.add_child(slot)
		var price := SpotlightRun.price(CardDB.lib, cid)
		var b := KyberButton.make("%d" % price, KyberButton.Style.GOLD)
		b.disabled = cid in bought or int(run["credits"]) < price
		if cid in bought:
			b.text = "Sold"
		var c_id: String = cid
		b.pressed.connect(func():
			run["credits"] = int(run["credits"]) - price
			SpotlightRun.gain_card(run, c_id)
			var sb: Dictionary = run.get("shop_bought", {})
			var lst: Array = sb.get(id, [])
			lst.append(c_id)
			sb[id] = lst
			run["shop_bought"] = sb
			_save()
			_refresh()
			mp.close()
			_open_node(id))
		col.add_child(b)
		grid.add_child(col)
	var rm := KyberButton.make("Remove a card (%d)" % int(prices.get("remove", 35)), KyberButton.Style.GHOST, "deck")
	rm.disabled = int(run["credits"]) < int(prices.get("remove", 35))
	rm.pressed.connect(func():
		mp.close()
		_pick_owned("Choose a card to remove", func(cid):
			run["credits"] = int(run["credits"]) - int(prices.get("remove", 35))
			SpotlightRun.remove_card(run, cid)
			_save()
			_refresh()
			_open_node(id)))
	mp.add(rm)
	var heal := KyberButton.make("Repairs: heal 6 (%d)" % int(prices.get("heal6", 20)), KyberButton.Style.GHOST, "heal")
	heal.disabled = int(run["credits"]) < int(prices.get("heal6", 20)) or int(run["base_damage"]) == 0
	heal.pressed.connect(func():
		SpotlightRun.apply_effect(run, {"credits": -int(prices.get("heal6", 20)), "heal": 6}, CardDB.lib, SpotlightRun.rng_for(run, 3))
		_save()
		_refresh()
		mp.close()
		_open_node(id))
	mp.add(heal)
	var up := KyberButton.make("Upgrade a card: +Experience (%d)" % int(prices.get("upgrade", 45)), KyberButton.Style.GHOST, "star")
	up.disabled = int(run["credits"]) < int(prices.get("upgrade", 45))
	up.pressed.connect(func():
		mp.close()
		_pick_owned("Choose a card to upgrade", func(cid):
			run["credits"] = int(run["credits"]) - int(prices.get("upgrade", 45))
			SpotlightRun.upgrade_card(run, cid, "experience")
			_save()
			_refresh()
			_open_node(id)))
	mp.add(up)
	var leave := KyberButton.make("Leave the market", KyberButton.Style.PRIMARY, "back")
	leave.pressed.connect(func():
		mp.close()
		_complete(id))
	mp.add(leave)


func _treasure_panel(mp: ModalPanel, id: String) -> void:
	mp.text("Choose one:", 17)
	var perks := SpotlightRun.random_perks(run, 2, SpotlightRun.rng_for(run, hash(id)))
	var defs: Dictionary = SpotlightRun.cfg().get("perks", {})
	for p in perks:
		var b := KyberButton.make("%s — %s" % [defs[p]["name"], defs[p]["desc"]], KyberButton.Style.GOLD, "star")
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var pid: String = p
		b.pressed.connect(func():
			mp.close()
			SpotlightRun.add_perk(run, pid)
			_complete(id))
		mp.add(b)
	var cr := KyberButton.make("Take 30 credits instead", KyberButton.Style.GHOST)
	cr.pressed.connect(func():
		mp.close()
		_finish_effect(id, {"credits": 30}))
	mp.add(cr)


# ---------------------------------------------------------------- rewards

func _reward() -> void:
	var rw: Dictionary = run.get("pending_reward", {})
	if rw.is_empty():
		return
	var mp := ModalPanel.open(self, 900.0, Kyber.C_GOLD)
	mp.add(UIKit.aurebesh("victory", 22))
	var t := mp.text("VICTORY · +%d CREDITS" % int(rw.get("credits", 0)), 30, Kyber.C_GOLD)
	t.add_theme_font_override("font", Kyber.font_title)
	var picks := int(rw.get("picks", 1))
	mp.text("Choose %d card%s to add to your deck (tap a card to choose, long-press to inspect)" % [picks, "s" if picks > 1 else ""], 17)
	var chosen: Array = []
	var row := HFlowContainer.new()
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("h_separation", 12)
	mp.add(row)
	var views := {}
	var sc := clampf(get_viewport_rect().size.x / 4.2 / CardView.PORTRAIT.x, 0.4, 0.75)
	for cid in rw.get("cards", []):
		var slot := Control.new()
		slot.custom_minimum_size = CardView.PORTRAIT * sc + Vector2(0, 24)
		var cv := CardView.create(cid)
		cv.pivot_offset = Vector2.ZERO
		cv.scale = Vector2(sc, sc)
		cv.home_scale = cv.scale
		cv.hover_lift = false
		cv.draggable = false
		cv.face_down = true
		slot.add_child(cv)
		var tag := UIKit.label("SPOTLIGHT" if run["locked"].has(cid) else "LOOT", 13, Kyber.C_KYBER if run["locked"].has(cid) else Kyber.C_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
		tag.position = Vector2(0, CardView.PORTRAIT.y * sc + 2)
		tag.size = Vector2(CardView.PORTRAIT.x * sc, 20)
		slot.add_child(tag)
		row.add_child(slot)
		views[cid] = cv
		get_tree().create_timer(0.3 + views.size() * 0.2).timeout.connect(func():
			if is_instance_valid(cv):
				Sfx.play("draw")
				cv.flip_to(true))
		var c_id: String = cid
		cv.inspect_requested.connect(func(c): InspectOverlay.open(self, c.card_id, c.get_global_rect()))
		cv.tapped.connect(func(_c):
			if c_id in chosen:
				chosen.erase(c_id)
			elif chosen.size() < picks:
				chosen.append(c_id)
			for k in views:
				views[k].selected = k in chosen)
	var perk_pick := {"p": ""}
	var perks: Array = rw.get("perks", [])
	if not perks.is_empty():
		mp.text("…and a perk:", 18, Kyber.C_GOLD)
		var defs: Dictionary = SpotlightRun.cfg().get("perks", {})
		var btns: Array = []
		for p in perks:
			var b := KyberButton.make("%s — %s" % [defs[p]["name"], defs[p]["desc"]], KyberButton.Style.GHOST, "star")
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.toggle_mode = true
			var pid: String = p
			b.pressed.connect(func():
				perk_pick["p"] = pid
				for o in btns:
					o.button_pressed = o == b)
			btns.append(b)
			mp.add(b)
	var done := KyberButton.make("Claim", KyberButton.Style.PRIMARY, "play", true)
	done.pressed.connect(func():
		for c in chosen:
			SpotlightRun.gain_card(run, c)
		if perk_pick["p"] != "":
			SpotlightRun.add_perk(run, perk_pick["p"])
		var boss: bool = rw.get("boss", false)
		run["pending_reward"] = {}
		if boss:
			SpotlightRun.next_sector(run, CardDB.lib, SpotlightFlow.spots())
		_save()
		mp.close()
		_refresh()
		if boss:
			Fx.banner(self, "Sector %d" % int(run["sector"]), Kyber.C_KYBER, "The enemy grows stronger"))
	mp.add(done)


# ---------------------------------------------------------------- deck

## Pick one owned card (for remove / upgrade).
func _pick_owned(title: String, cb: Callable) -> void:
	var mp := ModalPanel.open(self, 2000.0, Kyber.C_GOLD, true)
	mp.text(title.to_upper(), 24, Kyber.C_GOLD)
	var grid := GridContainer.new()
	var vs := get_viewport_rect().size
	var cols := 4 if vs.y >= vs.x else 7
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	mp.add(grid)
	var sc := (vs.x * 0.94 - 60 - cols * 8) / cols / CardView.PORTRAIT.x
	var ids: Array = run["owned"].keys()
	ids.sort_custom(func(a, b): return int(CardDB.card(a).get("cost", 0)) < int(CardDB.card(b).get("cost", 0)))
	for cid in ids:
		var slot := Control.new()
		slot.custom_minimum_size = CardView.PORTRAIT * sc
		var cv := CardView.create(cid)
		cv.pivot_offset = Vector2.ZERO
		cv.scale = Vector2(sc, sc)
		cv.home_scale = cv.scale
		cv.hover_lift = false
		cv.draggable = false
		var c_id: String = cid
		cv.tapped.connect(func(_c):
			mp.close()
			cb.call(c_id))
		cv.inspect_requested.connect(func(c): InspectOverlay.open(self, c.card_id, c.get_global_rect()))
		slot.add_child(cv)
		grid.add_child(slot)
	var cancel := KyberButton.make("Cancel", KyberButton.Style.GHOST)
	cancel.pressed.connect(mp.close)
	mp.add(cancel)


## Move owned cards in and out of the deck; shows upgrades.
func _edit_deck() -> void:
	var mp := ModalPanel.open(self, 760.0, Kyber.C_GOLD, true)
	var head := mp.text("", 20, Kyber.C_GOLD)
	var minimum := int(SpotlightRun.cfg().get("start", {}).get("deck_min", 20))
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	mp.add(list)
	var fill := func(): pass
	fill = func():
		for c in list.get_children():
			c.queue_free()
		head.text = "DECK %d CARDS (minimum %d) · %d owned" % [SpotlightRun.deck_size(run), minimum, _owned_total()]
		var ids: Array = run["owned"].keys()
		ids.sort_custom(func(a, b):
			var ca := CardDB.card(a)
			var cb2 := CardDB.card(b)
			if int(ca.get("cost", 0)) != int(cb2.get("cost", 0)):
				return int(ca.get("cost", 0)) < int(cb2.get("cost", 0))
			return str(ca.get("name", "")) < str(cb2.get("name", "")))
		for cid in ids:
			var c := CardDB.card(cid)
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 6)
			h.add_child(UIKit.label(str(int(c.get("cost", 0))), 18, Kyber.C_COST))
			for a in c.get("aspects", []):
				h.add_child(AspectIcon.make(a, 22.0))
			var ups: Array = run["upgrades"].get(cid, [])
			var nm := UIKit.label(str(c.get("name", cid)) + ("  ★" + " ★".join(ups.map(func(u): return "XP" if u == "experience" else "Shield")) if not ups.is_empty() else ""), 16, Kyber.C_TEXT)
			nm.clip_text = true
			nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			nm.mouse_filter = Control.MOUSE_FILTER_STOP
			var c_id: String = cid
			nm.gui_input.connect(func(ev):
				if ev is InputEventMouseButton and ev.pressed:
					InspectOverlay.open(self, c_id, nm.get_global_rect()))
			h.add_child(nm)
			h.add_child(UIKit.label("%d / %d" % [int(run["deck"].get(cid, 0)), int(run["owned"][cid])], 17, Kyber.C_KYBER))
			var minus := KyberButton.make("−", KyberButton.Style.GHOST)
			minus.custom_minimum_size = Vector2(44, 40)
			minus.disabled = int(run["deck"].get(cid, 0)) <= 0
			minus.pressed.connect(func():
				run["deck"][c_id] = int(run["deck"].get(c_id, 0)) - 1
				if int(run["deck"][c_id]) <= 0:
					run["deck"].erase(c_id)
				fill.call())
			h.add_child(minus)
			var plus := KyberButton.make("+", KyberButton.Style.GHOST)
			plus.custom_minimum_size = Vector2(44, 40)
			plus.disabled = int(run["deck"].get(cid, 0)) >= mini(3, int(run["owned"][cid]))
			plus.pressed.connect(func():
				run["deck"][c_id] = int(run["deck"].get(c_id, 0)) + 1
				fill.call())
			h.add_child(plus)
			list.add_child(h)
	fill.call()
	var done := KyberButton.make("Done", KyberButton.Style.PRIMARY, "play")
	done.pressed.connect(func():
		if SpotlightRun.deck_size(run) < minimum:
			Fx.float_text(self, done.get_global_rect().get_center(), "Need at least %d cards" % minimum, Kyber.C_EMPIRE, 22)
			return
		_save()
		mp.close()
		_refresh())
	mp.add(done)


func _owned_total() -> int:
	var n := 0
	for id in run["owned"]:
		n += int(run["owned"][id])
	return n


func _show_perks() -> void:
	var mp := ModalPanel.open(self, 620.0, Kyber.C_GOLD)
	mp.dismiss_on_backdrop = true
	mp.text("PERKS", 26, Kyber.C_GOLD)
	var defs: Dictionary = SpotlightRun.cfg().get("perks", {})
	if run["perks"].is_empty():
		mp.text("None yet — win elites, bosses and missions, or find hidden caches.", 16, Kyber.C_DIM)
	for p in run["perks"]:
		mp.text("%s — %s" % [defs[p]["name"], defs[p]["desc"]], 17, Kyber.C_TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	var close := KyberButton.make("Close", KyberButton.Style.GHOST)
	close.pressed.connect(mp.close)
	mp.add(close)


# ---------------------------------------------------------------- end of run

func _death(res: Dictionary) -> void:
	var s: Dictionary = res.get("summary", {})
	var rec := SpotlightFlow.record(deck_id)
	var box := VBoxContainer.new()
	box.name = "Death"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	body.add_child(box)
	box.add_child(UIKit.aurebesh("base destroyed", 24))
	box.add_child(UIKit.title("Run over", 52, Kyber.C_EMPIRE))
	if not s.is_empty():
		for line in ["Reached sector %d" % int(s["sector"]), "%d battles won · %d elites · %d bosses · %d missions" % [int(s["wins"]), int(s["elites"]), int(s["bosses"]), int(s["missions"])],
				"%d cards earned · final deck %d cards · %d perks" % [int(s["cards"]), int(s["deck"]), s["perks"].size()]]:
			box.add_child(UIKit.label(line, 20, Kyber.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	if not rec.is_empty():
		box.add_child(UIKit.label("Record: %d runs · best sector %d · most wins %d · %d bosses" % [int(rec["runs"]), int(rec["best_sector"]), int(rec["best_wins"]), int(rec["bosses"])], 18, Kyber.C_GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(UIKit.label("Cards you earned were added to your Collection Vault.", 15, Kyber.C_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	var b := KyberButton.make("Back to Spotlight Campaign", KyberButton.Style.PRIMARY, "back", true)
	b.pressed.connect(func(): Router.go("spotlight"))
	box.add_child(b)


func _on_resize() -> void:
	super._on_resize()
	var d := body.get_node_or_null("Death")
	if d:
		d.position = Vector2.ZERO
		d.size = body.size
