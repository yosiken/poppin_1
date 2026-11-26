shader_type canvas_item;

//
// 縁が光る、グラデーションの入った板。
//
// 地形(TerrainPolygon)に貼って使う。板の色は頂点カラー(fill_color)から取るので、
// 緑の足場・茶色の壁・赤い落下床が、同じシェーダーのまま色違いで出る。
//
// 形ごとに値が変わるので、マテリアルは板1枚につき1つ要る
// (tools/gen_tutorial_stage.py が形から計算して .tscn に書き出す):
//   edges[i]   … 形の i 本目の辺。xy が内向きの法線、z が原点からの距離。
//                dot(xy, UV) - z が、その辺までの距離(px)になる
//   edge_count … 辺の本数
//   bounds     … 形の外接矩形 (左, 上, 幅, 高さ)。縦のグラデーションに使う
//
// 位置は頂点シェーダーの VERTEX（＝ポリゴンのローカル座標）をそのまま使う。
// terrain_fill.gdshader が bottom_y でやっているのと同じ考え方
//
// 距離はすべて px で見ているので、大きい板でも小さい板でも縁の太さは変わらない。
//

const int MAX_EDGES = 16;

varying vec2 local_pos;

uniform vec3 edges[MAX_EDGES];
uniform int edge_count = 0;
uniform vec4 bounds = vec4(0.0, 0.0, 1.0, 1.0);

// ── 縁
/// はっきり光る線の太さ (px)
uniform float line_width : hint_range(0.0, 20.0) = 3.0;
/// 線をどれだけ白に寄せるか。0 なら板と同じ色のまま明るくなるだけ
uniform float line_white : hint_range(0.0, 1.0) = 0.6;
/// 線から内側へ流れる光の幅 (px)
uniform float glow_width : hint_range(0.0, 300.0) = 28.0;
uniform float glow_strength : hint_range(0.0, 2.0) = 0.45;

// ── 面
/// 上辺の明るさ
uniform float face_top : hint_range(0.0, 2.0) = 0.40;
/// 下辺の明るさ。上より暗くするとグラデーションになる
uniform float face_bottom : hint_range(0.0, 2.0) = 0.05;

// ── 面に薄く入れる格子
uniform float grid_size = 120.0;
uniform float grid_width = 2.0;
uniform float grid_strength : hint_range(0.0, 1.0) = 0.13;


/// 一番近い辺までの距離 (px)。内側が正
float edge_distance(vec2 p) {
	float d = 1e8;
	for (int i = 0; i < edge_count; i++) {
		d = min(d, dot(edges[i].xy, p) - edges[i].z);
	}
	return d;
}


/// 格子の線の上なら 1 に近づく
float grid_line(vec2 p) {
	vec2 g = abs(fract(p / grid_size) - 0.5) * grid_size;
	return 1.0 - smoothstep(0.0, max(grid_width, 0.5), min(g.x, g.y));
}


void vertex() {
	local_pos = VERTEX;
}


void fragment() {
	vec2 p = local_pos;
	float d = edge_distance(p);

	// 面。上を明るく、下へ向かって暗く
	float t = clamp((p.y - bounds.y) / max(bounds.w, 1.0), 0.0, 1.0);
	float v = mix(face_top, face_bottom, t);
	v += grid_line(p) * grid_strength;

	// 縁から内側へ流れる光。奥へ行くほど弱くなる
	float glow = 1.0 - smoothstep(0.0, max(glow_width, 0.001), d);
	v += glow * glow * glow_strength;

	vec3 col = COLOR.rgb * v;

	// 縁そのもの。白に寄せてはっきり光らせる
	float line = 1.0 - smoothstep(line_width, line_width + 1.5, d);
	col = mix(col, mix(COLOR.rgb, vec3(1.0), line_white), line);

	COLOR = vec4(col, COLOR.a);
}
