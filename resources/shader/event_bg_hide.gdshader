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
// 常に動かしている。動かし方は pattern で選ぶ。
//
//   pattern 0 … 流れる  : 目が画面をゆっくり滑っていく（既定）
//   pattern 1 … 拡縮    : 画面中心を軸に目が大きくなったり小さくなったりする
//   pattern 2 … 放射    : 中心ほど目が細かく、外ほど粗い。目は外へ流れ続ける
//
// 出力に COLOR を掛けてはいけない（末尾の注記を参照）。
//
// 名前について: Godot の canvas_item シェーダーには組み込みの識別子があり、
// 同じ名前を宣言するとその場で parse error になって、シェーダーごと死ぬ。
// 絵は「効果なし」で普通に出るので、見ただけでは気づけない。
// 組み込みは全て大文字（TIME / UV / COLOR / TEXTURE / PI / TAU / E など）なので、
// ここで宣言するものは全て小文字にしてある。TAU は組み込みをそのまま使う
//

// 隠す強さ。0 で素通し、1 で mosaic_cells の粗さ
uniform float hide : hint_range(0.0, 1.0) = 0.0;
// hide=1 のときの目の粗さ。画面を何分割するか。小さいほど粗い
uniform float mosaic_cells = 48.0;
// hide=0 のときの分割数。ここまで細かいと元の絵と区別がつかない
uniform float fine_cells = 4096.0;
// 動きの速さ。どの pattern でも共通で効く
uniform float drift_speed = 1.0;
// 動かし方。0=流れる 1=拡縮 2=放射。数値の意味は上の表を参照
uniform int pattern = 1;

// ─── pattern 0（流れる）用
// 目の位置がずれる量。セル何個ぶんか。0.5 で隣の目まで滑る
uniform float grid_drift : hint_range(0.0, 1.0) = 0.5;
// 目の大きさが伸び縮みする割合
uniform float cell_pulse : hint_range(0.0, 0.5) = 0.01;

// ─── pattern 1（拡縮）用
// 目の大きさが伸び縮みする割合。0.45 で 0.55 倍〜1.45 倍を往復する
uniform float scale_amount : hint_range(0.0, 0.9) = 0.45;

// ─── pattern 2（放射）用
// 画面の縦横比 (幅/高さ)。輪を楕円にしないために要る。Cutscene 側から入れる
uniform float aspect = 1.7777778;
// 輪が外へ流れる速さ。1 で「目ひとつぶん」進む
uniform float radial_flow : hint_range(0.0, 2.0) = 0.35;


// 画面をまたぐ四角い目。offset はセル単位のずれ
vec2 grid_uv(vec2 uv, float cells, vec2 offset) {
	return (floor(uv * cells + offset) + 0.5 - offset) / cells;
}


// 画面中心を軸にした四角い目。中心で目を切るので、大きさを変えると
// 目が中心から外へ向かって広がる（中心の目だけは動かない）
vec2 center_grid_uv(vec2 uv, float cells) {
	vec2 c = uv - 0.5;
	return (floor(c * cells) + 0.5) / cells + 0.5;
}


// 中心からの距離と角度で切る目。log を通してから等間隔に切るので、
// 目の大きさが半径に比例する（中心ほど細かく、外ほど粗い）。
// flow を増やすと輪がそのまま外へ流れる。log 空間では
// 1 進むごとに元の形に戻るので、繰り返しの継ぎ目が出ない
vec2 radial_uv(vec2 uv, float cells, float flow) {
	vec2 p = (uv - 0.5) * vec2(aspect, 1.0);
	float r = max(length(p), 0.0015);
	float a = atan(p.y, p.x);

	float rings = max(cells * 0.5, 1.0);
	float sectors = max(cells * 2.0, 3.0);

	float lr = log(r);
	float rq = exp((floor(lr * rings - flow) + 0.5 + flow) / rings);
	float aq = (floor(a / TAU * sectors) + 0.5) / sectors * TAU;

	vec2 q = vec2(cos(aq), sin(aq)) * rq;
	return clamp(q / vec2(aspect, 1.0) + 0.5, vec2(0.0), vec2(1.0));
}


void fragment() {
	vec4 src = texture(TEXTURE, UV);
	vec3 rgb = src.rgb;

	if (hide > 0.001) {
		float t = TIME * drift_speed;

		// 目の大きさで補間してから分割数へ戻す
		float cell = mix(1.0 / max(fine_cells, 1.0), 1.0 / max(mosaic_cells, 1.0), hide);
		float cells = 1.0 / max(cell, 0.000001);

		vec2 uv = UV;
		if (pattern == 1) {
			// 目の大きさそのものを往復させる。cells を割るので、
			// k が大きいほど目も大きい
			float k = 1.0 + sin(t * 1.1) * scale_amount;
			uv = center_grid_uv(UV, cells / max(k, 0.05));
		} else if (pattern == 2) {
			uv = radial_uv(UV, cells, t * radial_flow);
		} else {
			// 目の大きさをゆっくり伸び縮みさせる
			cells *= 1.0 + sin(t * 1.3) * cell_pulse;
			// 目の位置をずらす。割る前にセル単位で動かし、割ったあとに戻すことで
			// ブロックの境目そのものが滑っていく
			uv = grid_uv(UV, cells, vec2(sin(t * 0.7), cos(t * 0.53)) * grid_drift);
		}

		// 元の絵とは混ぜない。ここが混ざると「隠している」に見えなくなる
		rgb = texture(TEXTURE, uv).rgb;
	}

	// 色は取り直したものをそのまま出す。COLOR を掛けてはいけない。
	// fragment に入ってくる COLOR には texture(TEXTURE, UV) * modulate が
	// 既に入っているので、掛けると元の絵がもう一度掛かり、
	// モザイクに元絵が混ざったうえ、暗くなる。
	//
	// 透明度だけは COLOR.a を使う。ここには modulate の alpha が
	// 入っているので、Cutscene 側のフェード（modulate.a を動かす）が
	// そのまま効く。alpha は元の絵の位置のものを使うので、
	// モザイクで端がにじむこともない
	COLOR = vec4(rgb, COLOR.a);
}
