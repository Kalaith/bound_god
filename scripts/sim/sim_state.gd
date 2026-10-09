extends RefCounted
## Saving and restoring a whole world. The voxel grid is regenerated from the
## seed and only edited chunks are stored; everything else is plain data
## through var_to_bytes. Saving rebuilds the navigation graph from scratch in
## the running world too, so the saved world and the one that plays on share
## the same graph and continue identically.
const Agent = preload("res://scripts/agents/agent.gd")

const SCHEMA: int = 1


## {"sim": Dictionary, "chunks": Dictionary} for a running sim.
static func capture(sim: RefCounted) -> Dictionary:
	sim.nav.build()
	var people: Array = []
	for agent in sim.agents:
		people.append(agent.to_dict())
	var chunks: Dictionary = {}
	var keys: Array = sim.voxels.edited_chunks.keys()
	keys.sort()
	for chunk in keys:
		chunks[chunk] = sim.voxels.chunk_bytes(chunk).compress(FileAccess.COMPRESSION_ZSTD)
	var state: Dictionary = {
		"schema_version": SCHEMA, "seed": sim.world_seed, "options": sim.options.duplicate(true),
		"rng_seed": sim.rng.seed, "rng_state": sim.rng.state, "tick": sim.calendar.tick,
		"voxel_meta": sim.voxels.meta.duplicate(), "features": sim.features.duplicate(true),
		"sites": sim.sites.to_dict(), "structures": sim.structures.to_dict(), "settlements": sim.settlements.to_dict(),
		"settlement_life": sim.settlement_life.to_dict(), "construction": sim.construction.to_dict(),
		"items": sim.items.duplicate(true), "next_item_id": sim.next_item_id, "agents": people,
		"god": sim.god.to_dict(), "chronicle": sim.chronicle.to_dict(), "faith": sim.faith.to_dict(),
		"requests": sim.requests.to_dict(), "threats": sim.threats.to_dict(), "raids": sim.raids.to_dict(),
		"command_log": sim.command_log.duplicate(true), "kindled": sim.kindled.duplicate(true), "veils": sim.veils.duplicate(true),
	}
	return {"sim": state, "chunks": chunks}


## Why a saved state cannot be loaded, or "".
static func problem(state: Variant, chunks: Variant) -> String:
	if not state is Dictionary or not chunks is Dictionary:
		return "save_damaged"
	if int(state.get("schema_version", -1)) != SCHEMA:
		return "save_version"
	for key in ["seed", "options", "rng_seed", "rng_state", "tick", "voxel_meta", "sites", "structures", "settlements",
			"settlement_life", "construction", "items", "next_item_id", "agents", "god", "chronicle", "faith", "requests",
			"threats", "raids", "command_log", "kindled", "veils"]:
		if not state.has(key):
			return "save_damaged"
	for chunk in chunks:
		if not chunk is Vector3i or not chunks[chunk] is PackedByteArray:
			return "save_damaged"
	return ""


static func restore(state: Dictionary, chunks: Dictionary) -> RefCounted:
	var options: Dictionary = state.options.duplicate(true)
	options["restoring"] = true
	var sim = load("res://scripts/sim/sim.gd").create(int(state.seed), options)
	var size: int = 16 * 16 * 16
	for chunk in chunks:
		var bytes: PackedByteArray = chunks[chunk].decompress(size, FileAccess.COMPRESSION_ZSTD)
		sim.voxels.load_chunk_bytes(chunk, bytes)
	sim.voxels.meta = state.voxel_meta
	sim.voxels.take_dirty_chunks()
	sim.voxels.take_edits()
	sim.calendar.tick = int(state.tick)
	sim.sites.from_dict(state.sites)
	sim.structures.from_dict(state.structures)
	sim.settlements.from_dict(state.settlements)
	sim.settlement_life.from_dict(state.settlement_life)
	sim.construction.from_dict(state.construction)
	sim.items = state.items
	sim.next_item_id = int(state.next_item_id)
	sim.agents = []
	for data in state.agents:
		sim.agents.append(Agent.from_dict(data))
	sim.god.from_dict(state.god)
	sim.chronicle.from_dict(state.chronicle)
	sim.faith.from_dict(state.faith)
	sim.requests.from_dict(state.requests)
	sim.threats.from_dict(state.threats)
	sim.raids.from_dict(state.raids)
	sim.command_log = state.command_log
	sim.kindled = state.kindled
	sim.veils = state.veils
	sim.nav.build()
	sim.rng.seed = int(state.rng_seed)
	sim.rng.state = int(state.rng_state)
	sim.after_restore()
	return sim
