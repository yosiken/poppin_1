"""資材リストのイベント素材について、本番の絵が来るまでのダミーPNGを作る。

    python tools/make_placeholders.py

素材IDを描いただけの画像を、資材リストに載っている分だけ作る。
参照が切れたり差し替え漏れがあったりすると画面にIDが出るので気づける。

寸法は仕様書の数値ではなく、プロジェクトにある本番の絵に合わせてある
（背景=BG-01.png / OB=OB_a.png / カニエナガ=kanie_a.png）。
差し替えるときは同じパス・同じ名前で置けば、参照側は触らなくてよい。

既にあるファイルには書かない。本番の絵を消さないための歯止めなので外さないこと。
BG-01 は本番の絵があるため、ここでは作らない。

依存ライブラリなし。PNGの書き出しと5x7フォントを自前で持っている。
"""
import os
import re
import struct
import zlib

F = {
 'A':["01110","10001","10001","11111","10001","10001","10001"],
 'B':["11110","10001","10001","11110","10001","10001","11110"],
 'C':["01110","10001","10000","10000","10000","10001","01110"],
 'D':["11110","10001","10001","10001","10001","10001","11110"],
 'E':["11111","10000","10000","11110","10000","10000","11111"],
 'F':["11111","10000","10000","11110","10000","10000","10000"],
 'G':["01110","10001","10000","10111","10001","10001","01110"],
 'H':["10001","10001","10001","11111","10001","10001","10001"],
 'I':["11111","00100","00100","00100","00100","00100","11111"],
 'J':["00111","00010","00010","00010","00010","10010","01100"],
 'K':["10001","10010","10100","11000","10100","10010","10001"],
 'L':["10000","10000","10000","10000","10000","10000","11111"],
 'M':["10001","11011","10101","10101","10001","10001","10001"],
 'N':["10001","11001","10101","10011","10001","10001","10001"],
 'O':["01110","10001","10001","10001","10001","10001","01110"],
 'P':["11110","10001","10001","11110","10000","10000","10000"],
 'Q':["01110","10001","10001","10001","10101","10010","01101"],
 'R':["11110","10001","10001","11110","10100","10010","10001"],
 'S':["01111","10000","10000","01110","00001","00001","11110"],
 'T':["11111","00100","00100","00100","00100","00100","00100"],
 'U':["10001","10001","10001","10001","10001","10001","01110"],
 'V':["10001","10001","10001","10001","10001","01010","00100"],
 'W':["10001","10001","10001","10101","10101","11011","10001"],
 'X':["10001","10001","01010","00100","01010","10001","10001"],
 'Y':["10001","10001","01010","00100","00100","00100","00100"],
 'Z':["11111","00001","00010","00100","01000","10000","11111"],
 '0':["01110","10001","10011","10101","11001","10001","01110"],
 '1':["00100","01100","00100","00100","00100","00100","01110"],
 '2':["01110","10001","00001","00010","00100","01000","11111"],
 '3':["11111","00010","00100","00010","00001","10001","01110"],
 '4':["00010","00110","01010","10010","11111","00010","00010"],
 '5':["11111","10000","11110","00001","00001","10001","01110"],
 '6':["00110","01000","10000","11110","10001","10001","01110"],
 '7':["11111","00001","00010","00100","01000","01000","01000"],
 '8':["01110","10001","10001","01110","10001","10001","01110"],
 '9':["01110","10001","10001","01111","00001","00010","01100"],
 '-':["00000","00000","00000","11111","00000","00000","00000"],
 '.':["00000","00000","00000","00000","00000","01100","01100"],
 '/':["00001","00010","00010","00100","01000","01000","10000"],
 ' ':["00000","00000","00000","00000","00000","00000","00000"],
}

class Img:
    def __init__(self, w, h, rgba=(0, 0, 0, 0)):
        self.w, self.h = w, h
        self.px = bytearray(bytes(rgba) * (w * h))
    def _set(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            i = (y * self.w + x) * 4
            self.px[i:i+4] = bytes(c)
    def rect(self, x, y, w, h, c):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self._set(xx, yy, c)
    def border(self, t, c):
        self.rect(0, 0, self.w, t, c); self.rect(0, self.h - t, self.w, t, c)
        self.rect(0, 0, t, self.h, c); self.rect(self.w - t, 0, t, self.h, c)
    def text(self, x, y, s, sc, c):
        cx = x
        for ch in s.upper():
            g = F.get(ch, F[' '])
            for r in range(7):
                for col in range(5):
                    if g[r][col] == '1':
                        self.rect(cx + col * sc, y + r * sc, sc, sc, c)
            cx += 6 * sc
        return cx - x - sc
    @staticmethod
    def text_w(s, sc):
        return len(s) * 6 * sc - sc
    def save(self, path):
        raw = bytearray()
        for y in range(self.h):
            raw.append(0)
            raw += self.px[y * self.w * 4:(y + 1) * self.w * 4]
        def chunk(tag, data):
            c = struct.pack(">I", len(data)) + tag + data
            return c + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)
        out = b'\x89PNG\r\n\x1a\n'
        out += chunk(b'IHDR', struct.pack(">IIBBBBB", self.w, self.h, 8, 6, 0, 0, 0))
        out += chunk(b'IDAT', zlib.compress(bytes(raw), 9))
        out += chunk(b'IEND', b'')
        open(path, 'wb').write(out)
POP = "resources/text/ポップアップ絵リスト.txt"
ART = "resources/text/絵素材リスト_v4対応.txt"
pop_txt = open(POP, encoding="utf-8").read()
art_txt = open(ART, encoding="utf-8").read()

# --- 説明の取り出し ---
sec = pop_txt.split("１．採用ポップアップ一覧")[1].split("２．点数まとめ")[0]
pops = re.findall(r"^(POP-\d+) ★ (.+)$", sec, re.M)

ob_sec = art_txt.split("表情差分（12点＋任意1点）")[1].split("ポーズ差分")[0]
obs = [(f"OB-{m[0]}", m[1].strip()) for m in
       re.findall(r"^\s+(\d{2}) (.+?)(?:…|$)", ob_sec, re.M)][:12]

ka_sec = art_txt.split("表情差分（6点）")[1].split("■ シマエナガ")[0]
kas = [(f"KANIE-{m[0]}", m[1].strip()) for m in
       re.findall(r"^\s+(\d{2}) (.+?)(?:…|$)", ka_sec, re.M)][:6]

miss_sec = art_txt.split("４．誤答イメージ")[1].split("５．UI・演出素材")[0]
# 「※…を流用」と書かれているものは新規に描かないので、ダミーも作らない
misses = [(m[0], m[1].strip()) for m in
          re.findall(r"^\s+(MISS-\d+) (.+?)\s*…(.+)$", miss_sec, re.M)
          if not m[1].strip().startswith("※")]

bg_sec = art_txt.split("２．背景素材")[1].split("３．アイテム素材")[0]
bgs = re.findall(r"^\s+(BG-\d+) (.+?)\s*…(.+)$", bg_sec, re.M)

# カテゴリ: (出力先, 幅, 高さ, 枠色, 地色)
CAT = {
 "POP":   ("resources/texture/event/popup",  640,  360, (74,144,226,255), (74,144,226,60)),
 "BG":    ("resources/texture/BG/event",    1920, 1080, (56,160,120,255), (56,160,120,60)),
 "OB":    ("resources/texture/event/char",   848, 1200, (226,126,74,255), (226,126,74,60)),
 "KANIE": ("resources/texture/event/char",   909,  800, (150,100,200,255),(150,100,200,60)),
 "MISS":  ("resources/texture/event/popup",  640,  360, (217,64,64,255),  (217,64,64,60)),
}

items = ([("POP", i, t) for i, t in pops] + [("BG", i, f"{t}（{w}）") for i, t, w in bgs]
         + [("OB", i, t) for i, t in obs] + [("KANIE", i, t) for i, t in kas]
         + [("MISS", i, t) for i, t in misses])

made, skipped, manifest = [], [], []
for cat, ident, desc in items:
    d, w, h, edge, fill = CAT[cat]
    path = f"{d}/{ident}.png"
    manifest.append((path, ident, desc))
    # 実物があるものは絶対に上書きしない。別の場所に置かれている分も見る
    alt = [path, f"resources/texture/BG/{ident}.png", f"resources/texture/{ident}.png"]
    if any(os.path.exists(a) and os.path.getsize(a) > 100_000 for a in alt) or os.path.exists(path):
        skipped.append(path); continue
    os.makedirs(d, exist_ok=True)
    im = Img(w, h, fill)
    im.border(max(4, w // 160), edge)
    sc = max(2, int(w * 0.62 / (len(ident) * 6)))
    dark = tuple(int(v * 0.45) for v in edge[:3]) + (255,)
    im.text((w - Img.text_w(ident, sc)) // 2, h // 2 - sc * 7, ident, sc, dark)
    sub, s2 = f"PLACEHOLDER {w}X{h}", max(1, sc // 4)
    im.text((w - Img.text_w(sub, s2)) // 2, h // 2 + sc * 4, sub, s2, dark)
    im.save(path); made.append(path)

os.makedirs("resources/texture/event", exist_ok=True)
with open("resources/texture/event/README.txt", "w", encoding="utf-8") as f:
    f.write("イベント用ダミー素材の対応表\n")
    f.write("差し替えるときは、同じパス・同じファイル名で本番の絵を置くこと。\n")
    f.write("寸法は既存の実物に合わせてある（BG=BG-01.png / OB=OB_a.png / KANIE=kanie_a.png）。\n\n")
    f.write("【名前の系統が2つあること】\n")
    f.write("  KANIE-01〜06 と、resources/texture/ にある kanie_a〜kanie_f は別物として扱う。\n")
    f.write("  KANIE-XX は資材リストの表情差分、kanie_X は既存の立ち絵。統合しないこと。\n")
    f.write("  OB-01〜12 と OB_a〜OB_e も同様に別系統。\n\n")
    for p, i, d in manifest:
        mark = "実物あり" if i == "BG-01" else "ダミー  "
        f.write(f"{mark}  {i:<10} {d}\n    {p}\n")

print(f"生成 {len(made)} 件 / 既にあるため据え置き {len(skipped)} 件")
for p in skipped[:3]: print("  据え置き:", p)
if len(skipped) > 3: print(f"  ほか {len(skipped) - 3} 件")
print(f"内訳: POP {len(pops)} / MISS {len(misses)} / BG {len(bgs)}"
      f" / OB {len(obs)} / KANIE {len(kas)}")
