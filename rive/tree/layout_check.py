"""Sanity checks on the fruit layout (run: python rive/tree/layout_check.py)."""
import math

import discovery as D

print("slots", D.SLOTS, "min spacing", round(D.min_spacing(), 1), "px")
assert D.SLOTS == 12
assert D.min_spacing() >= 55, "cards closer than 55px would overlap (40px wide + edge)"
# At growth 0 the cards sit at EARLY * their offsets and at EARLY_SCALE size;
# approximate a sapling's spacing the same way.
early = [(c["off"][0] * D.EARLY, c["off"][1] * D.EARLY, c["cluster"]) for c in D.CARDS]
print("pop order (dist from centre):",
      [round(math.hypot(c["pos"][0] - D._CENTROID[0], c["pos"][1] - D._CENTROID[1])) for c in D.CARDS])
print("stems", [c["stem"] for c in D.CARDS])
print("tilts", [c["tilt"] for c in D.CARDS])
