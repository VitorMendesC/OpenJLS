#!/usr/bin/env python3
"""Per-Sources-file statement-coverage summary from the merged NVC coverage
database.

Exports <covdb-dir>/merged.covdb to cobertura XML (nvc --cover-export) and
unions statement hits per design unit across every instance. Two NVC export
quirks are handled here:
  - instantiated units are attributed to the root TB's filename, but the
    class name carries the entity (e.g. A1_GRADIENT_COMP(BEHAVIORAL)), so
    units are mapped back to their Sources/*.vhd by entity name;
  - `elsif`/`when` arms are exported as branch records (branch="true") whose
    hits attribute is always 0 — they are decision data, not statements, and
    counting them as statements understates coverage (the 90.4% -> 97.5%
    discrepancy of 2026-06-12). Only statement records are counted; branch
    detail lives in the HTML report.

Usage: cover_summary.py <covdb-dir> <sources-dir>
"""
import collections
import glob
import os
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET


def main():
    covdir, srcdir = sys.argv[1], sys.argv[2]
    # Sources/ plus the Sources/Xilinx/ wrappers — map by entity name, display
    # as path relative to srcdir (e.g. "Xilinx/openjls_axis.vhd").
    entity2file = {os.path.basename(f)[:-4].upper(): os.path.relpath(f, srcdir)
                   for f in glob.glob(os.path.join(srcdir, "*.vhd"))
                   + glob.glob(os.path.join(srcdir, "Xilinx", "*.vhd"))}
    # A labelled generate is exported as its own class named after the LABEL
    # (e.g. GEN_KEEP((null)) for openjls_top.vhd's gen_keep, with line numbers
    # of the defining file), so map generate labels back to their files too.
    gen_re = re.compile(r"^\s*(\w+)\s*:\s*(?:for|if)\b.*\bgenerate\b", re.M)
    for ent, f in sorted(entity2file.items()):
        with open(os.path.join(srcdir, f)) as fd:
            for lbl in gen_re.findall(fd.read()):
                entity2file.setdefault(lbl.upper(), f)

    hits = collections.defaultdict(dict)  # file -> {line: hit}
    with tempfile.TemporaryDirectory() as td:
        xml = os.path.join(td, "merged.xml")
        # --work: keep nvc's default ./work library stub in the temp dir.
        subprocess.run(["nvc", "--work=work:" + os.path.join(td, "work"),
                        "--cover-export", "--format=cobertura", "-o", xml,
                        os.path.join(covdir, "merged.covdb")],
                       check=True, capture_output=True)
        for cls in ET.parse(xml).getroot().iter("class"):
            ent = cls.get("name", "").split("(")[0]
            f = entity2file.get(ent)
            if f is None:
                continue
            for line in cls.iter("line"):
                if line.get("branch") == "true":
                    continue
                n, h = int(line.get("number")), int(line.get("hits"))
                hits[f][n] = hits[f].get(n, 0) or h

    totc = tott = 0
    print(f"{'file':32} {'stmt':>11}  uncovered lines")
    for f in sorted(hits):
        lines = hits[f]
        cov = sum(1 for h in lines.values() if h)
        missed = sorted(n for n, h in lines.items() if not h)
        totc += cov
        tott += len(lines)
        tag = ",".join(map(str, missed[:14])) + ("..." if len(missed) > 14 else "")
        print(f"{f:32} {cov:4}/{len(lines):<4} {100*cov/len(lines):5.1f}%  {tag}")
    uncovered = sorted(set(entity2file.values()) - set(hits) - {"openjls_pkg.vhd"})
    for f in uncovered:
        print(f"{f:32}    0/?      0.0%  NOT INSTRUMENTED BY ANY TEST")
    if tott:
        print(f"{'TOTAL':32} {totc:4}/{tott:<4} {100*totc/tott:5.1f}%")


if __name__ == "__main__":
    main()
