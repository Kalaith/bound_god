extends RefCounted
## Semantic checks for the sky (M20): every weather kind has its modifiers
## and a label, every season weighs only known kinds with sensible spells,
## snow falls only in winter and rain never does.
const Calendar = preload("res://scripts/sim/calendar.gd")
const DataRules = preload("res://addons/hatchery/core/data_rules.gd")


static func check_weather(data: Dictionary, labels: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not DataRules.finite(data.get("schema_version")) or int(data.schema_version) != 1:
		errors.append("weather: schema_version must be 1")
	var kinds: Dictionary = {}
	var list: Variant = data.get("kinds")
	if not list is Array or list.is_empty():
		errors.append("weather: the kind list is missing")
		return errors
	for entry in list:
		if not entry is Dictionary or not entry.get("id") is String or kinds.has(entry.id):
			errors.append("weather: kind ids must be unique strings")
			continue
		kinds[entry.id] = entry
		var label: String = "weather[" + entry.id + "]"
		for key in ["exposure", "trial"]:
			if not DataRules.finite(entry.get(key)) or float(entry[key]) < 0.0 or float(entry[key]) > 2.0:
				errors.append(label + ": " + key + " must be a number from 0 to 2")
		if not DataRules.finite(entry.get("work")) or float(entry.work) <= 0.0 or float(entry.work) > 1.5:
			errors.append(label + ": work must be a positive pace")
		if not entry.get("wet") is bool:
			errors.append(label + ": wet must be true or false")
		if not labels.has("weather_" + entry.id):
			errors.append(label + ": no label weather_" + entry.id)
	for key in ["clear", "rain", "thunderstorm", "snow"]:
		if not kinds.has(key):
			errors.append("weather: the systems need the kind " + key)
	var seasons: Variant = data.get("seasons")
	if not seasons is Dictionary:
		errors.append("weather: seasons are missing")
		return errors
	for season in Calendar.SEASONS:
		var spells: Variant = seasons.get(season)
		if not spells is Array or spells.is_empty():
			errors.append("weather: " + season + " has no spells")
			continue
		for spell in spells:
			var label: String = "weather." + season
			if not spell is Dictionary or not kinds.has(spell.get("kind")):
				errors.append(label + ": a spell names an unknown kind")
				continue
			if spell.kind == "snow" and season != "winter":
				errors.append(label + ": snow falls only in winter")
			if spell.kind == "rain" and season == "winter":
				errors.append(label + ": rain does not fall in winter")
			if not DataRules.finite(spell.get("weight")) or float(spell.weight) <= 0.0:
				errors.append(label + ": weights must be positive")
			var hours: Variant = spell.get("hours")
			if not hours is Array or hours.size() != 2 or not DataRules.finite(hours[0]) or not DataRules.finite(hours[1]) \
					or int(hours[0]) < 1 or int(hours[1]) < int(hours[0]):
				errors.append(label + ": hours must be [least, most] from 1")
	if not DataRules.finite(data.get("trial_wait")) or float(data.trial_wait) < 0.0 or float(data.trial_wait) > 1.0:
		errors.append("weather: trial_wait must be from 0 to 1")
	if not DataRules.finite(data.get("calm_hours")) or int(data.calm_hours) < 1:
		errors.append("weather: calm_hours must be at least 1")
	return errors
