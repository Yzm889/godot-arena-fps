extends RefCounted

# GDScript lambdas capture local ints by value, so signal counters have to live
# behind an object reference.
var value := 0
var events: Array = []


func hit() -> void:
	value += 1


func remember(event) -> void:
	value += 1
	events.append(event)
