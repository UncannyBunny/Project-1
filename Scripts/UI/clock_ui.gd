class_name ClockUI extends Control

@export var clock_display: Control
@export var clock_text: RichTextLabel
@export var clock_input_display: Control
@export var clock_input_display_text: RichTextLabel
@export var clock_input_hour: Button
@export var clock_input_minute: Button
var target_time: int

func _ready() -> void:
	clock_input_hour.pressed.connect(hour_changed)
	clock_input_minute.pressed.connect(minute_changed)
	target_time = TimeManager._day_start

func _process(delta: float) -> void:
	clock_update()
	if clock_input_display.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func clock_update() -> void:
	clock_text.text = TimeManager.time_as_string(TimeManager.get_current_time())
	if clock_input_display.visible:
		clock_input_display_text.text = TimeManager.time_as_string(target_time)

func hour_changed() -> void:
	var time: Vector2i = TimeManager.time_as_vector(target_time)
	if time.x + 1 <= TimeManager.time_as_vector(TimeManager._day_end).x - 1:
		time.x += 1
	else:
		time.x = TimeManager.time_as_vector(TimeManager._day_start).x
	target_time = TimeManager.time_from_vector(time)

func minute_changed() -> void:
	var time: Vector2i = TimeManager.time_as_vector(target_time)
	if time.y + 5 < 60:
		time.y += 5
	else:
		time.y = TimeManager.time_as_vector(TimeManager._day_start).y
	target_time = TimeManager.time_from_vector(time)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("menu_clock"):
		clock_input_display.visible = not clock_input_display.visible
		if not clock_input_display.visible:
			TimeManager.set_day_start(target_time)

func _close_ui() -> void:
	clock_input_display.visible = false
