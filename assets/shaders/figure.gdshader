// People and the avatar: one shared material, each part tinted per instance.
// Flat woodblock colour with a soft two-tone terminator, a faint dye wash and
// a darker rim toward the silhouette. Opaque, so the ink pass outlines them;
// fading (people inside a building, the dormant god) is a dither, not alpha.
shader_type spatial;
render_mode specular_disabled, diffuse_lambert;

instance uniform vec4 tint : source_color = vec4(1.0);
instance uniform float fade = 1.0;
instance uniform float glow = 0.0;
uniform vec3 ink : source_color = vec3(0.24, 0.2, 0.17);
uniform float rim = 0.28;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

float hash3(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

// Ordered 4x4 dither, so a faded figure stays crisp at its edges.
float bayer(vec2 frag) {
	ivec2 p = ivec2(mod(frag, 4.0));
	int index = p.x + p.y * 4;
	int table[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(table[index]) + 0.5) / 16.0;
}

void fragment() {
	if (fade < 0.999 && bayer(FRAGCOORD.xy) > fade) {
		discard;
	}
	// A faint uneven dye: cloth and skin are never one flat colour.
	vec3 cell = floor(local_pos * 18.0);
	vec3 colour = tint.rgb * (0.96 + hash3(cell) * 0.08);
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	colour = mix(colour, ink * colour * 1.8, (1.0 - smoothstep(0.1, 0.55, facing)) * rim);
	ALBEDO = colour;
	EMISSION = tint.rgb * glow;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

// Two soft tones with a gentle step between them, as a print would have.
void light() {
	float wrap = smoothstep(-0.1, 0.35, dot(NORMAL, LIGHT));
	float tone = mix(0.45, 1.0, wrap);
	DIFFUSE_LIGHT += LIGHT_COLOR * tone * ATTENUATION / PI;
}
