extends RefCounted
## Faith message receivers: stories, whispers and divine requests.
const KINDS: Array[String] = []


static func handles(kind: String) -> bool:
	return KINDS.has(kind)


static func receive(_sim: RefCounted, _agent: RefCounted, _message: Dictionary) -> bool:
	return false
