#!/usr/bin/env python3
# Copyright (C) 2026 Vitor Mendes Camilo
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of OpenJLS. Available under GPLv3 or a
# commercial license. See LICENSE and README for details.
#

"""Generate the OpenJLS wordmark (light and dark) into Docs/Images.

"Open" is set in ink, "JLS" in the Isentropic amber, in Inter Display
Regular. Glyphs are emitted as outlined paths, so the committed SVGs render
identically without the font installed - this script is only needed to
regenerate them.

Usage:
    python3 Scripts/gen_wordmark.py

Requires fontTools and cairosvg, plus the Inter Display Regular source font.
Override the font location with OPENJLS_WORDMARK_FONT if it lives elsewhere.
"""
import os
import sys

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.ttLib import TTFont
import cairosvg

# Isentropic brand palette.
INK = "#1A1A1A"     # wordmark ink, light theme
AMBER = "#D97706"   # accent, both themes
PAPER = "#FAFAF7"   # wordmark ink, dark theme

# Layout, in SVG user units.
SIZE = 96    # cap size
BASE = 130   # baseline
PAD = 40     # left/right padding
HEIGHT = 180

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "Docs", "Images")
FONT_PATH = os.environ.get(
    "OPENJLS_WORDMARK_FONT",
    os.path.expanduser("~/Repos/Isentropic/fonts/InterDisplay-Regular.ttf"),
)


def word_paths(font, text, size):
    """Outline `text` as (path_data, x_offset) pairs, plus the advance width."""
    upm = font["head"].unitsPerEm
    cmap = font.getBestCmap()
    glyphs = font.getGlyphSet()
    hmtx = font["hmtx"]

    scale = size / upm
    x = 0.0
    out = []
    for ch in text:
        gname = cmap[ord(ch)]
        pen = SVGPathPen(glyphs)
        glyphs[gname].draw(pen)
        d = pen.getCommands()
        if d:
            out.append((d, x))
        x += hmtx[gname][0] * scale
    return out, x


def word_group(font, text, size, x0, baseline, fill):
    """Render `text` as a fragment of absolutely-placed paths."""
    paths, width = word_paths(font, text, size)
    s = size / font["head"].unitsPerEm
    # The y-flip (-s) converts font coordinates to SVG's y-down space.
    frag = "".join(
        f'<path transform="translate({x0 + dx:.2f},{baseline:.2f}) '
        f'scale({s:.6f},-{s:.6f})" d="{d}" fill="{fill}"/>'
        for d, dx in paths
    )
    return frag, width


def build(font, name, ink):
    open_frag, w_open = word_group(font, "Open", SIZE, PAD, BASE, ink)
    jls_frag, w_jls = word_group(font, "JLS", SIZE, PAD + w_open, BASE, AMBER)
    width = PAD + w_open + w_jls + PAD

    svg = (
        f'<svg xmlns="http://www.w3.org/2000/svg" '
        f'viewBox="0 0 {width:.0f} {HEIGHT}" '
        f'width="{width:.0f}" height="{HEIGHT}">\n'
        f"{open_frag}{jls_frag}\n</svg>"
    )

    svg_path = os.path.join(OUT, name + ".svg")
    with open(svg_path, "w") as fh:
        fh.write(svg)
    cairosvg.svg2png(
        url=svg_path, write_to=os.path.join(OUT, name + ".png"), scale=2
    )
    return svg_path


def main():
    if not os.path.exists(FONT_PATH):
        sys.exit(
            f"font not found: {FONT_PATH}\n"
            "Set OPENJLS_WORDMARK_FONT to Inter Display Regular (.ttf)."
        )

    font = TTFont(FONT_PATH)
    os.makedirs(OUT, exist_ok=True)
    for name, ink in (
        ("openjls-wordmark", INK),
        ("openjls-wordmark-dark", PAPER),
    ):
        print("wrote", os.path.relpath(build(font, name, ink), REPO))


if __name__ == "__main__":
    main()
