shader_type canvas_item;
//
// 地形タイルの塗り。ミラータイリングと、下端を暗くする影をまとめて持つ。
//
// ミラータイリング: 1マスごとに絵を反転して貼る。継ぎ目のない素材でなくても
// 繋ぎ目が出なくなる代わりに、対称の模様が出る(mirror_tile.gdshader を統合)。
//
// 影: ポリゴンの下端(ローカルYの最大値。bottom_y としてスクリプトから渡す)
// からの距離で暗くする。地面に接している感じを出すため。
//

uniform bool mirror_tiling = false;

uniform float shadow_height = 24.0;
uniform float shadow_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float bottom_y = 0.0;

varying float local_y;

void vertex() {
	local_y = VERTEX.y;
}

void fragment() {
	vec2 uv = UV;
	if (mirror_tiling) {
		uv = abs(fract(uv * 0.5) * 2.0 - 1.0);
	}
	vec4 tex_color = texture(TEXTURE, uv) * COLOR;

	float dist_from_bottom = bottom_y - local_y;
	float shade = 1.0 - smoothstep(0.0, max(shadow_height, 0.001), dist_from_bottom);
	tex_color.rgb = mix(tex_color.rgb, shadow_color.rgb, shade * shadow_strength * shadow_color.a);

	COLOR = tex_color;
}
