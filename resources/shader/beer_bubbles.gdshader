// ビールの泡が下から上ってくるマテリアル（タイトルロゴの液体レイヤー用）。
//
// 絵の黄色い（色の濃い）ところだけに泡を描く。白っぽい泡（フォーム）や
// クリーム色のところには描かないので、泡は上の白い泡に吸い込まれて消えて見える。
// 大きい泡と、細かいシュワシュワの2種類。どちらも時間で上り続け、途切れない。
// ゆらゆらした明るさの波も下から上へ流す。
//
// 大きさや速さは、絵の画素（テクスチャの px）で指定する。
shader_type canvas_item;

group_uniforms beer;
// どれくらい色が濃ければビールとみなすか（彩度。この間でなめらかに切り替わる）
uniform vec2 beer_saturation = vec2(0.28, 0.5);

group_uniforms bubbles;
// 泡を置くマスの大きさ（px）。小さいほど泡が増える
uniform float bubble_cell = 46.0;
// マスに泡がある割合
uniform float bubble_density : hint_range(0.0, 1.0) = 0.55;
// 泡の半径（px）の最小と最大
uniform vec2 bubble_radius = vec2(4.5, 12.0);
// 上る速さ（px/秒）。列ごとに少しばらつく
uniform float bubble_speed = 70.0;
// 左右のゆれ幅（px）
uniform float bubble_wobble = 3.0;
// 泡の中の明るさ・ふちの光・光の点の強さ
uniform float bubble_body : hint_range(0.0, 1.0) = 0.35;
uniform float bubble_rim : hint_range(0.0, 1.0) = 0.6;
uniform float bubble_spec : hint_range(0.0, 1.0) = 0.9;
uniform vec3 rim_color : source_color = vec3(1.0, 0.98, 0.86);
uniform vec3 shade_color : source_color = vec3(0.93, 0.62, 0.12);

group_uniforms fizz;
// 細かいシュワシュワ
uniform float fizz_cell = 17.0;
uniform float fizz_density : hint_range(0.0, 1.0) = 0.3;
uniform vec2 fizz_radius = vec2(1.1, 2.4);
uniform float fizz_speed = 120.0;
uniform float fizz_strength : hint_range(0.0, 1.0) = 0.75;

group_uniforms shimmer;
// ゆらゆらした明るさの波（0 で無し）
uniform float shimmer = 0.05;
uniform float shimmer_speed = 2.2;

// 整数のハッシュ (PCG)。waterfall.gdshader と同じ。TIME が大きくなっても崩れない
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

// p（px）にいちばん効いている泡を探す。
// 戻り値: x = 泡の中か（0〜1）、y = 中心からの距離（半径で割った値）、
//         zw = 中心から p への向き（半径で割った値）
vec4 bubble(vec2 p, float cell, float density, vec2 radius, float speed, float wobble, float seed, float t) {
	vec4 best = vec4(0.0, 2.0, 0.0, 0.0);
	float col0 = floor(p.x / cell);
	for (int dx = -1; dx <= 1; dx++) {
		float col = col0 + float(dx);
		// 列ごとに上る速さを変える（そろって動くと板のように見える）
		float s = speed * (0.7 + 0.6 * hash(vec2(col, seed)));
		float rise = t * s;
		float row0 = floor((p.y + rise) / cell);
		for (int dy = -1; dy <= 1; dy++) {
			float row = row0 + float(dy);
			vec2 id = vec2(col, row);
			float h0 = hash(id + vec2(seed * 31.0, 7.0));
			if (h0 > density) {
				continue;
			}
			float h1 = hash(id + vec2(13.0, seed * 17.0));
			float h2 = hash(id + vec2(seed * 5.0, 29.0));
			float h3 = hash(id + vec2(41.0, seed * 3.0));
			float r = mix(radius.x, radius.y, h1 * h1);
			vec2 c = vec2((col + 0.3 + 0.4 * h2) * cell, (row + 0.3 + 0.4 * h3) * cell - rise);
			c.x += sin(t * (1.5 + 2.0 * h2) + h3 * 6.283) * wobble;
			vec2 d = (p - c) / r;
			float dist = length(d);
			if (dist < best.y) {
				best = vec4(1.0 - smoothstep(0.82, 1.0, dist), dist, d);
			}
		}
	}
	return best;
}

// 頂点の色（modulate）。COLOR は最初からテクスチャの色が掛かっているので、自分で読むときは分けておく
varying vec4 vertex_color;

void vertex() {
	vertex_color = COLOR;
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	vec3 col = base.rgb;

	// ビールらしさ（色の濃さ）
	float mx = max(col.r, max(col.g, col.b));
	float mn = min(col.r, min(col.g, col.b));
	float sat = (mx - mn) / max(mx, 1e-3);
	float beer = smoothstep(beer_saturation.x, beer_saturation.y, sat) * base.a;

	vec2 p = UV / TEXTURE_PIXEL_SIZE;
	float t = TIME;

	if (beer > 0.0) {
		// ゆらゆらした明るさの波
		float wave = sin(p.y * 0.045 + t * shimmer_speed + sin(p.x * 0.02 + t * 0.7) * 1.5);
		col *= 1.0 + shimmer * wave * beer;

		// 大きい泡
		vec4 b = bubble(p, bubble_cell, bubble_density, bubble_radius, bubble_speed, bubble_wobble, 1.0, t);
		float inside = b.x * beer;
		if (inside > 0.0) {
			// 右下はビールの色が濃く映る
			float shade = smoothstep(0.55, 1.0, b.y) * clamp(dot(normalize(b.zw + 1e-4), vec2(0.7071)), 0.0, 1.0);
			col = mix(col, col * shade_color * 1.1, shade * inside * 0.45);
			col = mix(col, min(col * 1.12 + 0.05, vec3(1.0)), inside * bubble_body);
			// ふちの光
			float rim = smoothstep(0.62, 0.92, b.y);
			col = mix(col, rim_color, rim * inside * bubble_rim);
			// 左上の光の点
			float spec = 1.0 - smoothstep(0.12, 0.3, length(b.zw - vec2(-0.38, -0.4)));
			col = mix(col, vec3(1.0), spec * inside * bubble_spec);
		}

		// 細かいシュワシュワ
		vec4 f = bubble(p, fizz_cell, fizz_density, fizz_radius, fizz_speed, 1.0, 2.0, t);
		col = mix(col, rim_color, f.x * beer * fizz_strength);
	}

	COLOR = vec4(col, base.a) * vertex_color;
}
