// Shared painterly voxel shading: a soft world-space colour wash over the
// atlas, faint broken ink lines on block edges near the camera (so building
// stays readable without outlining every voxel far away), soft wrapped light
// and no gloss. Vertex colour rgb is the mesher's face shade and occlusion;
// alpha 1 marks a full cube face that may carry edge lines.

uniform sampler2D atlas : source_color, filter_linear, repeat_disable;
uniform vec2 atlas_tiles = vec2(8.0, 7.0);
uniform float tile_pixels = 32.0;
uniform vec3 ink : source_color = vec3(0.19, 0.16, 0.14);
uniform float edge_strength = 0.22;
uniform float edge_fade = 26.0;
uniform float block_variation = 0.04;
uniform float wash_strength = 0.08;
// Atlas tiles that hold sacred growth glow faintly; -1 means unused.
uniform vec2 glow_tile_a = vec2(-1.0);
uniform vec2 glow_tile_b = vec2(-1.0);
uniform float glow_strength = 0.1;

float hash3(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y),
		f.z);
}

// Linear filtering inside a tile only: clamp half a texel from the tile rim so
// neighbouring tiles never bleed in.
vec4 sample_atlas(vec2 uv) {
	vec2 cell = uv * atlas_tiles;
	vec2 tile = floor(cell);
	vec2 local = clamp(cell - tile, vec2(0.5 / tile_pixels), vec2(1.0 - 0.5 / tile_pixels));
	return texture(atlas, (tile + local) / atlas_tiles);
}

vec2 atlas_tile(vec2 uv) {
	return floor(uv * atlas_tiles);
}

// Broad drifting patches of warmer and cooler, lighter and darker paint.
vec3 painted(vec3 albedo, vec3 world_pos, vec3 world_normal) {
	float broad = value_noise(world_pos * 0.07);
	float fine = value_noise(world_pos * 0.31 + 7.3);
	albedo *= 1.0 + ((broad * 0.65 + fine * 0.35) - 0.5) * 2.0 * wash_strength;
	float warm = smoothstep(0.35, 0.85, value_noise(world_pos * 0.03 + 11.0));
	albedo = mix(albedo, albedo * vec3(1.05, 1.01, 0.9), warm * 0.6);
	vec3 block = floor(world_pos - world_normal * 0.01);
	albedo *= 1.0 + (hash3(block) - 0.5) * 2.0 * block_variation;
	return albedo;
}

// Thin, slightly broken ink along the rim of a cube face, fading with distance.
float edge_ink(float cube, float view_distance, vec3 world_pos, vec3 world_normal) {
	if (cube < 0.5) {
		return 0.0;
	}
	vec3 n = abs(world_normal);
	vec2 plane = n.x > 0.5 ? world_pos.zy : (n.y > 0.5 ? world_pos.xz : world_pos.xy);
	vec2 f = fract(plane);
	vec2 rim = min(f, 1.0 - f);
	float d = min(rim.x, rim.y);
	float width = 0.016;
	float aa = max(fwidth(d), 0.0001) * 1.2;
	float line = 1.0 - smoothstep(width, width + aa, d);
	float brush = mix(0.45, 1.0, smoothstep(0.3, 0.7, value_noise(world_pos * 2.7)));
	float fade = 1.0 - smoothstep(edge_fade * 0.45, edge_fade, view_distance);
	// Open ground keeps only a whisper of its grid; walls and steps read clearer.
	float facing = n.y > 0.5 ? 0.55 : 1.0;
	return line * brush * fade * facing * edge_strength;
}

float sacred_glow(vec2 uv, vec4 texel) {
	vec2 tile = atlas_tile(uv);
	if (all(equal(tile, glow_tile_a))) {
		return glow_strength;
	}
	if (all(equal(tile, glow_tile_b))) {
		// The bark only glows along its pale veins.
		return smoothstep(0.08, 0.2, texel.b - texel.r) * glow_strength * 4.0;
	}
	return 0.0;
}

// Soft wrapped Lambert: the terminator is a gentle gradient, never a hard cut.
void soft_light(vec3 normal, vec3 light, vec3 light_color, float attenuation, inout vec3 diffuse) {
	float wrap = smoothstep(-0.15, 0.85, dot(normal, light));
	diffuse += light_color * wrap * attenuation / PI;
}
