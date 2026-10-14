extends Node
## Sound for the valley, synthesised at start (the project ships no audio):
## a soft wind that changes with the hour, a thud for a placed block, a
## crunch for a broken one, a chime where a miracle happens and a quiet bell
## for each prayer heard. It listens to the simulation and never changes it.
const Synth = preload("res://addons/hatchery/audio/synth.gd")
const VoicePool = preload("res://addons/hatchery/audio/voice_pool.gd")
## Peak levels the sounds were mixed at, as fractions of full scale.
const TONE_PEAK: float = 26000.0 / 32767.0
const WIND_PEAK: float = 12000.0 / 32767.0
const RAIN_PEAK: float = 9000.0 / 32767.0

var sim: RefCounted
var _place: AudioStreamWAV
var _break: AudioStreamWAV
var _chime: AudioStreamWAV
var _bell: AudioStreamWAV
var _wind := AudioStreamPlayer.new()
var _effects: Node
var _commands_seen: int = 0
var _event_seen: int = -1
var _prayers_seen: int = 0
var _rng := RandomNumberGenerator.new()
## M24: thunder for Heaven's strikes, rain under rain and storm, the bronze
## bell and raiders' drums, and a caption for each when captions are on.
var _thunder: AudioStreamWAV
var _bronze: AudioStreamWAV
var _drums: AudioStreamWAV
var _rain := AudioStreamPlayer.new()
var _struck: Dictionary = {}
var _chronicle_seen: int = -1
## Called with a caption's label key when captions are on (set by main).
var caption: Callable = Callable()
## Where the listener stands, for near and far thunder.
var listener := Vector3.ZERO


func _ready() -> void:
	_rng.seed = 7
	_place = _tone([[140.0, 0.6], [70.0, 0.4]], 0.09, 0.35, 30.0)
	_break = _tone([[90.0, 0.3]], 0.12, 0.7, 40.0)
	_chime = _tone([[880.0, 0.5], [1320.0, 0.3], [1760.0, 0.2]], 1.4, 0.0, 2.5)
	_bell = _tone([[660.0, 0.6], [990.0, 0.25]], 0.9, 0.0, 4.0)
	_thunder = _tone([[45.0, 0.5], [70.0, 0.3]], 2.6, 0.75, 1.6)
	_bronze = _tone([[330.0, 0.5], [512.0, 0.3], [790.0, 0.2]], 2.4, 0.0, 1.3)
	_drums = _tone([[60.0, 0.8]], 0.4, 0.25, 9.0)
	_rain.stream = Synth.hiss_loop(_rng, 4.0, RAIN_PEAK)
	_rain.bus = &"Effects"
	_rain.volume_db = -60.0
	add_child(_rain)
	_rain.play()
	_wind.stream = Synth.wind_loop(_rng, 4.0, 0.02, WIND_PEAK)
	_wind.bus = &"Music"
	_wind.volume_db = -18.0
	add_child(_wind)
	_wind.play()
	_effects = VoicePool.new()
	_effects.bus = &"Effects"
	add_child(_effects)
	if sim != null:
		_commands_seen = sim.command_log.size()


## Partials [[frequency, weight]], with a share of noise, decaying `decay`.
func _tone(partials: Array, seconds: float, noise: float, decay: float) -> AudioStreamWAV:
	return Synth.tone(_rng, partials, seconds, noise, decay, TONE_PEAK)


func _caption(key: String) -> void:
	if caption.is_valid():
		caption.call(key)


func _play(stream: AudioStreamWAV, volume_db: float, pitch: float = 1.0) -> void:
	_effects.play(stream, volume_db, pitch)


func _process(_delta: float) -> void:
	if sim == null:
		return
	var hour: float = sim.calendar.hour()
	_wind.volume_db = -14.0 if hour < 6.0 or hour > 20.0 else -19.0
	var commands: Array = sim.command_log
	for i in range(_commands_seen, commands.size()):
		var command: Dictionary = commands[i].command
		if command.get("type", "") == "edit_block":
			if int(command.get("id", 0)) == 0:
				_play(_break, -8.0, _rng.randf_range(0.9, 1.1))
			else:
				_play(_place, -6.0, _rng.randf_range(0.9, 1.1))
	_commands_seen = commands.size()
	_weather_and_omens()
	for event in sim.faith.events:
		if int(event.uid) > _event_seen:
			_event_seen = int(event.uid)
			_play(_chime, -6.0)
			_caption("caption_miracle")
	# The feed is capped, so follow the newest prayer's tick rather than its size.
	var feed: Array = sim.faith.feed.get(sim.god.active_shrine_id, [])
	var newest: int = int(feed.back().tick) if not feed.is_empty() else 0
	if newest > _prayers_seen:
		if _prayers_seen > 0:
			_play(_bell, -16.0, _rng.randf_range(0.95, 1.05))
			_caption("caption_prayer")
		_prayers_seen = newest


## Rain under the sky's rain, thunder for each of Heaven's strikes (louder
## near), the bell tower and the drums of a raid.
func _weather_and_omens() -> void:
	var wet: bool = sim.weather != null and str(sim.weather.kind) in ["rain", "thunderstorm"]
	_rain.volume_db = move_toward(_rain.volume_db, -16.0 if wet else -60.0, 0.5)
	if sim.tribulations != null:
		for id in sim.tribulations.entries:
			var trial: Dictionary = sim.tribulations.entries[id]
			var struck: int = int(trial.get("struck", 0))
			if struck > int(_struck.get(id, 0)):
				var distance: float = listener.distance_to(Vector3(trial.site))
				_play(_thunder, clampf(-2.0 - distance * 0.12, -24.0, -2.0), _rng.randf_range(0.85, 1.05))
				_caption("caption_thunder")
			_struck[id] = struck
	var entries: Array = sim.chronicle.entries
	if _chronicle_seen < 0:
		_chronicle_seen = entries.size()
	for i in range(_chronicle_seen, entries.size()):
		match str(entries[i].kind):
			"bell_rang":
				_play(_bronze, -6.0)
				_caption("caption_bell")
			"raid_begins":
				for k in range(3):
					_play(_drums, -6.0, 0.9 + k * 0.05)
				_caption("caption_drums")
	_chronicle_seen = entries.size()
