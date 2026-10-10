shader_type spatial;
render_mode specular_disabled, cull_disabled, diffuse_lambert, blend_mix, depth_draw_opaque;

#include "res://assets/shaders/voxel_common.gdshaderinc"

varying vec3 world_pos;
varying vec3 world_normal;

uniform vec3 crest : source_color = vec3(0.86, 0.89, 0.84);
uniform float opacity = 0.8;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Faded blue with slow, curling pale wave lines, as in a woodblock river.
void fragment() {
	vec4 texel = sample_atlas(UV);
	vec3 albedo = painted(texel.rgb * COLOR.rgb, world_pos, world_normal);
	if (world_normal.y > 0.5) {
		vec2 p = world_pos.xz;
		float curl = sin(p.y * 0.55 + TIME * 0.25) * 1.4 + value_noise(vec3(p * 0.4, TIME * 0.1)) * 2.0;
		float band = sin(p.x * 1.25 + curl + TIME * 0.5);
		float line = smoothstep(0.86, 0.97, band) * smoothstep(0.25, 0.6, value_noise(vec3(p * 0.6, 3.0)));
		albedo = mix(albedo, crest, line * 0.75);
	}
	ALBEDO = albedo;
	ALPHA = opacity;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	soft_light(NORMAL, LIGHT, LIGHT_COLOR, ATTENUATION, DIFFUSE_LIGHT);
}
