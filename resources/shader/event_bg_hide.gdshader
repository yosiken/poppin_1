shader_type canvas_item;
//
// イベント背景をモザイクで隠す。
//
// 元の絵と混ぜない。hide が 0 より大きければ、出るのは常に 100% モザイク。
// 混ぜる方式は、値が 1 に届いていないだけで「鮮明な元絵の上にブロックが乗った」
// 状態になり、隠しているのか崩れているのか分からない絵になる。
//
// hide は目の粗さを決める。0 で元の絵と見分けがつかない細かさ、
// 1 で mosaic_cells の粗さ。間の値も 100% モザイクのまま粗さだけが変わる。
//
// 粗さの補間は目の「大きさ」で行う。分割数で補間すると、1/x の効き方に
// なって中間の大半が細かいまま（元の絵に見える）になる。
//
// 止め絵にすると読み込みに失敗した絵や固まった画面と区別がつかないので、
// 常に動かしている。動かすのは目の位置と大きさの2つ。色は触らない。
//

// 隠す強さ。0 で素通し、1 で mosaic_cells の粗さ
uniform float hide : hint_range(0.0, 1.0) = 0.0;
// hide=1 のときの目の粗さ。画面を何分割するか。小さいほど粗い
uniform float mosaic_cells = 14.0;
// hide=0 のときの分割数。ここまで細かいと元の絵と区別がつかない
uniform float fine_cells = 4096.0;
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

		// 目の大きさで補間してから分割数へ戻す
		float cell = mix(1.0 / max(fine_cells, 1.0), 1.0 / max(mosaic_cells, 1.0), hide);
		float cells = 1.0 / max(cell, 0.000001);

		// 目の大きさをゆっくり伸び縮みさせる
		cells *= 1.0 + sin(t * 1.3) * cell_pulse;

		// 目の位置をずらす。割る前にセル単位で動かし、割ったあとに戻すことで
		// ブロックの境目そのものが滑っていく
		vec2 offset = vec2(sin(t * 0.7), cos(t * 0.53)) * grid_drift;
		vec2 uv = (floor(UV * cells + offset) + 0.5 - offset) / cells;

		// 元の絵とは混ぜない。ここが混ざると「隠している」に見えなくなる
		rgb = texture(TEXTURE, uv).rgb;
	}

	COLOR = vec4(rgb, src.a) * COLOR;
}
