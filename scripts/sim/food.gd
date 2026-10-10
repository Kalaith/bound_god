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
