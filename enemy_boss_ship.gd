extends RigidBody3D

@onready var ship = self
@onready var rim = $joint/rim
@onready var joint = $joint

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
const ATTACK_INTERVAL = 5.0
const CHARGE_SPEED = 15.0
const MOVE_TO_EDGE_SPEED = 10.0
const LEVEL_SIZE = 20.0
const CHARGE_ATTACK_HEIGHT = -2
const MOVEMENT_FORCE = 20.0  # Force multiplier for movement
const HOVER_FORCE = 500.0    # Force for maintaining hover height
const DAMPING = 0.95        # Damping factor to prevent excessive oscillation

enum State {
	CIRCLING,
	MOVING_TO_EDGE,
	CHARGING
}

var world
var player
var rim_angular_velocity = 3
var current_state = State.CIRCLING
var attack_timer = 0.0
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
var charge_start_position: Vector3
var charge_end_position: Vector3

func _ready() -> void:
	world = find_world()
	player = world.get_node_or_null("player")
	initial_height = global_position.y
	current_hover_height = randf_range(MIN_HOVER_HEIGHT, MAX_HOVER_HEIGHT)
	randomize()
	pick_new_flight_parameters()

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	
	rotate_rim(delta)
	apply_hover_force()
	
	match current_state:
		State.CIRCLING:
			attack_timer += delta
			circle_around_player(delta)
			
			if attack_timer >= ATTACK_INTERVAL:
				prepare_charge()
				
		State.MOVING_TO_EDGE:
			move_to_edge(delta)
			
		State.CHARGING:
			charge(delta)
	
	if rim is Area3D and rim.has_overlapping_bodies():
		if player in rim.get_overlapping_bodies():
			push_player()
			player.hurt()

func apply_hover_force() -> void:
	var target_height = initial_height + current_hover_height + current_height_offset
	var height_diff = target_height - global_position.y
	var hover_force = Vector3.UP * height_diff * HOVER_FORCE
	apply_force(hover_force)
	
	# Apply damping to vertical velocity to prevent bouncing
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
		0,  # Height handled by hover force
		sin(t) * current_radius + noise_z
	)
	
	var direction = (target - global_position).normalized()
	apply_force(direction * MOVEMENT_FORCE)
	
	# Look in movement direction
	if linear_velocity.length() > 0.1:
		ship.look_at(ship.global_position + linear_velocity.normalized(), Vector3.UP)

func move_to_edge(delta: float) -> void:
	if not player:
		return
	
	var direction = (charge_start_position - global_position).normalized()
	apply_force(direction * MOVEMENT_FORCE * 1.5)  # Increased force for positioning
	
	if global_position.distance_to(charge_start_position) < 1.0:
		var charge_direction = (charge_end_position - charge_start_position).normalized()
		ship.look_at(ship.global_position + charge_direction, Vector3.UP)
		current_state = State.CHARGING

func charge(delta: float) -> void:
	if not player:
		return
	
	var direction = (charge_end_position - charge_start_position).normalized()
	apply_force(direction * MOVEMENT_FORCE * 2.0)  # Increased force for charging
	
	# Keep facing charge direction
	ship.look_at(global_position + direction, Vector3.UP)
	
	# Check if we've passed the end position
	var to_end = charge_end_position - global_position
	if to_end.dot(direction) <= 0:
		current_state = State.CIRCLING
		attack_timer = 0.0

# Existing unchanged functions
func push_player() -> void:
	if not player:
		return
	var push_direction = (player.global_position - rim.global_position).normalized()
	push_direction.y *= .5
	var push_force = rim_angular_velocity * push_multiplier
	player.apply_impulse(push_direction * push_force)

func rotate_rim(delta: float) -> void:
	joint.rotate_y(rim_angular_velocity * delta)

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

func prepare_charge() -> void:
	if not player:
		return
		
	var sides = ["left", "right", "front", "back"]
	var chosen_side = sides[randi() % sides.size()]
	
	var player_pos = player.global_position
	player_pos.y = initial_height + CHARGE_ATTACK_HEIGHT
	
	var attack_direction: Vector3
	var start_offset: Vector3
	
	match chosen_side:
		"left":
			start_offset = Vector3(-LEVEL_SIZE, 0, 0)
			attack_direction = Vector3.RIGHT
		"right":
			start_offset = Vector3(LEVEL_SIZE, 0, 0)
			attack_direction = Vector3.LEFT
		"front":
			start_offset = Vector3(0, 0, -LEVEL_SIZE)
			attack_direction = Vector3.BACK
		"back":
			start_offset = Vector3(0, 0, LEVEL_SIZE)
			attack_direction = Vector3.FORWARD
	
	charge_start_position = player_pos + start_offset
	charge_start_position.y = initial_height + CHARGE_ATTACK_HEIGHT
	
	charge_end_position = player_pos - start_offset
	charge_end_position.y = initial_height + CHARGE_ATTACK_HEIGHT
	
	current_state = State.MOVING_TO_EDGE
