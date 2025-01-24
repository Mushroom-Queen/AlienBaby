extends Node3D

@onready var ray := $RayCast3D
@onready var mesh := $MeshInstance3D
var is_charging := false
var can_fire := true
var charge_timer: SceneTreeTimer = null
var world: Node
var player
var camera: Camera3D
const PROJECTILE_SPEED := 10.0
const MAX_PROJECTILE_LIFETIME := 2.0
const CHARGE_TIME := 0.5  # Time in seconds to charge the shot
var current_bolt = null  # Track the active bolt

func _ready():
	world = find_world(get_tree().root)
	player = world.get_node_or_null("player")
	if player:
		camera = player.get_node_or_null("SpringArmPivot/SpringArm3D/Camera3D")
		if camera:
			ray.add_exception(player)
	mesh.visible = false

func find_world(node) -> Node:
	if node.name.to_lower() == "world":
		return node
	for child in node.get_children():
		var found = find_world(child)
		if found:
			return found
	return null

func start_charging():
	if can_fire and world:  # Only start if we can fire and have a world reference
		is_charging = true
		can_fire = false
		# Store the timer reference so we can cancel it
		charge_timer = get_tree().create_timer(CHARGE_TIME)
		charge_timer.timeout.connect(fire_charged_bolt)

func start_firing():
	start_charging()

func stop_firing():
	stop_charging()

func stop_charging():
	if is_charging:
		is_charging = false
		# Immediately allow firing again if we cancel a charge
		can_fire = true
		# If we have a pending charge timer, disconnect and nullify it
		if charge_timer and is_instance_valid(charge_timer):
			if charge_timer.timeout.is_connected(fire_charged_bolt):
				charge_timer.timeout.disconnect(fire_charged_bolt)
		charge_timer = null

func fire_charged_bolt():
	if is_charging:
		spawn_bolt()
		is_charging = false
		# Add cooldown before next charge
		var cooldown_timer = get_tree().create_timer(0.2)
		cooldown_timer.timeout.connect(func(): can_fire = true)

func spawn_bolt():
	if not world:
		return
		
	# Remove previous bolt if it exists
	if current_bolt and is_instance_valid(current_bolt):
		current_bolt.queue_free()
	
	# Create new bolt
	var bolt = mesh.duplicate() as MeshInstance3D
	bolt.visible = true
	bolt.scale = Vector3(1.5, 1.5, 3.0)  # Make bolt larger than regular beam segments
	
	# Store bolt data
	var direction = -camera.global_transform.basis.z
	bolt.set_meta("direction", direction)
	bolt.set_meta("spawn_time", Time.get_unix_time_from_system())
	
	world.add_child(bolt)
	
	var spawn_pos = global_position
	
	bolt.global_position = spawn_pos
	
	bolt.global_transform.basis = camera.global_transform.basis
	bolt.rotate_object_local(Vector3.RIGHT, PI/2)
		
	current_bolt = bolt

func _physics_process(delta: float) -> void:
	if not camera or not is_instance_valid(camera):
		return
	
	# Update active bolt
	if current_bolt and is_instance_valid(current_bolt):
		var direction = current_bolt.get_meta("direction")
		var spawn_time = current_bolt.get_meta("spawn_time")
		var current_time = Time.get_unix_time_from_system()
		
		# Move bolt
		current_bolt.global_position += direction * PROJECTILE_SPEED * delta
		
		# Check lifetime
		if current_time - spawn_time >= MAX_PROJECTILE_LIFETIME:
			current_bolt.queue_free()
			current_bolt = null
