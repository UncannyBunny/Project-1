shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

group_uniforms AlbedoAndAlpha;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 top_color_tint : source_color = vec4(0.45, 0.68, 0.28, 1.0);
uniform vec4 bottom_color_tint : source_color = vec4(0.22, 0.36, 0.14, 1.0);
uniform float clump_color_variation : hint_range(0.0, 0.5) = 0.12;
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.45;
uniform float roughness : hint_range(0.0, 1.0) = 0.92;
uniform vec3 backlight_color : source_color = vec3(0.32, 0.48, 0.18);

group_uniforms DistanceFade;
uniform float fade_start_distance : hint_range(1.0, 200.0) = 35.0;
uniform float fade_end_distance : hint_range(1.0, 250.0) = 50.0;

group_uniforms WindSyncWithTrees;
uniform vec2 wind_direction = vec2(1.0, 0.4);
uniform float wind_speed : hint_range(0.0, 10.0) = 1.8;
uniform float wind_strength : hint_range(0.0, 1.5) = 0.28;
uniform float gust_turbulence : hint_range(0.0, 1.0) = 0.10;

varying float v_height_mask;
varying float v_random_tint;

void vertex() {
	// 1. Per-Instance Distance Fade (calculated from Camera to this specific blade's world origin)
	vec3 instance_world_origin = MODEL_MATRIX[3].xyz;
	vec3 camera_world_pos = INV_VIEW_MATRIX[3].xyz;
	float cam_dist = distance(instance_world_origin, camera_world_pos);
	float dist_scale = 1.0 - smoothstep(fade_start_distance, max(fade_end_distance, fade_start_distance + 0.01), cam_dist);

	if (dist_scale <= 0.001) {
		// Collapse triangle to a single point so the GPU skips rasterizing distant blades completely
		VERTEX = vec3(0.0);
	} else {
		// 2. Rotate Plane B (COLOR.r > 0.5) by the randomized cross-plane angle stored in INSTANCE_CUSTOM.a
		if (COLOR.r > 0.5) {
			float angle = INSTANCE_CUSTOM.a;
			float s = sin(angle);
			float c = cos(angle);
			VERTEX.xz = mat2(vec2(c, -s), vec2(s, c)) * VERTEX.xz;
		}

		// Scale vertex down smoothly as it approaches fade_end_distance
		VERTEX *= dist_scale;

		// UV.y = 1.0 at the ground root, UV.y = 0.0 at the top tip of the grass
		v_height_mask = clamp(1.0 - UV.y, 0.0, 1.0);
		v_random_tint = INSTANCE_CUSTOM.r;
		float random_phase = INSTANCE_CUSTOM.g * 6.28318;

		// 3. Synchronized World-Space Wind
		vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec2 dir = normalize(wind_direction + vec2(0.0001));

		float main_phase = dot(world_pos.xz, dir) * 0.25 + TIME * wind_speed;
		float main_wave = sin(main_phase) + cos(main_phase * 0.57) * 0.5;

		float flutter = sin(TIME * (wind_speed * 2.4) + random_phase + dot(world_pos.xz, vec2(1.7, 2.3)));

		float bend_weight = v_height_mask * v_height_mask;
		vec2 world_wind_xz = dir * (main_wave * wind_strength + flutter * gust_turbulence) * bend_weight * dist_scale;

		vec3 world_offset = vec3(world_wind_xz.x, -abs(main_wave) * wind_strength * 0.15 * bend_weight * dist_scale, world_wind_xz.y);
		vec3 local_offset = (inverse(MODEL_MATRIX) * vec4(world_offset, 0.0)).xyz;

		VERTEX += local_offset;

		// Force vertex normal straight up in world space so cross-planes never have dark shadow seams!
		NORMAL = normalize((inverse(MODEL_MATRIX) * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	}
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;

	// Blend from root color to sunlit tip color
	vec3 gradient_tint = mix(bottom_color_tint.rgb, top_color_tint.rgb, v_height_mask);
	float var_shift = 1.0 + (v_random_tint - 0.5) * clump_color_variation * 2.0;

	ALBEDO = tex.rgb * gradient_tint * var_shift;
	ROUGHNESS = roughness;
	BACKLIGHT = backlight_color;
}