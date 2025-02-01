extends Node2D

@onready var boss_life = $ProgressBar

var world
var player
var boss

func _ready():
	world = find_world(get_tree().root)
	player = world.get_node_or_null("player")
	boss = world.get_node_or_null("ship")


func find_world(node) -> Node:
	if node.name.to_lower() == "world":
		return node
	for child in node.get_children():
		var found = find_world(child)
		if found:
			return found
	return null


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	boss_life.value = boss.life
