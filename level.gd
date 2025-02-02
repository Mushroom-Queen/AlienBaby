extends Node3D

@onready var ground = $ground
@onready var rock_fall_stream = preload("res://sounds/rock_fall.wav")
@onready var rock_hit_stream = preload("res://sounds/rock_hit.wav")


var world: Node
var player
var boss
var active_meteors = {}  # Changed to dictionary to track meteor->warning pairs
const METEOR_FORCE = 20.0
const METEOR_SIZE = .5
const WARNING_TIME = 1.2
const SPAWN_INTERVAL = 1.0  
const SPAWN_HEIGHT = 10.0
var next_spawn_time = 0.0
var is_showering = false

class WarningIndicator extends Node3D:
	var time_left: float
	var cylinder: CSGCylinder3D
	
	func _init():
		cylinder = CSGCylinder3D.new()
		cylinder.radius = METEOR_SIZE
		cylinder.height = 0.1
		cylinder.sides = 16
		add_child(cylinder)
		
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(1, 0, 0, 0.5)
		mat.emission_enabled = true
		mat.emission = Color(1, 0, 0)
		mat.emission_energy_multiplier = 2.0
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cylinder.material = mat

func _ready() -> void:
	print("World _ready called")
	world = find_world()
	player = world.get_node_or_null("player")
	boss = world.get_node_or_null("ship")
	ground.add_collision_exception_with(boss)
	print("World ready - Found player: ", player != null)

func _process(delta: float) -> void:
	if is_showering:
		var current_time = Time.get_ticks_msec() / 1000.0
		if current_time >= next_spawn_time:
			print("Spawn timer triggered at time: ", current_time)
			create_meteor()
			next_spawn_time = current_time + SPAWN_INTERVAL
	
	# Update warning indicators
	var meteors_to_remove = []
	for meteor in active_meteors:
		var warning = active_meteors[meteor]
		if not is_instance_valid(warning):
			meteors_to_remove.append(meteor)
			continue
			
		warning.time_left -= delta
		if warning.time_left <= 0:
			warning.time_left = 999999  # Keep warning alive until impact
			launch_meteor(warning, meteor)
	
	# Clean up invalid meteors/warnings
	for meteor in meteors_to_remove:
		remove_meteor_and_warning(meteor)

func shower():
	print("Shower function called - Starting meteor shower")
	is_showering = true
	next_spawn_time = Time.get_ticks_msec() / 1000.0  # Start first spawn immediately

func end_shower():
	print("End shower function called - Stopping meteor shower")
	is_showering = false
	for meteor in active_meteors:
		var warning = active_meteors[meteor]
		if is_instance_valid(warning):
			warning.queue_free()
	active_meteors.clear()

func create_meteor():
	print("Creating meteor...")
	if not player:
		print("No player found, cannot create meteor")
		return
		
	print("Player position: ", player.global_position)
	
	var target_pos = player.global_position
	if player is RigidBody3D:
		# Add some prediction based on player velocity
		target_pos += player.linear_velocity * 2.0
	
	# Create warning indicator
	var warning = WarningIndicator.new()
	warning.position = target_pos
	warning.time_left = WARNING_TIME
	
	print("Adding warning indicator to scene")
	add_child(warning)
	
	# Create placeholder meteor (initially without physics)
	var meteor = Node3D.new()  # Changed from RigidBody3D
	active_meteors[meteor] = warning
	print("Warning indicators count: ", active_meteors.size())
	
	# Animate warning
	var tween = create_tween()
	tween.tween_property(warning.cylinder.material, "emission_energy_multiplier", 4.0, 0.2)
	tween.tween_property(warning.cylinder.material, "emission_energy_multiplier", 1.0, 0.2)
	tween.set_loops()

func launch_meteor(warning: WarningIndicator, placeholder: Node3D):
	print("Launching meteor...")
	
	# Create meteor
	var meteor = RigidBody3D.new()
	meteor.gravity_scale = 3.0 
	
	# Sound
	var audioStream = AudioStreamPlayer3D.new()
	audioStream.stream = rock_fall_stream
	meteor.add_child(audioStream)
	audioStream.call_deferred("play", true)
	var hitStream = AudioStreamPlayer3D.new()
	hitStream.name = "hitStream"
	hitStream.stream = rock_hit_stream
	meteor.add_child(hitStream)
	
	
	var mesh = CSGSphere3D.new()
	mesh.radius = METEOR_SIZE
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.2, 0.0)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.4, 0.0)
	mat.emission_energy_multiplier = 1.0
	mesh.material = mat
	meteor.add_child(mesh)
	
	# Add collision
	var collision = CollisionShape3D.new()
	var sphere_shape = SphereShape3D.new()
	sphere_shape.radius = METEOR_SIZE
	collision.shape = sphere_shape
	meteor.add_child(collision)
	
	# Add damage area
	var area = Area3D.new()
	var area_collision = CollisionShape3D.new()
	var area_shape = SphereShape3D.new()
	area_shape.radius = 1.2
	area_collision.shape = area_shape
	area.add_child(area_collision)
	meteor.add_child(area)
	
	# Position meteor above warning
	var spawn_pos = warning.position + Vector3(0, SPAWN_HEIGHT, 0)
	meteor.position = spawn_pos
	print("Meteor spawn position: ", spawn_pos)
	
	# Connect signals
	area.body_entered.connect(_on_meteor_hit.bind(meteor))
	meteor.body_entered.connect(_on_meteor_collision.bind(meteor))
	
	# Update tracking
	active_meteors[meteor] = warning
	active_meteors.erase(placeholder)
	placeholder.queue_free()
	
	add_child(meteor)
	
	# Add trail effect
	print("Adding particle trail")
	var trail = GPUParticles3D.new()
	var particle_material = ParticleProcessMaterial.new()
	particle_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	particle_material.gravity = Vector3(0, -5, 0)
	particle_material.initial_velocity_min = 2.0
	particle_material.initial_velocity_max = 5.0
	particle_material.scale_min = 0.3
	particle_material.scale_max = 0.6
	particle_material.color = Color(1, 0.5, 0)
	trail.process_material = particle_material
	trail.amount = 50
	trail.lifetime = 0.8
	meteor.add_child(trail)
	
	# Safety cleanup after a while
	var timer = get_tree().create_timer(5.0)
	timer.timeout.connect(func(): 
		if is_instance_valid(meteor):
			print("Safety cleanup of old meteor")
			remove_meteor_and_warning(meteor)
	)

func _on_meteor_collision(body: Node3D, meteor: RigidBody3D) -> void:
	if not is_instance_valid(meteor) or not (meteor in active_meteors):
		return
		
	# Check if this is a ground collision
	if body.is_in_group("ground") or body.get_parent().is_in_group("ground"):
		print("Meteor hit ground")
		remove_meteor_and_warning(meteor)

func _on_meteor_hit(body: Node3D, meteor: RigidBody3D) -> void:
	print("Meteor hit detected with body: ", body.name)
	meteor.get_node_or_null("hitStream").play()
	
	if not is_instance_valid(meteor) or not is_instance_valid(body) or not (meteor in active_meteors):
		return
		
	if body == player:
		print("Meteor hit player!")
		# Calculate push direction
		var push_dir = (player.global_position - meteor.global_position).normalized()
		push_dir.y = 0.5  # Add some upward force
		player.apply_impulse(push_dir * METEOR_FORCE)
		player.hurt()



func remove_meteor_and_warning(meteor: Node3D) -> void:
	if meteor in active_meteors:
		var warning = active_meteors[meteor]
		if is_instance_valid(warning):
			warning.queue_free()
		active_meteors.erase(meteor)
		
		if is_instance_valid(meteor):
			meteor.queue_free()

func find_world(node=get_tree().root) -> Node:
	if node.name.to_lower() == "world":
		return node
	for child in node.get_children():
		var found = find_world(child)
		if found:
			return found
	return null


func _on_audio_stream_player_finished() -> void:
	$AudioStreamPlayer.play()
