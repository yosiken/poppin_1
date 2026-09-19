shader_type canvas_item;
//
// ラスタースクロール。走査線ごとに横へずらして、水面や陽炎の揺れを出す。
//
// ずらす量は「画像の何px目か」で決める。UV(0〜1)で決めると画像の縦幅に
// よって波の細かさが変わってしまうため。
//
// 効かせる範囲を from_y〜to_y で切れるので、空と海が1枚に入った絵でも
// 海だけを揺らせる。
//

// 横ずれの大きさ (px)
uniform float amplitude = 2.0;
// 波の縦方向の間隔 (px)。小さいほど細かく波打つ
uniform float wavelength = 24.0;
// 波が流れる速さ
uniform float speed = 2.0;
// 効かせる範囲。画像の上端 0.0 〜 下端 1.0
uniform float from_y : hint_range(0.0, 1.0) = 0.0;
uniform float to_y : hint_range(0.0, 1.0) = 1.0;
// 範囲の境目をなじませる幅 (0〜1)。0 にすると効き始めに段差が出る
uniform float fade : hint_range(0.0, 0.5) = 0.03;

void fragment() {
	float texel_h = TEXTURE_PIXEL_SIZE.y;
	float y_px = UV.y / max(texel_h, 0.000001);

	// 範囲の内側だけ 1.0 に近づく重み
	float weight = smoothstep(from_y - fade, from_y + fade, UV.y)
		* (1.0 - smoothstep(to_y - fade, to_y + fade, UV.y));

	float offset_px = amplitude * sin(y_px / max(wavelength, 0.001) * TAU + TIME * speed);
	vec2 uv = UV + vec2(offset_px * TEXTURE_PIXEL_SIZE.x * weight, 0.0);
	COLOR = texture(TEXTURE, uv) * COLOR;
}
