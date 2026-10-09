extends RefCounted
## Debug-only captures of people and the inspector: `people_<tab>` runs the
## valley for a few hours, selects the first traveller and shows that tab.
const TABS: Array[String] = ["mind", "needs", "bonds", "life", "faith"]


static func arrange(main: Node3D, shot: Node, scenario: String) -> void:
	var sim: RefCounted = main.sim
	var hours: int = 30 if scenario.ends_with("_late") else 6
	var marker: int = scenario.find("_d")
	if marker > 0:
		hours = int(scenario.substr(marker + 2)) * 24
		scenario = scenario.substr(0, marker)
	sim.run_ticks(sim.calendar.ticks_per_hour() * hours)
	main.world_view.remesh_now()
	# The best-connected person makes the clearest picture of bonds.
	var agent: RefCounted = sim.agents[0]
	for other in sim.agents:
		if other.is_present() and other.beliefs.relations.size() > agent.beliefs.relations.size():
			agent = other
	main.avatar.global_position = agent.position + Vector3(-3.5, 0.2, -4.5)
	main.camera_rig.yaw = atan2(-3.5, -4.5)
	main.camera_rig.pitch = -0.32
	main.people.select(agent.id)
	var tab: String = scenario.trim_prefix("people_").trim_suffix("_late")
	main.inspector._tabs.current_tab = maxi(TABS.find(tab), 0)
	main.inspector._show_tab(main.inspector._tabs.current_tab)
	print("PEOPLE %s goal=%s activity=%s decisions=%d" % [agent.full_name(), agent.current_goal(), agent.activity, agent.decisions.size()])
	shot.shoot_after(40)
