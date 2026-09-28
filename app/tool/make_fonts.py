"""Cut the bundled static fonts out of the two variable families.

Ludeck ships static TTFs, not the variable files: Flutter does not map
`FontWeight` onto a variable font's `wght` axis, so a variable file would
render every weight as the default instance (or a synthesized fake bold).
One static file per weight is what makes `FontWeight.w700` mean 700.

Sources (both SIL Open Font License 1.1, licences in assets/fonts/):
  Plus Jakarta Sans   https://github.com/google/fonts/tree/main/ofl/plusjakartasans
  Bricolage Grotesque https://github.com/google/fonts/tree/main/ofl/bricolagegrotesque

Usage: python tool/make_fonts.py <dir holding jakarta.ttf and bricolage.ttf>
"""

import pathlib
import sys

from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "fonts"

# The interface face: every label, body line and control.
JAKARTA = {400: "Regular", 500: "Medium", 600: "SemiBold", 700: "Bold"}

# The display face: headlines and the big numbers only. Optical size 32 is
# cut for the 28-40px range it is used at (the 12pt master is too loose
# there, the 96pt one too tight).
BRICOLAGE = {600: "SemiBold", 700: "Bold", 800: "ExtraBold"}
BRICOLAGE_OPSZ = 32


def cut(src: pathlib.Path, family: str, weights: dict, extra: dict) -> None:
    for w, name in weights.items():
        font = TTFont(src)
        axes = {"wght": w, **extra}
        axes = {k: v for k, v in axes.items()
                if k in {a.axisTag for a in font["fvar"].axes}}
        # Names are not updated: Flutter takes the family and weight from
        # pubspec.yaml, never from the file, and the STAT table has no entry
        # for opsz 32 to derive a name from.
        inst = instantiateVariableFont(font, axes)
        out = OUT / f"{family}-{name}.ttf"
        inst.save(out)
        print(out.name, out.stat().st_size)


def main() -> None:
    src = pathlib.Path(sys.argv[1])
    OUT.mkdir(parents=True, exist_ok=True)
    cut(src / "jakarta.ttf", "PlusJakartaSans", JAKARTA, {})
    cut(src / "bricolage.ttf", "BricolageGrotesque", BRICOLAGE,
        {"opsz": BRICOLAGE_OPSZ, "wdth": 100})


if __name__ == "__main__":
    main()
