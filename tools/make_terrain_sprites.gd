extends SceneTree
##
## ステージのコリジョンから、見た目用のテクスチャポリゴンをまとめて作る。
##
##   godot --headless --path <project> --script res://tools/make_terrain_sprites.gd \
##       -- res://scenes/stages/Stage06.tscn
##
## 引数を省くと STAGE の値を使う。
##
## やること:
##   Terrain の下の CollisionPolygon2D それぞれに対して、
##   同じ形・同じ位置の TerrainSprite を Graphics の下に作る。
##   名前は Gfx_<コリジョン名> にそろえる。
##
## 作り直しても貼った絵は消えない:
##   同じ名前の TerrainSprite が既にあれば、形と位置だけ更新する。
##   texture・tile_size・mirror_tiling は触らない。
##   先に一度走らせて絵を割り当て、あとで地形を直してから走らせ直す、
##   という順で使える。
##
## 貼る絵の初期値は色で決める。コリジョンの塗り色が茶系(r > g)なら岩、
## それ以外は芝。あくまで置き場所を作るための仮なので、
## エディタで1枚ずつ選び直すことを前提にしている。
##
## Graphics は Terrain より後ろに足すので、ベタ塗りの上に重なって描かれる。
## レベルデザイン用の塗り色はデータとして残るため、Graphics を非表示に
## すれば元の見え方に戻る。
##

const STAGE := "res://scenes/stages/Stage06.tscn"
const GRASS := "res://resources/texture/Parts/tiles/tile_03.png"
const ROCK := "res://resources/texture/Parts/tiles/tile_04.png"
const DEFAULT_TILE_SIZE := Vector2(220.0, 0.0)


func _initialize() -> void:
	var path := STAGE
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		path = args[0]

	var packed := load(path) as PackedScene
	if packed == null:
		push_error("読み込めません: %s" % path)
		quit(1)
		return
	var stage := packed.instantiate()
	get_root().add_child(stage)

	var terrain := stage.get_node_or_null(^"Terrain") as StaticBody2D
	if terrain == null:
		push_error("%s に Terrain がありません" % path)
		quit(1)
		return

	var host := stage.get_node_or_null(^"Graphics") as Node2D
	if host == null:
		host = Node2D.new()
		host.name = "Graphics"
		stage.add_child(host)
		host.owner = stage

	var made := 0
	var kept := 0
	for child in terrain.get_children():
		var poly := child as CollisionPolygon2D
		if poly == null:
			continue
		var sprite_name := "Gfx_" + poly.name
		var sprite := host.get_node_or_null(NodePath(sprite_name)) as Polygon2D
		if sprite == null:
			sprite = Polygon2D.new()
			sprite.name = sprite_name
			sprite.set_script(load("res://scripts/terrain_sprite.gd"))
			host.add_child(sprite)
			sprite.owner = stage
			sprite.set("texture", load(ROCK if _is_brown(poly) else GRASS))
			sprite.set("tile_size", DEFAULT_TILE_SIZE)
			made += 1
		else:
			kept += 1
		# 形と位置はコリジョンに合わせ直す。貼った絵はそのまま残す
		sprite.transform = poly.transform
		sprite.polygon = poly.polygon.duplicate()
		sprite.set("copy_from", sprite.get_path_to(poly))

	var out := PackedScene.new()
	var err := out.pack(stage)
	if err == OK:
		err = ResourceSaver.save(out, path)
	print("%s → %s（新規 %d / 更新 %d）" % [path.get_file(), error_string(err), made, kept])
	quit()


## 塗り色が茶系か。岩と芝を振り分けるだけの目安
func _is_brown(poly: CollisionPolygon2D) -> bool:
	var value: Variant = poly.get("fill_color")
	if typeof(value) != TYPE_COLOR:
		return false
	var col: Color = value
	return col.r > col.g
