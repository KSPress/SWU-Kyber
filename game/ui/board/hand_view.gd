class_name HandView
extends Control
## Hearthstone-style fanned hand. Cards keep a home slot on the arc; hovering
## lifts a card, dragging pulls it free (CardView handles the motion).

signal card_tapped(card: CardView)
signal card_inspect(card: CardView)
signal card_drag_started(card: CardView)
signal card_drag_moved(card: CardView, at: Vector2)
signal card_dropped(card: CardView, at: Vector2)

var cards: Dictionary = {}      # uid -> CardView
var order: Array = []           # uids, left to right
var card_scale := 0.5
var spawn_from := Vector2.ZERO  # global, where new cards fly in from (deck)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func sync(hand: Array, playable: Dictionary, costs: Dictionary) -> void:
	var seen := {}
	for c in hand:
		seen[c.uid] = true
		if not cards.has(c.uid):
			var cv := CardView.create(c.id, c)
			cv.set_meta("uid", c.uid)
			cv.tapped.connect(func(x): card_tapped.emit(x))
			cv.inspect_requested.connect(func(x): card_inspect.emit(x))
			cv.drag_started.connect(func(x): card_drag_started.emit(x))
			cv.drag_moved.connect(func(x, p): card_drag_moved.emit(x, p))
			cv.drag_released.connect(func(x, p): card_dropped.emit(x, p))
			add_child(cv)
			cv.scale = Vector2(card_scale * 0.6, card_scale * 0.6)
			cv.position = spawn_from - global_position if spawn_from != Vector2.ZERO else Vector2(size.x, 0)
			cv.rotation = 0.6
			cards[c.uid] = cv
			order.append(c.uid)
			Sfx.play("draw")
	for uid in order.duplicate():
		if not seen.has(uid):
			var cv: CardView = cards[uid]
			cards.erase(uid)
			order.erase(uid)
			if is_instance_valid(cv) and not cv.is_queued_for_deletion():
				cv.queue_free()
	for uid in order:
		var cv: CardView = cards[uid]
		cv.playable = playable.has(uid)
		cv.cost_override = costs.get(uid, -1)
	layout()


func remove_card(uid: int) -> CardView:
	if not cards.has(uid):
		return null
	var cv: CardView = cards[uid]
	cards.erase(uid)
	order.erase(uid)
	return cv


func layout() -> void:
	var n := order.size()
	if n == 0:
		return
	var cw := CardView.PORTRAIT.x * card_scale
	var spread := minf(cw * 0.78, (size.x - cw) / maxf(1.0, n - 1)) if n > 1 else 0.0
	var total := spread * (n - 1)
	var x0 := (size.x - total) / 2.0 - cw / 2.0
	for i in n:
		var cv: CardView = cards[order[i]]
		var t := (i - (n - 1) / 2.0)
		cv.home_scale = Vector2(card_scale, card_scale)
		cv.pivot_offset = Vector2(CardView.PORTRAIT.x / 2.0, CardView.PORTRAIT.y)
		cv.home_rot = t * 0.06
		# position is the unscaled top-left; compensate for scaling about the bottom-centre pivot
		var shrink := Vector2(cv.pivot_offset.x, cv.pivot_offset.y) * (1.0 - card_scale)
		cv.home_pos = Vector2(x0 + i * spread, absf(t) * absf(t) * 3.5 + 6.0) - shrink
		cv.move_home(i * 0.02)
