extends RigidBody3D

@onready var armature := $player/Armature
@onready var animation_player := $player/AnimationPlayer
@onready var spring_arm_pivot := $SpringArmPivot
@onready var spring_arm := $SpringArmPivot/SpringArm3D
@onready var animation_tree := $AnimationTree
@onready var mesh := $player/Armature/Skeleton3D
@onready var leaf_bone = $player/Armature/Skeleton3D/leafs
@onready var leaf1 = $player/Armature/Skeleton3D/leafs/leaf_piv/leaf1
@onready var leaf2 = $player/Armature/Skeleton3D/leafs/leaf_piv/leaf2
@onready var leaf3 = $player/Armature/Skeleton3D/leafs/leaf_piv/leaf3
@onready var leaf4 = $player/Armature/Skeleton3D/leafs/leaf_piv/leaf4
@onready var leaf_piv = $player/Armature/Skeleton3D/leafs/leaf_piv
@onready var laser = $player/Armature/Skeleton3D/leafs/laser
@onready var collision_left = $CollisionShapeLeft
@onready var collision_right = $CollisionShapeRight
@onready var arm_bone_left = $player/Armature/Skeleton3D/left_arm
@onready var arm_bone_right = $player/Armature/Skeleton3D/right_arm
@onready var shield = $shield

const MOVEMENT_FORCE = 140.0
const FRICTION_FORCE = 10.0
const MAX_VELOCITY = 1
const ROLL_FORCE = 192.0
const ROLL_FRICTION = 200.0
const ROLL_DURATION = 0.6
const CAMERA_LERP_SPEED = 0.1
const SHOOTING_CAMERA_OFFSET = Vector3(0, 0, -.05)
const MIN_ZOOM = .1
const MAX_ZOOM = 1
const MAX_DIZZINESS = 2.5
const SPIN_DIZZ_COST = 0.0
const POST_SPIN_DIZZ_COST = 2.5
const SPIN_DIZZ_RESET_SPEED = 0.6
const DIZZY_SWAY_SPEED = 2.0
const DIZZY_SWAY_INTENSITY = 0.2
const DIZZY_POSITION_INTENSITY = 0.05
const LERP_VAL = .15
const SPIN_POWER = 40.0
const SPIN_ANGULAR_DAMP = 1.0
const MAX_ANGULAR_VELOCITY = 40.0
const SPIN_RESET_TIME = 2.0
const CANT_TOUCH_THIS_TIME = .5
const ATTACK_DURATION = 0.2
const SHIELD_FOLLOW_SPEED = 0.5  # New constant for shield movement interpolation
const SHIELD_VELOCITY_SYNC = 0.5  # New constant for velocity synchronization
const SHIELD_OFFSET = 0.1  # New constant for initial shield offset

enum ActionState {IDLE, WALK, ROLL, ATTACK, SPIN}

var life = 4
var hurt_counter = 0
var life_rendered = 4
var dizziness = 0
var action_state = ActionState.IDLE
var is_rolling = false
var is_spinning = false
var roll_direction = Vector3.ZERO
var roll_timer = 0.0
var initial_mesh_position = Vector3.ZERO
var prev_is_spinning = false
var dizzy_time = 0.0
var camera_original_position: Vector3
var camera_original_rotation: Vector3
var spin_count = 0
var spin_timeout = 0.0
var attack_timer = 0.0
var world
var previous_shield_pos: Vector3  # New variable to track previous shield position

func _ready():
	world = find_world()
	
	lock_rotation = true
	freeze = false
	contact_monitor = true
	linear_damp = 1.0
	angular_damp = 0.0
	can_sleep = false
	animation_tree.active = true
	spring_arm_pivot.top_level = true
	spring_arm_pivot.position.y = .44
	
	spring_arm.add_excluded_object(self)
	spring_arm.add_excluded_object(shield)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	mesh.rotation = Vector3(0, -PI, 0)
	initial_mesh_position = mesh.position
	camera_original_position = spring_arm.position
	camera_original_rotation = spring_arm.rotation
	shield.add_collision_exception_with(self)
	previous_shield_pos = shield.global_position

func find_world(node=get_tree().root) -> Node:
	if node.name.to_lower() == "world":
		return node
	for child in node.get_children():
		var found = find_world(child)
		if found:
			return found
	return null

func update_life_leafs():
	if life != life_rendered:
		life_rendered = life
		leaf1.visible = life >= 4
		leaf2.visible = life >= 3
		leaf3.visible = life >= 2
		leaf4.visible = life >= 1

func update_camera(delta: float) -> void:
	spring_arm_pivot.global_position = global_position + Vector3(0, 0.44, 0)
	
	dizzy_time += delta * DIZZY_SWAY_SPEED * (1.0 + dizziness * 0.5)
	
	var offset = Vector3.ZERO
	if action_state == ActionState.ATTACK:
		offset = SHOOTING_CAMERA_OFFSET
	
	if dizziness > 0:
		offset += Vector3(
			sin(dizzy_time * 1.3) * DIZZY_POSITION_INTENSITY,
			cos(dizzy_time * 1.5) * DIZZY_POSITION_INTENSITY,
			0
		) * (dizziness / MAX_DIZZINESS)
		spring_arm.rotation.z = sin(dizzy_time * 0.9) * DIZZY_SWAY_INTENSITY * (dizziness / MAX_DIZZINESS)
	else:
		spring_arm.rotation.z = move_toward(spring_arm.rotation.z, 0.0, delta * 2.0)
	
	spring_arm.position = spring_arm.position.lerp(offset, CAMERA_LERP_SPEED)

func hurt():
	if is_spinning:
		return
	if hurt_counter > 0:
		print("Can't touch this")
		return
	hurt_counter = CANT_TOUCH_THIS_TIME
	life -= 1

func update_hurt_counter(delta):
	if hurt_counter > 0:
		hurt_counter -= delta

func _unhandled_input(event):
	if Input.is_action_just_pressed("quit"):
		get_tree().quit()
	
	if Input.is_action_pressed("zoom_in"):
		spring_arm.spring_length = clamp(spring_arm.spring_length + .1, MIN_ZOOM, MAX_ZOOM)
	
	if Input.is_action_pressed("zoom_out"):
		spring_arm.spring_length = clamp(spring_arm.spring_length - .1, MIN_ZOOM, MAX_ZOOM)
	
	if Input.is_action_just_pressed("roll") and action_state not in [ActionState.ATTACK, ActionState.SPIN]:
		var input_dir := Input.get_vector("left", "right", "forward", "back")
		roll_direction = Vector3(input_dir.x, 0, input_dir.y).normalized()
		roll_direction = roll_direction.rotated(Vector3.UP, spring_arm_pivot.rotation.y)
		
		if roll_direction.length() > 0.1:
			action_state = ActionState.ROLL
			roll_timer = 0.0
			animation_tree.set("parameters/roll/request", true)
	
	if Input.is_action_just_pressed("attack") and action_state != ActionState.SPIN:
		action_state = ActionState.ATTACK
		attack_timer = ATTACK_DURATION
		animation_tree.set("parameters/shooting/blend_amount", 1.0)
		laser.start_firing()
	
	if event is InputEventMouseMotion:
		spring_arm_pivot.rotate_y(-event.relative.x * .005)
		spring_arm.rotate_x(-event.relative.y * .005)
		spring_arm.rotation.x = clamp(spring_arm.rotation.x, -PI/3, PI/3)

func shield_youself():
	# Calculate predicted shield position based on current velocity
	var predicted_shield_pos = shield.global_position + (shield.linear_velocity * get_physics_process_delta_time())
	
	# Calculate target position with offset
	var target_position = predicted_shield_pos - Vector3(0, .26, 0)
	
	# Store current position for velocity calculation
	var current_pos = global_position
	
	# Interpolate position with predicted position
	global_position = current_pos.lerp(target_position, SHIELD_FOLLOW_SPEED)
	
	# Calculate and apply velocity to match shield movement
	var velocity_target = (global_position - current_pos) / get_physics_process_delta_time()
	linear_velocity = linear_velocity.lerp(velocity_target, SHIELD_VELOCITY_SYNC)
	
	# Update shield previous position
	previous_shield_pos = shield.global_position
	
	# Update rotation
	armature.rotate_y(get_process_delta_time() * 70)

func init_shield():
	if not shield.visible:
		mesh.rotation = Vector3(0, 0, 0)
		animation_tree.set("parameters/spin/request", true)
		
		# Calculate initial shield position with offset
		var offset = global_transform.basis.z * SHIELD_OFFSET
		var initial_shield_pos = global_position + offset
		
		# Set shield properties
		shield.set_deferred("global_position", initial_shield_pos)
		shield.set_deferred("linear_velocity", linear_velocity)
		shield.set_deferred("angular_velocity", Vector3.ZERO)
		shield.set_deferred("mass", 100)
		shield.visible = true
		
		# Initialize previous shield position
		previous_shield_pos = initial_shield_pos

func stop_spin():
	spin_count += 1
	if spin_count >= 2:
		dizziness = min(dizziness + POST_SPIN_DIZZ_COST, MAX_DIZZINESS)
		spin_count = 0
	if not Input.is_action_pressed("spin"):
		action_state = ActionState.IDLE
		shield.visible = false
		shield.mass = 0.1
		armature.rotation.y = 0
	else:
		animation_tree.set("parameters/spin/request", true)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	update_life_leafs()
	
	is_rolling = animation_tree.get("parameters/roll/active")
	prev_is_spinning = is_spinning
	is_spinning = animation_tree.get("parameters/spin/active")
	
	if action_state == ActionState.ATTACK:
		attack_timer -= state.step
		if attack_timer <= 0:
			action_state = ActionState.IDLE
			animation_tree.set("parameters/shooting/blend_amount", 0.0)
	
	var current_velocity = state.linear_velocity
	var current_speed = current_velocity.length()
	var speed_factor = 1.0 - (current_speed / MAX_VELOCITY)
	speed_factor = clamp(speed_factor, 0.0, 1.0)
	
	if action_state == ActionState.ROLL and !is_rolling:
		action_state = ActionState.IDLE
		mesh.rotation = Vector3(0, -PI, 0)
	elif prev_is_spinning and !is_spinning:
		stop_spin()
	
	if dizziness > 0:
		dizziness -= SPIN_DIZZ_RESET_SPEED * state.step
		dizziness = max(dizziness, 0)
		transform.basis = transform.basis.rotated(Vector3.FORWARD, -transform.basis.get_euler().x * 0.1)
		transform.basis = transform.basis.rotated(Vector3.RIGHT, -transform.basis.get_euler().z * 0.1)
	
	if Input.is_action_pressed("spin") and action_state != ActionState.ATTACK and not is_rolling:
		if dizziness < MAX_DIZZINESS:
			if not is_spinning:
				action_state = ActionState.SPIN
				is_spinning = true
				spin_timeout = SPIN_RESET_TIME
			if not animation_tree.get("parameters/spin/active"):
				init_shield()
	
	if spin_timeout > 0:
		spin_timeout -= state.step
		if spin_timeout <= 0:
			spin_count = 0
	
	if not lock_rotation:
		state.angular_velocity.x = 0
		state.angular_velocity.z = 0
	
	var input_dir := Input.get_vector("left", "right", "forward", "back")
	var direction = Vector3(input_dir.x, 0, input_dir.y).normalized()
	if not is_spinning:
		direction = direction.rotated(Vector3.UP, spring_arm_pivot.rotation.y)
	
	if action_state == ActionState.ATTACK:
		armature.rotation.y = spring_arm_pivot.rotation.y + PI
		state.apply_central_force(direction * MOVEMENT_FORCE * 0.5)
	elif is_spinning:
		# Apply reduced movement force while spinning
		state.apply_central_force(direction * MOVEMENT_FORCE * 0.2)
		shield_youself()
		# Add damping to prevent excessive speed
		state.linear_velocity *= 0.98
	elif is_rolling:
		roll_timer += state.step
		var roll_progress = roll_timer / ROLL_DURATION
		
		if roll_timer >= ROLL_DURATION:
			roll_timer = 0.0
			action_state = ActionState.IDLE
		
		mesh.rotation = Vector3(roll_progress * (2 * PI), -PI, 0)
		mesh.position = initial_mesh_position + Vector3(0, sin(roll_progress * PI) * 0.3, 0)
		
		var roll_force = roll_direction * ROLL_FORCE
		state.apply_central_force(roll_force)
	else:
		mesh.rotation = Vector3(0, -PI, 0)
		mesh.position = initial_mesh_position
		
		if direction:
			if action_state == ActionState.IDLE:
				action_state = ActionState.WALK
			armature.rotation.y = lerp_angle(armature.rotation.y, atan2(direction.x, direction.z), LERP_VAL)
			state.apply_central_force(direction * MOVEMENT_FORCE)
		else:
			if action_state == ActionState.WALK:
				action_state = ActionState.IDLE
	
	current_velocity = state.linear_velocity
	current_velocity = current_velocity.move_toward(Vector3.ZERO, FRICTION_FORCE * state.step)
	state.linear_velocity = current_velocity
		
	animation_tree.set("parameters/walk/blend_position", current_velocity.length() / MAX_VELOCITY)


func _process(delta):
	collision_left.global_position = arm_bone_left.global_position
	collision_left.global_rotation = arm_bone_left.global_rotation
	collision_right.global_position = arm_bone_right.global_position
	collision_right.global_rotation = arm_bone_right.global_rotation
	update_camera(delta)
	update_hurt_counter(delta)
