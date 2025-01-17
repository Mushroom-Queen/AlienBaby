extends CharacterBody3D

@onready var armature := $player/Armature
@onready var animation_player := $player/AnimationPlayer
@onready var spring_arm_pivot := $SpringArmPivot
@onready var spring_arm := $SpringArmPivot/SpringArm3D
@onready var anim_tree := $AnimationTree

const SPEED = 5.0
const LERP_VAL = .15


var action_state = "walk"

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event):
	if Input.is_action_just_pressed("quit"):
		get_tree().quit()
	if Input.is_action_just_pressed("roll"):
		action_state = "roll"
		anim_tree.set("parameters/roll/request", true)
		 
	if Input.is_action_just_released("roll"):
		action_state = "walk"
	
	if Input.is_action_just_released("attack"):
		anim_tree.set("parameters/shooting/blend_amount", 0.0)
		
	if event is InputEventMouseMotion:
		spring_arm_pivot.rotate_y(-event.relative.x * .005)
		spring_arm.rotate_x(-event.relative.y * .005)
		spring_arm.rotation.x = clamp(spring_arm.rotation.x, -PI/4, PI/4)

func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta
		
		
	if Input.is_action_pressed("attack"):
		if action_state == "walk":
			var lerp_to_1 = lerpf(anim_tree.get("parameters/shooting/blend_amount"), 1.0, get_process_delta_time() * 20)
			anim_tree.set("parameters/shooting/blend_amount", lerp_to_1)

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var input_dir := Input.get_vector("left", "right", "forward", "back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	direction = direction.rotated(Vector3.UP, spring_arm_pivot.rotation.y)
	if direction:
		velocity.x = lerp(velocity.x, direction.x * SPEED, LERP_VAL)
		velocity.z = lerp(velocity.z, direction.z * SPEED, LERP_VAL)
		armature.rotation.y = lerp_angle(armature.rotation.y, atan2(velocity.x, velocity.z), LERP_VAL)
	else:
		velocity.x = lerp(velocity.x, 0.0, LERP_VAL)
		velocity.z = lerp(velocity.z, 0.0, LERP_VAL)
	
	anim_tree.set("parameters/walk/blend_position", velocity.length() / SPEED)

	move_and_slide()
