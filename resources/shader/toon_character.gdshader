shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
//
// シンプルな段階式トゥーンシェーディング。
// キーライトの当たり方を数階調にはっきり分けて、アニメ塗り風にする。
// 環境光(アンビエント)は通常通りなめらかに乗る（Godotの既定処理に任せる）ので、
// 段差が付くのはキーライト(DirectionalLight3D)側だけ
//

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_nearest;
uniform bool use_texture = false;

// 何階調に分けるか(2以上)
uniform int band_count : hint_range(2, 6) = 3;
// 一番暗い帯の明るさ。0にすると陰が真っ黒になる
uniform float shadow_floor : hint_range(0.0, 1.0) = 0.35;

void fragment() {
	vec4 base = albedo_color;
	if (use_texture) {
		base *= texture(albedo_texture, UV);
	}
	ALBEDO = base.rgb;
	// ALPHA には書かないこと。書いた時点でマテリアルが透明扱いになり、
	// 深度書き込みが止まってメッシュ内側（首など）が手前に描かれてしまう
}

void light() {
	float bands = float(max(band_count, 2));
	float lit = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float stepped = floor(lit * bands) / (bands - 1.0);
	stepped = mix(shadow_floor, 1.0, clamp(stepped, 0.0, 1.0));
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * stepped * ATTENUATION;
}
