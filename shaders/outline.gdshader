// Contour encré : coque inversée légèrement gonflée.
shader_type spatial;
render_mode unshaded, cull_front;

uniform vec4 color : source_color = vec4(0.03, 0.03, 0.05, 1.0);
uniform float thickness = 0.018;

void vertex() {
	VERTEX += NORMAL * thickness;
}

void fragment() {
	ALBEDO = color.rgb;
}
