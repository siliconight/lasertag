@tool
extends Marker3D
class_name LT_SpawnMarker
## Optional typed spawn marker. Plain Marker3D / Node3D nodes named with
## the LT_ hook prefixes work too — the harness discovers by name prefix,
## not by type (TDD §8).

enum SpawnKind { PLAYER, ENEMY, OBJECTIVE, ROUTE, COVER }

@export var kind: SpawnKind = SpawnKind.PLAYER
