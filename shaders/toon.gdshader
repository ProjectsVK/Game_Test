// Ombrage peint : 3 bandes de lumière, ombres teintées de bleu, touches de pinceau procédurales.
shader_type spatial;

uniform vec4 albedo : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform vec4 shadow_tint : source_color = vec4(0.32, 0.38, 0.62, 1.0);
uniform float brush_scale = 2.2;
uniform float brush_strength = 0.22;
uniform float rim_strength = 0.35;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;

varying vec3 wpos;
varying vec3 wnorm;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// projection triplanaire simple d'un bruit étiré, comme des coups de brosse
	vec3 an = abs(wnorm);
	vec2 uv = an.y > 0.6 ? wpos.xz : (an.x > an.z ? wpos.zy : wpos.xy);
	float strokes = vnoise(uv * brush_scale * vec2(1.0, 3.0)) * 0.6 + vnoise(uv * brush_scale * 4.0) * 0.4;
	ALBEDO = albedo.rgb * (1.0 - brush_strength * 0.5 + strokes * brush_strength);
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
	EMISSION = emission_color * emission_energy;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float band = smoothstep(-0.05, 0.05, ndl) * 0.55 + smoothstep(0.45, 0.55, ndl) * 0.45;
	float att = smoothstep(0.0, 0.08, ATTENUATION);
	vec3 shade = mix(shadow_tint.rgb * 0.35, vec3(1.0), band * att);
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * shade * min(ATTENUATION * 4.0, 1.0);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0) * step(0.0, ndl);
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * rim * rim_strength * att;
}
