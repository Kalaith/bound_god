shader_type spatial;
render_mode specular_disabled, diffuse_lambert;

#include "res://assets/shaders/voxel_common.gdshaderinc"

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec4 texel = sample_atlas(UV);
	vec3 albedo = snowed(painted(texel.rgb * COLOR.rgb, world_pos, world_normal), world_pos, world_normal);
	float view_distance = length(VERTEX);
	ALBEDO = mix(albedo, ink * albedo * 1.6, edge_ink(COLOR.a, view_distance, world_pos, world_normal));
	EMISSION = texel.rgb * sacred_glow(UV, texel);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	soft_light(NORMAL, LIGHT, LIGHT_COLOR, ATTENUATION, DIFFUSE_LIGHT);
}
