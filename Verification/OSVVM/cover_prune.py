#!/usr/bin/env python3
"""Prune non-DUT rows from an NVC --per-file coverage report.

The dut_only.spec coverage spec stops the OSVVM testbenches and the open-logic
primitives from being instrumented, but NVC's --per-file report still LISTS
every elaborated source file — the uninstrumented ones just show "N.A." in
every column. This removes those all-N.A. file rows (and their orphaned hier/
and source/ pages) so the published report shows only the DUT source files.

A DUT row always has at least one real coverage cell (class="percentNN" with a
digit, e.g. percent100/percent0); an uninstrumented row is class="percentna"
throughout. Usage: cover_prune.py <report-html-dir>
"""
import os
import re
import sys


def main():
    html_dir = sys.argv[1]
    index = os.path.join(html_dir, "index.html")
    text = open(index).read()

    pruned = []

    def keep(row):
        m = re.search(r'hier/([^"]+\.vhd\.html)', row)
        if not m:
            return True  # header / non-file row
        # real coverage cells are class="percent<digit>"; N.A. is "percentna"
        if re.search(r'class="percent\d', row):
            return True
        pruned.append(m.group(1))
        return False

    parts = re.split(r"(<tr>.*?</tr>)", text, flags=re.S)
    out = "".join(p for p in parts if not p.startswith("<tr>") or keep(p))
    open(index, "w").write(out)

    # drop the now-orphaned per-file pages
    for page in pruned:
        for sub in ("hier", "source"):
            p = os.path.join(html_dir, sub, page)
            if os.path.exists(p):
                os.remove(p)

    print(f"cover_prune: removed {len(pruned)} non-DUT rows from {index}")


if __name__ == "__main__":
    main()
