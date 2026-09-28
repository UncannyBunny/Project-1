class_name ReadableComponent extends Node3D

## Signal to notify the UI or other systems
signal on_read(text: String)

## The text content of the readable object
@export_multiline var clue_text: String = ""

## Method that will be called when interacting
func interact() -> void:
	# Emit the signal with the text content
	on_read.emit(clue_text)
	
	# Temporary debug print for testing purposes
	print("Read text: ", clue_text)
