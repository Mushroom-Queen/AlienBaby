extends CharacterBody3D

@onready var armature := $player/Armature
@onready var animation_player := $player/AnimationPlayer
@onready var spring_arm_pivot := $SpringArmPivot
@onready var spring_arm := $SpringArmPivot/SpringArm3D
@onready var animation_tree := $AnimationTree
@onready var mesh := $player/Armature/Skeleton3D
@onready var leaf_bone = $player/Armature/Skeleton3D/leafs
@onready var leaf1 = $player/Armature/Skeleton3D/leafs/leaf1
@onready var leaf2 = $player/Armature/Skeleton3D/leafs/leaf2
@onready var leaf3 = $player/Armature/Skeleton3D/leafs/leaf3
@onready var leaf4 = $player/Armature/Skeleton3D/leafs/leaf4

const ROLL_SPEED = 5.5
const SPEED = 5.0
const LERP_VAL = .15
const ROLL_ROTATION_SPEED = 10.0
const ROLL_HEIGHT = 3
const SPIN_ROTATION_SPEED = 15.0
const ROLL_DURATION = 0.4  # Fixed duration for roll in seconds

enum ActionState {IDLE, WALK, ROLL, ATTACK, SPIN}

var life = 4
var life_rendered = 4
var action_state = ActionState.IDLE
var is_rolling = false
var is_spinning = false
var roll_direction = Vector3.ZERO
var initial_roll_rotation = 0.0
var roll_timer = 0.0
var initial_mesh_position = Vector3.ZERO
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
			roll_timer = 0.0
			animation_tree.set("parameters/roll/request", true)
	
	if Input.is_action_just_pressed("attack") and action_state != ActionState.SPIN:
		action_state = ActionState.ATTACK
	
	if Input.is_action_just_released("attack"):
		if action_state == ActionState.ATTACK:
			action_state = ActionState.IDLE
			animation_tree.set("parameters/shooting/blend_amount", 0.0)
	
	if event is InputEventMouseMotion:
		spring_arm_pivot.rotate_y(-event.relative.x * .005)
		spring_arm.rotate_x(-event.relative.y * .005)
		spring_arm.rotation.x = clamp(spring_arm.rotation.x, -PI/4, PI/4)

func update_life_leafs():
	if life != life_rendered:
		life_rendered = life
		if life == 4:
			leaf1.visible = true
			leaf2.visible = true
			leaf3.visible = true
			leaf4.visable = true
		if life == 3:
			leaf1.visible = false
			leaf2.visible = true
			leaf3.visible = true
			leaf4.visable = true
		if life == 2:
			leaf1.visible = false
			leaf2.visible = false
			leaf3.visible = true
			leaf4.visable = true
		if life == 1:
			leaf1.visible = false
			leaf2.visible = false
			leaf3.visible = false
			leaf4.visable = true
		if life == 0:
			leaf1.visible = false
			leaf2.visible = false
			leaf3.visible = false
			leaf4.visable = false

func _physics_process(delta: float) -> void:
	update_life_leafs()
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
			direction = roll_direction * ROLL_SPEED
			armature.rotation.y = initial_roll_rotation
			roll_timer += delta
			
			var roll_progress = roll_timer / ROLL_DURATION
			var rotation_angle = roll_progress * (2 * PI)
			
			if roll_timer >= ROLL_DURATION:
				roll_timer = 0.0
				mesh.rotation = Vector3(0, -PI, 0)
				mesh.position = initial_mesh_position
				action_state = ActionState.IDLE
			else:
				mesh.rotation = Vector3(rotation_angle, -PI, 0)
				var height_offset = sin(roll_progress * PI) * ROLL_HEIGHT
				mesh.position = initial_mesh_position + Vector3(0, height_offset, 0)
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
				target_speed = ROLL_SPEED
				
			velocity.x = lerp(velocity.x, direction.x * target_speed, LERP_VAL)
			velocity.z = lerp(velocity.z, direction.z * target_speed, LERP_VAL)
		else:
			velocity.x = lerp(velocity.x, 0.0, LERP_VAL)
			velocity.z = lerp(velocity.z, 0.0, LERP_VAL)
	
	animation_tree.set("parameters/walk/blend_position", velocity.length() / SPEED)
	move_and_slide()
