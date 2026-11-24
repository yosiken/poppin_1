shader_type canvas_item;
//
// 滝。ColorRect に貼って使う（中景の Parallax2D の子に置く想定）。
//
// 矩形の上端が落ち口、下端が滝つぼ。水の帯は矩形の真ん中に width_ratio の
// 幅で落ち、滝つぼの泡としぶきは矩形いっぱいまで広がる。矩形の大きさを
// 変えるだけで形が決まるので、大きさをシェーダーに教える必要はない
// （fwidth で矩形の px を割り出している）。
//
// それらしく見せている仕掛け:
//
//   1. 重力で加速する。水の筋は、上では短く、落ちるほど引き伸ばされて
//      長くなる。模様を「落ちた距離の平方根」で読むと、模様が自由落下と
//      同じ動きになる（sqrt(y + y0) は時間に比例して増える）
//   2. 落ちるほど空気を含んで白くなる。上は透明で後ろが透け、下は白い
//   3. 縁はちぎれて細い筋になる
//   4. 後ろの景色が水でゆがむ（refraction）。0 にすると重さが少し減る
//   5. 落ち口の盛り上がりの光、流れと一緒に落ちるきらめき
//   6. 滝つぼで泡が湧き上がり、しぶきが横へ広がって立ちのぼる
//
// ピクセルアートの背景に合わせるときは pixel_size と color_steps を入れる。
//

// ─────────────────────────────── 形
group_uniforms shape;
// 水の帯の幅（矩形の横幅に対する割合）。残りは滝つぼのしぶき用の余白
uniform float width_ratio : hint_range(0.05, 1.0) = 0.5;
// 下に行くほど帯が広がる量。0 でまっすぐ、マイナスで細くなる
uniform float spread : hint_range(-0.5, 1.5) = 0.2;
// 縁のゆらぎ（帯の半分の幅に対する割合）
uniform float edge_wobble : hint_range(0.0, 0.5) = 0.12;
// 縁のぼかし（帯の半分の幅に対する割合）。小さすぎても 1px はぼかす
uniform float edge_softness : hint_range(0.0, 0.3) = 0.04;
// 落ち口の盛り上がりの光の太さ (px)
uniform float lip_size : hint_range(0.0, 40.0) = 6.0;
// 矩形の下端でぼかす高さ（割合）。下端が手前の絵で隠れるなら 0 でいい
uniform float bottom_fade : hint_range(0.0, 0.3) = 0.04;

// ─────────────────────────────── 流れ
group_uniforms flow;
// 全体の速さ
uniform float speed : hint_range(0.0, 3.0) = 1.0;
// 重力 (px/秒²)。大きいほど下で速くなる
uniform float gravity : hint_range(50.0, 4000.0) = 700.0;
// 落ち口での速さ (px/秒)
uniform float start_speed : hint_range(1.0, 400.0) = 80.0;
// 水の筋の太さ (px)
uniform float streak_width : hint_range(1.0, 40.0) = 7.0;
// 水の筋の長さ。大きいほど長く伸びる
uniform float streak_length : hint_range(0.2, 4.0) = 1.0;

// ─────────────────────────────── 色
group_uniforms colors;
// 深いところの色（筋の暗い部分）
uniform vec4 deep_color : source_color = vec4(0.06, 0.28, 0.38, 1.0);
// 水の色
uniform vec4 water_color : source_color = vec4(0.32, 0.66, 0.78, 1.0);
// 泡・しぶきの色
uniform vec4 foam_color : source_color = vec4(0.94, 0.98, 1.0, 1.0);
// 透明さ。上のほうでどれだけ後ろが透けるか
uniform float clarity : hint_range(0.0, 1.0) = 0.45;
// 落ちるほど白く泡立つ量
uniform float aeration : hint_range(0.0, 1.0) = 0.65;
// 落ち口の光の強さ
uniform float lip_glow : hint_range(0.0, 1.0) = 0.55;
// 流れと一緒に落ちるきらめきの量
uniform float sparkle : hint_range(0.0, 1.0) = 0.5;

// ─────────────────────────────── 滝つぼ
group_uniforms pool;
// 泡が湧く高さ（矩形の高さに対する割合）
uniform float foam_height : hint_range(0.0, 0.6) = 0.14;
// 泡が横へ広がる量（帯の幅に対する倍率）
uniform float foam_spread : hint_range(0.0, 3.0) = 0.8;
// しぶきの濃さ
uniform float mist_amount : hint_range(0.0, 1.0) = 0.55;
// しぶきが立ちのぼる高さ（割合）
uniform float mist_height : hint_range(0.0, 1.0) = 0.35;

// ─────────────────────────────── 後ろのゆがみ・ピクセル
group_uniforms look;
// 後ろの景色をゆがめる量 (px)。0 で切る
uniform float refraction : hint_range(0.0, 16.0) = 3.0;
// ドットの大きさ (px)。0 でなめらか。ピクセルアートの背景に合わせるなら 2〜3
uniform float pixel_size : hint_range(0.0, 8.0, 1.0) = 0.0;
// 色の段数。0 でなめらか。ピクセルアート風にするなら 6〜10
uniform float color_steps : hint_range(0.0, 32.0, 1.0) = 0.0;
group_uniforms;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

// ノードの中での px。ColorRect なら左上が (0,0)
varying vec2 local_px;
// 頂点の色（ColorRect の color / modulate）。最後に掛ける
varying vec4 vertex_color;


void vertex() {
	local_px = VERTEX;
	vertex_color = COLOR;
}


// ─────────────────────────────── ノイズ
// 整数のハッシュ (PCG)。TIME が大きくなっても模様が崩れない
// （小数の sin/fract のハッシュは、座標が数万を超えると縞が出る。
// 掛け算1回の簡単な整数ハッシュは、隣のマスと値が似てしまい、
// 筋の中に渦のような細い線が出た）
float hash(vec2 p) {
	uvec2 v = uvec2(ivec2(floor(p)));
	v = v * 1664525u + 1013904223u;
	v.x += v.y * 1664525u;
	v.y += v.x * 1664525u;
	v = v ^ (v >> 16u);
	v.x += v.y * 1664525u;
	v.y += v.x * 1664525u;
	v = v ^ (v >> 16u);
	return float(v.x) * (1.0 / 4294967295.0);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += amp * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.3);
		amp *= 0.5;
	}
	return sum / 0.9375;
}

// 上に重ねる（a が手前）。rgb はまだ alpha を掛けていない色
vec4 over(vec4 front, vec4 back) {
	float a = front.a + back.a * (1.0 - front.a);
	vec3 rgb = (front.rgb * front.a + back.rgb * back.a * (1.0 - front.a)) / max(a, 1e-5);
	return vec4(rgb, a);
}


void fragment() {
	// 矩形の大きさ (px)。px と UV はどちらも矩形の上で一次なので、
	// 傾きの比がそのまま大きさになる
	vec2 size = fwidth(local_px) / max(fwidth(UV), vec2(1e-6));
	// 左上からの px。local_px をそのまま使わないのは、中央基準のノード
	// （Sprite2D など）に貼っても上端が落ち口になるようにするため
	vec2 px = UV * size;
	vec2 uv = UV;
	if (pixel_size >= 1.0) {
		px = (floor(px / pixel_size) + 0.5) * pixel_size;
		uv = px / size;
	}
	float t = TIME * speed;

	// ── 落ちる水と一緒に動く座標
	// 自由落下では sqrt(y + y0) が時間に比例して増える。だから
	// w = sqrt(y + y0) - t * sqrt(g/2) は、落ちていく水の1かたまりの上で一定。
	// これで模様を読むと、上で遅く下で速く、筋が下ほど伸びる
	float g = max(gravity, 1.0);
	float y0 = start_speed * start_speed / (2.0 * g);
	float fall_px = uv.y * size.y;
	float w = (sqrt(fall_px + y0) - t * sqrt(0.5 * g)) * 0.3 / max(streak_length, 0.01);
	float xs = (uv.x - 0.5) * size.x / max(streak_width, 0.5);

	// ── 水の帯の形
	float half_w = 0.5 * width_ratio * (1.0 + spread * uv.y);
	float nx = (uv.x - 0.5) / max(half_w, 1e-4);              // 帯の中で -1〜1
	float wob_l = (fbm(vec2(w * 0.6, 3.7)) - 0.5) * 2.0 * edge_wobble;
	float wob_r = (fbm(vec2(w * 0.6, 11.2)) - 0.5) * 2.0 * edge_wobble;
	float soft = max(edge_softness, 1.0 / max(half_w * size.x, 1.0));
	float body = smoothstep(-1.0 - wob_l - soft, -1.0 - wob_l + soft, nx)
			* (1.0 - smoothstep(1.0 + wob_r - soft, 1.0 + wob_r + soft, nx));

	// ── 水の筋
	float n1 = fbm(vec2(xs * 0.5, w));
	float n2 = fbm(vec2(xs * 1.3 + 5.2, w * 2.1 + 3.1));
	float n3 = vnoise(vec2(xs * 3.0 + 1.7, w * 4.0));
	float streak = n1 * 0.5 + n2 * 0.35 + n3 * 0.15;

	// 縁はちぎれて細い筋になる
	float edge = smoothstep(0.55, 1.0, abs(nx));
	body *= mix(1.0, smoothstep(0.35, 0.6, n2 + 0.15 * (1.0 - uv.y)), edge);

	// 落ちるほど・縁ほど空気を含んで白い
	float aer = clamp(aeration * smoothstep(-0.15, 0.9, uv.y) + 0.35 * edge * aeration, 0.0, 1.0);
	float white = smoothstep(0.62 - aer * 0.45, 0.95 - aer * 0.3, streak);

	vec3 col = mix(deep_color.rgb, water_color.rgb, smoothstep(0.2, 0.8, n1));
	// 光は左上から。帯を丸い柱に見せる
	col *= 0.92 + 0.16 * (0.5 - 0.5 * nx);
	col = mix(col, foam_color.rgb, white);

	// 落ち口の光。縁を越えて丸く盛り上がったところが光る
	float lip = exp(-pow(fall_px / max(lip_size, 0.5) - 0.8, 2.0));
	lip *= 0.6 + 0.4 * vnoise(vec2(xs * 0.4 + t * 0.6, 2.0));
	col += foam_color.rgb * lip * lip_glow * 0.6;

	// きらめき。水と一緒に落ちる小さな点が、ときどき光る
	vec2 sc = vec2(xs * 1.2, w * 2.5);
	vec2 cf = fract(sc) - 0.5;
	float h = hash(floor(sc) + vec2(71.0, 13.0));
	float dot_shape = smoothstep(0.3, 0.0, length(cf * vec2(1.0, 0.6)));
	float twinkle = pow(max(sin(TIME * 7.0 + h * 60.0), 0.0), 6.0);
	col += foam_color.rgb * step(0.9, h) * dot_shape * twinkle * sparkle * 0.8;

	// 透け具合。澄んだところは後ろが見え、白いところは見えない
	float opacity = mix(1.0 - clarity, 1.0, clamp(white + aer * 0.6 + lip * 0.5, 0.0, 1.0));

	// 後ろの景色（ゆがめて、水の色で少し染める）
	vec2 offset = vec2(n2 - 0.5, n1 - 0.5) * 2.0 * refraction;
	vec3 behind = textureLod(screen_tex, SCREEN_UV + offset * SCREEN_PIXEL_SIZE, 0.0).rgb;
	behind *= mix(vec3(1.0), water_color.rgb * 1.3, 0.55);
	vec4 water = vec4(mix(behind, col, opacity), body);

	// ── 滝つぼの泡
	// 泡の場所で 0→1。fl は上へはみ出すとマイナスになる（盛り上がりの計算用）
	float fl = (uv.y - (1.0 - foam_height)) / max(foam_height, 1e-3);
	float fy = clamp(fl, 0.0, 1.0);
	fy = fy * fy * (3.0 - 2.0 * fy);
	vec2 fp = px / 26.0;
	vec2 warp = vec2(fbm(fp + vec2(0.0, t * 0.8)), fbm(fp + vec2(5.2, -t * 0.6)));
	// 模様を下から読んでいくので、泡は湧き上がるように上へ動く
	float f = fbm(fp * 1.3 + warp * 2.0 + vec2(0.0, t * 0.9));
	float bottom_half_w = 0.5 * width_ratio * (1.0 + spread);
	float foam_hw = bottom_half_w * (1.0 + foam_spread * fy);
	float fx = abs(uv.x - 0.5) / max(foam_hw, 1e-4);
	float foam = (1.0 - smoothstep(0.55, 1.0, fx + (f - 0.5) * 0.6))
			* smoothstep(0.0, 0.35, fl + (f - 0.5) * 0.8);
	// ↑ fy ではなく fl で読む。fy は泡の場所より上で 0 に貼り付くので、
	// そこへノイズを足すと滝の途中まで泡が漏れ、煙のような渦が出ていた。
	// fl なら上へ行くほどマイナスが大きくなり、盛り上がりは泡の高さの3割まで
	foam = clamp(foam * (0.85 + 0.4 * f), 0.0, 1.0);
	vec3 foam_rgb = mix(foam_color.rgb * vec3(0.72, 0.84, 0.9), foam_color.rgb, smoothstep(0.3, 0.75, f));
	vec4 foam_layer = vec4(foam_rgb, foam);

	// ── しぶき。広く薄く、横へ流れながら立ちのぼる
	float my = smoothstep(1.0 - max(mist_height, 1e-3), 1.0, uv.y);
	float mx = 1.0 - smoothstep(0.25, 1.0, abs(uv.x - 0.5) * 2.0);
	float m = fbm(px / 70.0 + vec2(t * 0.12, t * 0.35));
	float m2 = fbm(px / 32.0 + vec2(-t * 0.2, t * 0.6) + 3.0);
	float mist = mist_amount * my * mx * smoothstep(0.2, 0.75, m * 0.7 + m2 * 0.3) * 0.9;
	vec4 mist_layer = vec4(foam_color.rgb, mist);

	vec4 result = over(mist_layer, over(foam_layer, water));

	// 下端でぼかす
	result.a *= 1.0 - smoothstep(1.0 - max(bottom_fade, 1e-4), 1.0, uv.y) * step(1e-4, bottom_fade);

	// 明るさだけを段にする。R/G/B を別々に段にすると、白の近くで
	// 紫やピンクの色ずれが出る
	if (color_steps >= 1.0) {
		float lum = max(max(result.r, result.g), result.b);
		float q = floor(lum * color_steps + 0.5) / color_steps;
		result.rgb *= q / max(lum, 1e-4);
		result.a = floor(result.a * color_steps + 0.5) / color_steps;
	}
	COLOR = result * vertex_color;
}
