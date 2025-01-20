extends Node3D

@onready var core = $core
@onready var rim = $core/joint/rim
@onready var joint = $core/joint

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	rim.angular_velocity.y = 1



func _physics_process(delta: float) -> void:
	core.rotation = core.rotation.lerp(Vector3(0,0,0), delta)
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
