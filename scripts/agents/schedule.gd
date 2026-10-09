extends RefCounted
## Daily rhythms: work hours and sleep time, shifted for night owls.
const Balance = preload("res://scripts/core/balance.gd")


static func is_work_hours(sim: RefCounted, agent: RefCounted) -> bool:
	var owl: float = 2.0 if agent.personality.night_owl else 0.0
	var hour: float = sim.calendar.hour()
	return hour >= Balance.number("time.work_start_hour") + owl and hour < Balance.number("time.work_end_hour") + owl


static func is_sleep_time(sim: RefCounted, agent: RefCounted) -> bool:
	var owl: float = 3.0 if agent.personality.night_owl else 0.0
	var hour: float = fposmod(sim.calendar.hour() - owl, 24.0)
	return hour >= Balance.number("time.sleep_hour") or hour < Balance.number("time.dawn_hour")
