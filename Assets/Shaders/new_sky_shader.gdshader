// Physical Sky Shader with Anti-Aliased Galactic Stars & Smooth Cumulus Clouds
shader_type sky;
render_mode use_debanding;

group_uniforms Atmosphere;
uniform float rayleigh : hint_range(0, 64) = 2.0;
uniform vec4 rayleigh_color : source_color = vec4(0.3, 0.405, 0.6, 1.0);
uniform float mie : hint_range(0, 1) = 0.005;
uniform float mie_eccentricity : hint_range(-1, 1) = 0.8;
uniform vec4 mie_color : source_color = vec4(0.69, 0.729, 0.812, 1.0);
uniform float turbidity : hint_range(0, 1000) = 10.0;
uniform float sun_disk_scale : hint_range(0, 360) = 4.0;
uniform float sun_glow_intensity : hint_range(0.0, 5.0) = 1.2;
uniform float sun_glow_falloff : hint_range(1.0, 64.0) = 12.0;
uniform vec4 ground_color : source_color = vec4(0.1, 0.07, 0.034, 1.0);
uniform float exposure : hint_range(0, 128) = 1.0;

group_uniforms NightSkyAndStars;
uniform float star_brightness : hint_range(0.0, 10.0) = 2.0;
uniform float star_base_density : hint_range(0.0, 1.0) = 0.14;
uniform float star_scale : hint_range(40.0, 200.0) = 105.0;
uniform float band_width : hint_range(0.05, 1.0) = 0.25;
uniform vec3 band_normal = vec3(0.45, 0.35, 0.82);
uniform vec3 band_glow_color : source_color = vec3(0.06, 0.09, 0.16);
uniform float band_glow_intensity : hint_range(0.0, 2.0) = 0.25;
uniform float star_twinkle_speed : hint_range(0.0, 10.0) = 1.2;

group_uniforms CumulusClouds;
uniform bool clouds_enabled = true;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.48;
uniform float cloud_softness : hint_range(0.01, 0.5) = 0.18;
uniform float cloud_scale : hint_range(0.1, 10.0) = 1.2;
uniform vec2 cloud_speed = vec2(0.012, 0.006);
uniform vec3 cloud_day_color : source_color = vec3(0.96, 0.97, 1.0);
uniform vec3 cloud_shadow_color : source_color = vec3(0.42, 0.47, 0.56);
uniform vec3 cloud_night_color : source_color = vec3(0.04, 0.05, 0.08);

const vec3 UP = vec3(0.0, 1.0, 0.0);
const float rayleigh_zenith_size = 8.4e3;
const float mie_zenith_size = 1.25e3;

float henyey_greenstein(float cos_theta, float g) {
	const float k = 0.0795774715459;
	return k * (1.0 - g * g) / (pow(1.0 + g * g - 2.0 * g * cos_theta, 1.5));
}

// --- Precision-Safe Gradient Noise ---
vec2 hash22(vec2 p) {
	p = mod(p, 289.0);
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy) * 2.0 - 1.0;
}

float gradient_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(
		mix(dot(hash22(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0)),
			dot(hash22(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0)), u.x),
		mix(dot(hash22(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)),
			dot(hash22(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0)), u.x),
		u.y
	) * 0.5 + 0.5;
}

float worley_puff(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float min_dist = 1.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 point = hash22(i + neighbor) * 0.4 + 0.5;
			float d = length(neighbor + point - f);
			min_dist = min(min_dist, d);
		}
	}
	return 1.0 - clamp(min_dist, 0.0, 1.0);
}

float fbm_cumulus(vec2 p) {
	float base_puff = mix(gradient_noise(p), worley_puff(p * 0.85), 0.45);
	float v = base_puff * 0.52;
	float a = 0.26;
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	p = rot * p * 2.02 + vec2(13.7, 29.3);
	
	for (int i = 0; i < 4; i++) {
		v += a * gradient_noise(p);
		p = rot * p * 2.03 + vec2(17.1, 31.4);
		a *= 0.5;
	}
	return v;
}

// --- Anti-Aliased Star Helpers ---
vec3 hash33(vec3 p) {
	p = mod(p, 289.0);
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

vec3 get_star_color(float temp_rand) {
	if (temp_rand < 0.22) {
		return mix(vec3(1.0, 0.52, 0.32), vec3(1.0, 0.84, 0.58), temp_rand / 0.22);
	} else if (temp_rand < 0.68) {
		return mix(vec3(1.0, 0.84, 0.58), vec3(1.0, 0.98, 1.0), (temp_rand - 0.22) / 0.46);
	} else {
		return mix(vec3(1.0, 0.98, 1.0), vec3(0.62, 0.78, 1.0), (temp_rand - 0.68) / 0.32);
	}
}

vec3 compute_stars(vec3 dir, float scale, float band_factor) {
	vec3 p = dir * scale;
	vec3 id = floor(p);
	vec3 f = fract(p) - 0.5;
	vec3 rnd = hash33(id);
	
	float prob = mix(star_base_density * 0.15, star_base_density, band_factor);
	if (rnd.x > prob) {
		return vec3(0.0);
	}
	
	vec3 star_offset = (rnd - 0.5) * 0.40;
	float dist = length(f - star_offset);
	
	// Screen-space derivative padding prevents sub-pixel shimmering when camera moves
	float aa_pad = clamp(fwidth(dist) * 1.5, 0.02, 0.12);
	float radius = mix(0.18, 0.30, rnd.y) + aa_pad;
	float star = smoothstep(radius, radius * 0.15, dist);
	
	float twinkle = 0.90 + 0.10 * sin(TIME * star_twinkle_speed + rnd.z * 62.83);
	vec3 col = get_star_color(rnd.z);
	float intensity = mix(0.45, 1.35, fract(rnd.x * 31.7));
	return col * star * twinkle * intensity * star_brightness;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 sky_color = vec3(0.0);
	vec3 sun_dir = vec3(0.0, -1.0, 0.0);
	float zenith_angle = -1.0;
	
	if (LIGHT0_ENABLED) {
		sun_dir = normalize(LIGHT0_DIRECTION);
		zenith_angle = clamp(dot(UP, sun_dir), -1.0, 1.0);
		float sun_energy = max(0.0, 0.757 * zenith_angle) * LIGHT0_ENERGY;
		float sun_fade = 1.0 - clamp(1.0 - exp(LIGHT0_DIRECTION.y), 0.0, 1.0);

		float rayleigh_coefficient = rayleigh - (1.0 * (1.0 - sun_fade));
		vec3 rayleigh_beta = rayleigh_coefficient * rayleigh_color.rgb * 0.0001;
		vec3 mie_beta = turbidity * mie * mie_color.rgb * 0.000434;

		float zenith = max(0.0, dot(UP, dir));
		float optical_mass = 1.0 / (zenith + 0.15 * pow(3.885 + 54.5 * zenith, -1.253));
		float rayleigh_scatter = rayleigh_zenith_size * optical_mass;
		float mie_scatter = mie_zenith_size * optical_mass;

		vec3 extinction = exp(-(rayleigh_beta * rayleigh_scatter + mie_beta * mie_scatter));

		float cos_theta = dot(dir, sun_dir);

		float rayleigh_phase = (3.0 / (16.0 * PI)) * (1.0 + pow(cos_theta * 0.5 + 0.5, 2.0));
		vec3 betaRTheta = rayleigh_beta * rayleigh_phase;

		float mie_phase = henyey_greenstein(cos_theta, mie_eccentricity);
		vec3 betaMTheta = mie_beta * mie_phase;

		vec3 Lin = pow(sun_energy * ((betaRTheta + betaMTheta) / (rayleigh_beta + mie_beta)) * (1.0 - extinction), vec3(1.5));
		Lin *= mix(vec3(1.0), pow(sun_energy * ((betaRTheta + betaMTheta) / (rayleigh_beta + mie_beta)) * extinction, vec3(0.5)), clamp(pow(1.0 - zenith_angle, 5.0), 0.0, 1.0));
		Lin *= mix(ground_color.rgb, vec3(1.0), smoothstep(-0.1, 0.1, dot(UP, dir)));

		// Solar Disk + Soft Corona Glow
		float effective_size = max(LIGHT0_SIZE, 0.01) * sun_disk_scale;
		float sunAngularDiameterCos = cos(effective_size);
		float sunAngularDiameterCos2 = cos(effective_size * 0.35);
		float sundisk = smoothstep(sunAngularDiameterCos, sunAngularDiameterCos2, cos_theta);
		
		float sun_halo = pow(max(0.0, cos_theta), sun_glow_falloff * 8.0) * sun_glow_intensity;
		vec3 L0 = (sun_energy * extinction) * (sundisk + sun_halo) * LIGHT0_COLOR;
		L0 *= smoothstep(-0.04, 0.02, dir.y);

		vec3 color = Lin + L0;
		sky_color = pow(color, vec3(1.0 / (1.2 + (1.2 * sun_fade))));
		sky_color *= exposure;
	}

	float horizon_mask = smoothstep(0.0, 0.12, dir.y);
	float star_visibility = 1.0 - smoothstep(-0.14, 0.04, zenith_angle);
	
	float cloud_alpha = 0.0;
	vec3 cloud_final_color = vec3(0.0);

	// --- 2D Cumulus Clouds ---
	if (clouds_enabled && dir.y > 0.0) {
		vec2 cloud_uv = (dir.xz / (dir.y + 0.35)) * cloud_scale;
		vec2 wind_offset = TIME * cloud_speed;
		
		float n = fbm_cumulus(cloud_uv + wind_offset);
		
		float threshold = 1.0 - cloud_coverage;
		float raw_cloud = smoothstep(threshold, threshold + cloud_softness, n);
		float cloud_horizon_fade = smoothstep(0.02, 0.18, dir.y);
		cloud_alpha = raw_cloud * cloud_horizon_fade;
		
		if (cloud_alpha > 0.001) {
			vec2 sun_uv_dir = normalize(sun_dir.xz + vec2(0.0001));
			float n_lit = fbm_cumulus(cloud_uv + wind_offset + sun_uv_dir * 0.08);
			float self_shade = clamp((n - n_lit) * 3.0 + 0.55, 0.0, 1.0);
			float puff_gradient = smoothstep(threshold, threshold + cloud_softness * 2.2, n);
			float light_factor = clamp(mix(puff_gradient, self_shade, 0.5), 0.0, 1.0);
			
			float day_weight = smoothstep(-0.08, 0.22, zenith_angle);
			float sunset_weight = smoothstep(-0.16, 0.02, zenith_angle) * (1.0 - smoothstep(0.02, 0.28, zenith_angle));
			
			vec3 day_cloud = mix(cloud_shadow_color, cloud_day_color, light_factor);
			vec3 sunset_tint = mix(vec3(0.22, 0.14, 0.25), vec3(1.0, 0.42, 0.18) * LIGHT0_COLOR, light_factor);
			
			vec3 lit_cloud = mix(cloud_night_color, day_cloud, day_weight);
			lit_cloud = mix(lit_cloud, sunset_tint, sunset_weight * 0.85);
			cloud_final_color = lit_cloud * exposure;
		}
	}

	if (!AT_CUBEMAP_PASS && star_visibility > 0.001 && horizon_mask > 0.001) {
		vec3 norm_band = normalize(band_normal);
		float dist_to_band = abs(dot(dir, norm_band));
		float band_factor = exp(-pow(dist_to_band / max(band_width, 0.01), 2.0));
		
		vec3 stars = compute_stars(dir, star_scale, band_factor);
		stars += compute_stars(dir + vec3(19.4, 7.2, 41.1), star_scale * 1.45, band_factor * 0.85) * 0.55;
		
		float dust_noise = gradient_noise(dir.xz * 3.5 + dir.y * 2.0);
		vec3 milky_way_glow = band_glow_color * band_factor * dust_noise * band_glow_intensity;
		
		float cloud_occlusion = 1.0 - clamp(cloud_alpha * 1.25, 0.0, 1.0);
		sky_color += (stars + milky_way_glow) * star_visibility * horizon_mask * cloud_occlusion;
	}

	sky_color = mix(sky_color, cloud_final_color, cloud_alpha);
	COLOR = sky_color;
}