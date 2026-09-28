"""Store and launcher art from the real tree, not a drawing of it.

  python app/tool/store_assets.py

Renders the shipped tree (full canopy, no fruit) on the app's preview night sky
with the Rive CLI at 4x, then cuts:
  docs/store/icon-512.png              Play listing icon
  docs/store/feature-1024x500.png      Play feature graphic
  app/android/.../mipmap-*/ic_launcher.png         legacy launcher icons
  app/android/.../mipmap-*/ic_launcher_bg.png      adaptive icon layer
  app/android/.../mipmap-anydpi-v26/ic_launcher.xml
The adaptive icon puts the whole picture in its BACKGROUND layer (sky + tree,
tree inside the 66% safe zone) with a transparent foreground, so a launcher's
mask crops only sky.
"""
import os
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.dirname(HERE)
ROOT = os.path.dirname(APP)
TREE = os.path.join(ROOT, "rive", "tree")
RES = os.path.join(APP, "android", "app", "src", "main", "res")
STORE = os.path.join(ROOT, "docs", "store")
RIVE = os.path.expandvars(r"%USERPROFILE%\.rive\bin\rive.exe")

K = 4                      # render scale over the 412x732 artboard
TREE_CX = 212 * K          # visual centre of the canopy + trunk, artboard x
TREE_TOP = 190 * K         # just above the canopy
HILL_Y = 672 * K           # where the trunk meets the hill


def render():
    env = dict(os.environ, TREE_PREVIEW_SKY="1")
    build = [sys.executable, os.path.join(TREE, "build_tree.py")]
    subprocess.run(build, cwd=TREE, env=env, check=True, capture_output=True)
    out = os.path.join(TREE, "build", "_store_src.png")
    try:
        subprocess.run([RIVE, ".", "--artboard=TreeDiscovery", f"--screenshot={out}",
                        f"--viewport={412 * K}x{732 * K}", "--fit=contain",
                        "--data=grown=12", "--data=found=0", "--advance=200"],
                       cwd=TREE, check=True, capture_output=True, timeout=180)
    finally:
        # Never leave the preview sky in the shipped scene source.
        env.pop("TREE_PREVIEW_SKY")
        subprocess.run(build, cwd=TREE, env=env, check=True, capture_output=True)
    return Image.open(out).convert("RGB")


def widen(src, left, right):
    """Extend the sky sideways. The preview sky is a vertical gradient, so
    each row's edge pixel continues it exactly."""
    w, h = src.size
    out = Image.new("RGB", (w + left + right, h))
    out.paste(src, (left, 0))
    out.paste(src.crop((0, 0, 1, h)).resize((left, h)), (0, 0))
    out.paste(src.crop((w - 1, 0, w, h)).resize((right, h)), (left + w, 0))
    return out


def square(src, side, cx, cy):
    pad = side  # generous; widen() is exact for this sky
    wide = widen(src, pad, pad)
    # Vertically: the sky's top row and the hill's bottom row are both flat,
    # so continuing them is exact too.
    w, h = wide.size
    tall = Image.new("RGB", (w, h + 2 * pad))
    tall.paste(wide, (0, pad))
    tall.paste(wide.crop((0, 0, w, 1)).resize((w, pad)), (0, 0))
    tall.paste(wide.crop((0, h - 1, w, h)).resize((w, pad)), (0, pad + h))
    x0 = cx + pad - side // 2
    y0 = cy + pad - side // 2
    return tall.crop((x0, y0, x0 + side, y0 + side))


def save(im, path, size):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.resize((size, size), Image.LANCZOS).save(path, optimize=True)
    print("wrote", os.path.relpath(path, ROOT), f"{size}x{size}")


def font(size, bold=True):
    for name in (("segoeuib.ttf", "seguisb.ttf") if bold else ("segoeui.ttf",)):
        p = os.path.join(os.environ.get("WINDIR", r"C:\Windows"), "Fonts", name)
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    raise SystemExit("no Segoe UI font found")


def feature(src):
    """1024x500: wordmark on the left, the tree standing on the right."""
    W, H = 1024 * 2, 500 * 2
    # The tree from canopy to hill, scaled so it stands the full height.
    tree_h = HILL_Y + 40 * K - TREE_TOP
    s = H / tree_h
    band = widen(src, 5000, 5000).crop((0, TREE_TOP, src.size[0] + 10000, HILL_Y + 40 * K))
    band = band.resize((int(band.size[0] * s), H), Image.LANCZOS)
    cx = int((TREE_CX + 5000) * s)
    x0 = cx - int(W * 0.72)
    im = band.crop((x0, 0, x0 + W, H))
    d = ImageDraw.Draw(im)
    x = int(W * 0.07)
    d.text((x, int(H * 0.30)), "Ludeck", font=font(230), fill=(248, 240, 248))
    d.text((x + 8, int(H * 0.30) + 290), "Your games, grown into an orchard.",
           font=font(64, bold=False), fill=(214, 196, 222))
    os.makedirs(STORE, exist_ok=True)
    p = os.path.join(STORE, "feature-1024x500.png")
    im.resize((1024, 500), Image.LANCZOS).save(p, optimize=True)
    print("wrote", os.path.relpath(p, ROOT), "1024x500")


def main():
    src = render()
    # The tree, canopy top to hill, fills ~90% of the Play icon ...
    span = HILL_Y + 24 * K - TREE_TOP
    cy = TREE_TOP + span // 2
    icon = square(src, int(span / 0.90), TREE_CX, cy)
    save(icon, os.path.join(STORE, "icon-512.png"), 512)
    # ... and ~64% of the adaptive layer, inside the launcher mask's safe zone.
    bg = square(src, int(span / 0.64), TREE_CX, cy)
    for dens, legacy in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96),
                         ("xxhdpi", 144), ("xxxhdpi", 192)):
        folder = os.path.join(RES, f"mipmap-{dens}")
        save(bg, os.path.join(folder, "ic_launcher_bg.png"), int(legacy * 108 / 48))
        # Pre-Android-8 launchers show the square icon with rounded corners.
        mask = Image.new("L", (legacy * 4,) * 2, 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, legacy * 4 - 1, legacy * 4 - 1),
                                               radius=legacy * 4 // 5, fill=255)
        rounded = icon.resize((legacy * 4,) * 2, Image.LANCZOS).convert("RGBA")
        rounded.putalpha(mask.filter(ImageFilter.GaussianBlur(1)))
        rounded.resize((legacy, legacy), Image.LANCZOS).save(
            os.path.join(folder, "ic_launcher.png"), optimize=True)
        print("wrote", f"mipmap-{dens}/ic_launcher.png", f"{legacy}x{legacy}")
    xml_dir = os.path.join(RES, "mipmap-anydpi-v26")
    os.makedirs(xml_dir, exist_ok=True)
    with open(os.path.join(xml_dir, "ic_launcher.xml"), "w", encoding="utf-8", newline="\n") as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<!-- Generated by app/tool/store_assets.py. The picture is the\n'
                '     background layer; the foreground is intentionally empty. -->\n'
                '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                '    <background android:drawable="@mipmap/ic_launcher_bg"/>\n'
                '    <foreground android:drawable="@android:color/transparent"/>\n'
                '</adaptive-icon>\n')
    feature(src)


if __name__ == "__main__":
    main()
