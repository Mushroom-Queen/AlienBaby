extends Node3D

@onready var ray := $RayCast3D
@onready var beam := $MeshInstance3D
var is_firing := false
var world: Node
var player: CharacterBody3D
var camera: Camera3D

func _ready():
	beam.visible = false
	ray.enabled = true
	
	var root = get_tree().root
	world = find_world(root)
	if world:
		player = world.get_node_or_null("player")
		if player:
			camera = player.get_node_or_null("SpringArmPivot/SpringArm3D/Camera3D")
			if camera:
				ray.add_exception(player)
			else:
				push_warning("Camera not found in player node")
		else:
			push_warning("Player node not found in world")
	else:
		push_warning("World node not found")

func find_world(node: Node) -> Node:
	if node.name.to_lower() == "world":
		return node
	for child in node.get_children():
		var found = find_world(child)
		if found:
			return found
	return null

func start_firing():
	print("Start firing called")
	is_firing = true
	beam.visible = true
	
func stop_firing():
	print("Stop firing called")
	is_firing = false
	beam.visible = false

func _physics_process(delta: float) -> void:
	if not camera or not is_instance_valid(camera):
		print("Camera invalid - exiting")
		return
	
	# Get camera's transform
	var cam_transform := camera.global_transform
	
	# Debug prints
	print("State check:")
	print("- Camera valid: ", is_instance_valid(camera))
	print("- Is firing: ", is_firing)
	print("- Ray enabled: ", ray.enabled)
	print("- Beam visible: ", beam.visible)
	print("- Weapon position: ", global_position)
	print("- Camera position: ", camera.global_position)
	print("- Camera forward: ", -cam_transform.basis.z)
	
	# Update ray to match weapon position
	ray.global_position = global_position
	
	if is_firing:
		# Get the direction from weapon to where camera is pointing
		var weapon_to_camera = camera.global_position - global_position
		var cam_forward = -cam_transform.basis.z
		
		# Project the weapon's forward direction onto the camera's forward plane
		var projected_direction = cam_forward
		ray.target_position = projected_direction * 1000
		
		print("Ray target: ", ray.target_position)
		print("Is colliding: ", ray.is_colliding())
		
		if ray.is_colliding():
			var hit_point = ray.get_collision_point()
			var distance = global_position.distance_to(hit_point)
			
			beam.global_position = global_position
			beam.global_transform = ray.global_transform
			beam.scale = Vector3(1, distance, 1)
			beam.position.y = distance / 2
			
			var collider = ray.get_collider()
			if collider and collider.has_method("get") and collider.get("life") != null:
				collider.life -= 10.0 * delta
