extends RigidBody3D

@onready var ship = self
@onready var rim = $joint/rim
@onready var joint = $joint
@onready var gun_1 = $enemy_boss_ship/L1/gun1
@onready var gun_2 = $enemy_boss_ship/L2/gun2
@onready var gun_3 = $enemy_boss_ship/L3/gun3
@onready var gun_4 = $enemy_boss_ship/L4/gun4

# New shooting-related variables
const SHOOT_COOLDOWN = 2.0
const BOLT_SPEED = 12.0
const BOLT_LIFETIME = 3.0
const BOLT_MASS = 20.0
var can_shoot := true
var shoot_timer := 0.0
var current_bolt = null
var life = 100

# Lightning bolt specific constants
const SEGMENTS = 6  # Number of segments in the lightning bolt
const SEGMENT_LENGTH = 0.15  # Length of each segment
const DEVIATION = 0.1  # Maximum random deviation for each segment
const BOLT_WIDTH = 0.05  # Width of the lightning bolt

# Existing constants
const push_multiplier = 7
const HOVER_HEIGHT = 3.0
const MIN_HOVER_HEIGHT = 0.1
const MAX_HOVER_HEIGHT = 3
const MIN_HEIGHT_OFFSET = -2.0
const MAX_HEIGHT_OFFSET = 2.0
const HEIGHT_CHANGE_SPEED = 2.5
const MIN_RADIUS = 1.0
const MAX_RADIUS = 6.0
const BASE_CIRCLE_SPEED = 1
const DIRECTION_CHANGE_TIME = 3.0
const MOVEMENT_FORCE = 60.0
const CHARGE_FORCE = 400.0
const HOVER_FORCE = 2000.0
const DAMPING = 0.95
const CHARGE_PREPARE_TIME = 1.0
const LEVEL_SIZE = Vector2(30, 30)
const CIRCLING_TIME = 15.0
const CHARGE_HEIGHT = -2.5
const CHARGE_HEIGHT_TRANSITION_SPEED = 3.0
const RIM_SPIN_SPEED = 5.0
const CHARGE_TIMEOUT = 5.0

const UP_STABILIZATION = 400.0
const ROTATION_DAMPING = 0.75
const MAX_ANGULAR_VELOCITY = 1.5
const ROTATION_INTERPOLATION = 0.2
const ORIENTATION_THRESHOLD = 0.01
const UPRIGHT_FORCE = 150.0

enum {
	CIRCLING,
	PREPARING_CHARGE,
	CHARGING
}

# Existing variables
var world
var player
var current_state = CIRCLING
var direction_change_timer = 0.0
var circle_angle = 0.0
var current_radius = 10.0
var target_radius = 10.0
var current_height_offset = 0.0
var current_hover_height = 0.0
var target_height_offset = 0.0
var current_circle_speed = BASE_CIRCLE_SPEED
var circle_direction = 1.0
var initial_height: float
var initial_transform: Transform3D
var state_timer = 0.0
var charge_target: Vector3
var charge_start_pos: Vector3
var charge_height_current = 0.0

func _ready() -> void:
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	
	can_sleep = false
	lock_rotation = false
	
	var new_basis = Basis()
	new_basis.y = Vector3.UP
	new_basis.x = Vector3.RIGHT
	new_basis.z = Vector3.BACK
	transform = Transform3D(new_basis, transform.origin)
	
	world = find_world()
	player = world.get_node_or_null("player")
	initial_height = global_position.y
	current_hover_height = randf_range(MIN_HOVER_HEIGHT, MAX_HOVER_HEIGHT)
	randomize()
	pick_new_flight_parameters()
	state_timer = 0.0

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	
	state_timer += delta
	
	if can_shoot:
		shoot_timer += delta
	
	match current_state:
		CIRCLING:
			if state_timer >= CIRCLING_TIME:
				start_charge_attack()
			else:
				stabilize_orientation(delta)
				apply_hover_force()
				circle_around_player(delta)
				attempt_shoot()
				if rim:
					rim.rotation.y += RIM_SPIN_SPEED * delta
		
		PREPARING_CHARGE:
			stabilize_orientation(delta)
			apply_hover_force()
			if state_timer >= CHARGE_PREPARE_TIME:
				begin_charge()
		
		CHARGING:
			stabilize_orientation(delta)
			apply_hover_force(0.5)
			execute_charge(delta)
	
	if rim is Area3D and rim.has_overlapping_bodies():
		if player in rim.get_overlapping_bodies():
			push_player()
			player.hurt()

func attempt_shoot() -> void:
	if not can_shoot or not player or shoot_timer < SHOOT_COOLDOWN:
		return
	
	shoot_timer = 0.0
	can_shoot = false
	spawn_bolt()
	
	# Reset shooting after cooldown
	var timer = get_tree().create_timer(SHOOT_COOLDOWN)
	timer.timeout.connect(func(): can_shoot = true)

func get_best_gun() -> Node3D:
	if not player:
		return gun_1  # Default to gun_1 if no player
	
	var guns = [gun_1, gun_2, gun_3, gun_4]
	var best_gun = gun_1
	var best_dot = -1.0
	
	# Get the direction to the player
	var to_player = (player.global_position - global_position).normalized()
	
	# Check each gun's facing direction against the player direction
	for gun in guns:
		# Get the gun's forward direction in global space
		var gun_forward = -gun.global_transform.basis.z
		var dot_product = gun_forward.dot(to_player)
		
		# Update best gun if this one has better alignment
		if dot_product > best_dot:
			best_dot = dot_product
			best_gun = gun
	
	return best_gun

func spawn_bolt() -> void:
	if not world or not player:
		return
	
	if current_bolt and is_instance_valid(current_bolt):
		current_bolt.queue_free()
	
	# Get the best positioned gun
	var firing_gun = get_best_gun()
	
	# Create main bolt node
	var bolt_body = RigidBody3D.new()
	bolt_body.mass = BOLT_MASS
	bolt_body.gravity_scale = 0.1
	
	# Create the lightning bolt mesh
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Generate lightning bolt vertices
	var points = []
	var current_point = Vector3.ZERO
	points.append(current_point)
	
	# Generate zigzag pattern
	for i in range(SEGMENTS):
		var next_point = current_point + Vector3(
			randf_range(-DEVIATION, DEVIATION),
			randf_range(-DEVIATION, DEVIATION),
			-SEGMENT_LENGTH
		)
		points.append(next_point)
		current_point = next_point
	
	# Create the mesh geometry
	for i in range(len(points) - 1):
		var start = points[i]
		var end = points[i + 1]
		var direction = (end - start).normalized()
		var perpendicular = direction.cross(Vector3.FORWARD).normalized()
		
		# Calculate vertices for this segment
		var v1 = start + perpendicular * BOLT_WIDTH
		var v2 = start - perpendicular * BOLT_WIDTH
		var v3 = end + perpendicular * BOLT_WIDTH
		var v4 = end - perpendicular * BOLT_WIDTH
		
		# Add vertices with UV coordinates
		st.set_uv(Vector2(0, float(i) / SEGMENTS))
		st.add_vertex(v1)
		st.set_uv(Vector2(1, float(i) / SEGMENTS))
		st.add_vertex(v2)
		st.set_uv(Vector2(0, float(i + 1) / SEGMENTS))
		st.add_vertex(v3)
		st.set_uv(Vector2(1, float(i + 1) / SEGMENTS))
		st.add_vertex(v4)
		
		# Add triangles
		var base_idx = i * 4
		st.add_index(base_idx)
		st.add_index(base_idx + 1)
		st.add_index(base_idx + 2)
		st.add_index(base_idx + 1)
		st.add_index(base_idx + 3)
		st.add_index(base_idx + 2)
	
	# Create the mesh instance
	var bolt_mesh = MeshInstance3D.new()
	bolt_mesh.mesh = st.commit()
	
	# Create material
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.3, 0.7, 1.0, 1.0)  # Light blue color
	material.emission_enabled = true
	material.emission = Color(0.3, 0.7, 1.0, 1.0)
	material.emission_energy_multiplier = 4.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bolt_mesh.material_override = material
	
	# Create collision shape using cylinder
	var collision = CollisionShape3D.new()
	var cylinder_shape = CylinderShape3D.new()
	cylinder_shape.radius = BOLT_WIDTH
	cylinder_shape.height = SEGMENT_LENGTH * SEGMENTS
	collision.shape = cylinder_shape
	# Rotate cylinder to align with bolt direction
	collision.rotation_degrees.x = 90
	bolt_body.add_child(collision)
	
	# Create damage area with cylinder
	var damage_area = Area3D.new()
	damage_area.name = "DamageArea"
	var area_collision = CollisionShape3D.new()
	var area_shape = CylinderShape3D.new()
	area_shape.radius = BOLT_WIDTH * 2
	area_shape.height = SEGMENT_LENGTH * SEGMENTS
	area_collision.shape = area_shape
	# Rotate cylinder to align with bolt direction
	area_collision.rotation_degrees.x = 90
	damage_area.add_child(area_collision)
	bolt_body.add_child(damage_area)
	
	# Add mesh to bolt
	bolt_body.add_child(bolt_mesh)
	
	# Setup physics
	bolt_body.add_collision_exception_with(self)
	var direction = (player.global_position - firing_gun.global_position + Vector3(0,.1,0)).normalized()
	bolt_body.linear_velocity = direction * BOLT_SPEED
	
	# Add metadata for lifetime tracking
	bolt_body.set_meta("spawn_time", Time.get_unix_time_from_system())
	
	# Add to scene and position
	world.add_child(bolt_body)
	bolt_body.global_position = firing_gun.global_position
	
	# Look at player
	bolt_body.look_at(player.global_position)
	
	# Connect Area3D signals
	damage_area.body_entered.connect(_on_bolt_area_entered.bind(bolt_body))
	
	current_bolt = bolt_body
	
	# Add animation
	var tween = create_tween()
	tween.tween_property(material, "emission_energy_multiplier", 0.5, 0.1)
	tween.tween_property(material, "emission_energy_multiplier", 4.0, 0.1)
	tween.set_loops()

func _on_bolt_area_entered(body: Node3D, bolt: RigidBody3D) -> void:
	if body == player:
		player.hurt()  # Call player's hurt method
		bolt.queue_free()
		current_bolt = null

func start_charge_attack() -> void:
	current_state = PREPARING_CHARGE
	state_timer = 0.0
	
	global_position.y = initial_height + CHARGE_HEIGHT
	
	var edge_pos = get_random_edge_position()
	charge_start_pos = Vector3(edge_pos.x, initial_height + CHARGE_HEIGHT, edge_pos.y)
	
	# Calculate direction through player position
	var to_player = (player.global_position - charge_start_pos).normalized()
	var charge_distance = LEVEL_SIZE.length() * 2
	charge_target = charge_start_pos + to_player * charge_distance
	charge_target.y = initial_height + CHARGE_HEIGHT
	
	linear_velocity = Vector3.ZERO

func get_random_edge_position() -> Vector2:
	var side = randi() % 4
	var pos = Vector2.ZERO
	
	match side:
		0:
			pos = Vector2(randf_range(-LEVEL_SIZE.x, LEVEL_SIZE.x), -LEVEL_SIZE.y)
		1:
			pos = Vector2(LEVEL_SIZE.x, randf_range(-LEVEL_SIZE.y, LEVEL_SIZE.y))
		2:
			pos = Vector2(randf_range(-LEVEL_SIZE.x, LEVEL_SIZE.x), LEVEL_SIZE.y)
		3:
			pos = Vector2(-LEVEL_SIZE.x, randf_range(-LEVEL_SIZE.y, LEVEL_SIZE.y))
	
	return pos

func begin_charge() -> void:
	current_state = CHARGING
	state_timer = 0.0
	global_position = charge_start_pos
	
	var to_player = (player.global_position - global_position).normalized()
	
	var target_basis = Basis()
	target_basis.y = Vector3.UP
	target_basis.x = to_player.cross(Vector3.UP).normalized()
	target_basis.z = -to_player
	transform = Transform3D(target_basis, global_position)
	
	if rim:
		rim.rotation = Vector3.ZERO
		rim.rotation.z = PI/2

func execute_charge(delta: float) -> void:
	var direction = (charge_target - global_position).normalized()
	apply_force(direction * CHARGE_FORCE)
	
	if rim:
		rim.rotation.x += RIM_SPIN_SPEED * delta
	
	var distance_from_start = global_position.distance_to(charge_start_pos)
	var distance_to_target = global_position.distance_to(charge_target)
	
	# Simplified end conditions with timeout
	if distance_from_start > LEVEL_SIZE.length() or distance_to_target < 2.0 or state_timer > CHARGE_TIMEOUT:
		if rim:
			rim.rotation = Vector3.ZERO
		current_state = CIRCLING
		state_timer = 0.0
		pick_new_flight_parameters()

func stabilize_orientation(delta: float) -> void:
	var current_up = transform.basis.y.normalized()
	var up_alignment = current_up.dot(Vector3.UP)
	
	if up_alignment < 0.95:
		var target_up = Vector3.UP
		var rotation_axis = current_up.cross(target_up).normalized()
		var angle = current_up.angle_to(target_up)
		var correction_strength = (1.0 - up_alignment) * UPRIGHT_FORCE
		var correction = rotation_axis * angle * correction_strength
		apply_torque(correction * delta)
	
	if current_state != CHARGING and linear_velocity.length_squared() > 0.1:
		var target_forward = linear_velocity.normalized()
		target_forward.y = 0
		target_forward = target_forward.normalized()
		
		var target_basis = Basis()
		target_basis.y = Vector3.UP
		target_basis.x = target_forward.cross(Vector3.UP).normalized()
		target_basis.z = -target_forward
		
		var target_transform = Transform3D(target_basis, global_position)
		transform = transform.interpolate_with(target_transform, ROTATION_INTERPOLATION)
	
	angular_velocity *= ROTATION_DAMPING
	
	if angular_velocity.length() > MAX_ANGULAR_VELOCITY:
		angular_velocity = angular_velocity.normalized() * MAX_ANGULAR_VELOCITY
	
	angular_velocity.x *= ROTATION_DAMPING * 0.8
	angular_velocity.z *= ROTATION_DAMPING * 0.8

func hurt():
	life -= 5

func apply_hover_force(multiplier: float = 1.0) -> void:
	var target_height = initial_height
	
	match current_state:
		CIRCLING:
			target_height += current_hover_height + current_height_offset
		PREPARING_CHARGE, CHARGING:
			target_height += CHARGE_HEIGHT
			if global_position.y > target_height:
				apply_force(Vector3.DOWN * HOVER_FORCE * 2.0 * multiplier)
	
	var height_diff = target_height - global_position.y
	var hover_force = Vector3.UP * height_diff * HOVER_FORCE * multiplier
	
	var up_alignment = transform.basis.y.dot(Vector3.UP)
	if up_alignment < 0.95:
		hover_force *= 1.5
	
	apply_force(hover_force)
	linear_velocity.y *= DAMPING

func circle_around_player(delta: float) -> void:
	if not player:
		return
		
	direction_change_timer += delta
	if direction_change_timer >= DIRECTION_CHANGE_TIME:
		direction_change_timer = 0.0
		pick_new_flight_parameters()
	
	current_radius = lerp(current_radius, target_radius, delta * 1.5)
	current_height_offset = lerp(current_height_offset, target_height_offset, delta * HEIGHT_CHANGE_SPEED)
	
	var height_factor = (current_height_offset - MIN_HEIGHT_OFFSET) / (MAX_HEIGHT_OFFSET - MIN_HEIGHT_OFFSET)
	var current_speed = current_circle_speed * (1.2 - height_factor * 0.4)
	
	circle_angle += current_speed * circle_direction * delta
	
	var noise_x = sin(Time.get_ticks_msec() * 0.0005) * 1.0
	var noise_z = cos(Time.get_ticks_msec() * 0.0004) * 1.0
	
	var t = circle_angle
	var target = player.global_position + Vector3(
		cos(t) * current_radius + noise_x,
		0,
		sin(t) * current_radius + noise_z
	)
	
	var direction = (target - global_position).normalized()
	apply_force(direction * MOVEMENT_FORCE)

func push_player() -> void:
	if not player:
		return
	var push_direction = (player.global_position - rim.global_position).normalized()
	push_direction.y *= .5
	var push_force = push_multiplier  
	player.apply_impulse(push_direction * push_force)

func pick_new_flight_parameters() -> void:
	target_radius = randf_range(MIN_RADIUS, MAX_RADIUS)
	current_hover_height = randf_range(MIN_HOVER_HEIGHT, MAX_HOVER_HEIGHT)
	
	var height_pattern = randi() % 3
	match height_pattern:
		0:
			target_height_offset = randf_range(MIN_HEIGHT_OFFSET, MIN_HEIGHT_OFFSET * 0.5)
		1:
			target_height_offset = randf_range(MIN_HEIGHT_OFFSET * 0.3, MAX_HEIGHT_OFFSET * 0.3)
		2:
			target_height_offset = randf_range(0, MAX_HEIGHT_OFFSET)
	
	current_circle_speed = BASE_CIRCLE_SPEED * randf_range(0.8, 1.1)
	circle_direction = 1.0 if randf() > 0.5 else -1.0

func find_world(node=get_tree().root) -> Node:
	if node.name.to_lower() == "world":
		return node
	for child in node.get_children():
		var found = find_world(child)
		if found:
			return found
	return null
