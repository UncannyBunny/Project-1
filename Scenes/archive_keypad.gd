
extends ReadableComponent

@export var correct_code: String = "4826"

func _ready() -> void:
	# Creamos el teclado
	var keypad := ReadableEntry.new()
	keypad.input_type = ReadableEntry.InputType.KEYPAD

	# Creamos la respuesta correcta
	var success := ReadableEntry.new()
	success.readable_text = "Access granted."
	success.keys_unlocked = [&"archive_access"]

	# Conectamos el codigo con la respuesta
	keypad.readable_chain[correct_code] = success

	# Registramos el teclado
	entries.clear()
	entries.append(keypad)

	super._ready()
