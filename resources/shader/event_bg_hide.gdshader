shader_type canvas_item;
//
// イベント背景をモザイクで隠す。
//
// hide は元の絵と「モザイクにした版」を混ぜる割合。0 で元の絵、1 で
// モザイクだけになる。効果の強さを hide でスケールしてはいけない。
// そうすると中間値のとき目が細かいままになり、元の絵がただ薄まったように見える。
// モザイクは常に全開で作り、見せる量だけを hide で決める。
//
// 隠せるかどうかは目の粗さだけで決まる。細かいと縮小版にしかならず、
// 家具の配置から部屋だと分かってしまう。既定の 14 分割は、画面を
// 14x8 程度のブロックに割る粗さ。
//
// 止め絵にすると読み込みに失敗した絵や固まった画面と区別がつかないので、
// 常に動かしている。動かすのは目の位置と大きさの2つ。色は触らない。
//

// モザイクにした版をどれだけ見せるか。0 で元の絵、1 でモザイクだけ
uniform float hide : hint_range(0.0, 1.0) = 0.0;
// 目の粗さ。画面を何分割するか。小さいほど粗い
uniform float mosaic_cells = 14.0;
// 動きの速さ
uniform float drift_speed = 0.4;
// 目の位置がずれる量。セル何個ぶんか。0.5 で隣の目まで滑る
uniform float grid_drift : hint_range(0.0, 1.0) = 0.5;
// 目の大きさが伸び縮みする割合
uniform float cell_pulse : hint_range(0.0, 0.5) = 0.08;

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	vec3 rgb = src.rgb;

	if (hide > 0.001) {
		float t = TIME * drift_speed;

		// 目の大きさをゆっくり伸び縮みさせる
		float cells = max(mosaic_cells, 1.0) * (1.0 + sin(t * 1.3) * cell_pulse);

		// 目の位置をずらす。割る前にセル単位で動かし、割ったあとに戻すことで
		// ブロックの境目そのものが滑っていく
		vec2 offset = vec2(sin(t * 0.7), cos(t * 0.53)) * grid_drift;
		vec2 uv = (floor(UV * cells + offset) + 0.5 - offset) / cells;

		rgb = mix(src.rgb, texture(TEXTURE, uv).rgb, hide);
	}

	COLOR = vec4(rgb, src.a) * COLOR;
}
