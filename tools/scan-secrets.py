#!/usr/bin/env python3
"""Refuse to ship a place file containing anything shaped like a credential.

A plain length rule flagged comment separators ("-----"), so the test also
requires the entropy a real key has: both letters and digits, and enough
distinct characters that prose and rule lines cannot qualify.

This script self-tests on every run. If the detector stops catching a
synthetic key, the build fails loudly rather than passing a weakened check.
"""
import re
import sys

TOKEN = re.compile(r"[A-Za-z0-9_\-\.]{32,}")


def looks_like_credential(token: str) -> bool:
    if len(token) < 32:
        return False
    if not any(c.isalpha() for c in token):
        return False
    if not any(c.isdigit() for c in token):
        return False
    # Rule lines, repeated padding and ordinary words lack character variety.
    if len(set(token)) < 12:
        return False
    # Dotted code identifiers (footnotePanel.ScrollBarImageColor3) are long and
    # varied but are not random. Real keys are not shaped like identifiers.
    if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)+", token):
        return False
    # A digit-density rule was tried here and rejected: the self-test showed it
    # would miss a base64url JWT header, which is digit-sparse. The dotted
    # identifier rule above is precise enough for the false positives actually
    # seen, and no real key is shaped like one.
    return True


def self_test() -> None:
    # Samples below must be synthetic. A real key was once used here as the
    # "must catch" example, which committed the very secret this tool exists
    # to keep out of the repository.
    must_catch = [
        "M8ntnYDUDvuEqEYLzeMgJhNge7Y608Iiq2DehNhhnWOZ5bGZ",   # YVP app key SHAPE (random; never a real key)
        "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6IjEyMyJ9",  # JWT header shape
        "Ad9znECt28kAUoVOotjdTLlSyfrBI7eu1GiEf4tu",   # generic key shape (random; avoids real vendor key prefixes)
    ]
    must_ignore = [
        "-" * 70,
        "=" * 50,
        "ReplicatedStorageScriptureKioskAttributionModule",     # long, no digits
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1111111111",         # low variety
        "https://www.biblica.com/yv-learn-more/",
        "footnotePanel.ScrollBarImageColor3",                   # dotted identifier
        "self.attributionLabel.AbsoluteSize.Y",                 # dotted identifier
        "TextTruncate.AtEnd.Enum.TextXAlignment.Left",          # dotted identifier
    ]
    for token in must_catch:
        if not looks_like_credential(token):
            raise SystemExit(f"secret scanner self-test FAILED: missed {token[:20]}...")
    for token in must_ignore:
        if looks_like_credential(token):
            raise SystemExit(f"secret scanner self-test FAILED: false positive on {token[:20]}...")


def main() -> int:
    self_test()
    path = sys.argv[1]
    raw = open(path, encoding="utf-8", errors="replace").read()
    hits = sorted({t for t in TOKEN.findall(raw) if looks_like_credential(t)})
    if hits:
        print(f"refusing to ship: {len(hits)} credential-shaped token(s) in {path}")
        for token in hits[:10]:
            print(f"  [{len(token)}] {token[:24]}...")
        return 1
    print("credential scan: clean (self-test passed)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
