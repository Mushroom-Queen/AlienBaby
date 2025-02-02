extends Area3D

var world
var player
var boss

func _ready():
	world = find_world()
	player = world.get_node_or_null("player")
	boss = world.get_node_or_null("ship")

func find_world(node=get_tree().root) -> Node:
	if node.name.to_lower() == "world":
		return node
	for child in node.get_children():
		var found = find_world(child)
		if found:
			return found
	return null


func _process(delta: float) -> void:
	if player in get_overlapping_bodies():
		if player.life < 4:
			player.life += 1
			queue_free()
