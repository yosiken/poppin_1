extends SceneTree
##
## resources/texture/foods/ の素材を 3x3 のスプライトシートに焼いて
## resources/texture/foods.png を作り直す開発用ツール。
##
##   godot --headless --path <project> --script res://tools/make_goal_sheet.gd
##
## foods.png は Stage01〜09 の Goal/Sprite が hframes=3 / vframes=3 で参照している。
## frame 番号はステージ番号-1 なので、SOURCES の並びを変えるとゴールの絵がずれる。
## Stage10 のゴールだけは別テクスチャ (goal.png) なのでここには含めない。
##
## 素材フォルダは .gdignore を置いてインポート対象から外してある（4MB超の元絵を
## 書き出しに含めないため）。そのため load() ではなく Image.load_from_file() で読む。
##

const SRC_DIR := "res://resources/texture/foods"
const OUT_PATH := "res://resources/texture/foods.png"

## frame 0〜8 = Stage01〜09 のゴール
const SOURCES: Array[String] = [
	"日本酒.png",    # 1 日本酒「風の林」
	"ビール.png",    # 2 ビール「ハイパードライ」
	"かに.png",      # 3 カニ
	"ウクレレ.png",  # 4 ウクレレ「レッドアイ田中」
	"まんが.png",    # 5 漫画『葬送のオバーレン』
	"FF6.png",       # 6 ゲーム『ファイナルファンタジア6』
	"宝.png",        # 7 宝箱
	"金.png",        # 8 現金
	"天城越え.png",  # 9 カラオケ「天城越え」
]

const COLS := 3
const ROWS := 3

## 1コマの大きさ。旧 foods.png (278x414) をコマ数で割り切れるよう 1px だけ詰めた値。
## ここを変えるとゴールの表示サイズが全ステージで変わるので、変えるなら
## 各 Stage の Goal/Sprite の scale も同じ比率で直すこと
const CELL := Vector2i(93, 138)

## コマの中での寄せ方。ゴールは地面に置くものなので下寄せにしている
const ALIGN_BOTTOM := true


func _initialize() -> void:
	var sheet := Image.create_empty(CELL.x * COLS, CELL.y * ROWS, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0, 0, 0, 0))

	var failed := 0
	for i in SOURCES.size():
		var path := "%s/%s" % [SRC_DIR, SOURCES[i]]
		var src := Image.load_from_file(path)
		if src == null:
			push_error("読めません: %s" % path)
			failed += 1
			continue
		src.convert(Image.FORMAT_RGBA8)

		# 元絵の余白は素材ごとにバラバラなので、透明な縁を落としてから合わせる
		var used := src.get_used_rect()
		if used.size.x <= 0 or used.size.y <= 0:
			push_error("中身が空です: %s" % path)
			failed += 1
			continue
		var trimmed := src.get_region(used)

		var fitted := _fit(trimmed, CELL)
		var cell_pos := Vector2i(i % COLS, i / COLS) * CELL
		var offset := Vector2i(
			(CELL.x - fitted.get_width()) / 2,
			CELL.y - fitted.get_height() if ALIGN_BOTTOM
				else (CELL.y - fitted.get_height()) / 2)
		sheet.blit_rect(fitted, Rect2i(Vector2i.ZERO, fitted.get_size()),
			cell_pos + offset)

		print("frame %d  %-14s %4dx%-4d -> %3dx%-3d (Stage%02d)" % [
			i, SOURCES[i], used.size.x, used.size.y,
			fitted.get_width(), fitted.get_height(), i + 1])

	if failed > 0:
		push_error("%d 件読めなかったので書き出しを中止します" % failed)
		quit(1)
		return

	var err := sheet.save_png(OUT_PATH)
	print("-> %s  %dx%d  %s" % [OUT_PATH, sheet.get_width(), sheet.get_height(),
		error_string(err)])
	quit(1 if err != OK else 0)


## 縦横比を保ったままコマに収まる最大サイズへ縮小する
func _fit(src: Image, cell: Vector2i) -> Image:
	var w := src.get_width()
	var h := src.get_height()
	var k: float = minf(float(cell.x) / w, float(cell.y) / h)
	var out := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, src.get_data())

	# 透明部分の RGB は黒のことが多く、そのまま縮小すると縁が黒ずむ。
	# アルファを乗算してから縮小し、あとで割り戻す
	_premultiply(out, true)
	out.resize(maxi(1, int(round(w * k))), maxi(1, int(round(h * k))),
		Image.INTERPOLATE_LANCZOS)
	_premultiply(out, false)
	return out


func _premultiply(img: Image, forward: bool) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a <= 0.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var k := c.a if forward else 1.0 / c.a
			img.set_pixel(x, y, Color(
				clampf(c.r * k, 0.0, 1.0),
				clampf(c.g * k, 0.0, 1.0),
				clampf(c.b * k, 0.0, 1.0), c.a))
