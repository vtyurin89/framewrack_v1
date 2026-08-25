shader_type canvas_item;
// Subtle CRT scanlines + edge vignette. No full-screen bloom / glow.

uniform float scanline_intensity : hint_range(0.0, 0.4) = 0.07;
uniform float scanline_density : hint_range(200.0, 1200.0) = 720.0;
uniform float vignette_strength : hint_range(0.0, 0.8) = 0.32;
uniform float vignette_radius : hint_range(0.2, 1.2) = 0.72;
uniform vec4 tint_color : source_color = vec4(0.031, 0.051, 0.039, 1.0);

void fragment() {
	vec2 uv = UV;
	float scan = sin(uv.y * scanline_density * 3.14159) * 0.5 + 0.5;
	float line_dark = 1.0 - scanline_intensity * scan;

	float dist = distance(uv, vec2(0.5));
	float vignette = 1.0 - smoothstep(vignette_radius * 0.55, vignette_radius, dist) * vignette_strength;

	// Nearly transparent overlay: darken only via scan + vignette.
	float alpha = (1.0 - line_dark * vignette) * 0.85;
	alpha = clamp(alpha, 0.0, 0.45);
	COLOR = vec4(tint_color.rgb, alpha);
}
