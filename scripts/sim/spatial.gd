extends RefCounted
## Buckets things by 16x16 xz cells so "what is near here" never scans every
## list. Agents are re-bucketed each tick; sites are bucketed on change.
const BUCKET: int = 16

## Vector2i bucket -> Array[int] of ids, per layer name.
var layers: Dictionary = {}


func clear_layer(layer: String) -> void:
	layers[layer] = {}


func insert(layer: String, id: int, cell: Vector3i) -> void:
	if not layers.has(layer):
		layers[layer] = {}
	var key := Vector2i(cell.x >> 4, cell.z >> 4)
	var buckets: Dictionary = layers[layer]
	if not buckets.has(key):
		buckets[key] = []
	buckets[key].append(id)


func remove(layer: String, id: int, cell: Vector3i) -> void:
	var buckets: Dictionary = layers.get(layer, {})
	var key := Vector2i(cell.x >> 4, cell.z >> 4)
	if buckets.has(key):
		buckets[key].erase(id)


## Ids whose bucket overlaps the square of `radius` around `cell`, ascending.
func near(layer: String, cell: Vector3i, radius: float) -> Array:
	var buckets: Dictionary = layers.get(layer, {})
	var result: Array = []
	var reach: int = int(ceil(radius))
	for bz in range((cell.z - reach) >> 4, ((cell.z + reach) >> 4) + 1):
		for bx in range((cell.x - reach) >> 4, ((cell.x + reach) >> 4) + 1):
			var list: Array = buckets.get(Vector2i(bx, bz), [])
			result.append_array(list)
	result.sort()
	return result
