extends Node3D

@onready var ray := $RayCast3D
@onready var mesh := $MeshInstance3D
var world: Node
var player
var boss
var camera: Camera3D
var can_fire := true
var active_bolts: Array[RigidBody3D] = []
const PROJECTILE_SPEED := 6.0
const MAX_PROJECTILE_LIFETIME := 2.0
const BOLT_MASS := 200.0
const FIRE_RATE := 0.5  # 2 shots per second (1/2 = 0.5 seconds between shots)

func _ready():
	world = find_world()
	player = world.get_node_or_null("player")
	boss = world.get_node_or_null("ship")
	if player:
		camera = player.get_node_or_null("SpringArmPivot/SpringArm3D/Camera3D")
		if camera:
			ray.add_exception(player)
	mesh.visible = false

func find_world(node=get_tree().root) -> Node:
	if node.name.to_lower() == "world":
		return node
	for child in node.get_children():
		var found = find_world(child)
		if found:
			return found
	return null

func start_firing():
	if can_fire and world:
		fire_bolt()
		can_fire = false
		var cooldown_timer = get_tree().create_timer(FIRE_RATE)
		cooldown_timer.timeout.connect(func(): can_fire = true)

func fire_bolt():
	if not world:
		return
	
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
	
	# Add Area3D for ship detection
	var area = Area3D.new()
	var area_collision = CollisionShape3D.new()
	var area_shape = CapsuleShape3D.new()
	area_shape.radius = 0.3  # Slightly larger than the collision shape
	area_shape.height = 1.2
	area_collision.shape = area_shape
	area.add_child(area_collision)
	bolt_body.add_child(area)
	
	# Connect Area3D signal
	area.body_entered.connect(_on_area_body_entered.bind(bolt_body))
	
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
	
	# Add to active bolts array
	active_bolts.append(bolt_body)

func _on_area_body_entered(body: Node3D, bolt: RigidBody3D):
	if body == boss:
		boss.hurt()
		# Set shorter lifetime
		var current_time = Time.get_unix_time_from_system()
		bolt.set_meta("spawn_time", current_time - (MAX_PROJECTILE_LIFETIME - 0.2))

func _on_bolt_collision(body: Node3D, bolt: RigidBody3D):
	if body != player:  # Ignore collisions with player
		remove_bolt(bolt)

func remove_bolt(bolt: RigidBody3D) -> void:
	if bolt and is_instance_valid(bolt):
		active_bolts.erase(bolt)
		bolt.queue_free()

func _physics_process(_delta: float) -> void:
	if not camera or not is_instance_valid(camera):
		return
	
	var current_time = Time.get_unix_time_from_system()
	
	# Check all active bolts for lifetime
	for bolt in active_bolts.duplicate():  # Duplicate array to safely modify while iterating
		if not is_instance_valid(bolt):
			active_bolts.erase(bolt)
			continue
			
		var spawn_time = bolt.get_meta("spawn_time")
		if current_time - spawn_time >= MAX_PROJECTILE_LIFETIME:
			remove_bolt(bolt)
