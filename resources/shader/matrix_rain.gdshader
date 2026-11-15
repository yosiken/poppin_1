shader_type canvas_item;
// Matrix-style digital rain for Godot 4.x
// Attach to a full-screen ColorRect with a ShaderMaterial.
// Set "glyph_atlas" to glyph_atlas.png (16x6 grid, 96 glyphs).
// Parallax: drive "parallax_offset" (-1..1 in x/y) from a script
// (see matrix_parallax.gd) or animate it by hand.

// ---------- Glyph atlas ----------
uniform sampler2D glyph_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 atlas_grid = vec2(16.0, 6.0);
uniform float glyph_count = 96.0;
uniform float aspect = 1.7778; // screen width / height, set from script

// ---------- Look ----------
uniform vec4 bg_color : source_color = vec4(0.0, 0.015, 0.0, 1.0);
uniform vec4 rain_color : source_color = vec4(0.12, 1.0, 0.35, 1.0);
uniform vec4 head_color : source_color = vec4(0.8, 1.0, 0.88, 1.0);
uniform float brightness = 1.15;

// ---------- Rain ----------
uniform float rain_rows = 26.0;      // vertical cells of the near layer
uniform float rain_speed = 1.0;      // global speed multiplier
uniform float trail_length = 16.0;   // trail length in cells
uniform float density = 0.8;         // fraction of active columns (0..1)
// How much of a cell the glyph fills (1.0 = no gap between glyphs).
// Shrink the cells (rain_rows) as you raise this to keep the glyph size.
uniform float glyph_fill : hint_range(0.3, 1.0) = 0.82;

// ---------- Floating glyphs ----------
uniform float float_rows = 6.0;      // cell size of the floating layer
uniform float float_alpha = 0.4;     // visibility of floating glyphs
uniform float float_speed = 1.0;     // drift speed multiplier

// ---------- Parallax ----------
// (0,0) = center. Layers shift by depth * strength * offset.
uniform vec2 parallax_offset = vec2(0.0);
uniform float parallax_strength = 0.045;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float glyph_alpha(vec2 cell_uv, float idx) {
	float col = mod(idx, atlas_grid.x);
	float row = floor(idx / atlas_grid.x);
	vec2 uv = (vec2(col, row) + cell_uv) / atlas_grid;
	return texture(glyph_atlas, uv).a;
}

// One rain layer. depth: 0 = far (no parallax), 1 = near.
vec3 rain_layer(vec2 uv, float rows, float speed, float depth, float seed, float bright) {
	vec2 suv = uv - parallax_offset * parallax_strength * depth;
	vec2 g = vec2(suv.x * aspect, suv.y) * rows;
	float col_id = floor(g.x);
	vec2 cell = vec2(col_id, floor(g.y));
	vec2 f = fract(g);

	float rnd = hash11(col_id * 12.9898 + seed * 78.233);
	if (rnd > density) {
		return vec3(0.0);
	}

	float col_speed = speed * (0.5 + 1.1 * hash11(col_id * 3.7 + seed));
	float cycle = rows + trail_length * 2.0;
	float head = mod(rnd * cycle * 7.31 + TIME * col_speed * 7.0, cycle) - trail_length;
	float cell_d = head - cell.y; // 0 = head cell, >0 = trail behind (above) head
	if (cell_d < 0.0 || cell_d > trail_length) {
		return vec3(0.0);
	}

	// Glyph is fixed to its position in the stream; some cells mutate over time.
	float stream = cell.y - floor(head);
	float base = hash21(vec2(col_id, stream) + seed);
	float idx = floor(base * glyph_count);
	if (base > 0.85) {
		idx = floor(hash21(vec2(col_id + floor(TIME * 3.0), stream) + seed) * glyph_count);
	}

	// Shrink the glyph a bit inside its cell.
	float pad = (1.0 - glyph_fill) * 0.5;
	vec2 gf = (f - pad) / glyph_fill;
	if (gf.x < 0.0 || gf.x > 1.0 || gf.y < 0.0 || gf.y > 1.0) {
		return vec3(0.0);
	}
	float a = glyph_alpha(gf, idx);
	if (a <= 0.001) {
		return vec3(0.0);
	}

	float fade = pow(clamp(1.0 - cell_d / trail_length, 0.0, 1.0), 1.5);
	float head_f = 1.0 - smoothstep(0.0, 1.5, cell_d);
	vec3 col = mix(rain_color.rgb, head_color.rgb, head_f);
	return col * (a * fade * (0.35 + 0.65 * bright) + a * head_f * 0.9) * bright;
}

// Sparse, large glyphs drifting slowly inside their cells.
vec3 float_layer(vec2 uv, float rows, float depth) {
	vec2 suv = uv - parallax_offset * parallax_strength * depth;
	suv += vec2(sin(TIME * 0.021), cos(TIME * 0.017)) * 0.008; // slow whole-layer sway
	vec2 g = vec2(suv.x * aspect, suv.y) * rows;
	vec2 cell = floor(g);
	vec2 f = fract(g);

	float rnd = hash21(cell + 4.7);
	if (rnd < 0.8) {
		return vec3(0.0); // only ~20% of cells hold a glyph
	}
	float phase = rnd * 40.0;
	vec2 drift = vec2(
		sin(TIME * 0.35 * float_speed + phase),
		cos(TIME * 0.27 * float_speed + phase * 1.7)) * 0.16;
	float size = 0.55;
	vec2 gf = (f - drift - vec2(0.5 - size * 0.5)) / size;
	if (gf.x < 0.0 || gf.x > 1.0 || gf.y < 0.0 || gf.y > 1.0) {
		return vec3(0.0);
	}
	float idx = floor(hash21(cell + 9.3) * glyph_count);
	float pulse = 0.55 + 0.45 * sin(TIME * (0.3 + rnd * 0.7) * float_speed + phase);
	return rain_color.rgb * glyph_alpha(gf, idx) * float_alpha * pulse;
}

void fragment() {
	vec3 col = bg_color.rgb;
	col += rain_layer(UV, rain_rows * 1.5, rain_speed * 0.65, 0.4, 3.1, 0.45); // far layer
	col += float_layer(UV, float_rows, 1.6);                                    // floating glyphs
	col += rain_layer(UV, rain_rows, rain_speed, 1.0, 9.7, 1.0);                // near layer
	COLOR = vec4(col * brightness, 1.0);
}
