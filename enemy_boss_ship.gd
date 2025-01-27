extends Node3D

@onready var core = $core
@onready var rim = $core/joint/rim
@onready var joint = $core/joint

const push_multiplier = 10

var world
var player
var rim_angular_velocity = 3

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
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


func push_player() -> void:
	if not player:
		return

	var push_direction = (player.global_position - rim.global_position).normalized()
	

	var push_force = rim_angular_velocity * push_multiplier
	
	if player is RigidBody3D:
		player.apply_impulse(push_direction * push_force)
	elif "velocity" in player:
		player.velocity += push_direction * push_force

func rotate_rim(delta):
	joint.rotate_y(rim_angular_velocity * delta)

	
func _process(delta: float) -> void:
	rotate_rim(delta)
	if rim.area_entered:
		if player in rim.get_overlapping_bodies():
			print("Player hit")
			push_player()
			player.hurt()
