shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

group_uniforms AlbedoAndAlpha;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 top_color_tint : source_color = vec4(0.45, 0.68, 0.28, 1.0);
uniform vec4 bottom_color_tint : source_color = vec4(0.18, 0.30, 0.12, 1.0);
uniform float clump_color_variation : hint_range(0.0, 0.5) = 0.12;
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.45;
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
uniform vec3 backlight_color : source_color = vec3(0.25, 0.38, 0.12);

group_uniforms WindSyncWithTrees;
uniform vec2 wind_direction = vec2(1.0, 0.4);
uniform float wind_speed : hint_range(0.0, 10.0) = 1.8;
uniform float wind_strength : hint_range(0.0, 1.5) = 0.28;
uniform float gust_turbulence : hint_range(0.0, 1.0) = 0.10;

varying float v_height_mask;
varying float v_random_tint;

void vertex() {
	// UV.y = 1.0 at the ground root, UV.y = 0.0 at the top tip of the grass
	v_height_mask = clamp(1.0 - UV.y, 0.0, 1.0);
	v_random_tint = INSTANCE_CUSTOM.r;
	float random_phase = INSTANCE_CUSTOM.g * 6.28318;

	// World-space position of this vertex for synchronized wind waves across the map
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 dir = normalize(wind_direction + vec2(0.0001));

	// Main traveling wind wave (matches tree wind wave direction & spatial frequency)
	float main_phase = dot(world_pos.xz, dir) * 0.25 + TIME * wind_speed;
	float main_wave = sin(main_phase) + cos(main_phase * 0.57) * 0.5;

	// Local blade flutter so neighboring clumps have organic micro-motion
	float flutter = sin(TIME * (wind_speed * 2.4) + random_phase + dot(world_pos.xz, vec2(1.7, 2.3)));

	// Quadratic bend mask keeps the base (UV.y = 1.0) strictly planted in the dirt
	float bend_weight = v_height_mask * v_height_mask;
	vec2 world_wind_xz = dir * (main_wave * wind_strength + flutter * gust_turbulence) * bend_weight;

	// Convert world XZ displacement back into the clump's local space
	vec3 world_offset = vec3(world_wind_xz.x, -abs(main_wave) * wind_strength * 0.15 * bend_weight, world_wind_xz.y);
	vec3 local_offset = (inverse(MODEL_MATRIX) * vec4(world_offset, 0.0)).xyz;

	VERTEX += local_offset;

	// Keep normal pointing upward in model space for soft, seam-free ground shading
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;

	// Blend from darker root color (AO) at the bottom to lighter sunlit color at the tips
	vec3 gradient_tint = mix(bottom_color_tint.rgb, top_color_tint.rgb, v_height_mask);
	// Apply subtle per-clump brightness/hue shift
	float var_shift = 1.0 + (v_random_tint - 0.5) * clump_color_variation * 2.0;

	ALBEDO = tex.rgb * gradient_tint * var_shift;
	ROUGHNESS = roughness;
	BACKLIGHT = backlight_color;
}