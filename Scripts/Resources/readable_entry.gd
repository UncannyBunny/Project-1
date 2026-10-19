## Resource defining a dialogue node or readable note entry, including branching choices and key conditions.
class_name ReadableEntry extends Resource

enum InputType {
	BUTTONS,
	TEXT,
	KEYPAD
}

@export_group("Content")
## Higher priority entries are chosen first when multiple entries are valid
@export var priority: int = 0
## Characters revealed per second during the text animation
@export var text_speed: float = 15.0
## Text displayed in the dialogue box
@export_multiline var readable_text: String = ""
## Determines whether this entry uses choice buttons, a LineEdit text box, or the 4-digit keypad
@export var input_type: InputType = InputType.BUTTONS
## Response options where the key is the button text, text password, or 4-digit code and the value is the next ReadableEntry
@export var readable_chain: Dictionary[String, ReadableEntry] = {}

@export_group("Key Conditions & Effects")
## Keys required to display this entry
@export var key_whitelist: Array[StringName] = []
## Keys that block this entry from being displayed
@export var key_blacklist: Array[StringName] = []
## Keys unlocked when this entry is displayed
@export var keys_unlocked: Array[StringName] = []
## Keys removed when this entry is displayed
@export var keys_taken: Array[StringName] = []

@export_group("Presentation Hooks")
## Optional voice blip or sound effect played when this dialogue node starts
@export var dialogue_audio: AudioStream
## Optional curve defining the pitch/modulation profile for NPC voice playback
@export var npc_voice_profile: Curve
## Optional animation name to trigger on the speaker when this entry is read
@export var speaker_animation: StringName = &""
