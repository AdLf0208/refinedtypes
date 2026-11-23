#!/usr/bin/env python3
"""How much of the energizer menu's bar a screenshot shows, in GUI pixels.

    python3 tools/bar_check.py SHOT.png GUI_WIDTH GUI_HEIGHT
    -> "<filled> <trough>"

The screen is the port's own (`screen`: 176 × 189, upstream's `NetworkEnergizerScreen`
numbers), centred by `HudBatch::centered_origin` (a truncated `(gui - size) / 2`), and the
bar is upstream's `EnergyProgressWidget` rectangle: 16 × 70 at (80, 20) from the screen's top
left (`NetworkEnergizerScreen.init`).

Two counts, because one alone cannot tell a drawn bar from the plain panel behind it:

  * `filled` — rows whose mean green exceeds red by more than 40: the fill is `#5AD35A`
    (green-heavy), the plain container panel is grey and the trough is near-black.
  * `trough` — rows whose mean colour is near black: the `#1B1B1B` rectangle the port draws
    under the fill. A screen that does not draw at all has neither.

So a nearly-empty bar reads a large `trough` and a tiny `filled`, a full one the other way
round, and no bar at all reads `0 0`.
"""
from __future__ import annotations

import sys

from PIL import Image

# The port's `support::screen` and `support::BAR_AT` / `BAR_SIZE`.
SCREEN = (176.0, 189.0)
BAR = (80.0, 20.0, 16.0, 70.0)
GREEN_OVER_RED = 40.0
DARK = 60.0


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: bar_check.py SHOT.png GUI_WIDTH GUI_HEIGHT", file=sys.stderr)
        return 64
    shot, gui_w, gui_h = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
    image = Image.open(shot).convert("RGB")
    scale = image.width / gui_w
    left = (int((gui_w - SCREEN[0]) / 2.0) + BAR[0]) * scale
    top = (int((gui_h - SCREEN[1]) / 2.0) + BAR[1]) * scale
    width = max(1, round(BAR[2] * scale))
    height = max(1, round(BAR[3] * scale))
    filled = trough = 0
    for row in range(height):
        y = round(top) + row
        if y >= image.height:
            break
        red = green = blue = 0.0
        seen = 0
        for column in range(width):
            x = round(left) + column
            if x >= image.width:
                break
            r, g, b = image.getpixel((x, y))
            red += r
            green += g
            blue += b
            seen += 1
        if not seen:
            break
        (red, green, blue) = (red / seen, green / seen, blue / seen)
        if green - red > GREEN_OVER_RED:
            filled += 1
        elif (red + green + blue) / 3.0 < DARK:
            trough += 1
    print(f"{filled / scale:.1f} {trough / scale:.1f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
