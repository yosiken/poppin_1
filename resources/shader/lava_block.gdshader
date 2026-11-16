shader_type canvas_item;
//
// 熱い板。落ちたら死ぬ床（Hazard）に貼って、触れたら終わりだと見せる。
//
// neon_block.gdshader と同じ形の渡し方をする（edges / edge_count / bounds）ので、
// 生成スクリプトはどのシェーダーでも同じ値を書き出せる。違うのは中身だけ。
//
// 作り: 冷えた殻（暗い）を熱の筋（明るい）が割っている、という絵にする。
// 筋はゆっくり流れ、上の面ほど熱い。上の面はプレイヤーが触れる面なので、
// 「どこまでが危ないか」が一目で分かるように一番明るくする。
//
// 色は頂点カラー(fill_color)から取り、熱いところだけ hot_color へ寄せる。
// 距離はすべて px で見ているので、板の大きさが変わっても縁の太さは変わらない。

const int MAX_EDGES = 16;

varying vec2 local_pos;

uniform vec3 edges[MAX_EDGES];
uniform int edge_count = 0;
uniform vec4 bounds = vec4(0.0, 0.0, 1.0, 1.0);

// 熱の筋
uniform float noise_size = 160.0;                           // 模様の大きさ (px)
uniform float flow_speed = 0.07;                            // 流れる速さ
uniform float vein_width : hint_range(0.01, 0.5) = 0.08;    // 筋の太さ
uniform float crust_dark : hint_range(0.0, 1.0) = 0.2;     // 冷えた殻の暗さ

// 熱さ
uniform float heat : hint_range(0.0, 2.0) = 1.0;            // 全体の熱さ
uniform vec4 hot_color : source_color = vec4(1.0, 0.86, 0.45, 1.0);
uniform float top_heat_height = 70.0;                       // 上の面が熱い高さ (px)
uniform float top_heat : hint_range(0.0, 2.0) = 1.0;

// 縁と陽炎
uniform float line_width : hint_range(0.0, 20.0) = 2.5;
uniform float glow_width : hint_range(0.0, 300.0) = 22.0;
uniform float glow_strength : hint_range(0.0, 2.0) = 0.22;
uniform float shimmer_speed = 2.6;
uniform float shimmer_size = 0.035;
uniform float shimmer_strength : hint_range(0.0, 1.0) = 0.12;


/// 一番近い辺までの距離 (px)。内側が正
float edge_distance(vec2 p) {
	float d = 1e8;
	for (int i = 0; i < edge_count; i++) {
		d = min(d, dot(edges[i].xy, p) - edges[i].z);
	}
	return d;
}


float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}


float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = p - i;
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}


float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * value_noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}


void vertex() {
	local_pos = VERTEX;
}


void fragment() {
	vec2 p = local_pos;
	float d = edge_distance(p);
	float t = TIME * flow_speed;

	// 模様。一度ずらしてから重ねると、溶けて流れている形になる
	vec2 q = p / max(noise_size, 1.0) + vec2(t, 0.0);
	float warp = fbm(q * 0.7 + vec2(0.0, t * 0.5));
	float n = fbm(q + warp);

	// 殻の割れ目ほど熱い
	float hot = 1.0 - smoothstep(0.0, vein_width, abs(n - 0.5));

	// 上の面（触れる面）は常に熱い。
	// ここも模様で少し揺らしておく。板が地形の絵に隠れて上の面しか見えない
	// 置き方（本編の Stage06 など）でも、のっぺりした帯にならないように
	float top = 1.0 - smoothstep(0.0, max(top_heat_height, 1.0), p.y - bounds.y);
	hot = max(hot, top * top_heat * mix(0.72, 1.0, n));

	// 縁の内側も熱を持たせて、板の形を見せる
	float glow = 1.0 - smoothstep(0.0, max(glow_width, 0.001), d);
	hot = clamp((hot + glow * glow * glow_strength) * heat, 0.0, 1.0);

	// 冷えた殻 → 素の色 → 一番熱い色。
	// 殻も模様で少し明暗をつけて、のっぺりした赤にならないようにする
	vec3 crust = COLOR.rgb * crust_dark * mix(0.7, 1.3, n);
	vec3 col = mix(crust, COLOR.rgb, smoothstep(0.0, 0.55, hot));
	col = mix(col, hot_color.rgb, smoothstep(0.6, 1.0, hot));

	// 陽炎。熱いところだけ揺らぐ
	float shimmer = sin(p.x * shimmer_size + TIME * shimmer_speed)
		* sin(p.y * shimmer_size * 1.7 - TIME * shimmer_speed * 0.6);
	col *= 1.0 + shimmer * shimmer_strength * hot;

	// 縁そのもの
	float line = 1.0 - smoothstep(line_width, line_width + 1.5, d);
	col = mix(col, hot_color.rgb, line);

	COLOR = vec4(col, COLOR.a);
}
