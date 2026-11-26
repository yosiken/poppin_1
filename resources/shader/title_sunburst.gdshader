// タイトルの背景。ロゴの後ろから放射状の光がゆっくり回り、
// 大きな泡が下から上へふわふわ上っていく。画面全体の ColorRect に貼る。
shader_type canvas_item;

group_uniforms rays;
uniform vec3 color_a : source_color = vec3(0.30, 0.66, 0.93);
uniform vec3 color_b : source_color = vec3(0.42, 0.76, 0.97);
// 中心のやわらかい光
uniform vec3 glow_color : source_color = vec3(0.86, 0.95, 1.0);
uniform float glow_radius = 520.0;
// 光の中心（画面の割合）
uniform vec2 center = vec2(0.5, 0.42);
uniform float ray_count = 14.0;
// 回る速さ（ラジアン/秒）
uniform float ray_speed = 0.05;
// 光の筋のふちのぼかし
uniform float ray_softness : hint_range(0.0, 1.0) = 0.12;
// 画面のふちを暗くする強さ
uniform float vignette : hint_range(0.0, 1.0) = 0.35;

group_uniforms bubbles;
uniform float bubble_cell = 190.0;
uniform float bubble_density : hint_range(0.0, 1.0) = 0.35;
uniform vec2 bubble_radius = vec2(14.0, 46.0);
uniform float bubble_speed = 40.0;
uniform float bubble_alpha : hint_range(0.0, 1.0) = 0.22;

float hash(vec2 p) {
	uvec2 v = uvec2(ivec2(floor(p)));
	v = v * 1664525u + 1013904223u;
	v.x += v.y * 1664525u;
	v.y += v.x * 1664525u;
	v = v ^ (v >> 16u);
	v.x += v.y * 1664525u;
	v.y += v.x * 1664525u;
	v = v ^ (v >> 16u);
	return float(v.x) * (1.0 / 4294967295.0);
}

void fragment() {
	vec2 px = SCREEN_UV / SCREEN_PIXEL_SIZE;
	vec2 size = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 d = px - center * size;
	float r = length(d);

	float a = atan(d.y, d.x) + TIME * ray_speed;
	float s = sin(a * ray_count);
	float ray = smoothstep(-ray_softness, ray_softness, s);
	vec3 col = mix(color_a, color_b, ray);
	col = mix(col, glow_color, exp(-r / glow_radius) * 0.85);

	// 大きな泡（輪だけのうすい泡）
	float col0 = floor(px.x / bubble_cell);
	float ring = 0.0;
	for (int dx = -1; dx <= 1; dx++) {
		float c = col0 + float(dx);
		float sp = bubble_speed * (0.6 + 0.8 * hash(vec2(c, 3.0)));
		float rise = TIME * sp;
		float row0 = floor((px.y + rise) / bubble_cell);
		for (int dy = -1; dy <= 1; dy++) {
			vec2 id = vec2(c, row0 + float(dy));
			if (hash(id + vec2(5.0, 11.0)) > bubble_density) {
				continue;
			}
			float h1 = hash(id + vec2(17.0, 2.0));
			float h2 = hash(id + vec2(3.0, 23.0));
			float rad = mix(bubble_radius.x, bubble_radius.y, h1);
			vec2 ctr = vec2((id.x + 0.25 + 0.5 * h2) * bubble_cell, (id.y + 0.25 + 0.5 * h1) * bubble_cell - rise);
			ctr.x += sin(TIME * (0.8 + h2) + h1 * 6.283) * 10.0;
			float dist = length(px - ctr) / rad;
			float body = 1.0 - smoothstep(0.92, 1.0, dist);
			float edge = smoothstep(0.7, 0.95, dist) * body;
			float spec = 1.0 - smoothstep(0.1, 0.25, length((px - ctr) / rad - vec2(-0.4, -0.4)));
			ring = max(ring, max(edge * 0.8 + body * 0.15, spec * body));
		}
	}
	col = mix(col, vec3(1.0), ring * bubble_alpha);

	// 画面のふちを少し暗く
	vec2 q = SCREEN_UV - 0.5;
	col *= 1.0 - vignette * smoothstep(0.25, 0.75, length(q * vec2(1.0, 1.2)));

	COLOR = vec4(col, 1.0);
}
