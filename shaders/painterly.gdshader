// Passe plein écran : filtre de Kuwahara (aplats peints), contours d'encre par profondeur,
// étalonnage chaud/froid, grain de toile et vignette.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform int radius = 3;
uniform float spread = 1.4;
uniform float edge_strength = 0.75;
uniform float saturation = 1.15;
uniform vec3 shadow_color : source_color = vec3(0.12, 0.16, 0.28);
uniform vec3 light_color : source_color = vec3(1.05, 0.95, 0.82);
uniform float grain = 0.05;
uniform float vignette = 0.45;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

vec4 region(vec2 uv, vec2 px, vec2 dir) {
	vec3 sum = vec3(0.0);
	vec3 sq = vec3(0.0);
	float n = 0.0;
	for (int i = 0; i <= radius; i++) {
		for (int j = 0; j <= radius; j++) {
			vec3 c = textureLod(screen_tex, uv + vec2(float(i) * dir.x, float(j) * dir.y) * px * spread, 0.0).rgb;
			sum += c;
			sq += c * c;
			n += 1.0;
		}
	}
	vec3 mean = sum / n;
	vec3 v = abs(sq / n - mean * mean);
	return vec4(mean, v.r + v.g + v.b);
}

float lin_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -v.z / v.w;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = 1.0 / VIEWPORT_SIZE;

	vec4 a = region(uv, px, vec2(-1.0, -1.0));
	vec4 b = region(uv, px, vec2(1.0, -1.0));
	vec4 c = region(uv, px, vec2(-1.0, 1.0));
	vec4 d = region(uv, px, vec2(1.0, 1.0));
	vec3 col = a.rgb;
	float mv = a.a;
	if (b.a < mv) { mv = b.a; col = b.rgb; }
	if (c.a < mv) { mv = c.a; col = c.rgb; }
	if (d.a < mv) { mv = d.a; col = d.rgb; }

	// contours d'encre là où la profondeur saute
	float dc = lin_depth(uv, INV_PROJECTION_MATRIX);
	float dl = lin_depth(uv - vec2(px.x, 0.0) * 1.5, INV_PROJECTION_MATRIX);
	float dr = lin_depth(uv + vec2(px.x, 0.0) * 1.5, INV_PROJECTION_MATRIX);
	float du = lin_depth(uv - vec2(0.0, px.y) * 1.5, INV_PROJECTION_MATRIX);
	float dd = lin_depth(uv + vec2(0.0, px.y) * 1.5, INV_PROJECTION_MATRIX);
	// 1/profondeur varie linéairement sur une surface plane : seuls les vrais bords ressortent
	float ic = 1.0 / max(dc, 0.001);
	float lap = abs(1.0 / max(dl, 0.001) + 1.0 / max(dr, 0.001) + 1.0 / max(du, 0.001) + 1.0 / max(dd, 0.001) - 4.0 * ic) / ic;
	float edge = smoothstep(0.04, 0.15, lap) * (1.0 - smoothstep(25.0, 45.0, dc));
	col = mix(col, col * 0.18, edge * edge_strength);

	// étalonnage : ombres bleutées, lumières chaudes
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col * mix(shadow_color * 3.0, vec3(1.0), smoothstep(0.0, 0.35, l)), col * light_color, smoothstep(0.4, 1.0, l));
	col = mix(vec3(l), col, saturation);

	// grain de toile
	float g = hash(floor(uv * VIEWPORT_SIZE / 2.0)) - 0.5;
	col += g * grain;

	// vignette
	vec2 q = uv - 0.5;
	col *= 1.0 - dot(q, q) * vignette * 2.0;

	ALBEDO = col;
}
