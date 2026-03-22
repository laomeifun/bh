extends Control

## Black Hole shader controller
## Passes resolution and mouse position to the Buffer A shader uniforms

@onready var buffer_a: ColorRect = $BufferA

func _ready() -> void:
	_update_resolution()

func _process(_delta: float) -> void:
	_update_resolution()

func _update_resolution() -> void:
	var viewport_size := get_viewport_rect().size
	var mat := buffer_a.material as ShaderMaterial
	mat.set_shader_parameter("resolution", viewport_size)

func _input(event: InputEvent) -> void:
	var mat := buffer_a.material as ShaderMaterial
	if event is InputEventMouseMotion:
		var viewport_size := get_viewport_rect().size
		var normalized := Vector2(
			event.position.x / viewport_size.x,
			1.0 - event.position.y / viewport_size.y  # flip Y for shader
		)
		mat.set_shader_parameter("mouse_pos", normalized)

	if event is InputEventMouseButton:
		mat.set_shader_parameter("mouse_pressed", event.pressed)
