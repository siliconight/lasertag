extends Node
class_name LT_PlayerRegistry
## Tracks all players — human, bot, and (later) networked (TDD §14).
## The most important architectural rule: think in players plural.

signal player_registered(player: Node3D)
signal player_unregistered(player: Node3D)

var players: Array[Node3D] = []

func _ready() -> void:
	add_to_group(LT_Const.GROUP_REGISTRY)

func register_player(player: Node3D) -> void:
	if not players.has(player):
		players.append(player)
		player_registered.emit(player)

func unregister_player(player: Node3D) -> void:
	if players.has(player):
		players.erase(player)
		player_unregistered.emit(player)

func clear() -> void:
	players.clear()

func get_all_players() -> Array[Node3D]:
	var valid: Array[Node3D] = []
	for player in players:
		if is_instance_valid(player):
			valid.append(player)
	return valid

func get_alive_players() -> Array[Node3D]:
	var alive: Array[Node3D] = []

	for player in get_all_players():
		if player.has_node("LT_Health"):
			var health: LT_Health = player.get_node("LT_Health")
			if not health.is_dead:
				alive.append(player)

	return alive

func all_players_dead() -> bool:
	return not get_all_players().is_empty() and get_alive_players().is_empty()

## Multi-player target scoring (TDD §15.3):
## visible +50, closest +30, recently-damaged-this-enemy +25, low health +5.
func get_best_target_for_enemy(enemy: Node3D) -> Node3D:
	var alive := get_alive_players()
	if alive.is_empty():
		return null
	if alive.size() == 1:
		return alive[0]

	var best_player: Node3D = null
	var best_score := -INF
	var closest_player := _closest(alive, enemy.global_position)

	for player in alive:
		var score := 0.0
		if player == closest_player:
			score += 30.0

		var world := enemy.get_world_3d() if enemy is Node3D else null
		var eye := enemy.global_position + Vector3.UP * 1.4
		var body := enemy as CollisionObject3D
		if LT_LineOfSightTester.has_line_of_sight(eye, player, world, body):
			score += 50.0

		if enemy.has_meta("lt_last_damager") and enemy.get_meta("lt_last_damager") == player:
			score += 25.0

		if player.has_node("LT_Health"):
			var health: LT_Health = player.get_node("LT_Health")
			if health.current_health <= 2:
				score += 5.0

		if score > best_score:
			best_score = score
			best_player = player

	return best_player

func _closest(candidates: Array[Node3D], from_position: Vector3) -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for candidate in candidates:
		var distance := from_position.distance_to(candidate.global_position)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best
