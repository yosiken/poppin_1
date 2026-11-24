shader_type canvas_item;
//
// 地形を模様で塗る。芝や土のような、画面いっぱいに敷く絵のためのもの。
//
// terrain_fill.gdshader との違いは2つだけ。
//
//   1. UV を Polygon2D の UV ではなく「ワールドの px」から作る。
//      ブロックの拡大率や、地形をどこで分割したかに関係なく、
//      隣のブロックと柄が繋がる。本編の Gfx ブロックは縦横別に拡大されている
//      ものが多いので（Stage04 の (0.28, 2.6) など）、UV のままだと
//      ブロックごとに模様の伸び方が変わってしまう
//   2. parallax_offset のぶん模様をずらす。カメラが動くと模様だけが少し
//      遅れて動き、地面に厚みがあるように見える。値はスクリプトが入れる
//      （scripts/terrain_sprite.gd）
//
// 下端を暗くする影は terrain_fill と同じものを持っている。混ぜて使っても
// 地面の接地感が変わらないようにするため。

uniform vec2 pattern_size = vec2(1024.0, 1024.0);  // 1枚ぶんの大きさ (ワールド px)
uniform vec2 parallax_offset = vec2(0.0);        // 模様をずらす量 (px)。スクリプトが入れる
// 1マスごとに絵を反転して貼る。四辺が繋がっていない絵でも継ぎ目が出ない
uniform bool mirror_tiling = true;
// 模様の絵をノードのテクスチャとは別に持つとき（GroundPattern の .tres を
// 割り当てたとき）に使う。スクリプトが入れる。切っているあいだは
// ノードのテクスチャを模様として読む（前からの使いかた）
uniform bool use_pattern_texture = false;
uniform sampler2D pattern_texture : filter_nearest, repeat_enable;

uniform float shadow_height = 24.0;
uniform float shadow_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float bottom_y = 0.0;

varying float local_y;
varying vec2 world_pos;
// 頂点の色（Polygon2D の color）。fragment の COLOR は絵が掛かったあとなので、
// 素の色はここで取っておく
varying vec4 vertex_color;


void vertex() {
	local_y = VERTEX.y;
	vertex_color = COLOR;
	// ワールド座標。ノードの位置・拡大・回転を通したあとの px
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}


void fragment() {
	vec2 uv = (world_pos - parallax_offset) / max(pattern_size, vec2(1.0, 1.0));
	if (mirror_tiling) {
		uv = abs(fract(uv * 0.5) * 2.0 - 1.0);
	}
	// 掛けるのは頂点の色（vertex() で取っておいたもの）。COLOR ではない。
	//
	// fragment に入ってくる COLOR には、組み込みがもう texture(TEXTURE, UV) を
	// 掛けてある。そこへ自分で読んだ絵をさらに掛けると、絵が2回掛かって
	// 暗く・濃くなる（同じ UV なら色が2乗になる。tile_00 で 219,138,75 が
	// 194,81,23 になっていた）。UV が違うと、別の写像の絵が薄く重なる。
	// event_bg_hide.gdshader の末尾にも同じ注意書きがある
	//
	// 絵は最近傍で読む（texelFetch で1ドットを直接取る）。
	//
	// texture() で読むと、フィルタはノードの texture_filter に従う。今は
	// TerrainSprite が Nearest に固定しているので問題ないが、ノードの設定を
	// 誰かが Linear にしたり、このマテリアルを別のノードに貼ったりすると、
	// ドットの境目がぼける。texelFetch はフィルタを通らないので、どこに
	// 貼っても必ず四角いドットのまま出る
	vec2 tex_size = vec2(use_pattern_texture ? textureSize(pattern_texture, 0) : textureSize(TEXTURE, 0));
	vec2 wrapped = mirror_tiling ? uv : fract(uv);   // 反転のときは uv がもう 0〜1
	ivec2 texel = clamp(ivec2(floor(wrapped * tex_size)), ivec2(0), ivec2(tex_size) - 1);
	vec4 src = use_pattern_texture ? texelFetch(pattern_texture, texel, 0) : texelFetch(TEXTURE, texel, 0);
	vec4 tex_color = src * vertex_color;

	float dist_from_bottom = bottom_y - local_y;
	float shade = 1.0 - smoothstep(0.0, max(shadow_height, 0.001), dist_from_bottom);
	tex_color.rgb = mix(tex_color.rgb, shadow_color.rgb, shade * shadow_strength * shadow_color.a);

	COLOR = tex_color;
}
