extends Node3D

@onready var core = $core
@onready var rim = $core/joint/rim
@onready var joint = $core/joint

var world
var player

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	rim.angular_velocity.y = 1
	world = find_world()
	player = world.get_node_or_null("player")

func find_world(node=get_tree().root) -> Node:
	if node.name.to_lower() == "world":
		return node
	for child in node.get_children():
		var found = find_world(child)
		if found:
			return found
	return null

func _physics_process(delta: float) -> void:
	core.rotation = core.rotation.lerp(Vector3(0,0,0), delta)
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
