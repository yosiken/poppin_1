shader_type canvas_item;
//
// 降る雪。クレジットの背景の上に、全画面の ColorRect で重ねる。
//
// 冬の公開に合わせたもの。CreditsData の「雪」を切れば出なくなる
// （組み立ては scripts/credits.gd）。
//
// 作り: 粒をセルの格子に1つずつ置き、格子ごと下へ流す。セルが下へずれるだけなので、
// 粒は湧いたり消えたりせず、画面の上から下へ通り抜けていく。
//
// 奥行きは3層。奥は小さく・暗く・遅く、手前は大きく・明るく・速くする。
// 横幅は aspect で正す（matrix_rain.gdshader と同じ渡し方。スクリプトが入れる）。
//
// 降りかたは一定ではなく、ゆっくりした波（breath_*）で強まったり弱まったりする。
// 層ごとに波の位相をずらしてあるので、画面全体が同時に息をつくようには見えない。
//
// 粒の大きさと落ちる速さは画面の高さに対する割合で持つので、
// 解像度が変わっても見え方は変わらない。

uniform float aspect = 1.7778;                          // 画面の 横/縦。スクリプトが入れる
uniform vec4 flake_color : source_color = vec4(1.0, 1.0, 1.0, 0.85);

// 降り方
uniform float amount : hint_range(0.0, 2.0) = 1.0;      // 粒の多さ
uniform float fall_speed : hint_range(0.0, 3.0) = 1.0;  // 落ちる速さ
uniform float wind : hint_range(-0.5, 0.5) = 0.05;      // 横へ流す量。正で右へ
uniform float sway : hint_range(0.0, 0.5) = 0.22;       // 1粒ごとの横揺れ（セル単位）
uniform float sway_speed : hint_range(0.0, 4.0) = 0.8;

// ゆらぎ。強く降ったり弱まったりを繰り返す
uniform float breath_speed : hint_range(0.0, 2.0) = 0.3;   // 波の速さ。0.3 で約21秒に一巡
uniform float breath_amount : hint_range(0.0, 1.0) = 0.35; // 量の振れ幅
uniform float breath_motion : hint_range(0.0, 1.0) = 0.35; // 落ちる速さと風の振れ幅

// 粒
uniform float size : hint_range(0.2, 3.0) = 1.0;        // 粒の大きさ
uniform float softness : hint_range(0.05, 1.0) = 0.6;   // 縁のぼけ。1 に近いほど芯が小さい


vec2 hash22(vec2 p) {
	float a = dot(p, vec2(127.1, 311.7));
	float b = dot(p, vec2(269.5, 183.3));
	return fract(sin(vec2(a, b)) * 43758.5453);
}


/// 速さを揺らしながら進んだ距離。
///
/// 速さそのものに sin を掛けると、速さが変わった瞬間に粒が飛ぶ。
/// 進んだ距離は速さの積分なので、
///   速さ v(t) = rate * (1 + m*sin(wt + p))
///   距離 s(t) = rate * (t + m/w * (cos(p) - cos(wt + p)))
/// として距離の側で揺らす。t=0 で 0 から始まり、途中で飛ばない
float travelled(float rate, float phase) {
	float w = max(breath_speed, 0.001);
	return rate * (TIME + breath_motion / w * (cos(phase) - cos(w * TIME + phase)));
}


/// 1層ぶんの雪。戻り値は粒の濃さ [0,1]
///
/// rows    … 画面の高さを何セルに割るか。小さいほど粒が大きく疎になる
/// fall    … 1秒に落ちる量（1.0 で画面の高さぶん）
/// radius  … 粒の半径（セル単位）
/// density … 粒を置くセルの割合
/// phase   … この層のゆらぎの位相。層ごとにずらす
float snow_layer(vec2 uv, float rows, float fall, float radius, float density,
		float seed, float phase) {
	// セルを正方形にしたいので、横は aspect で伸ばす
	vec2 g = vec2(uv.x * aspect, uv.y) * rows;
	// 格子ごと動かす。引くと粒が下（風は右）へ進む
	g.y -= travelled(fall, phase) * rows;
	g.x -= travelled(wind, phase + 2.1) * rows;

	vec2 base = floor(g);
	vec2 f = g - base;

	// 今どれくらい降っているか。波で増えたり減ったりする
	float now = density * (1.0 + breath_amount * sin(breath_speed * TIME + phase));

	// 粒が隣のセルにはみ出していても切れないよう、周りの8つも見る
	float a = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 ofs = vec2(float(x), float(y));
			vec2 r = hash22(base + ofs + seed);
			// 量が変わるときに粒が点いたり消えたりしないよう、境目は薄く出す
			float live = smoothstep(0.0, 0.12, now - r.x);
			if (live <= 0.0) {
				continue;                       // 粒の無いセル
			}
			// セルの中の位置。はみ出しは隣のセルが拾う
			vec2 c = vec2(fract(r.x * 7.31), fract(r.y * 5.17)) * 0.7 + 0.15;
			c.x += sin(TIME * sway_speed + base.y + ofs.y + r.y * 6.28) * sway;
			float rr = radius * size * (0.55 + 0.9 * r.y);   // 粒ごとに大きさを変える
			float d = length(f - (ofs + c));
			a = max(a, (1.0 - smoothstep(rr * (1.0 - softness), rr, d)) * live);
		}
	}
	return a;
}


void fragment() {
	// 奥 → 手前。手前ほど大きく、速く、濃い。ゆらぎの位相も層ごとにずらす
	float a = snow_layer(UV, 20.0, 0.07 * fall_speed, 0.05, 0.55 * amount, 1.7, 0.0) * 0.45;
	a = max(a, snow_layer(UV, 12.0, 0.112 * fall_speed, 0.055, 0.45 * amount, 9.1, 2.3) * 0.7);
	a = max(a, snow_layer(UV, 7.0, 0.182 * fall_speed, 0.06, 0.3 * amount, 23.3, 4.4));
	COLOR = vec4(flake_color.rgb, a * flake_color.a);
}
