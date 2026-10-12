extends RefCounted
## Named ages (M23). The campaign's chronicle falls into ages: each day the
## new entries of every region are read in region order, and an entry that
## matches a turning point in `saga.json` `ages.rules` closes the current age
## and opens the next, named from what turned it (a new master's name, the
## sect that formed, the tree's new phase). A famine, many starved within a
## few days, is a turning point of its own. Rules look at the valley unless
## marked `any_region`; a rule marked `once` turns an age only the first time.
## Each new age is chronicled in the region it began in. An age is
## {name: label key, arg: value worded on display, tick, day, region, cause}.
const Data = preload("res://scripts/core/data.gd")


static func config() -> Dictionary:
	return Data.file("saga").ages


## The ages so far, the first opened when the campaign began.
static func begin(campaign: RefCounted) -> void:
	if not campaign.ages.is_empty():
		return
	var home: RefCounted = campaign.sim_of(0)
	campaign.ages.append({"name": str(config().first), "arg": "", "tick": home.calendar.tick, "day": home.calendar.day(), "region": 0, "cause": ""})


## Reads every region's new chronicle entries for turning points.
static func daily(campaign: RefCounted) -> void:
	begin(campaign)
	for region in campaign.regions:
		var id: int = int(region.id)
		var entries: Array = region.sim.chronicle.entries
		var from: int = int(campaign.chronicle_read.get(id, 0))
		for i in range(from, entries.size()):
			var entry: Dictionary = entries[i]
			# What kinds of things have happened, for the deeds (deeds.gd).
			var kind: String = str(entry.kind)
			campaign.kinds_seen[kind] = int(campaign.kinds_seen.get(kind, 0)) + 1
			if id == 0:
				campaign.kinds_seen["valley:" + kind] = int(campaign.kinds_seen.get("valley:" + kind, 0)) + 1
			var rule: Dictionary = _rule(campaign, id, str(entry.kind))
			if not rule.is_empty():
				_turn(campaign, region.sim, id, rule, entry)
		campaign.chronicle_read[id] = entries.size()
	_famine(campaign)


static func _rule(campaign: RefCounted, region: int, kind: String) -> Dictionary:
	for rule in config().rules:
		if str(rule.kind) != kind or str(rule.kind) == "famine":
			continue
		if region != 0 and not bool(rule.get("any_region", false)):
			continue
		if bool(rule.get("once", false)) and campaign.ages.any(func(age: Dictionary) -> bool: return str(age.name) == str(rule.name)):
			continue
		return rule
	return {}


## A new age, opened by `entry`, chronicled where it began.
static func _turn(campaign: RefCounted, sim: RefCounted, region: int, rule: Dictionary, entry: Dictionary) -> void:
	var arg: String = str(entry.get("args", {}).get(str(rule.get("arg", "")), "")) if not str(rule.get("arg", "")).is_empty() else ""
	var age: Dictionary = {"name": str(rule.name), "arg": arg, "tick": int(entry.tick), "day": int(entry.day), "region": region, "cause": str(entry.kind)}
	campaign.ages.append(age)
	sim.chronicle.add(sim.calendar.tick, sim.calendar.day(), "age_began", str(entry.place), {"age": key(age)}, "cause_age_turned|chronicle_" + str(entry.kind), [])


## The age as the chronicle keeps it: "age:<name>|<arg>", worded on display.
static func key(age: Dictionary) -> String:
	return "age:%s|%s" % [str(age.name), str(age.arg)]


## Many starved in a few days in the valley: the Long Hunger begins (once
## for each famine: not again while the last age is a famine).
static func _famine(campaign: RefCounted) -> void:
	var home: RefCounted = campaign.sim_of(0)
	if str(campaign.ages.back().name) == "age_famine" and home.calendar.day() - int(campaign.ages.back().day) < int(config().famine_days) * 4:
		return
	var since: int = home.calendar.tick - home.calendar.ticks_for_days(float(config().famine_days))
	var starved: int = 0
	var last: Dictionary = {}
	for i in range(home.chronicle.entries.size() - 1, -1, -1):
		var entry: Dictionary = home.chronicle.entries[i]
		if int(entry.tick) < since:
			break
		if str(entry.kind) == "death" and str(entry.cause).contains("starv"):
			starved += 1
			if last.is_empty():
				last = entry
	if starved < int(config().famine_deaths):
		return
	for rule in config().rules:
		if str(rule.kind) == "famine":
			_turn(campaign, home, 0, rule, {"tick": home.calendar.tick, "day": home.calendar.day(), "kind": "famine", "place": str(last.get("place", "")), "args": {}})
			return


## The age a tick falls in.
static func at(campaign: RefCounted, tick: int) -> Dictionary:
	var result: Dictionary = {}
	for age in campaign.ages:
		if int(age.tick) <= tick:
			result = age
	return result
