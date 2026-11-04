shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

group_uniforms AlbedoAndAlpha;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.5;
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform vec3 backlight_color : source_color = vec3(0.25, 0.35, 0.15);

group_uniforms TrunkSwaySync;
uniform float tree_height : hint_range(1.0, 30.0) = 8.0;
uniform vec2 wind_direction = vec2(1.0, 0.4);
uniform float trunk_sway_speed : hint_range(0.0, 5.0) = 1.2;
uniform float trunk_sway_strength : hint_range(0.0, 2.0) = 0.25;

group_uniforms BranchFlutter;
uniform float branch_sway_strength : hint_range(0.0, 2.0) = 0.35;
uniform float branch_sway_speed : hint_range(0.0, 10.0) = 2.6;
uniform float leaf_flutter_strength : hint_range(0.0, 0.5) = 0.08;
uniform float leaf_flutter_speed : hint_range(0.0, 15.0) = 6.0;

// Shared trunk displacement so branch bases stay glued to the swaying trunk
vec3 get_trunk_sway(vec3 local_pos, vec3 world_origin, float time) {
	vec2 dir = normalize(wind_direction + vec2(0.0001));
	float height_factor = clamp(local_pos.y / max(tree_height, 0.01), 0.0, 1.0);
	// Quadratic bend so the bottom of the trunk stays rooted
	float bend_mask = height_factor * height_factor;
	
	float phase = dot(world_origin.xz, dir) * 0.25 + time * trunk_sway_speed;
	float wave = sin(phase) + cos(phase * 0.57) * 0.4;
	
	vec3 offset = vec3(0.0);
	offset.xz = dir * wave * trunk_sway_strength * bend_mask;
	// Slight vertical dip when bending far to preserve trunk length
	offset.y = -abs(wave) * trunk_sway_strength * 0.12 * bend_mask;
	return offset;
}

void vertex() {
	vec3 world_origin = MODEL_MATRIX[3].xyz;
	vec3 world_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	// 1. Base sway from the trunk at this vertex's height
	vec3 total_offset = get_trunk_sway(VERTEX, world_origin, TIME);
	
	// 2. Branch tip weight: UV.y = 1.0 at trunk (0 weight), UV.y = 0.0 at outer tip (1 weight)
	float tip_weight = clamp(1.0 - UV.y, 0.0, 1.0);
	float edge_weight = abs(UV.x - 0.5) * 2.0; // 0 at center stem, 1 at left/right leaf edges
	
	// Unique spatial phase per branch so all branches don't move in robotic unison
	float branch_phase = dot(world_vertex, vec3(0.73, 1.13, 0.53)) + TIME * branch_sway_speed;
	vec2 dir = normalize(wind_direction + vec2(0.0001));
	
	// Primary up/down + horizontal branch bobbing at the tip
	float tip_wave = sin(branch_phase);
	float tip_bob = cos(branch_phase * 1.35);
	total_offset.xz += dir * tip_wave * branch_sway_strength * (tip_weight * tip_weight);
	total_offset.y += tip_bob * branch_sway_strength * 0.65 * (tip_weight * tip_weight);
	
	// Secondary rapid flutter along the outer leaf edges
	float flutter = sin(TIME * leaf_flutter_speed + dot(world_vertex, vec3(3.1, 2.7, 3.5)));
	total_offset += NORMAL * flutter * leaf_flutter_strength * tip_weight * edge_weight;
	
	VERTEX += total_offset;
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV) * albedo_tint;
	ALBEDO = tex.rgb;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;
	ROUGHNESS = roughness;
	BACKLIGHT = backlight_color;
	
	// Flip normal when viewed from below so the underside of the branch plane catches light properly
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}