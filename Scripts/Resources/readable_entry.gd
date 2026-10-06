class_name ReadableEntry extends Resource
 
## The priority of the entry, if multiple entries overlap the one with the highest priority should be picked.
@export var priority: int
## Time in multiplier for the text animation
@export var text_speed: float = 15
## The text content of the entry
@export_multiline var readable_text: String
## If true, a response box will be used
@export var has_input: bool = false
## The keys required to be able to trigger the entry
@export var key_whitelist: Array[String]
@export var key_blacklist: Array[String]
## The keys unlocked by triggering the entry
@export var keys_unlocked: Array[String]
## The keys lost by triggering the entry
@export var keys_taken: Array[String]
## The response options for the entry, where the key is the response and the nested entry the next readable
@export var readable_chain: Dictionary[String, ReadableEntry]
