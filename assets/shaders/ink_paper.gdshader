// Ink and paper over the whole 3D view, as one multiply pass so water and other
// transparent effects underneath stay intact: ink lines where depth jumps
// (silhouettes of trees, cliffs, buildings, people) and, more faintly near the
// camera, where surfaces fold; plus fixed paper grain and a soft vignette.
// The UI is drawn on its own canvas layer and is untouched.
shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform sampler2D normal_texture : hint_normal_roughness_texture, filter_nearest;
uniform vec3 ink : source_color = vec3(0.24, 0.2, 0.17);
uniform vec3 paper_shadow : source_color = vec3(0.93, 0.9, 0.84);
uniform float silhouette = 0.85;
uniform float crease = 0.4;
uniform float depth_threshold = 0.035;
uniform float line_far = 160.0;
uniform float grain = 0.07;
uniform float vignette = 0.16;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float hash2(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1, 0)), f.x), mix(hash2(i + vec2(0, 1)), hash2(i + vec2(1, 1)), f.x), f.y);
}

float view_depth(vec2 uv, mat4 inv_projection) {
	float raw = texture(depth_texture, uv).r;
	vec4 view = inv_projection * vec4(uv * 2.0 - 1.0, raw, 1.0);
	return -view.z / view.w;
}

void fragment() {
	vec2 px = 1.0 / VIEWPORT_SIZE;
	vec2 uv = SCREEN_UV;
	float d0 = view_depth(uv, INV_PROJECTION_MATRIX);
	vec3 n0 = texture(normal_texture, uv).xyz * 2.0 - 1.0;
	float edge = 0.0;
	float fold = 0.0;
	// Taps one and two pixels out give silhouettes a two-pixel brush line.
	vec2 taps[8] = vec2[](vec2(1, 0), vec2(-1, 0), vec2(0, 1), vec2(0, -1), vec2(2, 0), vec2(-2, 0), vec2(0, 2), vec2(0, -2));
	for (int i = 0; i < 8; i++) {
		vec2 at = uv + taps[i] * px;
		// Only the nearer side of a jump is inked, so lines stay one pixel wide.
		float d = view_depth(at, INV_PROJECTION_MATRIX);
		edge = max(edge, smoothstep(depth_threshold, depth_threshold * 2.5, (d - d0) / d0));
		if (i < 4) {
			vec3 n = texture(normal_texture, at).xyz * 2.0 - 1.0;
			fold = max(fold, smoothstep(0.35, 0.8, 1.0 - dot(n0, n)));
		}
	}
	float far = smoothstep(line_far * 0.25, line_far, d0);
	edge *= mix(1.0, 0.45, far);
	fold *= 1.0 - smoothstep(10.0, 45.0, d0);
	// A loaded brush: lines thicken and thin along their length.
	float brush = mix(0.55, 1.0, value_noise(FRAGCOORD.xy * 0.08));
	float line = clamp(max(edge * silhouette, fold * crease) * brush, 0.0, 1.0);
	vec3 shade = mix(vec3(1.0), ink, line);
	// Paper: fine fibre grain and broad, soft blotches fixed to the canvas.
	float fibre = value_noise(FRAGCOORD.xy * 0.7) * 0.6 + value_noise(FRAGCOORD.xy * vec2(0.08, 0.3)) * 0.4;
	float blotch = value_noise(uv * vec2(5.0, 3.0));
	shade *= 1.0 - (fibre - 0.5) * 2.0 * grain;
	shade *= mix(vec3(1.0), paper_shadow, blotch * 0.5);
	float rim = smoothstep(0.55, 1.05, length((uv - 0.5) * vec2(1.25, 1.0)) * 1.3);
	shade *= mix(vec3(1.0), paper_shadow * 0.92, rim * vignette / 0.16);
	ALBEDO = shade;
}
