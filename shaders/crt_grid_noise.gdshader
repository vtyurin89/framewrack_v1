shader_type canvas_item;
// Translucent phosphor grain + scanlines composited OVER panel content
// (cells, items, chrome). ColorRect must sit on top with mouse_filter IGNORE.

render_mode unshaded, blend_mix;

uniform float grain_amount : hint_range(0.0, 0.12) = 0.045;
uniform float scanline_opacity : hint_range(0.0, 0.25) = 0.06;
uniform float static_speed : hint_range(0.0, 10.0) = 2.0;
uniform vec3 phosphor_tint : source_color = vec3(0.658, 0.941, 0.658); // PHOSPHOR_BRIGHT

float random(vec2 uv) {
	return fract(sin(dot(uv.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

void fragment() {
	vec2 noise_uv = UV + vec2(TIME * static_speed * 0.01, TIME * static_speed * 0.02);
	float grain = (random(noise_uv) - 0.5) * grain_amount;
	float scanline = sin(UV.y * 800.0) * scanline_opacity;
	float signed_v = grain - scanline;

	// Mix toward phosphor (bright flecks) or near-black (scanline troughs).
	if (signed_v >= 0.0) {
		COLOR = vec4(phosphor_tint, signed_v * 1.35);
	} else {
		COLOR = vec4(vec3(0.02, 0.04, 0.03), -signed_v * 1.6);
	}
}
