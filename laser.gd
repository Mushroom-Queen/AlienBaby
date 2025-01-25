extends Node3D

@onready var ray := $RayCast3D
@onready var mesh := $MeshInstance3D
var is_charging := false
var can_fire := true
var charge_timer: SceneTreeTimer = null
var world: Node
var player
var camera: Camera3D
const PROJECTILE_SPEED := 6.0
const MAX_PROJECTILE_LIFETIME := 2.0
const CHARGE_TIME := 0.5
const BOLT_MASS := 100.0
var current_bolt = null

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
	if can_fire and world:
		is_charging = true
		can_fire = false
		charge_timer = get_tree().create_timer(CHARGE_TIME)
		charge_timer.timeout.connect(fire_charged_bolt)

func start_firing():
	start_charging()

func stop_firing():
	stop_charging()

func stop_charging():
	if is_charging:
		is_charging = false
		can_fire = true
		if charge_timer and is_instance_valid(charge_timer):
			if charge_timer.timeout.is_connected(fire_charged_bolt):
				charge_timer.timeout.disconnect(fire_charged_bolt)
		charge_timer = null

func fire_charged_bolt():
	if is_charging:
		spawn_bolt()
		is_charging = false
		var cooldown_timer = get_tree().create_timer(0.2)
		cooldown_timer.timeout.connect(func(): can_fire = true)

func spawn_bolt():
	if not world:
		return
		
	if current_bolt and is_instance_valid(current_bolt):
		current_bolt.queue_free()
	
	# Create RigidBody3D for physics-based bolt
	var bolt_body = RigidBody3D.new()
	bolt_body.mass = BOLT_MASS
	bolt_body.gravity_scale = 0.1  # Reduced gravity effect
	
	# Create collision shape
	var collision = CollisionShape3D.new()
	var capsule_shape = CapsuleShape3D.new()
	capsule_shape.radius = 0.2
	capsule_shape.height = 1.0
	collision.shape = capsule_shape
	bolt_body.add_child(collision)
	
	# Add mesh
	var bolt_mesh = mesh.duplicate() as MeshInstance3D
	bolt_mesh.visible = true
	bolt_body.add_child(bolt_mesh)
	
	# Setup physics
	bolt_body.add_collision_exception_with(player)
	var direction = -camera.global_transform.basis.z
	bolt_body.linear_velocity = direction * PROJECTILE_SPEED
	bolt_body.set_meta("spawn_time", Time.get_unix_time_from_system())
	
	# Add to scene
	world.add_child(bolt_body)
	bolt_body.global_position = global_position
	bolt_body.global_transform.basis = camera.global_transform.basis
	bolt_body.rotate_object_local(Vector3.RIGHT, PI/2)
	
	# Connect physics signals
	bolt_body.body_entered.connect(_on_bolt_collision.bind(bolt_body))
	
	current_bolt = bolt_body

func _on_bolt_collision(body: Node3D, bolt: RigidBody3D):
	if body != player:  # Ignore collisions with player
		# Add impact effects here if desired
		bolt.queue_free()
		current_bolt = null

func _physics_process(_delta: float) -> void:
	if not camera or not is_instance_valid(camera):
		return
	
	if current_bolt and is_instance_valid(current_bolt):
		var spawn_time = current_bolt.get_meta("spawn_time")
		var current_time = Time.get_unix_time_from_system()
		
		if current_time - spawn_time >= MAX_PROJECTILE_LIFETIME:
			current_bolt.queue_free()
			current_bolt = null
