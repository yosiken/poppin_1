shader_type canvas_item;
//
// SubViewport に焼いた3Dキャラの外周へ輪郭線を描く。
// 3D側で裏返しのメッシュを重ねる方式と違い、モデルの形状や法線に左右されず、
// 太さが常に画面基準で一定になる。
//
// 透明な画素のうち、少し離れたところに不透明な画素があるものを縁として塗る。
// キャラがビューポートの端に接していると、その辺だけ縁が出ないので注意
//

uniform vec4 outline_color : source_color = vec4(0.08, 0.07, 0.1, 1.0);
// 輪郭の太さ (SubViewport のテクセル単位)
uniform float outline_width : hint_range(0.0, 8.0) = 2.0;

// ビューポートの外はテクスチャの繰り返し設定に左右されるため、
// 範囲外は必ず透明として扱う
// TEXTURE は fragment の外から参照できないので引数で受け取る
float alpha_at(sampler2D tex, vec2 uv) {
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		return 0.0;
	}
	return texture(tex, uv).a;
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	if (base.a > 0.5 || outline_width <= 0.0) {
		COLOR = base;
	} else {
		vec2 d = TEXTURE_PIXEL_SIZE * outline_width;
		// 斜めは 1/√2 に縮める。同じ長さで取ると角だけ太って四角く見える
		vec2 dd = d * 0.70710678;
		float a = 0.0;
		a = max(a, alpha_at(TEXTURE, UV + vec2(d.x, 0.0)));
		a = max(a, alpha_at(TEXTURE, UV - vec2(d.x, 0.0)));
		a = max(a, alpha_at(TEXTURE, UV + vec2(0.0, d.y)));
		a = max(a, alpha_at(TEXTURE, UV - vec2(0.0, d.y)));
		a = max(a, alpha_at(TEXTURE, UV + dd));
		a = max(a, alpha_at(TEXTURE, UV - dd));
		a = max(a, alpha_at(TEXTURE, UV + vec2(dd.x, -dd.y)));
		a = max(a, alpha_at(TEXTURE, UV - vec2(dd.x, -dd.y)));
		COLOR = vec4(outline_color.rgb, outline_color.a * step(0.5, a));
	}
}
