shader_type canvas_item;
//
// イベント背景を隠す効果。モザイク・ボケ・彩度落とし・単色への寄せを重ねた
// 「隠した版」を作り、元の絵とそれを hide で混ぜる。
//
// hide は混ぜる割合そのもの。0 で元の絵、1 で隠した版だけになる。
// 効果の強さを hide でスケールしてはいけない。そうすると中間値のとき
// モザイクの目が細かいままになり、元の絵がただ薄まっただけに見える。
// 隠した版は常に全開で作り、見せる量だけを hide で決める。
//
// モザイクとボケだけでは隠せない。どちらも明暗の配置を残すので、
// 「窓が明るい」「床が暗い」といった手がかりから絵柄が読めてしまう。
// 色を抜き、単色へ寄せて情報量そのものを落とす必要がある。
//
// ボケは元のテクスチャを 3x3 で取る。画面テクスチャを使った多段ぼかしは
// GL Compatibility では割に合わないので採用していない。
//

// 隠した版をどれだけ見せるか。0 で元の絵のまま、1 で完全に隠れる
uniform float hide : hint_range(0.0, 1.0) = 0.0;
// モザイクの粗さ。画像を何分割するか。小さいほど粗い
uniform float mosaic_cells = 28.0;
// ボケの広がり (px)
uniform float blur_px = 4.0;
// 揺らぎの速さ
uniform float drift_speed = 0.4;
// 揺らぎの大きさ (UV)。大きくしすぎると絵が泳いで見える
uniform float drift_amount = 0.005;
// 隠すための覆いの色
uniform vec4 veil_color : source_color = vec4(0.06, 0.07, 0.12, 1.0);
// 覆いへ寄せる割合。1 にすると元の絵は一切残らない
uniform float veil_amount : hint_range(0.0, 1.0) = 0.92;
// 色を抜く割合。色は絵柄を思い出す手がかりになるので落とす
uniform float desaturate : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	vec4 col = src;

	// hide が 0 のときは何も作らない
	if (hide > 0.001) {
		float t = TIME * drift_speed;

		// ゆっくり漂わせる
		vec2 uv = UV + vec2(sin(t * 1.7 + UV.y * 6.0),
			cos(t * 1.3 + UV.x * 5.0)) * drift_amount;

		// モザイク。目の大きさをゆっくり呼吸させ、止まって見えないようにする
		float cells = max(mosaic_cells, 1.0) * (1.0 + sin(t * 2.1) * 0.04);
		uv = (floor(uv * cells) + 0.5) / cells;

		// ボケ。3x3 の平均
		vec4 hid;
		if (blur_px > 0.01) {
			vec2 step_uv = TEXTURE_PIXEL_SIZE * blur_px;
			hid = vec4(0.0);
			for (int y = -1; y <= 1; y++) {
				for (int x = -1; x <= 1; x++) {
					hid += texture(TEXTURE, uv + vec2(float(x), float(y)) * step_uv);
				}
			}
			hid /= 9.0;
		} else {
			hid = texture(TEXTURE, uv);
		}

		// 色を抜く
		float gray = dot(hid.rgb, vec3(0.299, 0.587, 0.114));
		hid.rgb = mix(hid.rgb, vec3(gray), desaturate);

		// 覆いへ寄せる。
		// 揺らぎは覆いの「色の明るさ」に掛ける。混ぜる割合に掛けると、
		// veil_amount を 1.0 にしても揺らぎのぶんだけ元の絵が透け、
		// しかも透ける量が周期的に変わるので、元の絵とモザイクが混ざったまま
		// 明滅しているように見えてしまう
		float wave = 0.85 + 0.15 * sin(t * 1.9 + UV.x * 4.0 + UV.y * 3.0);
		hid.rgb = mix(hid.rgb, veil_color.rgb * wave, veil_amount);

		// 元の絵と隠した版を混ぜる。ここだけが hide の仕事
		col.rgb = mix(src.rgb, hid.rgb, hide);
	}

	// 透明度は元の絵のまま。ボケで端がにじむのを避ける
	col.a = src.a;
	COLOR = col * COLOR;
}
