extends Node
## The score (M24), synthesised at start: plucked pentatonic notes (a
## guqin-like voice: a few partials, a quick pluck, a long decay) over a soft
## drone. The moment chooses the mood (dawn, day, dusk, night; winter; a storm
## or a trial; meditation; a raid), and the mood chooses the scale, register,
## tempo and how often a note falls. Phrases come from a seeded stream so the
## score never loops audibly. Reads the simulation only; plays on the Music bus.
const Synth = preload("res://addons/hatchery/audio/synth.gd")
const VoicePool = preload("res://addons/hatchery/audio/voice_pool.gd")
const RATE: int = Synth.RATE
const PLUCK_PEAK: float = 20000.0 / 32767.0

## Semitone steps of the scales the moods use, from the drone's root.
const SCALES: Dictionary = {
	"bright": [0, 2, 4, 7, 9, 12, 14, 16, 19, 21],
	"dark": [0, 3, 5, 7, 10, 12, 15, 17, 19, 22],
	"tense": [0, 1, 5, 7, 8, 12, 13, 17, 19, 20],
}
## mood -> [scale, seconds a beat, chance of a note a beat, register (semitones), drone]
const MOODS: Dictionary = {
	"dawn": ["bright", 1.1, 0.45, 12, "calm"],
	"day": ["bright", 0.9, 0.5, 12, "calm"],
	"dusk": ["dark", 1.1, 0.42, 7, "calm"],
	"night": ["dark", 1.5, 0.28, 0, "calm"],
	"winter": ["dark", 1.6, 0.22, 0, "calm"],
	"storm": ["tense", 0.7, 0.55, 0, "tense"],
	"meditation": ["bright", 1.8, 0.3, 12, "calm"],
	"raid": ["tense", 0.6, 0.4, -5, "tense"],
}
const ROOT_HZ: float = 146.83

var sim: RefCounted
var driver: Node
## The mood now and how many notes it has played (read by captures).
var mood: String = ""
var notes_played: int = 0
var _notes: Dictionary = {}
var _bell: AudioStreamWAV
var _drum: AudioStreamWAV
var _drones: Dictionary = {}
var _drone := AudioStreamPlayer.new()
var _voices: Node
var _beat_left: float = 0.0
var _beats: int = 0
var _last_step: int = 4
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 2026
	_bell = _ring(ROOT_HZ * 4.0, 3.0)
	_drum = _thump()
	_drones = {"calm": _drone_loop([1.0, 1.5], 0.06), "tense": _drone_loop([0.5, 0.5 * pow(2.0, 1.0 / 12.0)], 0.08)}
	_drone.bus = &"Music"
	_drone.volume_db = -20.0
	add_child(_drone)
	_voices = VoicePool.new()
	_voices.bus = &"Music"
	add_child(_voices)


## A plucked string: a few partials, a sharp attack, a long decay.
func _pluck(hz: float) -> AudioStreamWAV:
	return Synth.pluck(hz, 2.4, 1.6, PLUCK_PEAK)


func _ring(hz: float, seconds: float) -> AudioStreamWAV:
	var count: int = int(seconds * RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in range(count):
		var t: float = float(i) / RATE
		var value: float = (sin(TAU * hz * t) * 0.5 + sin(TAU * hz * 2.76 * t) * 0.3 + sin(TAU * hz * 5.4 * t) * 0.15) * exp(-t * 1.1) * minf(t * 500.0, 1.0)
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 16000.0))
	return _stream(data)


func _thump() -> AudioStreamWAV:
	var count: int = int(0.5 * RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in range(count):
		var t: float = float(i) / RATE
		var hz: float = 70.0 * exp(-t * 4.0) + 40.0
		var value: float = sin(TAU * hz * t) * exp(-t * 9.0) + _rng.randf_range(-1.0, 1.0) * 0.15 * exp(-t * 30.0)
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 26000.0))
	return _stream(data)


## Eight seconds of a soft drone on the root (ratios of it), looping cleanly.
func _drone_loop(ratios: Array, wobble: float) -> AudioStreamWAV:
	var count: int = RATE * 8
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in range(count):
		var t: float = float(i) / RATE
		var swell: float = 0.7 + 0.3 * sin(TAU * t / 8.0)
		var value: float = 0.0
		for ratio in ratios:
			var hz: float = ROOT_HZ * 0.5 * float(ratio)
			value += sin(TAU * hz * t + wobble * sin(TAU * 0.25 * t)) / ratios.size()
		data.encode_s16(i * 2, int(clampf(value * swell, -1.0, 1.0) * 9000.0))
	var stream: AudioStreamWAV = _stream(data)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = count
	return stream


func _stream(data: PackedByteArray) -> AudioStreamWAV:
	return Synth.stream(data)


## The mood the moment asks for.
func moment() -> String:
	if driver != null and driver.has_method("meditating") and driver.meditating():
		return "meditation"
	if sim.raids != null:
		for id in sim.raids.bands:
			if str(sim.raids.bands[id].state) == "raiding":
				return "raid"
	if (sim.weather != null and sim.weather.is_storm()) or (sim.tribulations != null and not sim.tribulations.entries.is_empty()):
		return "storm"
	if sim.calendar.is_winter():
		return "winter"
	var hour: float = sim.calendar.hour()
	if hour >= 5.0 and hour < 8.0:
		return "dawn"
	if hour >= 18.0 and hour < 21.0:
		return "dusk"
	if hour >= 21.0 or hour < 5.0:
		return "night"
	return "day"


func _process(delta: float) -> void:
	if sim == null:
		return
	var now: String = moment()
	if now != mood:
		mood = now
		var drone: AudioStreamWAV = _drones[str(MOODS[mood][4])]
		if _drone.stream != drone:
			_drone.stream = drone
			_drone.play()
	_beat_left -= delta
	if _beat_left > 0.0:
		return
	var setting: Array = MOODS[mood]
	_beat_left = float(setting[1]) * _rng.randf_range(0.85, 1.2)
	_beats += 1
	if mood == "meditation" and _beats % 8 == 0:
		_play(_bell, -14.0)
	if mood == "raid" and _beats % 2 == 0:
		_play(_drum, -10.0)
	if _rng.randf() >= float(setting[2]):
		return
	# A phrase wanders by small steps through the scale, now and then leaping.
	var scale: Array = SCALES[str(setting[0])]
	_last_step = clampi(_last_step + (_rng.randi_range(-2, 2) if _rng.randf() < 0.85 else _rng.randi_range(-4, 4)), 0, scale.size() - 1)
	var semitone: int = int(scale[_last_step]) + int(setting[3])
	# Notes are rendered the first time they are wanted, so the start is quick.
	if not _notes.has(semitone):
		_notes[semitone] = _pluck(ROOT_HZ * pow(2.0, semitone / 12.0))
	_play(_notes[semitone], -15.0 + _rng.randf_range(-2.0, 1.0))
	notes_played += 1


func _play(stream: AudioStreamWAV, volume_db: float) -> void:
	_voices.play(stream, volume_db)
