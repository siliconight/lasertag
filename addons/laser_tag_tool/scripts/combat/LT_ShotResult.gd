extends RefCounted
class_name LT_ShotResult
## Result of one hitscan laser shot (TDD §13.2).
## Hit types: MISS, WORLD_BLOCKED, PLAYER_HIT, ENEMY_HIT, FRIENDLY_HIT,
## CHARACTER_HIT, INVALID.

var did_hit: bool = false
var did_damage: bool = false
var was_blocked: bool = false

var shooter: Node
var shooter_is_player: bool = false
var shooter_peer_id: int = 1
var collider: Object
var hit_position: Vector3
var hit_normal: Vector3
var hit_type: String = "MISS"

var start_position: Vector3
var end_position: Vector3

var damage_applied: int = 0

func distance() -> float:
	return start_position.distance_to(end_position)
