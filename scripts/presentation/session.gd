extends RefCounted
## What the title screen asked the main scene to do. Static, because it only
## has to survive one scene change.

## "new" starts a world from `seed`; "load" restores `slot`.
static var mode: String = "new"
static var seed: int = 1
static var slot: String = "world"
## The running campaign, kept across the scene change when the god steps
## into another region (M22): the scene is rebuilt round its active region.
static var campaign: RefCounted = null
## Set by the title screen when validation found broken data.
static var data_errors: Array[String] = []
