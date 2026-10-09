#!/usr/bin/env python3
"""Export launcher/browser icons from assets/branding/logo.svg (requires librsvg)."""

import copy
import json
import math
from pathlib import Path
import shutil
import struct
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SVG = "http://www.w3.org/2000/svg"
ET.register_namespace("", SVG)
SOURCE = ET.parse(ROOT / "assets/branding/logo.svg").getroot()
RES = ROOT / "android/app/src/main/res"
PUBLIC = ROOT / "webapp/public"
SIZE = float(SOURCE.get("width"))
TILES = SOURCE.find(f"{{{SVG}}}g[@id='tiles']")
BACKGROUND = SOURCE.find(f"{{{SVG}}}rect[@id='background']").get("fill")
PATTERN = SOURCE.find(f".//{{{SVG}}}pattern[@id='grid']")
GRID = PATTERN.find(f"{{{SVG}}}path")
GRADIENTS = {
    gradient.get("id"): gradient
    for gradient in SOURCE.findall(f".//{{{SVG}}}linearGradient")
}


def write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content + "\n")


def svg_variant(*, rounded=False, scale=1):
    root = copy.deepcopy(SOURCE)
    if scale != 1:
        pattern = root.find(f".//{{{SVG}}}pattern[@id='grid']")
        for attribute in ("x", "y"):
            pattern.set(attribute, str(SIZE / 2 + (float(pattern.get(attribute)) - SIZE / 2) * scale))
        for attribute in ("width", "height"):
            pattern.set(attribute, str(float(pattern.get(attribute)) * scale))
        path = pattern.find(f"{{{SVG}}}path")
        pitch = pattern.get("width")
        path.set("d", f"M{pitch} 0H0V{pitch}")
        path.set("stroke-width", str(float(path.get("stroke-width")) * scale))
        tiles = root.find(f"{{{SVG}}}g[@id='tiles']")
        offset = SIZE / 2 * (1 - scale)
        tiles.set("transform", f"translate({offset} {offset}) scale({scale})")
    if rounded:
        defs = root.find(f"{{{SVG}}}defs")
        clip = ET.SubElement(defs, f"{{{SVG}}}clipPath", {"id": "icon-mask"})
        ET.SubElement(clip, f"{{{SVG}}}rect", {
            "width": str(SIZE), "height": str(SIZE), "rx": "208",
        })
        art = ET.Element(f"{{{SVG}}}g", {"clip-path": "url(#icon-mask)"})
        for element in list(root):
            if element.tag in (f"{{{SVG}}}rect", f"{{{SVG}}}g"):
                root.remove(element)
                art.append(element)
        root.append(art)
    return ET.tostring(root, encoding="unicode")


def render(svg, path, size, *, opaque=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run([
        "rsvg-convert", "--width", str(size), "--height", str(size),
    ], input=svg.encode(), stdout=subprocess.PIPE, check=True)
    path.write_bytes(result.stdout)
    width, height, _, color_type = struct.unpack(">IIBB", result.stdout[16:26])
    if (width, height) != (size, size) or (opaque and color_type != 2):
        raise ValueError(f"Invalid icon size or alpha channel: {path}")


def rectangle_path(rect):
    x, y, width, height, radius = (float(rect.get(key)) for key in ("x", "y", "width", "height", "rx"))
    right, bottom = x + width, y + height
    return (
        f"M{x + radius},{y}H{right - radius}A{radius},{radius} 0 0,1 {right},{y + radius}"
        f"V{bottom - radius}A{radius},{radius} 0 0,1 {right - radius},{bottom}"
        f"H{x + radius}A{radius},{radius} 0 0,1 {x},{bottom - radius}"
        f"V{y + radius}A{radius},{radius} 0 0,1 {x + radius},{y}Z"
    )


def android_foreground(*, monochrome=False):
    # The entire cross fits within 62 dp of the 66 dp circular safe zone.
    bounds = [float(tile.get("x")) for tile in TILES]
    width = max(float(tile.get("x")) + float(tile.get("width")) for tile in TILES) - min(bounds)
    factor = 62 / 108 * SIZE / width
    offset = SIZE / 2 * (1 - factor)
    paths = []
    for tile in TILES:
        data = rectangle_path(tile)
        if monochrome:
            paths.append(f'    <path android:fillColor="#ffffffff" android:pathData="{data}"/>')
            continue
        gradient = GRADIENTS[tile.get("fill")[5:-1]]
        x, y = float(tile.get("x")), float(tile.get("y"))
        end_x = x + float(tile.get("width")) * float(gradient.get("x2"))
        end_y = y + float(tile.get("height")) * float(gradient.get("y2"))
        stops = "\n".join(
            f'          <item android:color="{stop.get("stop-color")}" android:offset="{stop.get("offset", "0")}"/>'
            for stop in gradient
        )
        paths.append(f'''    <path android:pathData="{data}">
      <aapt:attr name="android:fillColor">
        <gradient android:type="linear" android:startX="{x}" android:startY="{y}" android:endX="{end_x}" android:endY="{end_y}">
{stops}
        </gradient>
      </aapt:attr>
    </path>''')
    content = "\n".join(paths)
    return f'''<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android" xmlns:aapt="http://schemas.android.com/aapt"
    android:width="108dp" android:height="108dp" android:viewportWidth="{SIZE:g}" android:viewportHeight="{SIZE:g}">
  <group android:scaleX="{factor}" android:scaleY="{factor}" android:translateX="{offset}" android:translateY="{offset}">
{content}
  </group>
</vector>''', factor


def android_background(factor):
    pitch = float(PATTERN.get("width")) * factor
    first = SIZE / 2 + (float(PATTERN.get("x")) - SIZE / 2) * factor
    first -= math.floor(first / pitch) * pitch
    lines = []
    position = first
    while position <= SIZE:
        lines.extend((f"M{position},0V{SIZE}", f"M0,{position}H{SIZE}"))
        position += pitch
    data = " ".join(lines)
    return f'''<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp" android:height="108dp" android:viewportWidth="{SIZE:g}" android:viewportHeight="{SIZE:g}">
  <path android:fillColor="{BACKGROUND}" android:pathData="M0,0H{SIZE}V{SIZE}H0Z"/>
  <path android:fillColor="#00000000" android:strokeColor="{GRID.get('stroke')}"
      android:strokeWidth="{float(GRID.get('stroke-width')) * factor}" android:pathData="{data}"/>
</vector>'''


def main():
    if not shutil.which("rsvg-convert"):
        raise SystemExit("Install librsvg first (macOS: brew install librsvg).")
    full = svg_variant()
    rounded = svg_variant(rounded=True)
    render(full, ROOT / "assets/branding/logo.png", 1024, opaque=True)
    icon_set = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    images = json.loads((icon_set / "Contents.json").read_text())["images"]
    for item in images:
        size = round(float(item["size"].split("x")[0]) * float(item["scale"][:-1]))
        render(full, icon_set / item["filename"], size, opaque=True)
    for density, size in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        render(rounded, RES / f"mipmap-{density}/ic_launcher.png", size)
    foreground, factor = android_foreground()
    monochrome, _ = android_foreground(monochrome=True)
    write(RES / "drawable/ic_launcher_foreground.xml", foreground)
    write(RES / "drawable/ic_launcher_monochrome.xml", monochrome)
    write(RES / "drawable/ic_launcher_background.xml", android_background(factor))
    for api in (26, 33):
        mono = '\n  <monochrome android:drawable="@drawable/ic_launcher_monochrome"/>' if api == 33 else ""
        write(RES / f"mipmap-anydpi-v{api}/ic_launcher.xml", f'''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
  <background android:drawable="@drawable/ic_launcher_background"/>
  <foreground android:drawable="@drawable/ic_launcher_foreground"/>{mono}
</adaptive-icon>''')
    write(PUBLIC / "favicon.svg", rounded)
    for size in (16, 32):
        render(rounded, PUBLIC / f"favicon-{size}.png", size)
    render(full, PUBLIC / "apple-touch-icon.png", 180, opaque=True)
    for size in (192, 512):
        render(full, PUBLIC / f"icons/icon-{size}.png", size, opaque=True)
    render(svg_variant(scale=0.88), PUBLIC / "icons/icon-maskable-512.png", 512, opaque=True)
    # A disposable native-scale preview, kept outside the shipped asset directories.
    preview = ROOT / "build/branding"
    preview.mkdir(parents=True, exist_ok=True)
    render(svg_variant(scale=factor), preview / "android-adaptive.png", 432, opaque=True)
    print("Exported iOS, Android and web icons from assets/branding/logo.svg.")


if __name__ == "__main__":
    main()
