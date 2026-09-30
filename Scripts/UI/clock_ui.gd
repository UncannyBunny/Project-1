class_name ClockUI extends Control

@export var clock_text: RichTextLabel

func _process(delta: float) -> void:
	var time: int = TimeManager.get_current_time()
	var hours: int = time / 60
	var hours_string: String = "0" + str(hours) if hours < 10 else str(hours)
	var minutes: int = time % 60
	var minutes_string: String = "0" + str(minutes) if minutes < 10 else str(minutes)
	clock_text.text = str(hours_string) + ":" + str(minutes_string)
