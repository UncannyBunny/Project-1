class_name ScoreComponent extends Node

## Signal emitted when the score changes (useful for updating UI or triggering events)
signal score_changed(new_score: int)

## The current score or value stored
@export var current_score: int = 0

## Increments the score by the given amount
func increment(amount: int = 1) -> void:
	current_score += amount
	score_changed.emit(current_score)
	# print("Score incremented to: ", current_score) # Uncomment for debugging

## Decreases the score by the given amount
func decrease(amount: int = 1) -> void:
	current_score -= amount
	score_changed.emit(current_score)
	# print("Score decreased to: ", current_score) # Uncomment for debugging

## Exposes and returns the current score
func get_score() -> int:
	return current_score
