extends CharacterBody3D

@onready var armature := $player/Armature
@onready var animation_player := $player/AnimationPlayer
@onready var spring_arm_pivot := $SpringArmPivot
@onready var spring_arm := $SpringArmPivot/SpringArm3D
@onready var animation_tree := $AnimationTree
@onready var mesh := $player/Armature/Skeleton3D

const ROLL_SPEED = 6.0
const SPEED = 5.0
const LERP_VAL = .15
const ROLL_ROTATION_SPEED = 10.0
const ROLL_HEIGHT = 1.5
const ROLL_SPEED_FALLOFF = 0.5
const SPIN_ROTATION_SPEED = 15.0

enum ActionState {IDLE, WALK, ROLL, ATTACK, SPIN}

var action_state = ActionState.IDLE
var is_rolling = false
var is_spinning = false
var roll_direction = Vector3.ZERO
var initial_roll_rotation = 0.0
var total_roll_rotation = 0.0
var initial_mesh_position = Vector3.ZERO
var current_roll_speed = 0.0
var spin_rotation = 0.0
var prev_is_spinning = false

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	mesh.rotation = Vector3(0, -PI, 0)
	initial_mesh_position = mesh.position

func _unhandled_input(event):
	if Input.is_action_just_pressed("quit"):
		get_tree().quit()
	
	if Input.is_action_just_pressed("spin") and action_state != ActionState.ROLL:
		action_state = ActionState.SPIN
		is_spinning = true
		spin_rotation = 0.0
		animation_tree.set("parameters/spin/request", true)
	
	if Input.is_action_just_pressed("roll") and action_state != ActionState.ATTACK and action_state != ActionState.SPIN:
		var input_dir := Input.get_vector("left", "right", "forward", "back")
		var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		direction = direction.rotated(Vector3.UP, spring_arm_pivot.rotation.y)
		
		if direction.length() > 0.1:
			action_state = ActionState.ROLL
			roll_direction = direction
			armature.rotation.y = atan2(direction.x, direction.z)
			initial_roll_rotation = armature.rotation.y
			total_roll_rotation = 0.0
			current_roll_speed = ROLL_SPEED
			animation_tree.set("parameters/roll/request", true)
	
	if Input.is_action_just_pressed("attack") and action_state != ActionState.SPIN:
		action_state = ActionState.ATTACK
	
	if Input.is_action_just_released("roll"):
		if action_state == ActionState.ROLL:
			action_state = ActionState.IDLE
			roll_direction = Vector3.ZERO
			mesh.rotation = Vector3(0, -PI, 0)
			mesh.position = initial_mesh_position
			current_roll_speed = 0.0
	
	if Input.is_action_just_released("attack"):
		if action_state == ActionState.ATTACK:
			action_state = ActionState.IDLE
			animation_tree.set("parameters/shooting/blend_amount", 0.0)
	
	if event is InputEventMouseMotion:
		spring_arm_pivot.rotate_y(-event.relative.x * .005)
		spring_arm.rotate_x(-event.relative.y * .005)
		spring_arm.rotation.x = clamp(spring_arm.rotation.x, -PI/4, PI/4)

func _physics_process(delta: float) -> void:
	is_rolling = animation_tree.get("parameters/roll/active")
	prev_is_spinning = is_spinning
	is_spinning = animation_tree.get("parameters/spin/active")
	
	if prev_is_spinning and !is_spinning:
		action_state = ActionState.IDLE
	
	if not is_on_floor():
		velocity += get_gravity() * delta
	
	if action_state == ActionState.ATTACK:
		var lerp_to_1 = lerpf(animation_tree.get("parameters/shooting/blend_amount"), 1.0, get_process_delta_time() * 20)
		animation_tree.set("parameters/shooting/blend_amount", lerp_to_1)
	
	var input_dir := Input.get_vector("left", "right", "forward", "back")
	var direction: Vector3
	
	if is_spinning:
		direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		direction = direction.rotated(Vector3.UP, spring_arm_pivot.rotation.y)
		spin_rotation += SPIN_ROTATION_SPEED * delta
		armature.rotation.y = spin_rotation
		
		if direction:
			velocity.x = lerp(velocity.x, direction.x * SPEED * 0.2, LERP_VAL)
			velocity.z = lerp(velocity.z, direction.z * SPEED * 0.2, LERP_VAL)
		else:
			velocity.x = lerp(velocity.x, 0.0, LERP_VAL)
			velocity.z = lerp(velocity.z, 0.0, LERP_VAL)
	else:
		if is_rolling:
			direction = roll_direction * current_roll_speed
			armature.rotation.y = initial_roll_rotation
			total_roll_rotation += ROLL_ROTATION_SPEED * delta
			
			var roll_progress = total_roll_rotation / (2 * PI)
			
			if total_roll_rotation >= 2 * PI:
				total_roll_rotation = 0.0
				mesh.rotation = Vector3(0, -PI, 0)
				mesh.position = initial_mesh_position
				current_roll_speed = 0.0
				action_state = ActionState.IDLE
			else:
				mesh.rotation = Vector3(total_roll_rotation, -PI, 0)
				var height_offset = sin(roll_progress * PI) * ROLL_HEIGHT
				mesh.position = initial_mesh_position + Vector3(0, height_offset, 0)
				
				if roll_progress > 0.6:
					current_roll_speed = lerp(current_roll_speed, SPEED, ROLL_SPEED_FALLOFF * delta)
		else:
			direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
			direction = direction.rotated(Vector3.UP, spring_arm_pivot.rotation.y)
			
			if direction:
				action_state = ActionState.WALK if action_state == ActionState.IDLE else action_state
				armature.rotation.y = lerp_angle(armature.rotation.y, atan2(direction.x, direction.z), LERP_VAL)
			
			mesh.rotation = Vector3(0, -PI, 0)
			mesh.position = initial_mesh_position
		
		if direction:
			var target_speed = SPEED
			if action_state == ActionState.ATTACK:
				target_speed *= 0.5
			elif is_rolling:
				target_speed = current_roll_speed
				
			velocity.x = lerp(velocity.x, direction.x * target_speed, LERP_VAL)
			velocity.z = lerp(velocity.z, direction.z * target_speed, LERP_VAL)
		else:
			velocity.x = lerp(velocity.x, 0.0, LERP_VAL)
			velocity.z = lerp(velocity.z, 0.0, LERP_VAL)
	
	animation_tree.set("parameters/walk/blend_position", velocity.length() / SPEED)
	move_and_slide()
