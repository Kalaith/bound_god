extends RefCounted
## The whole campaign's chronicle as Markdown (M23): every region's entries
## by day under the ages they fall in, then the saga's deeds and numbers.
## Written to user://chronicles/ by the chronicle screen.
const Text = preload("res://scripts/core/text.gd")
const ChronicleText = preload("res://scripts/presentation/ui/chronicle_text.gd")
const SagaText = preload("res://scripts/presentation/ui/saga_text.gd")
const Statistics = preload("res://scripts/sim/statistics.gd")


static func markdown(campaign: RefCounted) -> String:
	var entries: Array = []
	for region in campaign.regions:
		for entry in region.sim.chronicle.entries:
			if entry.known:
				entries.append([int(entry.tick), int(region.id), entry])
	entries.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var lines: Array[String] = ["# " + Text.label("export_title"), ""]
	var age_index: int = -1
	for item in entries:
		while age_index + 1 < campaign.ages.size() and int(campaign.ages[age_index + 1].tick) <= int(item[0]):
			age_index += 1
			lines.append("")
			lines.append("## " + SagaText._sentence(SagaText.age_name(campaign.ages[age_index])))
			lines.append("")
		var region: String = Text.label(str(campaign.regions[int(item[1])].name))
		lines.append("- " + region + " · " + ChronicleText.line(item[2]))
	lines.append("")
	lines.append("## " + Text.label("export_deeds"))
	for line in SagaText.deeds(campaign):
		lines.append("- " + line)
	lines.append("")
	lines.append("## " + Text.label("export_numbers"))
	for line in SagaText.numbers(Statistics.of(campaign)):
		lines.append("- " + line.strip_edges())
	return "\n".join(lines) + "\n"


## Writes the chronicle; returns the file's path (or "" on failure).
static func write(campaign: RefCounted, slot: String) -> String:
	DirAccess.make_dir_recursive_absolute("user://chronicles")
	var path: String = "user://chronicles/%s_day%d.md" % [slot, campaign.sim_of(0).calendar.day()]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(markdown(campaign))
	file.close()
	return ProjectSettings.globalize_path(path)
