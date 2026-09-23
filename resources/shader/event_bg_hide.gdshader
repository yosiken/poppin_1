shader_type canvas_item;
//
// イベント背景を隠す効果。モザイクとボケを同時にかけ、hide で強さを決める。
//
// 隠している間も微かに動かしている。完全な止め絵にすると、読み込みに失敗した絵や
// 一時停止と見分けがつかず「わざと隠している」と伝わらないため。
//
// モザイクとボケだけでは隠せない。どちらも明暗の配置を残すので、
// 「窓が明るい」「床が暗い」といった手がかりから絵柄が読めてしまう。
// 色を抜き、単色へ寄せて情報量そのものを落とす必要がある。
//
// ボケは元のテクスチャを 3x3 で取る。画面テクスチャを使った多段ぼかしは
// GL Compatibility では割に合わないので採用していない。
//

// 隠す強さ。0 で素通し、1 で完全に隠す
uniform float hide : hint_range(0.0, 1.0) = 0.0;
// hide=1 のときのモザイクの粗さ。画像を何分割するか。小さいほど粗い
uniform float mosaic_cells = 28.0;
// hide=1 のときのボケの広がり (px)
uniform float blur_px = 4.0;
// 揺らぎの速さ
uniform float drift_speed = 0.4;
// 揺らぎの大きさ (UV)。大きくしすぎると絵が泳いで見える
uniform float drift_amount = 0.005;
// 隠すための覆いの色
uniform vec4 veil_color : source_color = vec4(0.06, 0.07, 0.12, 1.0);
// hide=1 のときに覆いへ寄せる割合。1 で完全な単色になる。
// ここが実際に「隠す」効き目を決める
uniform float veil_amount : hint_range(0.0, 1.0) = 0.75;
// hide=1 のときに色を抜く割合。色は絵柄を思い出す手がかりになるので落とす
uniform float desaturate : hint_range(0.0, 1.0) = 0.65;

void fragment() {
	vec2 uv = UV;
	float t = TIME * drift_speed;

	// 隠しているときだけ、ゆっくり漂わせる
	uv += vec2(sin(t * 1.7 + UV.y * 6.0), cos(t * 1.3 + UV.x * 5.0)) * drift_amount * hide;

	// モザイク。hide が上がるほど粗くする。
	// 目の大きさ自体もゆっくり呼吸させて、止まって見えないようにする
	if (hide > 0.001) {
		float cells = mix(4096.0, max(mosaic_cells, 1.0), hide);
		cells *= 1.0 + sin(t * 2.1) * 0.04 * hide;
		uv = (floor(uv * cells) + 0.5) / cells;
	}

	// ボケ。3x3 の平均
	float r = blur_px * hide;
	vec4 col;
	if (r > 0.01) {
		vec2 step_uv = TEXTURE_PIXEL_SIZE * r;
		col = vec4(0.0);
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				col += texture(TEXTURE, uv + vec2(float(x), float(y)) * step_uv);
			}
		}
		col /= 9.0;
	} else {
		col = texture(TEXTURE, uv);
	}

	// 色を抜く
	float gray = dot(col.rgb, vec3(0.299, 0.587, 0.114));
	col.rgb = mix(col.rgb, vec3(gray), desaturate * hide);

	// 覆いへ寄せる。覆いの濃さ自体もゆっくり流して、面で動いて見えるようにする
	float wave = 0.85 + 0.15 * sin(t * 1.9 + UV.x * 4.0 + UV.y * 3.0);
	col.rgb = mix(col.rgb, veil_color.rgb, clamp(veil_amount * hide * wave, 0.0, 1.0));

	COLOR = col * COLOR;
}
