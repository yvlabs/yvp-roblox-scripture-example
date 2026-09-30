#!/usr/bin/env python3
"""Overlay panels must not hide their own children behind them.

Setting ZIndex on a container while leaving its children at the default draws
the children behind the container's opaque background under Global ZIndex
behaviour. That produced a version picker that looked like an empty box, and
it is invisible to unit tests, so it is checked statically instead.
"""
import re
import sys
import pathlib

ui = pathlib.Path("src/client/KioskUI.luau").read_text()

failures = []

if "ZIndexBehavior.Sibling" not in ui:
    failures.append("ScreenGui does not set ZIndexBehavior.Sibling")

# Every overlay that raises its own ZIndex must also raise its children.
overlays = re.findall(r"(\w+)\.ZIndex = (\d+)", ui)
raised = {name: int(z) for name, z in overlays if int(z) > 1}
for name, z in raised.items():
    # Children are created via the label()/button() helpers with an explicit
    # ZIndex field; require at least one above the container's.
    higher = [int(m) for m in re.findall(r"ZIndex = (\d+)", ui) if int(m) > z]
    if not higher:
        failures.append(f"{name} raises ZIndex to {z} with no child above it")

if failures:
    for f in failures:
        print(f"  FAIL {f}")
    sys.exit(1)
print("overlay z-order check: ok")
