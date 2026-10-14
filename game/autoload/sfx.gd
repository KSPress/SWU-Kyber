extends Node
## Placeholder sound design. If res://ip/audio/<name>.ogg exists it is used,
## otherwise a tiny synthesized blip stands in so every interaction has feedback
## without shipping copyrighted film audio (spec 8.5).

const NAMES := ["saber_on", "swing", "click", "hover", "whoosh", "play", "blaster", "saber", "hit", "shield", "defeat", "deploy", "turn", "win", "lose", "draw"]
const POOL := 6

var _streams: Dictionary = {}
var _players: Array = []
var _next := 0


func _ready() -> void:
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	for n in NAMES:
		var path := "res://ip/audio/%s.ogg" % n
		_streams[n] = load(path) if ResourceLoader.exists(path) else _synth(n)


func play(name: String, pitch := 1.0) -> void:
	if not _streams.has(name):
		return
	var vol: float = Kyber.settings.get("sfx_volume", 0.7)
	if vol <= 0.01:
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % POOL
	p.stream = _streams[name]
	p.volume_db = linear_to_db(vol) - 8.0
	p.pitch_scale = pitch * randf_range(0.96, 1.04)
	p.play()


## Generates a short 16-bit mono WAV: frequency sweep + noise, shaped by an envelope.
func _synth(name: String) -> AudioStreamWAV:
	var spec := {
		"saber_on": [0.45, 70.0, 160.0, 0.08], "swing": [0.3, 220.0, 110.0, 0.25],
		"click": [0.05, 1400.0, 900.0, 0.0], "hover": [0.03, 2200.0, 2400.0, 0.0],
		"whoosh": [0.30, 300.0, 90.0, 0.8], "play": [0.16, 520.0, 880.0, 0.1],
		"blaster": [0.22, 1900.0, 260.0, 0.05], "saber": [0.40, 140.0, 95.0, 0.15],
		"hit": [0.14, 160.0, 60.0, 0.6], "shield": [0.25, 900.0, 1500.0, 0.1],
		"defeat": [0.45, 220.0, 40.0, 0.7], "deploy": [0.5, 180.0, 440.0, 0.2],
		"turn": [0.12, 660.0, 990.0, 0.0], "win": [0.8, 440.0, 880.0, 0.0],
		"lose": [0.8, 330.0, 110.0, 0.1], "draw": [0.08, 1200.0, 1600.0, 0.3],
	}
	var s: Array = spec.get(name, [0.1, 800.0, 800.0, 0.0])
	var rate := 22050
	var n: int = int(s[0] * rate)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		var f: float = lerpf(s[1], s[2], t)
		phase += TAU * f / rate
		var env := minf(t * 30.0, 1.0) * pow(1.0 - t, 2.0)
		var v: float = sin(phase) * (1.0 - s[3]) + randf_range(-1.0, 1.0) * s[3]
		if name in ["saber", "saber_on", "swing"]:
			v = sin(phase) * 0.6 + sin(phase * 2.01) * 0.3 + randf_range(-1, 1) * 0.1
		bytes.encode_s16(i * 2, int(clampf(v * env, -1.0, 1.0) * 26000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = bytes
	return w
