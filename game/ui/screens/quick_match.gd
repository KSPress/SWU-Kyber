class_name QuickMatch
extends ScreenBase
## Battle setup vs the bot.
##   Standard Battle: traditional SWU (Premier) — pick one of your saved decks,
##     a Spotlight deck, or auto-build around a leader + base chosen from the
##     radial picker.
##   Quick Battle: pick a Spotlight deck for the current Quick mode
##     (One Lane / Traditional / Ground Only / Space Only — also in Settings).

const PROFILES := ["aggressive", "tempo", "defensive"]
const MODE_ORDER := ["one_lane", "traditional", "ground", "space"]
const SlotCard := preload("res://ui/screens/deck_editor.gd").SlotCard

var _format := 0                # 0 standard, 1 quick
var _profile := 1
var _scroll: ScrollContainer
var _box: VBoxContainer
var _flow: HFlowContainer
var _auto_row: HBoxContainer
var _leader_slot
var _base_slot
var _opp_btn: KyberButton
var _mode_btn: KyberButton
var _ai_btn: KyberButton
var _go: KyberButton
var _choices: Array = []        # deck dicts shown as tiles
var _tiles: Array = []
var _sel := -1
var _auto := {"leader": "SEC_015", "base": "HMW_019"}
var _opp_idx := -1              # -1 = random


# ---------------------------------------------------------------- configs (also used by tests)

static func _all_of(kind: String) -> Array:
	var out: Array = []
	for id in CardDB.lib.cards:
		var c: Dictionary = CardDB.lib.cards[id]
		if not c.get("custom", false) and c.get("type") == kind:
			out.append(id)
	return out


static func default_config() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var leaders := _all_of("leader")
	var bases := _all_of("base")
	return make_config(leaders[rng.randi_range(0, leaders.size() - 1)], bases[rng.randi_range(0, bases.size() - 1)], 0, "tempo", rng)


## Legacy auto-deck config (fmt 0 standard, 1 quick ground, 2 quick space).
static func make_config(leader: String, base: String, fmt: int, profile: String, rng: RandomNumberGenerator) -> Dictionary:
	var rules := RuleSet.premier()
	if fmt == 1:
		rules = RuleSet.quick("ground")
	elif fmt == 2:
		rules = RuleSet.quick("space")
	var leaders := _all_of("leader")
	var bases := _all_of("base")
	var el: String = leaders[rng.randi_range(0, leaders.size() - 1)]
	var eb: String = bases[rng.randi_range(0, bases.size() - 1)]
	var you := {"leader": leader, "base": base, "list": DeckBuilder.auto_deck(CardDB.lib, leader, base, rules.deck_min, rng, rules.arenas)}
	var opp := {"leader": el, "base": eb, "list": DeckBuilder.auto_deck(CardDB.lib, el, eb, rules.deck_min, rng, rules.arenas)}
	return config_for(you, opp, rules, profile, rng)


## you/opp = {leader, base, list:[ids]} or a deck dict with "cards".
static func config_for(you: Dictionary, opp: Dictionary, rules: RuleSet, profile: String, rng: RandomNumberGenerator) -> Dictionary:
	var yl: Array = you.get("list", Save.deck_list(you))
	var ol: Array = opp.get("list", Save.deck_list(opp))
	return {
		"seed": rng.randi(), "rules": rules, "tokens": ["initiative"],
		"players": [
			{"name": "You", "leader": you["leader"], "base": you["base"], "ai": false, "deck": yl},
			{"name": CardDB.card(opp["leader"]).get("name", "Bot"), "leader": opp["leader"], "base": opp["base"],
				"ai": true, "profile": profile, "deck": ol},
		],
	}


# ---------------------------------------------------------------- UI

func build() -> void:
	_format = int(Router.params.get("format", 0))
	set_header("Quick Battle" if _format > 0 else "Standard Battle")
	bg.backdrop = Art.ui_texture("coruscant")
	bg.backdrop_alpha = 0.25
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_scroll)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 12)
	_scroll.add_child(_box)
	if _format == 1:
		_mode_btn = KyberButton.make("", KyberButton.Style.GOLD, "ground")
		_mode_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_mode_btn.pressed.connect(_cycle_mode)
		_box.add_child(_mode_btn)
	var actions := HFlowContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("h_separation", 10)
	actions.add_theme_constant_override("v_separation", 10)
	_box.add_child(actions)
	_box.add_child(UIKit.label("YOUR DECK", 20, Kyber.C_KYBER))
	_flow = HFlowContainer.new()
	_flow.add_theme_constant_override("h_separation", 12)
	_flow.add_theme_constant_override("v_separation", 12)
	_box.add_child(_flow)
	_auto_row = HBoxContainer.new()
	_auto_row.add_theme_constant_override("separation", 12)
	_auto_row.visible = false
	_leader_slot = SlotCard.new()
	_leader_slot.kind = "leader"
	_leader_slot.custom_minimum_size = Vector2(196, 140)
	_leader_slot.pressed.connect(func(): _pick("leader"))
	_base_slot = SlotCard.new()
	_base_slot.kind = "base"
	_base_slot.custom_minimum_size = Vector2(196, 140)
	_base_slot.pressed.connect(func(): _pick("base"))
	_auto_row.add_child(_leader_slot)
	_auto_row.add_child(_base_slot)
	_box.add_child(_auto_row)
	_opp_btn = KyberButton.make("", KyberButton.Style.EMPIRE, "boss")
	_opp_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_opp_btn.custom_minimum_size.x = 300
	_opp_btn.pressed.connect(_cycle_opp)
	actions.add_child(_opp_btn)
	_ai_btn = KyberButton.make("", KyberButton.Style.GHOST, "gear")
	_ai_btn.pressed.connect(func():
		_profile = (_profile + 1) % PROFILES.size()
		_refresh_labels())
	_ai_btn.custom_minimum_size.x = 220
	actions.add_child(_ai_btn)
	_go = KyberButton.make("Battle!", KyberButton.Style.PRIMARY, "fight", true)
	_go.custom_minimum_size = Vector2(220, 64)
	_go.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_go.pressed.connect(_start)
	actions.add_child(_go)
	_fill_decks()


func _mode() -> String:
	return str(Kyber.settings.get("quick_mode", "traditional"))


func _cycle_mode() -> void:
	var i := MODE_ORDER.find(_mode())
	Kyber.set_setting("quick_mode", MODE_ORDER[(i + 1) % MODE_ORDER.size()])
	_opp_idx = -1
	_fill_decks()


func _opp_pool() -> Array:
	return CardDB.spotlight_for_mode(_mode() if _format == 1 else "traditional")


func _fill_decks() -> void:
	for c in _flow.get_children():
		c.queue_free()
	_tiles.clear()
	_choices.clear()
	if _format == 0:
		for d in Save.decks():
			_choices.append(d)
		_choices.append({"auto": true, "name": "Auto-build", "icon": "gear", "leader": _auto["leader"], "base": _auto["base"], "count": 50})
		for d in CardDB.spotlight_for_mode("traditional"):
			_choices.append(d)
	else:
		_choices = CardDB.spotlight_for_mode(_mode())
	var i := 0
	for d in _choices:
		var sub := ""
		if d.get("auto", false):
			sub = "Pick a leader & base"
		elif d.get("spotlight", false):
			sub = "%s · Spotlight%s" % [d.get("set_label", ""), " (provisional)" if d.get("provisional", false) else ""]
		var t := DeckTile.make(d, sub)
		var idx := i
		t.pressed.connect(func(_t): _select(idx))
		t.long_pressed.connect(func(_t): InspectOverlay.open(self, d["leader"], t.get_global_rect()))
		_flow.add_child(t)
		_tiles.append(t)
		UIKit.pop_in(t, i * 0.03)
		i += 1
	_sel = -1
	if _choices.size() > 0:
		_select(0)
	_refresh_labels()


func _select(i: int) -> void:
	_sel = i
	for k in _tiles.size():
		_tiles[k].selected = k == i
	var d: Dictionary = _choices[i]
	_auto_row.visible = d.get("auto", false)
	if _auto_row.visible:
		_leader_slot.set_card(_auto["leader"])
		_base_slot.set_card(_auto["base"])
	_refresh_labels()


func _pick(kind: String) -> void:
	var slot: Control = _leader_slot if kind == "leader" else _base_slot
	var flt := {}
	if _format == 1:
		flt["pilot"] = "only" if _mode() == "space" else "exclude"
	var p := CardPicker.open(self, kind, slot.get_global_rect(), flt)
	p.picked.connect(func(id):
		_auto[kind] = id
		_fill_decks()
		for k in _choices.size():
			if _choices[k].get("auto", false):
				_select(k))


func _cycle_opp() -> void:
	var pool := _opp_pool()
	_opp_idx += 1
	if _opp_idx >= pool.size():
		_opp_idx = -1
	_refresh_labels()


func _refresh_labels() -> void:
	if _mode_btn:
		var m: Array = Kyber.QUICK_MODES.get(_mode(), ["?", ""])
		_mode_btn.text = "Mode: %s — %s  (tap to change)" % [m[0], m[1]]
	var pool := _opp_pool()
	if _opp_idx < 0 or _opp_idx >= pool.size():
		_opp_btn.text = "Opponent: Random Spotlight deck  (tap to choose)"
	else:
		_opp_btn.text = "Opponent: %s" % pool[_opp_idx].get("full_name", pool[_opp_idx]["name"])
	_ai_btn.text = "Bot style: " + PROFILES[_profile].capitalize()
	var ok := _sel >= 0
	if ok and _format == 0:
		var d: Dictionary = _choices[_sel]
		if not d.get("auto", false) and not d.get("spotlight", false):
			var errs := DeckBuilder.validate(CardDB.lib, RuleSet.premier(), d.get("leader", ""), d.get("base", ""), Save.deck_list(d))
			_go.text = "Battle!" if errs.is_empty() else "Battle! (deck not Premier-legal: %s)" % errs[0]
			ok = d.get("leader", "") != "" and d.get("base", "") != "" and Save.deck_size(d) > 0
		else:
			_go.text = "Battle!"
	_go.disabled = not ok


func _start() -> void:
	if _sel < 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var mode := _mode() if _format == 1 else "standard"
	var rules := RuleSet.quick_mode(mode) if _format == 1 else RuleSet.premier()
	var d: Dictionary = _choices[_sel]
	var you: Dictionary
	if d.get("auto", false):
		you = {"leader": _auto["leader"], "base": _auto["base"],
			"list": DeckBuilder.auto_deck(CardDB.lib, _auto["leader"], _auto["base"], 50, rng, rules.arenas)}
	else:
		you = d
	var pool := _opp_pool()
	var opp: Dictionary
	if _opp_idx >= 0 and _opp_idx < pool.size():
		opp = pool[_opp_idx]
	else:
		var others: Array = pool.filter(func(x): return x.get("id", "") != d.get("id", "-"))
		if others.is_empty():
			others = pool
		opp = others[rng.randi_range(0, others.size() - 1)]
	var cfg := config_for(you, opp, rules, PROFILES[_profile], rng)
	var theme: String = "auto"
	var title: String = "Standard Battle" if _format == 0 else "Quick · " + Kyber.QUICK_MODES[mode][0]
	Router.go("match", {"mode": "quick", "format": _format, "cfg": cfg, "theme": theme, "title": title})


func relayout(_p: bool, r: Rect2) -> void:
	_scroll.position = Vector2.ZERO
	_scroll.size = r.size
	_box.custom_minimum_size.x = r.size.x - 16
