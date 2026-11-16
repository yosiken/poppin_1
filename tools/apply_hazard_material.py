# -*- coding: utf-8 -*-
"""本編ステージの落下床（Hazards の下の板）に、熱いマテリアルを貼る。

    python tools/apply_hazard_material.py

チュートリアル面は gen_tutorial_stage.py が丸ごと書き出すので対象外。
こちらは手書きの .tscn を直接書き換える。何度流しても結果は同じ（貼り直すだけ）。

やっていること:

1. ノードの scale をポリゴンの座標に畳み込む（scale 行は消す）。
   lava_block.gdshader は縁の太さや模様の大きさを px で見ているので、
   ノードが拡大縮小されていると、縦横で伸び方が変わって歪む。
   特に Stage09 は (0.02, -0.28) のように極端。
   座標に畳み込んでも当たり判定と見た目の位置は変わらない（位置は position、
   回転は無し、なので world = position + 点 * scale のまま）。

2. 板の形から edges / edge_count / bounds を出して、板1枚に1つ
   ShaderMaterial を足す。考え方は docs/チュートリアル案.md の 10.11 と同じ。

形を変えたら流し直すこと。手で座標だけ直すと、縁の位置がズレる。
"""
import io
import math
import os
import re

# Stage09 は入れない。あそこの Hazards は「落ちたら死ぬ床」ではなく、
# signboard02.png のトゲ球の当たり判定（33〜150px の小さな板）で、
# 絵は別に置いてある。熱い板を貼っても絵の裏に隠れるだけで、意味も合わない
STAGES = ["Stage02", "Stage06"]
SHADER = "res://resources/shader/lava_block.gdshader"
EXT_ID = "lava_sh"
MAX_EDGES = 16


def edge_planes(points):
    """各辺を (内向きの法線x, y, 原点からの距離) にする。凸形であることが前提。"""
    n = len(points)
    area = 0.0
    for i in range(n):
        ax, ay = points[i]
        bx, by = points[(i + 1) % n]
        area += ax * by - bx * ay
    s = 1.0 if area > 0.0 else -1.0
    out = []
    for i in range(min(n, MAX_EDGES)):
        ax, ay = points[i]
        bx, by = points[(i + 1) % n]
        nx, ny = -(by - ay) * s, (bx - ax) * s
        length = math.hypot(nx, ny)
        if length < 1e-6:
            continue
        nx, ny = nx / length, ny / length
        out.append((nx, ny, nx * ax + ny * ay))
    return out


def is_convex(points):
    n = len(points)
    sign = 0
    for i in range(n):
        ax, ay = points[i]
        bx, by = points[(i + 1) % n]
        cx, cy = points[(i + 2) % n]
        cross = (bx - ax) * (cy - by) - (by - ay) * (cx - bx)
        if abs(cross) < 1e-6:
            continue                      # 一直線に並んだ点は数えない
        now = 1 if cross > 0 else -1
        if sign == 0:
            sign = now
        elif sign != now:
            return False
    return True


## 括弧の中だけを数に直す。
## 先に中身を取り出さないと PackedVector2Array の "2" まで拾ってしまう
def nums(text):
    inner = text[text.index("(") + 1:text.rindex(")")] if "(" in text else text
    return [float(x) for x in re.findall(r"-?\d+(?:\.\d+)?(?:e-?\d+)?", inner)]


def fmt(v):
    return ("%g" % v)


def poly_text(points):
    return "PackedVector2Array(%s)" % ", ".join(
        "%s, %s" % (fmt(x), fmt(y)) for x, y in points)


def planes_text(points):
    return "PackedVector3Array(%s)" % ", ".join(
        "%s, %s, %s" % (fmt(a), fmt(b), fmt(c)) for a, b, c in edge_planes(points))


def bounds_text(points):
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    return "Vector4(%s, %s, %s, %s)" % (
        fmt(min(xs)), fmt(min(ys)), fmt(max(xs) - min(xs)), fmt(max(ys) - min(ys)))


## .uid があればそれを書く。無ければ省く（Godot が初回読み込みで振る）
def shader_uid():
    path = SHADER + ".uid"
    path = path.replace("res://", "")
    if not os.path.exists(path):
        return ""
    return ' uid="%s"' % io.open(path, encoding="utf-8").read().strip()


def apply(path):
    src = io.open(path, encoding="utf-8").read()
    blocks = re.split(r"(?m)^(?=\[)", src)
    mats = []
    changed = 0

    for bi, block in enumerate(blocks):
        head = re.match(r'\[node name="([^"]+)" type="CollisionPolygon2D" parent="([^"]+)"',
                        block)
        if head is None:
            continue
        name, parent = head.group(1), head.group(2)
        if not (parent == "Hazards" or parent.endswith("/Hazards")):
            continue
        pg = re.search(r"(?m)^polygon = (.+)$", block)
        if pg is None:
            print("  --  %s にポリゴンが無いので飛ばす" % name)
            continue

        flat = nums(pg.group(1))
        points = list(zip(flat[0::2], flat[1::2]))

        # 1. scale をポリゴンに畳み込む
        sc = re.search(r"(?m)^scale = Vector2\(([^)]+)\)\n", block)
        if sc:
            sx, sy = nums(sc.group(1))
            points = [(x * sx, y * sy) for x, y in points]
            block = block.replace(sc.group(0), "")
            print("  ok  %s: scale(%g, %g) を座標に畳み込んだ" % (name, sx, sy))

        if not is_convex(points):
            print("  NG  %s は凸形ではない。縁の光り方がおかしくなるので飛ばす" % name)
            continue

        mid = "MatLava%s" % name
        mats.append((mid, points))

        # 2. ポリゴンを書き戻して、マテリアルを足す
        block = re.sub(r"(?m)^polygon = .+$", "polygon = " + poly_text(points), block)
        block = re.sub(r"(?m)^material = SubResource\(\"MatLava[^\"]*\"\)\n", "", block)
        lines = block.split("\n")
        lines.insert(1, 'material = SubResource("%s")' % mid)
        blocks[bi] = "\n".join(lines)
        changed += 1

    if not mats:
        print("  --  落下床が無い")
        return False

    out = "".join(blocks)

    # 前に流したときの sub_resource は作り直す
    out = re.sub(r'(?ms)^\[sub_resource type="ShaderMaterial" id="MatLava[^"]*"\].*?(?=^\[)',
                 "", out)

    # シェーダーの ext_resource（無ければ足す）
    if EXT_ID not in out:
        line = '[ext_resource type="Shader"%s path="%s" id="%s"]\n' % (
            shader_uid(), SHADER, EXT_ID)
        last = list(re.finditer(r"(?m)^\[ext_resource .*\]\n", out))[-1]
        out = out[:last.end()] + line + out[last.end():]

    # sub_resource は最初のノードの手前に置く
    first_node = re.search(r"(?m)^\[node ", out)
    blockstr = ""
    for mid, points in mats:
        blockstr += '[sub_resource type="ShaderMaterial" id="%s"]\n' % mid
        blockstr += 'shader = ExtResource("%s")\n' % EXT_ID
        blockstr += "shader_parameter/edges = %s\n" % planes_text(points)
        blockstr += "shader_parameter/edge_count = %d\n" % len(edge_planes(points))
        blockstr += "shader_parameter/bounds = %s\n\n" % bounds_text(points)
    out = out[:first_node.start()] + blockstr + out[first_node.start():]

    io.open(path, "w", encoding="utf-8", newline="\n").write(out)
    print("  ok  %s: 落下床 %d 枚に貼った" % (os.path.basename(path), changed))
    return True


def main():
    for name in STAGES:
        path = os.path.join("scenes", "stages", "%s.tscn" % name)
        print("--- %s" % name)
        apply(path)


if __name__ == "__main__":
    main()
