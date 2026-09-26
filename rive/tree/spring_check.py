"""Print the pop springs' overshoot and settle, from the generated keys."""
import re

import discovery as D

for name, kw, a, b in (("scaleX", D.POP_SX, 0, 1), ("scaleY", D.POP_SY, 0, 1),
                       ("rotation", D.POP_ROT, 0.5, 0)):
    ks = D.spring_keys(a, b, frames=D.POP_FRAMES, **kw)
    frames = [int(re.search(r'frame="(\d+)"', k).group(1)) for k in ks]
    vals = [float(re.search(r'value="([^"]+)"', k).group(1)) for k in ks]
    ext = max(vals) if b > a else min(vals)
    i = vals.index(ext)
    settle = next(f for f, v in zip(frames, vals)
                  if all(abs(w - b) < 0.02 for w in vals[frames.index(f):]))
    print(f"{name:8s} peak {ext:+.3f} at frame {frames[i]} "
          f"({frames[i] / 60 * 1000:.0f}ms), within 2% from frame {settle} "
          f"({settle / 60 * 1000:.0f}ms), last {vals[-2]:.4f} -> {vals[-1]}")
