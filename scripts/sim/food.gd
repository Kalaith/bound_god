extends RefCounted
## What counts as food and how far it goes. Each food restores a set amount
## of the Food need when eaten; a settlement's food days are the food in its
## chests against what its people eat in a day.
const Balance = preload("res://scripts/core/balance.gd")


static func is_food(resource: String) -> bool:
	return Balance.dict("food.values").has(resource)


## How much of the Food need one unit restores.
static func value(resource: String) -> float:
	return float(Balance.dict("food.values").get(resource, 0.0))


## Foods from most to least wanted.
static func eat_order() -> Array:
	return Balance.list("food.eat_order")


## Food in a set of goods, in units of the Food need.
static func worth(goods: Dictionary) -> float:
	var sum: float = 0.0
	for resource in eat_order():
		sum += float(goods.get(resource, 0)) * value(resource)
	return sum


## What one person eats in a day, in units of the Food need.
static func daily_need() -> float:
	return float(Balance.dict("needs.decay_per_day").food)



## Whether a settlement is still putting grain by for the winter: outside
## winter, while its grain would not feed everyone for some days. Grain
## keeps and berries do not, so until then people eat the berries first.
static func putting_by(sim: RefCounted, id: int, people: int) -> bool:
	if id < 0 or sim.calendar.is_winter():
		return false
	var reserve: float = people * Balance.number("food.grain_reserve_days") * daily_need() / value("grain")
	return sim.settlements.amount(id, "grain") < reserve


## Meals a settlement wants in its stores: about a day's worth, since they
## keep only a few days.
static func meals_wanted(people: int) -> int:
	return ceili(people * Balance.number("food.meals_per_person"))
