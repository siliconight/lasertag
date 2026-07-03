extends Node
class_name LT_Health
## Simple hit-point component (TDD §13.1).
## Node MUST be named "LT_Health" on pills — LT_Shooter looks it up by name.

signal damaged(current_health: int, max_health: int)
signal died

@export var max_health: int = 2

var current_health: int = 0
var is_dead: bool = false

func _ready() -> void:
	reset_health()

func reset_health() -> void:
	current_health = max_health
	is_dead = false

func apply_hit(amount: int = 1) -> void:
	if is_dead:
		return

	current_health -= amount
	damaged.emit(current_health, max_health)

	if current_health <= 0:
		current_health = 0
		is_dead = true
		died.emit()
