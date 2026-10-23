// Ink and paper over the whole 3D view, as one multiply pass so water and other
// transparent effects underneath stay intact: ink lines where the picture's
// brightness jumps (silhouettes of trees, cliffs, buildings, people against what
// lies behind them, and the faces of blocks that catch the sun differently),
// plus fixed paper grain and a soft vignette. It reads only the screen, so the
// Compatibility/WebGL renderer, which has no depth or normal buffer in 4.2, can
// draw it. A full-screen rect on a canvas layer under the UI: the UI is untouched.
shader_type canvas_item;
render_mode blend_mul;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform vec3 ink : source_color = vec3(0.24, 0.2, 0.17);
uniform vec3 paper_shadow : source_color = vec3(0.93, 0.9, 0.84);
uniform float silhouette = 0.85;
uniform float crease = 0.4;
uniform float edge_threshold = 0.09;
uniform float fold_threshold = 0.035;
uniform float grain = 0.07;
uniform float vignette = 0.16;

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

float luma(vec2 uv) {
	return dot(texture(screen_texture, uv).rgb, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec2 uv = SCREEN_UV;
	float l0 = luma(uv);
	float edge = 0.0;
	float fold = 0.0;
	// Taps one and two pixels out give silhouettes a two-pixel brush line.
	vec2 taps[8] = vec2[](vec2(1, 0), vec2(-1, 0), vec2(0, 1), vec2(0, -1), vec2(2, 0), vec2(-2, 0), vec2(0, 2), vec2(0, -2));
	for (int i = 0; i < 8; i++) {
		// Only the darker side of a jump is inked, so lines stay one pixel wide.
		float jump = luma(uv + taps[i] * px) - l0;
		edge = max(edge, smoothstep(edge_threshold, edge_threshold * 2.5, jump));
		if (i < 4) {
			fold = max(fold, smoothstep(fold_threshold, fold_threshold * 2.5, jump) * (1.0 - edge));
		}
	}
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
	COLOR = vec4(shade, 1.0);
}
