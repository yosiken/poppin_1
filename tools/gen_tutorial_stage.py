# -*- coding: utf-8 -*-
"""scenes/stages/StageTutorial.tscn を作り直す。

チュートリアル面は「1ステージを 3x2 の区画に割り、1区画＝1チュートリアル」
という作り。寸法を手で .tscn に打つと区画どうしのズレに気づけないので、
このスクリプトで座標を1か所にまとめて書き出す。

    python tools/gen_tutorial_stage.py

レベルデザインはまだ仮。SECTIONS の数値を書き換えて実行し直せば面が入れ替わる。
座標は区画のローカル（左上が 0,0、2500x1500）で書く。
"""
import io
import math
import os

OUT = os.path.join("scenes", "stages", "StageTutorial.tscn")

# ── ステージ全体と区画
STAGE_W, STAGE_H = 7500.0, 3000.0
COLS, ROWS = 3, 2
CELL_W, CELL_H = STAGE_W / COLS, STAGE_H / ROWS   # 2500 x 1500

# ── 区画の共通寸法（ローカル座標）
WALL = 80.0          # 区画の左右の壁の厚み
WALL_TOP = 150.0     # 壁の上端
WALL_BOTTOM = 1300.0
FLOOR_TOP = 1150.0   # 主な足場の高さ
FLOOR_BOTTOM = 1300.0
HAZARD_TOP = 1380.0  # 落ちたら死ぬ床。区画の中に収めてあるので隣へ落ちていかない
HAZARD_BOTTOM = 1480.0

# 板は neon_block.gdshader で「面は暗く、縁が光る」形に描かれる。
# シェーダーが色を暗くしてから縁だけ白に寄せるので、素の色は濃いめにしておく
GREEN = "Color(0.16, 1, 0.45, 1)"
BROWN = "Color(0.13, 0.58, 0.55, 1)"  # 区画の左右の壁。奥に引くので緑より地味に
BLUE = "Color(0.25, 0.72, 1, 1)"      # 滑る坂。氷のシェーダーを通すので薄い水色に出る
RED = "Color(1, 0.25, 0.3, 1)"        # 落ちたら死ぬ床

# 地形の見た目。既定は「縁が光るグラデーションの板」。
# 滑って登れない坂だけ氷にして、足場にならないことを見た目でも分かるようにする。
# どちらも形の渡し方(edges / edge_count / bounds)は同じなので、書き出し方は変わらない
TERRAIN_SHADER = "res://resources/shader/neon_block.gdshader"
ICE_SHADER = "res://resources/shader/ice_block.gdshader"
MAX_EDGES = 16                        # シェーダー側の配列の長さと合わせる

# 板の種類。terrain の4つ目に書くと、その板だけ別のシェーダーになる
NEON = "neon"
ICE = "ice"
SHADER_IDS = {NEON: "10_neon", ICE: "11_ice"}

# uid が分かっている既存スクリプトはそのまま書く。新しいスクリプトは
# パスだけ書いておき、uid は Godot が初回読み込み時に振る
SCRIPTS = [
    ("1_tstage", "res://scripts/tutorial_stage.gd", None),
    ("2_tsec", "res://scripts/tutorial_section.gd", None),
    ("3_titem", "res://scripts/tutorial_item.gd", None),
    ("6_thint", "res://scripts/tutorial_hint.gd", None),
    ("4_terrain", "res://scripts/terrain_polygon.gd", "uid://rbtayp8ewgx5"),
    ("5_hazard", "res://scripts/hazard.gd", "uid://dgqq7nscbsglg"),
    ("7_mtxpara", "res://scripts/matrix_parallax.gd", None),
]

# 背景（マトリックス風の文字の雨）。チュートリアル面だけ自前の背景を持つので、
# ルートの hide_world_background を立てて Main の共通背景を隠す
BG_SHADER = "res://resources/shader/matrix_rain.gdshader"
BG_ATLAS = "res://resources/texture/matrix_glyphs.png"
# シェーダーの既定値から変えるものだけ。遊ぶ画面の後ろなので、
# 本家より暗く・薄くして、足場と文字が喧嘩しないようにする
BG_PARAMS = [
    # 何も降っていないところの色。画面に出るのが rgb(0, 20, 0) になるようにする。
    # シェーダーの最後で brightness を掛けるので、その逆数を見込んだ値
    #   20 / 255 / 0.75 = 0.104575
    ("bg_color", "Color(0, 0.104575, 0, 1)"),
    ("brightness", "0.75"),
    # 列は全部使い、尾を画面の高さぶんまで伸ばして隙間を埋める。
    #
    # 枡を細かく(30→42)した上で、文字が枡を埋める割合を上げている(0.82→0.98)。
    # 掛け合わせると画面に出る文字の大きさはほぼ変わらないまま、
    # 文字と文字の隙間だけが 1/4 ほどになる。
    # 尾の長さは「枡の数」なので、画面の高さぶん＝ rain_rows と同じ値
    ("density", "1.0"),
    ("rain_rows", "42.0"),
    ("glyph_fill", "0.98"),
    ("trail_length", "42.0"),
    ("float_alpha", "0.22"),
    # カメラに合わせてずらす量。既定(0.045)だと動いたのが分かりにくい
    ("parallax_strength", "0.07"),
]
# 背景のずらし方。カメラ連動を主役にして、マウスは添える程度にする。
# 矢印キーの流れは切る（遊んでいる間は傾ける操作とぶつかる）
BG_PARALLAX = [
    ("follow_camera", "true"),
    ("camera_span", "1000.0"),
    # 縦は本編の背景に合わせて、世界とほぼ同じだけ動かす。
    #   画面のずれ(px) = (カメラの移動 / camera_span_y) * parallax_strength * 1080
    #   手前の層で等倍になるのは 0.07 * 1080 / 1.4(ズーム) = 54
    ("camera_span_y", "54.0"),
    ("mouse_weight", "0.15"),
    ("key_speed", "0.0"),
]


def box(x0, y0, x1, y1):
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


def floor_box(x0, x1, top=FLOOR_TOP, bottom=FLOOR_BOTTOM):
    return box(x0, top, x1, bottom)


def ramp(x0, x1, top, base=FLOOR_TOP, bottom=FLOOR_BOTTOM):
    """x0 から x1 へ登る坂。登れるのは約31.8度まで（run >= rise * 1.61）。"""
    return [(x0, base), (x1, top), (x1, bottom), (x0, bottom)]


def step_box(x0, x1, top, chamfer=100.0, bottom=FLOOR_BOTTOM):
    """登れない段。立ち上がりを斜めにして、根元で挟まったまま出られなくなるのを防ぐ。"""
    return [(x0, top + chamfer * 2.4), (x0 + chamfer, top), (x1, top), (x1, bottom),
            (x0, bottom)]


# ─────────────────────────────── 仮のレベルデザイン
#
# 教える順番は docs/チュートリアル案.md に合わせている。
#   1 基本操作 → 2 ジャンプの練習 → 3 押しっぱなしの連続ジャンプ
#   → 4 溜めジャンプ → 5 跳ぶ場所で変わる → 6 総合（本編へ）
#
SECTIONS = [
    {
        "name": "Tutorial1",
        "title": "基本操作",
        "hint": "← →  /  A D で傾ける   ※ボタンを押さなくても勝手に跳ねる",
        "message": "これが基本。\nポッピンは放っておいても跳ね続ける。← → で傾けた方へ進む。\nボタンで跳ぶのではなく、傾きで行き先を決める乗り物。",
        "spawn": (300, 1050),
        "item": (2240, 900),
        "recovery": [(300, 1050), (1300, 1050)],
        "terrain": [
            ("Floor", floor_box(WALL, 1400), GREEN),
            ("Ramp", ramp(1400, 1800, 1000), GREEN),
            ("Shelf", box(1800, 1000, 2420, FLOOR_BOTTOM), GREEN),
        ],
        "sign": (700, 780, "傾けて\n右へ"),
        "hints": [
            ((1200, 0, 1950, 1500), "坂は傾けたまま登れる   傾けるのをやめると止まる"),
            ((1950, 0, 2500, 1500), "金色の玉に触れるとチュートリアル合格"),
        ],
    },
    {
        "name": "Tutorial2",
        "title": "ジャンプの練習",
        "hint": "跳ぶ前から傾けておく   傾きが大きいほど遠くへ飛ぶ",
        "message": "傾きが大きいほど遠くへ飛び、そのぶん高さは下がる。\n谷を渡るときは、跳ぶ前から傾けておくこと。",
        "spawn": (300, 1050),
        "item": (2150, 900),
        "recovery": [(300, 1050), (1150, 800)],
        "terrain": [
            ("Floor", floor_box(WALL, 900), GREEN),
            ("Step", step_box(900, 1300, 900), GREEN),
            ("Landing", box(1500, 1000, 2420, FLOOR_BOTTOM), GREEN),
        ],
        "sign": (1050, 780, "谷を\n越える"),
        "hints": [
            ((850, 0, 1400, 1500), "段の上から、傾けたまま跳んで谷を越える"),
            ((1500, 0, 2500, 1500), "渡れた   そのまま玉へ"),
        ],
    },
    {
        "name": "Tutorial3",
        "title": "押しっぱなしで連続ジャンプ",
        "hint": "SPACE を押しっぱなし   着地のたびに溜まって、だんだん高く跳ぶ",
        "message": "SPACE を押しっぱなしにすると、着地のたびに溜めが入って跳ねが高くなる。\n階段はこれで登る。離すと高さが戻ってしまう。",
        "spawn": (250, 1050),
        "item": (2150, 300),
        "recovery": [(250, 1050), (620, 900), (1320, 600), (2000, 300)],
        "terrain": [
            ("Floor", floor_box(WALL, 450), GREEN),
            ("Step1", step_box(450, 800, 1000, 60.0), GREEN),
            ("Step2", step_box(800, 1150, 850, 60.0), GREEN),
            ("Step3", step_box(1150, 1500, 700, 60.0), GREEN),
            ("Step4", step_box(1500, 1850, 550, 60.0), GREEN),
            ("Top", step_box(1850, 2420, 400, 60.0), GREEN),
        ],
        "sign": (250, 820, "SPACE\n押しっぱなし"),
        "hints": [
            ((600, 0, 1800, 1500), "離さずに押し続ける   離すと高さが戻ってしまう"),
            ((1800, 0, 2500, 1500), "登りきった   玉へ"),
        ],
    },
    {
        "name": "Tutorial4",
        "title": "溜めジャンプ",
        "hint": "同じ場所で2〜3回跳ね直すと高さが戻る   高い段はそれから跳ぶ",
        "message": "1回の跳ねでは 250 の段に届かない。\n同じ場所で2〜3回跳ね直して高さを作り、それから傾けて跳ぶ。",
        "spawn": (300, 1050),
        "item": (2100, 550),
        "recovery": [(300, 1050), (1100, 800)],
        "terrain": [
            ("Floor", floor_box(WALL, 800), GREEN),
            ("Step1", step_box(800, 1500, 900), GREEN),
            ("Step2", step_box(1500, 2420, 650), GREEN),
        ],
        "sign": (500, 780, "跳ね直して\nから"),
        "hints": [
            ((450, 0, 900, 1500), "ここで2〜3回跳ね直して高さを作り、それから右へ傾ける"),
            ((900, 0, 1550, 1500), "もう一段ある   同じように跳ね直してから"),
            ((1550, 0, 2500, 1500), "登れた   玉へ"),
        ],
    },
    {
        "name": "Tutorial5",
        "title": "跳ぶ場所で変わる",
        "hint": "坂で跳ねると斜めに飛ぶ   青い急坂は滑って登れない",
        "message": "同じ操作でも、跳ぶ場所で結果が変わる。\nゆるい坂は足場になり、斜め上へ飛べる。青い急坂は滑り落ちる。\n高い棚へは、手前の平らな場所から跳ぶ。",
        "spawn": (300, 1050),
        "item": (2240, 750),
        "recovery": [(300, 1050), (1300, 980)],
        "terrain": [
            ("Floor", floor_box(WALL, 1000), GREEN),
            ("RampOk", [(1000, FLOOR_TOP), (1200, 1057), (1200, FLOOR_BOTTOM),
                        (1000, FLOOR_BOTTOM)], GREEN),
            ("Plateau", box(1200, 1057, 1400, FLOOR_BOTTOM), GREEN),
            ("Flat", floor_box(1400, 1900), GREEN),
            ("RampSlip", [(1500, FLOOR_TOP), (1650, 1024), (1650, FLOOR_TOP)], BLUE, ICE),
            ("Ledge", step_box(2050, 2420, 850), GREEN),
        ],
        "sign": (780, 780, "ゆるい坂\n急な坂"),
        "hints": [
            ((900, 0, 1450, 1500), "ゆるい坂で跳ねると、斜め上へ飛ぶ"),
            ((1450, 0, 1800, 1500), "青い急坂は滑る   足場にならない"),
            ((1800, 0, 2500, 1500), "平らな所から跳んで、高い棚に乗る"),
        ],
    },
    {
        "name": "Tutorial6",
        "title": "総合",
        "hint": "高いところから落ちて着地すると、その勢いで高く跳ね返る",
        "message": "落差で勢いをつけて高く跳ね返る。これが最後の技。\nこれでチュートリアルは終わり。本編へ進もう。",
        "spawn": (300, 150),
        "item": (2240, 750),
        "recovery": [(300, 150), (900, 1050)],
        "terrain": [
            ("Start", box(WALL, 250, 600, 370), GREEN),
            ("Floor", floor_box(600, 1700), GREEN),
            ("GoalLedge", box(1900, 850, 2420, 970), GREEN),
        ],
        "sign": (700, 900, "落差を\n使う"),
        "hints": [
            ((0, 0, 700, 600), "ここから落ちる   落差がそのまま跳ね返りになる"),
            ((550, 600, 1800, 1500), "落ちた勢いのまま、右へ傾けて棚へ"),
            ((1800, 400, 2500, 1200), "乗れた   玉へ"),
        ],
    },
]


def cell_origin(index):
    return ((index % COLS) * CELL_W, (index // COLS) * CELL_H)


def vec(p):
    return "Vector2(%g, %g)" % (p[0], p[1])


def poly(points):
    flat = ", ".join("%g, %g" % (x, y) for x, y in points)
    return "PackedVector2Array(%s)" % flat


## 形の各辺を「内向きの法線 n と原点からの距離 c」にする。
## シェーダー側で dot(n, p) - c を取ると、その辺までの距離(px)になる
def edge_planes(points):
    n = len(points)
    area = 0.0
    for i in range(n):
        ax, ay = points[i]
        bx, by = points[(i + 1) % n]
        area += ax * by - bx * ay
    # 時計回りと反時計回りで内側の向きが逆になるので、符号で合わせる
    s = 1.0 if area > 0.0 else -1.0
    out = []
    for i in range(min(n, MAX_EDGES)):
        ax, ay = points[i]
        bx, by = points[(i + 1) % n]
        nx, ny = -(by - ay) * s, (bx - ax) * s
        length = math.hypot(nx, ny)
        if length < 1e-6:
            continue                  # 同じ点が続いている辺は飛ばす
        nx, ny = nx / length, ny / length
        out.append((nx, ny, nx * ax + ny * ay))
    return out


def bounds_vec(points):
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    return "Vector4(%g, %g, %g, %g)" % (
        min(xs), min(ys), max(xs) - min(xs), max(ys) - min(ys))


def planes_array(points):
    flat = ", ".join("%g, %g, %g" % e for e in edge_planes(points))
    return "PackedVector3Array(%s)" % flat


## その区画の地形。左右の壁もここで足す（区画の外へ流れていかないように）。
## 板の種類を書き忘れたものは NEON 扱いにして、(名前, 形, 色, 種類) に揃える
def section_parts(sec):
    parts = [tuple(part) + (NEON,) if len(part) == 3 else tuple(part)
             for part in sec["terrain"]]
    parts.append(("WallLeft", box(0, WALL_TOP, WALL, WALL_BOTTOM), BROWN, NEON))
    parts.append(("WallRight", box(CELL_W - WALL, WALL_TOP, CELL_W, WALL_BOTTOM),
                  BROWN, NEON))
    return parts


## 落ちたら死ぬ床。Hazards の下に付くので地形とは別扱い
def pit_points():
    return box(0, HAZARD_TOP, CELL_W, HAZARD_BOTTOM)


def esc(text):
    out = text.replace("\\", "\\\\")
    out = out.replace(chr(34), "\\" + chr(34))
    return out.replace("\n", "\\n")


## 板1枚につきマテリアル1つ。形(辺と外接矩形)が1枚ごとに違うので共有できない
def material_id(section_index, part_name):
    return "Mat%d%s" % (section_index + 1, part_name)


def main():
    out = []
    w = out.append

    # 板ごとのマテリアル。(id, 形, 種類) を先に集める
    mats = []
    for i, sec in enumerate(SECTIONS):
        for pname, points, _color, kind in section_parts(sec):
            mats.append((material_id(i, pname), points, kind))
        mats.append((material_id(i, "Pit"), pit_points(), NEON))

    # ext_resource(スクリプト + 背景の2つ + 地形シェーダー2つ)
    # と sub_resource(背景の材質 + 板のぶん)
    steps = len(SCRIPTS) + 3 + 2 + len(mats) + 1
    w("[gd_scene load_steps=%d format=3]" % steps)
    w("")
    for ident, path, uid in SCRIPTS:
        if uid:
            w('[ext_resource type="Script" uid="%s" path="%s" id="%s"]' % (uid, path, ident))
        else:
            w('[ext_resource type="Script" path="%s" id="%s"]' % (path, ident))
    w('[ext_resource type="Shader" path="%s" id="8_mtxsh"]' % BG_SHADER)
    w('[ext_resource type="Texture2D" path="%s" id="9_mtxatlas"]' % BG_ATLAS)
    w('[ext_resource type="Shader" path="%s" id="10_neon"]' % TERRAIN_SHADER)
    w('[ext_resource type="Shader" path="%s" id="11_ice"]' % ICE_SHADER)
    w("")
    w('[sub_resource type="ShaderMaterial" id="MatrixRain"]')
    w('shader = ExtResource("8_mtxsh")')
    w('shader_parameter/glyph_atlas = ExtResource("9_mtxatlas")')
    for name, value in BG_PARAMS:
        w("shader_parameter/%s = %s" % (name, value))
    w("")
    # 板の形をシェーダーへ渡す。辺までの距離が分かるので、縁だけ光らせられる
    for mid, points, kind in mats:
        w('[sub_resource type="ShaderMaterial" id="%s"]' % mid)
        w('shader = ExtResource("%s")' % SHADER_IDS[kind])
        w("shader_parameter/edges = %s" % planes_array(points))
        w("shader_parameter/edge_count = %d" % len(edge_planes(points)))
        w("shader_parameter/bounds = %s" % bounds_vec(points))
        w("")
    w('[node name="StageTutorial" type="Node2D"]')
    w('script = ExtResource("1_tstage")')
    w('display_name = "チュートリアル"')
    w("hide_world_background = true")
    w("")
    # 背景。CanvasLayer を負の層に置くと2Dの世界より奥に描かれる
    w('[node name="MatrixBg" type="CanvasLayer" parent="."]')
    w("layer = -100")
    w("")
    w('[node name="Rain" type="ColorRect" parent="MatrixBg"]')
    w("material = SubResource(\"MatrixRain\")")
    w("anchors_preset = 15")
    w("anchor_right = 1.0")
    w("anchor_bottom = 1.0")
    w("grow_horizontal = 2")
    w("grow_vertical = 2")
    w("mouse_filter = 2")          # クリックを吸わない
    w('script = ExtResource("7_mtxpara")')
    for name, value in BG_PARALLAX:
        w("%s = %s" % (name, value))
    w("")
    w('[node name="CameraBounds" type="Polygon2D" parent="."]')
    # 遊ぶ画面では隠す。本編の面と同じ色だと、背景の雨の上に橙色が乗って
    # 全体が濁る。エディタでは選べば頂点が出るので、隠していても編集できる
    w("visible = false")
    w("color = Color(1, 0.85, 0.3, 0.15)")
    w("polygon = %s" % poly(box(0, 0, STAGE_W, STAGE_H)))
    w("")
    # 保険。区画が1つも無いときだけ使われる
    w('[node name="Spawn" type="Marker2D" parent="."]')
    first = SECTIONS[0]
    ox, oy = cell_origin(0)
    w("position = %s" % vec((ox + first["spawn"][0], oy + first["spawn"][1])))
    w("")
    w('[node name="Tutorials" type="Node2D" parent="."]')
    w("")

    for i, sec in enumerate(SECTIONS):
        base = "Tutorials/" + sec["name"]
        w('[node name="%s" type="Node2D" parent="Tutorials"]' % sec["name"])
        w("position = %s" % vec(cell_origin(i)))
        w('script = ExtResource("2_tsec")')
        w('title = "%s"' % esc(sec["title"]))
        w('hint = "%s"' % esc(sec["hint"]))
        w('message = "%s"' % esc(sec["message"]))
        w("")

        w('[node name="Spawn" type="Marker2D" parent="%s"]' % base)
        w("position = %s" % vec(sec["spawn"]))
        w("")

        w('[node name="Item" type="Area2D" parent="%s"]' % base)
        w("position = %s" % vec(sec["item"]))
        w('script = ExtResource("3_titem")')
        w("")

        # 画面上部の説明を切り替える範囲。ここに入っている間だけ別の文章になる
        if sec.get("hints"):
            w('[node name="Hints" type="Node2D" parent="%s"]' % base)
            w("")
            for j, (rect, text) in enumerate(sec["hints"]):
                x0, y0, x1, y1 = rect
                w('[node name="Hint%d" type="Node2D" parent="%s/Hints"]' % (j + 1, base))
                w("position = %s" % vec(((x0 + x1) * 0.5, (y0 + y1) * 0.5)))
                w('script = ExtResource("6_thint")')
                w('text = "%s"' % esc(text))
                w("size = %s" % vec((x1 - x0, y1 - y0)))
                w("")

        if sec["recovery"]:
            w('[node name="RecoveryPoints" type="Node2D" parent="%s"]' % base)
            w("")
            for j, p in enumerate(sec["recovery"]):
                w('[node name="Point%d" type="Marker2D" parent="%s/RecoveryPoints"]'
                  % (j + 1, base))
                w("position = %s" % vec(p))
                w("")

        w('[node name="Terrain" type="StaticBody2D" parent="%s"]' % base)
        w("")
        for pname, points, color, _kind in section_parts(sec):
            w('[node name="%s" type="CollisionPolygon2D" parent="%s/Terrain"]' % (pname, base))
            w('material = SubResource("%s")' % material_id(i, pname))
            w("polygon = %s" % poly(points))
            w('script = ExtResource("4_terrain")')
            w("fill_color = %s" % color)
            w("")

        w('[node name="Hazards" type="Area2D" parent="%s"]' % base)
        w('script = ExtResource("5_hazard")')
        w("")
        w('[node name="Pit" type="CollisionPolygon2D" parent="%s/Hazards"]' % base)
        w('material = SubResource("%s")' % material_id(i, "Pit"))
        w("polygon = %s" % poly(pit_points()))
        w('script = ExtResource("4_terrain")')
        w("fill_color = %s" % RED)
        w("")

        if sec.get("sign"):
            sx, sy, text = sec["sign"]
            w('[node name="Signs" type="Node2D" parent="%s"]' % base)
            w("")
            w('[node name="Sign" type="Label" parent="%s/Signs"]' % base)
            w("offset_left = %g" % sx)
            w("offset_top = %g" % sy)
            w("offset_right = %g" % (sx + 420))
            w("offset_bottom = %g" % (sy + 180))
            w('text = "%s"' % esc(text))
            w("theme_override_colors/font_color = Color(1, 0.95, 0.82, 1)")
            w("theme_override_colors/font_outline_color = Color(0.1, 0.09, 0.12, 1)")
            w("theme_override_constants/outline_size = 10")
            w("theme_override_font_sizes/font_size = 40")
            w("")

    io.open(OUT, "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n")
    print("%s を書き出した（区画 %d）" % (OUT, len(SECTIONS)))


if __name__ == "__main__":
    main()
