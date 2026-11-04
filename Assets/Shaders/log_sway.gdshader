shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.9;

group_uniforms TrunkSwaySync;
uniform float tree_height : hint_range(1.0, 30.0) = 8.0;
uniform vec2 wind_direction = vec2(1.0, 0.4);
uniform float trunk_sway_speed : hint_range(0.0, 5.0) = 1.2;
uniform float trunk_sway_strength : hint_range(0.0, 2.0) = 0.25;

vec3 get_trunk_sway(vec3 local_pos, vec3 world_origin, float time) {
	vec2 dir = normalize(wind_direction + vec2(0.0001));
	float height_factor = clamp(local_pos.y / max(tree_height, 0.01), 0.0, 1.0);
	float bend_mask = height_factor * height_factor;
	
	float phase = dot(world_origin.xz, dir) * 0.25 + time * trunk_sway_speed;
	float wave = sin(phase) + cos(phase * 0.57) * 0.4;
	
	vec3 offset = vec3(0.0);
	offset.xz = dir * wave * trunk_sway_strength * bend_mask;
	offset.y = -abs(wave) * trunk_sway_strength * 0.12 * bend_mask;
	return offset;
}

void vertex() {
	vec3 world_origin = MODEL_MATRIX[3].xyz;
	VERTEX += get_trunk_sway(VERTEX, world_origin, TIME);
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV) * albedo_tint;
	ALBEDO = tex.rgb;
	ROUGHNESS = roughness;
}