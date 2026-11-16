shader_type canvas_item;
//
// 氷の板。滑って登れない坂に貼って「ここは足場にならない」と見せる。
//
// neon_block.gdshader と同じ形の渡し方をする（edges / edge_count / bounds）ので、
// 生成スクリプトはどちらのシェーダーでも同じ値を書き出せる。違うのは中身だけで、
// こちらは面を結晶の粒に割り、割れ目と縁を白く光らせる。
//
// 色は頂点カラー(fill_color)から取る。白へ寄せる量(white_mix)があるので、
// 青以外の色を入れても氷らしい薄さのまま出る。
//
// 距離はすべて px で見ているので、板の大きさが変わっても粒や縁の太さは変わらない。

const int MAX_EDGES = 16;

varying vec2 local_pos;

uniform vec3 edges[MAX_EDGES];
uniform int edge_count = 0;
uniform vec4 bounds = vec4(0.0, 0.0, 1.0, 1.0);

// 結晶の粒
uniform float shard_size = 38.0;                            // 粒の大きさ (px)
uniform float shard_stretch : hint_range(0.2, 3.0) = 0.6;  // 1より小さいと縦に伸びる
uniform float shard_contrast : hint_range(0.0, 1.0) = 0.34; // 粒ごとの明暗の差
uniform float crack_width : hint_range(0.0, 10.0) = 2.0;    // 割れ目の太さ (px)
uniform float crack_light : hint_range(0.0, 1.0) = 0.62;    // 割れ目の白さ

// 面
uniform float white_mix : hint_range(0.0, 1.0) = 0.38;      // 素の色を白へ寄せる量
uniform float face_top : hint_range(0.0, 2.0) = 0.9;
uniform float face_bottom : hint_range(0.0, 2.0) = 0.42;

// 縁
uniform float line_width : hint_range(0.0, 20.0) = 2.5;
uniform float line_white : hint_range(0.0, 1.0) = 0.9;
uniform float glow_width : hint_range(0.0, 300.0) = 16.0;
uniform float glow_strength : hint_range(0.0, 2.0) = 0.5;

// 表面を流れる光。0 にすれば止まる
uniform float sheen_speed = 0.35;
uniform float sheen_width = 0.0075;
uniform float sheen_strength : hint_range(0.0, 1.0) = 0.18;


/// 一番近い辺までの距離 (px)。内側が正
float edge_distance(vec2 p) {
	float d = 1e8;
	for (int i = 0; i < edge_count; i++) {
		d = min(d, dot(edges[i].xy, p) - edges[i].z);
	}
	return d;
}


vec2 hash2(vec2 c) {
	float a = dot(c, vec2(127.1, 311.7));
	float b = dot(c, vec2(269.5, 183.3));
	return fract(sin(vec2(a, b)) * 43758.5453);
}


/// 結晶の粒割り(ボロノイ)。
/// border … 粒の境目までの距離(セル単位)。0 に近いほど割れ目の上
/// tone   … 粒ごとに決まる明暗 [0,1)
void crystal(vec2 p, out float border, out float tone) {
	vec2 cell = floor(p);
	vec2 f = p - cell;
	float d1 = 9.0;
	float d2 = 9.0;
	vec2 id = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 c = cell + g;
			float d = length(g + hash2(c) - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				id = c;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	border = d2 - d1;
	tone = fract(sin(dot(id, vec2(12.9898, 78.233))) * 43758.5453);
}


void vertex() {
	local_pos = VERTEX;
}


void fragment() {
	vec2 p = local_pos;
	float d = edge_distance(p);
	float cell = max(shard_size, 1.0);

	// 面。上を明るく、下へ向かって暗く
	float t = clamp((p.y - bounds.y) / max(bounds.w, 1.0), 0.0, 1.0);
	float v = mix(face_top, face_bottom, t);

	// 結晶の粒。粒ごとに明暗をつけて、面の中に稜線が見えるようにする
	float border;
	float tone;
	crystal(vec2(p.x, p.y * shard_stretch) / cell, border, tone);
	v *= 1.0 + (tone - 0.5) * 2.0 * shard_contrast;

	// 縁から内側へ流れる光
	float glow = 1.0 - smoothstep(0.0, max(glow_width, 0.001), d);
	v += glow * glow * glow_strength;

	// 表面をゆっくり流れる光。氷の照り返し
	float sheen = sin((p.x + p.y * 2.0) * sheen_width + TIME * sheen_speed);
	v += smoothstep(0.7, 1.0, sheen) * sheen_strength;

	vec3 col = mix(COLOR.rgb, vec3(1.0), white_mix) * v;

	// 粒の割れ目。白く光らせる
	float crack = 1.0 - smoothstep(0.0, max(crack_width, 0.5) / cell, border);
	col = mix(col, vec3(1.0), crack * crack_light);

	// 縁そのもの
	float line = 1.0 - smoothstep(line_width, line_width + 1.5, d);
	col = mix(col, mix(COLOR.rgb, vec3(1.0), line_white), line);

	COLOR = vec4(col, COLOR.a);
}
