extends RefCounted
## Construction effects: marking sites, delivering materials, placing blocks.


static func apply(_sim: RefCounted, _agent: RefCounted, action: Dictionary) -> void:
	push_error("Unknown effect " + str(action.type))
