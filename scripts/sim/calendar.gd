extends RefCounted
## Simulation time. 720 ticks a day, 10-day seasons, 4 seasons a year. Rates
## are authored per day and converted with per_tick, so changing the tick
## rate never retunes the game.
const Balance = preload("res://addons/hatchery/core/balance.gd")

const SEASONS: Array[String] = ["spring", "summer", "autumn", "winter"]

var tick: int = 0
var ticks_per_day: int = 720
var days_per_season: int = 10
var _dawn: float = 6.0
var _dusk: float = 20.0


func _init() -> void:
	ticks_per_day = Balance.integer("time.ticks_per_day")
	days_per_season = Balance.integer("time.days_per_season")
	_dawn = Balance.number("time.dawn_hour")
	_dusk = Balance.number("time.dusk_hour")


func hour() -> float:
	return float(tick % ticks_per_day) * 24.0 / float(ticks_per_day)


## Day 1 is the first day.
func day() -> int:
	return tick / ticks_per_day + 1


func day_of_season() -> int:
	return (day() - 1) % days_per_season + 1


func season() -> int:
	return ((day() - 1) / days_per_season) % SEASONS.size()


func season_name() -> String:
	return SEASONS[season()]


func year() -> int:
	return (day() - 1) / (days_per_season * SEASONS.size()) + 1


func is_winter() -> bool:
	return season() == 3


func is_daylight() -> bool:
	var h: float = hour()
	return h >= _dawn and h < _dusk


func is_new_day() -> bool:
	return tick % ticks_per_day == 0


func is_new_hour() -> bool:
	return tick % maxi(ticks_per_day / 24, 1) == 0


func per_tick(per_day: float) -> float:
	return per_day / float(ticks_per_day)


func ticks_for_days(days: float) -> int:
	return int(days * ticks_per_day)


func ticks_per_hour() -> int:
	return maxi(ticks_per_day / 24, 1)


func clock_text() -> String:
	var h: float = hour()
	return "%02d:%02d" % [int(h), int((h - floorf(h)) * 60.0)]
