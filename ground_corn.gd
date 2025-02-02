extends Node3D
var corn
var corn_field = []


var radius_start = 10.0  # Starting radius of first circle
var row_spacing = .5   # Space between each circular row
var num_rows = 2       # Number of circular rows
var corn_per_row = 190   # Number of corn plants per row

# Variation settings
var height_min = 0.8    # Minimum height multiplier
var height_max = 1.2    # Maximum height multiplier
var tilt_max = 0.2      # Maximum tilt 

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	corn = preload("res://corn_import.tscn")
	spawn_corn_field()

# Spawns corn in concentric circles
func spawn_corn_field() -> void:
	for row in range(num_rows):
		var current_radius = radius_start + (row * row_spacing)
		var angle_step = (2 * PI) / corn_per_row
		
		for i in range(corn_per_row):
			var angle = i * angle_step
			var x = current_radius * cos(angle)
			var z = current_radius * sin(angle)
			
			var corn_instance = corn.instantiate()
			add_child(corn_instance)
			corn_instance.position = Vector3(x, 0, z)
			
			var mesh = corn_instance.find_child("mesh")
			var corn1 = mesh.find_child("corn1")
			var corn2 = mesh.find_child("corn2")
			var corn3 = mesh.find_child("corn3")
			if randi_range(1,10) < 8:
				corn1.visible = false
			if randi_range(1,10) < 8:
				corn2.visible = false
			if randi_range(1,10) < 8:
				corn3.visible = false
			# Random rotation around Y axis
			mesh.rotation.y = randf_range(0, PI * 2)
			
			# Random tilt in X and Z axes
			mesh.rotation.x = randf_range(-tilt_max, tilt_max)
			mesh.rotation.z = randf_range(-tilt_max, tilt_max)
			
			# Random height scale only
			var height = randf_range(height_min, height_max)
			mesh.scale = Vector3(1, height, 1)
			
			corn_field.append(corn_instance)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
