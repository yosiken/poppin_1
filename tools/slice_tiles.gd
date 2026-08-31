extends SceneTree
##
## タイルシートを1枚ずつの画像に切り出す開発用ツール。
##   godot --headless --path <project> --script res://tools/slice_tiles.gd
##
## なぜ切り出すか:
##   Polygon2D にテクスチャを繰り返して貼るには、1枚が独立した画像である
##   必要がある。シートのまま貼ると、繰り返しでシート全体が並んでしまう。
##
## texture01.jpg の並び (4x4、左上から右へ):
##    0 荒波      1 空と雲    2 砂浜      3 芝
##    4 丸石畳    5 木の板    6 レンガ    7 土
##    8 茂み      9 うろこ雲 10 溶岩     11 水面(淡)
##   12 金属板   13 花畑     14 星空     15 水面(白波)
##

const SRC := "res://resources/texture/Parts/texture01.jpg"
const OUT_DIR := "res://resources/texture/Parts/tiles"
const COLS := 4
const ROWS := 4
## 1枚ごとに内側へ削る量 (px)。シートのマス目の区切り線をそのまま含めると、
## 繰り返して貼ったときに格子状の線として出てしまう。
## jpg なので圧縮で滲んだぶんも見込んで少し多めに削る
const INSET := 5


func _initialize() -> void:
	var tex := load(SRC) as Texture2D
	if tex == null:
		push_error("読み込めません: %s" % SRC)
		quit(1)
		return
	var src := tex.get_image()
	var w := src.get_width() / COLS
	var h := src.get_height() / ROWS
	print("元 %dx%d → 1枚 %dx%d を %d 枚（区切り線を %dpx 削る）"
		% [src.get_width(), src.get_height(), w - INSET * 2, h - INSET * 2, COLS * ROWS, INSET])

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var index := 0
	for row in ROWS:
		for col in COLS:
			var cell := src.get_region(Rect2i(
				col * w + INSET, row * h + INSET, w - INSET * 2, h - INSET * 2))
			var path := "%s/tile_%02d.png" % [OUT_DIR, index]
			var err := cell.save_png(ProjectSettings.globalize_path(path))
			if err != OK:
				push_error("保存に失敗: %s (%s)" % [path, error_string(err)])
			index += 1
	print("→ %s" % OUT_DIR)
	quit()
