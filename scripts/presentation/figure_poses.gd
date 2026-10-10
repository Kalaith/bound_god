extends RefCounted
## Target joint angles for each activity, as a dictionary the rig eases
## toward. Angles in radians: legs and arms swing forward with negative x,
## the torso and head lean forward with positive x, `arm_*_z` lifts an arm
## away from the body. `lie` and `root` lay a sleeper down or seat a person.

const HANDWORK: Array[String] = ["working", "building", "breaking", "reaping", "sowing", "tending", "gardening", "cooking"]


static func target(activity: String, time: float, stride: float, speed: float, spirit: bool, carrying: bool) -> Dictionary:
	# Breathing and a slow look about, under everything else.
	var pose: Dictionary = {"torso_x": sin(time * 1.6) * 0.015, "head_y": sin(time * 0.37) * 0.35, "arm_l_z": 0.08, "arm_r_z": 0.08}
	if activity == "sleeping":
		return {"lie": -PI * 0.5, "root": Vector3(0, 0.17, 0.75), "arm_l_z": 0.05, "arm_r_z": 0.05, "head_y": 0.3}
	if activity == "relaxing" and speed < 0.2:
		return _sitting(pose, time)
	if speed > 0.2:
		return _walking(pose, activity, stride, speed, spirit, carrying)
	if activity in HANDWORK:
		return _handwork(pose, activity, time)
	match activity:
		"praying":
			var bow: float = maxf(sin(time * 0.8), 0.0) * 0.25
			pose.merge({"torso_x": 0.08 + bow, "head_x": 0.3 + bow * 0.5, "head_y": 0.0,
				"arm_l_x": -1.15, "arm_r_x": -1.15, "arm_l_z": -0.42, "arm_r_z": -0.42}, true)
		"talking":
			pose.merge({"arm_r_x": -0.55 - sin(time * 3.1) * 0.3, "arm_r_z": 0.25, "head_x": sin(time * 4.0) * 0.08,
				"head_y": sin(time * 0.6) * 0.2}, true)
		"eating":
			var bite: float = smoothstep(0.2, 0.8, sin(time * 1.8) * 0.5 + 0.5)
			pose.merge({"arm_r_x": -0.4 - bite * 1.75, "arm_r_z": -0.35 * bite, "arm_l_x": -0.5, "head_x": 0.1}, true)
		"fighting":
			pose.merge({"torso_x": 0.18, "arm_l_x": -1.3 - sin(time * 9.0) * 0.4, "arm_r_x": -1.3 + sin(time * 9.0) * 0.4,
				"arm_l_z": -0.2, "arm_r_z": -0.2, "head_y": 0.0}, true)
		"sheltering":
			pose.merge({"torso_x": 0.3, "head_x": 0.35, "arm_l_x": -2.5, "arm_r_x": -2.5, "arm_l_z": -0.3, "arm_r_z": -0.3}, true)
		"recovering":
			pose.merge({"torso_x": 0.22, "head_x": 0.35, "head_y": 0.0, "arm_l_x": -0.3, "arm_r_x": -0.3, "arm_l_z": -0.25, "arm_r_z": -0.25}, true)
		"waiting", "scouting":
			pose.merge({"arm_l_x": 0.25, "arm_r_x": 0.25, "arm_l_z": -0.2, "arm_r_z": -0.2, "head_y": sin(time * 0.5) * 0.6}, true)
	if carrying:
		pose.merge({"arm_l_x": -0.95, "arm_r_x": -0.95, "arm_l_z": -0.22, "arm_r_z": -0.22}, true)
	return pose


static func _walking(pose: Dictionary, activity: String, stride: float, speed: float, spirit: bool, carrying: bool) -> Dictionary:
	var swing: float = sin(stride)
	var reach: float = clampf(speed / 3.0, 0.35, 1.0)
	var fleeing: bool = activity == "fleeing"
	var legs: float = (0.75 if fleeing else 0.5) * reach
	var arms: float = (0.7 if fleeing else 0.4) * reach
	pose.merge({"leg_l": -swing * legs, "leg_r": swing * legs, "arm_l_x": swing * arms, "arm_r_x": -swing * arms,
		"torso_x": 0.05 + (0.2 if fleeing else 0.0), "torso_y": swing * 0.06, "bob": absf(cos(stride)) * 0.045 * reach,
		"head_y": 0.0}, true)
	if spirit:
		# The god glides: no step, only the sleeves trailing and a lean.
		pose.merge({"leg_l": 0.0, "leg_r": 0.0, "bob": 0.0, "torso_x": 0.1 * reach, "arm_l_x": 0.35 + swing * 0.08,
			"arm_r_x": 0.35 - swing * 0.08, "arm_l_z": 0.18, "arm_r_z": 0.18}, true)
	elif carrying:
		pose.merge({"arm_l_x": -0.95, "arm_r_x": -0.95, "arm_l_z": -0.22, "arm_r_z": -0.22, "torso_x": -0.04}, true)
	return pose


static func _handwork(pose: Dictionary, activity: String, time: float) -> Dictionary:
	var beat: float = sin(time * 5.0)
	match activity:
		"building", "breaking", "working":
			# A mallet or axe brought down and lifted again.
			var strike: float = pow(beat * 0.5 + 0.5, 2.0)
			pose.merge({"torso_x": 0.12 + strike * 0.18, "arm_r_x": -2.3 + strike * 1.7, "arm_r_z": 0.05,
				"arm_l_x": -0.7, "arm_l_z": -0.15, "head_x": 0.2, "head_y": 0.0}, true)
		"reaping":
			pose.merge({"torso_x": 0.4, "torso_y": beat * 0.3, "arm_l_x": -1.0, "arm_r_x": -1.0, "arm_l_z": -0.1 + beat * 0.35,
				"arm_r_z": -0.1 - beat * 0.35, "head_x": 0.25, "head_y": 0.0}, true)
		"cooking":
			pose.merge({"torso_x": 0.15, "arm_r_x": -0.9 + sin(time * 4.0) * 0.15, "arm_r_z": -0.15 + cos(time * 4.0) * 0.2,
				"arm_l_x": -0.6, "head_x": 0.3, "head_y": 0.0}, true)
		_:
			# Bent to the soil: sowing, tending, gardening.
			pose.merge({"torso_x": 0.65, "head_x": 0.1, "head_y": 0.0, "arm_l_x": -0.6 + beat * 0.25, "arm_r_x": -0.6 - beat * 0.25,
				"arm_l_z": -0.05, "arm_r_z": -0.05, "leg_l": -0.12, "leg_r": 0.12}, true)
	return pose


static func _sitting(pose: Dictionary, time: float) -> Dictionary:
	pose.merge({"root": Vector3(0, -0.5, -0.05), "leg_l": -1.45, "leg_r": -1.35, "torso_x": -0.08 + sin(time * 1.4) * 0.015,
		"arm_l_x": 0.45, "arm_r_x": 0.45, "arm_l_z": 0.22, "arm_r_z": 0.22}, true)
	return pose
