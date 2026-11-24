shader_type canvas_item;
//
// 雲形のポリゴンの中で、雲の絵をゆっくり流す。中景の雲用。
//
// CloudPolygon（scripts/cloud_polygon.gd）のノードに貼って使う。
// ふちを透明にしてBGへなじませるための「縁のマスク」は、ポリゴンの形から
// スクリプトが作ってノードのテクスチャ（TEXTURE）に入れている。
// マスクはポリゴンの内側で白、ふちへ向かって黒へ落ちる。
//
// 雲の絵はノードのテクスチャではなく cloud_texture で持つので、
// このマテリアルを何枚の雲に貼っても同じ .tres を見る（1か所直せば全部変わる）。
//
// 縁は、マスクのぼかしに雲の明るさを混ぜて、雲の形にちぎれるようにしている
// （edge_breakup）。絵が流れると縁の形もゆっくり変わる。
//

// 流す雲の絵。横に継ぎ目がない絵を使う（縦は繰り返さない）
uniform sampler2D cloud_texture : source_color, filter_linear_mipmap, repeat_enable;
// 絵1px をノードの何 px で見せるか
uniform float texture_scale : hint_range(0.05, 8.0) = 1.0;
// 絵の位置合わせ (px)。ノードの原点に絵の縦の真ん中が来るのが 0
uniform vec2 texture_offset = vec2(0.0, 0.0);
// 流れる速さ (px/秒)。マイナスで左へ
uniform vec2 flow_speed = vec2(-6.0, 0.0);

// ふちを雲の形でちぎる量。0 でマスクどおりのなめらかなぼかし
uniform float edge_breakup : hint_range(0.0, 1.0) = 0.5;
// 青空の部分を透かす量。0 で絵のまま、1 で雲だけ残す（色の鮮やかさで見分ける）
uniform float sky_cutout : hint_range(0.0, 1.0) = 0.0;
// 全体の濃さ
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
// 色を掛ける。遠くの雲を薄く・青っぽくするのに使う
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// ノードの中での px
varying vec2 local_px;
// 頂点の色（Polygon2D の color）。fragment の COLOR には組み込みがもう
// TEXTURE（ここではマスク）を掛けてあるので、素の色はここで取っておく
varying vec4 vertex_color;


void vertex() {
	local_px = VERTEX;
	vertex_color = COLOR;
}


void fragment() {
	vec2 tex_size = vec2(textureSize(cloud_texture, 0)) * max(texture_scale, 0.01);
	vec2 p = (local_px - texture_offset - TIME * flow_speed) / tex_size + vec2(0.0, 0.5);
	// 縦は繰り返さない（空の上と下で色が違うので、繋ぐと段が出る）。
	// 横は繰り返しのサンプラーに任せる。fract を通さないので継ぎ目でミップマップが乱れない
	p.y = clamp(p.y, 0.001, 0.999);
	vec4 cloud = texture(cloud_texture, p);

	// 縁のマスク（スクリプトが作ったもの）。内側 1、ふち 0
	float mask = texture(TEXTURE, UV).r;

	// 明るいところ（雲の白）ほど外まで残り、暗いところ（空・雲の影）から先に消える
	float lum = dot(cloud.rgb, vec3(0.299, 0.587, 0.114));
	float a = clamp(mask * (1.0 + edge_breakup) - edge_breakup * (1.0 - lum), 0.0, 1.0);
	a = a * a * (3.0 - 2.0 * a);

	// 青空を透かす。空は鮮やか、雲は白に近い（鮮やかさが低い）
	float mx = max(max(cloud.r, cloud.g), cloud.b);
	float sat = (mx - min(min(cloud.r, cloud.g), cloud.b)) / max(mx, 1e-4);
	a *= mix(1.0, 1.0 - smoothstep(0.25, 0.6, sat), sky_cutout);

	COLOR = vec4(cloud.rgb * tint.rgb, a * opacity * tint.a) * vertex_color;
}
