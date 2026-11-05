@tool
## Resource defining a roadside decoration's model/scene, min/avg spawn frequency, offsets, and overlap radius.
class_name PathDecorationEntry extends Resource

enum PlacementSide {
	RIGHT,
	LEFT,
	BOTH_SYMMETRIC,
	BOTH_ALTERNATING,
	RANDOM_SIDE
}

@export_group("Model or Scene")
## Optional PackedScene to instantiate (use for prefabs with scripts/lights/colliders like poles or signs)
@export var decoration_scene: PackedScene
## Optional Mesh to instantiate as a MeshInstance3D (if decoration_scene is left empty)
@export var decoration_mesh: Mesh
## Optional material override when using decoration_mesh
@export var mesh_material_override: Material

@export_group("Frequency & Clearance")
## X = Minimum distance (m) between spawns, Y = Average distance (m) between spawns. Set X == Y for exact fixed intervals.
@export var frequency_distance: Vector2 = Vector2(12.0, 15.0)
## Distance from the start of the path before the first instance of this decoration can spawn
@export_range(0.0, 200.0, 0.5) var start_offset: float = 2.0
## Distance from the end of the path where this decoration stops spawning
@export_range(0.0, 200.0, 0.5) var end_margin: float = 2.0
## Minimum physical radius around this object where no other decoration is allowed to spawn
@export_range(0.1, 30.0, 0.1) var clearance_radius: float = 1.5
## If blocked by another decoration, how far (in meters) along the path it may nudge forward/back to find a free spot (0 = skip instead)
@export_range(0.0, 10.0, 0.25) var max_overlap_nudge: float = 2.0

@export_group("Placement & Offsets")
@export var side: PlacementSide = PlacementSide.RIGHT
## Lateral distance in meters from the center of the path (positive = outward from center)
@export var lateral_offset: float = 4.0
## Random +/- jitter added to lateral_offset
@export_range(0.0, 10.0, 0.05) var lateral_jitter: float = 0.0
## Vertical offset in meters from the ground/curve hit point
@export var vertical_offset: float = 0.0
## Base Y rotation offset in degrees relative to the path's forward direction
@export var yaw_offset_degrees: float = 0.0
## If true, items on the LEFT side are rotated 180 degrees so they still face inward toward the road
@export var mirror_yaw_on_left_side: bool = true
## Random +/- yaw jitter in degrees
@export_range(0.0, 180.0, 1.0) var random_yaw_jitter_degrees: float = 0.0
## Random uniform scale range (1.0, 1.0 = no scale variation)
@export var scale_range: Vector2 = Vector2(1.0, 1.0)

@export_group("Terrain Alignment")
## Raycasts down at the decoration's world XZ position so it snaps to the ground height
@export var snap_to_terrain: bool = true
## Tilts the decoration to match the ground slope normal (0 = strictly upright, 1 = perpendicular to slope)
@export_range(0.0, 1.0, 0.05) var align_to_slope_factor: float = 0.0
