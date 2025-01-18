extends Node3D

@onready var ray := $RayCast3D
@onready var mesh := $MeshInstance3D
var is_firing := false
var world: Node
var player: CharacterBody3D
var camera: Camera3D
const PROJECTILE_SPEED := 50.0  # Adjust this for laser speed
const MAX_PROJECTILE_LIFETIME := 2.0  # Seconds before deletion
const SEGMENT_SPACING := 1.0  # Distance between segments

# Store active projectiles as an array of arrays (each inner array is a laser beam)
var laser_beams := []

func _ready():
	var root = get_tree().root
	world = find_world(root)
	if world:
		player = world.get_node_or_null("player")
		if player:
			camera = player.get_node_or_null("SpringArmPivot/SpringArm3D/Camera3D")
			if camera:
				ray.add_exception(player)
	# Hide the original mesh - we'll use it as a template
	mesh.visible = false

func find_world(node: Node) -> Node:
	if node.name.to_lower() == "world":
		return node
	for child in node.get_children():
		var found = find_world(child)
		if found:
			return found
	return null

func start_firing():
	is_firing = true
	spawn_laser_beam()
	
func stop_firing():
	is_firing = false

func spawn_laser_beam():
	var segments = []
	var num_segments = 5  # Number of segments in each laser beam
	var direction = -camera.global_transform.basis.z
	
	for i in range(num_segments):
		# Duplicate the template mesh
		var segment = mesh.duplicate() as MeshInstance3D
		segment.visible = true
		
		# Set initial transform
		segment.global_position = global_position + (direction * i * SEGMENT_SPACING)
		segment.global_transform.basis = camera.global_transform.basis
		
		# Store segment index
		segment.set_meta("segment_index", i)
		
		# Add to scene
		add_child(segment)
		segments.append(segment)
	
	# Store creation time and initial direction for the beam
	var beam_data = {
		"segments": segments,
		"spawn_time": Time.get_unix_time_from_system(),
		"direction": direction
	}
	
	laser_beams.append(beam_data)

func _physics_process(delta: float) -> void:
	if not camera or not is_instance_valid(camera):
		return
	
	# Spawn new laser beams while firing
	if is_firing:
		spawn_laser_beam()
	
	# Update existing laser beams
	var current_time = Time.get_unix_time_from_system()
	var expired_beams = []
	
	for beam in laser_beams:
		var segments = beam["segments"]
		var direction = beam["direction"]
		
		for i in range(segments.size()):
			var segment = segments[i]
			
			# Move segment
			segment.global_position += direction * PROJECTILE_SPEED * delta
			
			# Make segment look at the next segment (except for the last one)
			if i < segments.size() - 1:
				var next_segment = segments[i + 1]
				var look_at_pos = next_segment.global_position
				
				# Look at next segment using camera's up vector for consistent orientation
				var up_vector = camera.global_transform.basis.y
				segment.look_at_from_position(segment.global_position, look_at_pos, up_vector)
				# Rotate to align with beam direction
				segment.rotate_object_local(Vector3.RIGHT, PI/2)
			else:
				# Last segment maintains original direction
				segment.global_transform.basis = camera.global_transform.basis
				segment.rotate_object_local(Vector3.RIGHT, PI/2)
		
		# Check lifetime
		var age = current_time - beam["spawn_time"]
		if age >= MAX_PROJECTILE_LIFETIME:
			expired_beams.append(beam)
	
	# Remove expired beams
	for beam in expired_beams:
		laser_beams.erase(beam)
		for segment in beam["segments"]:
			segment.queue_free()
