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
const SPIN_DIZZ_COST = 1.5
const SPIN_DIZZ_RESET_SPEED = 0.6
const DIZZY_SWAY_SPEED = 2.0
const DIZZY_SWAY_INTENSITY = 0.2
const DIZZY_POSITION_INTENSITY = 0.05
const LERP_VAL = .15

enum ActionState {IDLE, WALK, ROLL, ATTACK, SPIN}

var life = 4
var life_rendered = 4
var dizziness = 0
var action_state = ActionState.IDLE
var is_rolling = false
var is_spinning = false
var roll_direction = Vector3.ZERO
var roll_timer = 0.0
var initial_mesh_position = Vector3.ZERO
var spin_rotation = 0.0
var prev_is_spinning = false
var dizzy_time = 0.0
var camera_original_position: Vector3
var camera_original_rotation: Vector3

func _ready():
	lock_rotation = true
	freeze = false
	contact_monitor = true
	linear_damp = 1.0
	animation_tree.active = true
	
	spring_arm.add_excluded_object(self)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	mesh.rotation = Vector3(0, -PI, 0)
	initial_mesh_position = mesh.position
	camera_original_position = spring_arm.position
	camera_original_rotation = spring_arm.rotation

func update_life_leafs():
	if life != life_rendered:
		life_rendered = life
		leaf1.visible = life >= 4
		leaf2.visible = life >= 3
		leaf3.visible = life >= 2
		leaf4.visible = life >= 1

func update_camera(delta: float) -> void:
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

func _unhandled_input(event):
	if Input.is_action_just_pressed("quit"):
		get_tree().quit()
	
	if Input.is_action_pressed("zoom_in"):
		spring_arm.spring_length = clamp(spring_arm.spring_length + .1, MIN_ZOOM, MAX_ZOOM)
	
	if Input.is_action_pressed("zoom_out"):
		spring_arm.spring_length = clamp(spring_arm.spring_length - .1, MIN_ZOOM, MAX_ZOOM)
	
	if Input.is_action_just_pressed("roll") and action_state not in [ActionState.ATTACK, ActionState.SPIN]:
		var input_dir := Input.get_vector("left", "right", "forward", "back")
		roll_direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		roll_direction = roll_direction.rotated(Vector3.UP, spring_arm_pivot.rotation.y)
		
		if roll_direction.length() > 0.1:
			action_state = ActionState.ROLL
			roll_timer = 0.0
			animation_tree.set("parameters/roll/request", true)
	
	if Input.is_action_just_pressed("attack") and action_state != ActionState.SPIN:
		action_state = ActionState.ATTACK
		laser.start_firing()
	
	if Input.is_action_just_released("attack") and action_state == ActionState.ATTACK:
		action_state = ActionState.IDLE
		animation_tree.set("parameters/shooting/blend_amount", 0.0)
		laser.stop_firing()
	
	if event is InputEventMouseMotion:
		spring_arm_pivot.rotate_y(-event.relative.x * .005)
		spring_arm.rotate_x(-event.relative.y * .005)
		spring_arm.rotation.x = clamp(spring_arm.rotation.x, -PI/3, PI/3)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	update_life_leafs()
	
	is_rolling = animation_tree.get("parameters/roll/active")
	prev_is_spinning = is_spinning
	is_spinning = animation_tree.get("parameters/spin/active")
	
	var current_velocity = state.linear_velocity
	var current_speed = current_velocity.length()
	var speed_factor = 1.0 - (current_speed / MAX_VELOCITY)
	speed_factor = clamp(speed_factor, 0.0, 1.0)
	
	if action_state == ActionState.ROLL and !is_rolling:
		action_state = ActionState.IDLE
		mesh.rotation = Vector3(0, -PI, 0)
	elif prev_is_spinning and !is_spinning:
		action_state = ActionState.IDLE
		mesh.rotation = Vector3(0, -PI, 0)
	
	if dizziness > 0:
		leaf_piv.rotate_y(state.step * dizziness * 5)
		dizziness -= SPIN_DIZZ_RESET_SPEED * state.step
		dizziness = max(dizziness, 0)
	
	if Input.is_action_pressed("spin") and action_state != ActionState.ATTACK and not is_rolling:
		if dizziness < MAX_DIZZINESS:
			if not is_spinning:
				action_state = ActionState.SPIN
				is_spinning = true
				spin_rotation = 0.0
			if not animation_tree.get("parameters/spin/active"):
				dizziness += SPIN_DIZZ_COST
				animation_tree.set("parameters/spin/request", true)
	
	var input_dir := Input.get_vector("left", "right", "forward", "back")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	direction = direction.rotated(Vector3.UP, spring_arm_pivot.rotation.y)
	
	if action_state == ActionState.ATTACK:
		var lerp_to_1 = lerpf(animation_tree.get("parameters/shooting/blend_amount"), 1.0, state.step * 20)
		animation_tree.set("parameters/shooting/blend_amount", lerp_to_1)
		armature.rotation.y = spring_arm_pivot.rotation.y
		state.apply_central_force(direction * MOVEMENT_FORCE * 0.5)
	elif is_spinning:
		spin_rotation += PI * 2 * state.step
		armature.rotation.y = spin_rotation
		state.apply_central_force(direction * MOVEMENT_FORCE * 0.2)
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
	
	# Print debug info
	print("Action State:", ActionState.keys()[action_state], 
		  " Velocity:", current_velocity.length(), 
		  " Speed:", current_velocity.length() / MAX_VELOCITY)
		
	animation_tree.set("parameters/walk/blend_position", current_velocity.length() / MAX_VELOCITY)

func _process(delta):
	collision_left.global_position = arm_bone_left.global_position
	collision_left.global_rotation = arm_bone_left.global_rotation
	collision_right.global_position = arm_bone_right.global_position
	collision_right.global_rotation = arm_bone_right.global_rotation
	update_camera(delta)
