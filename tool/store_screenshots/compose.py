#!/usr/bin/env python3
"""Composes the App Store screenshots from the raw screens run.sh took.

    tool/store_screenshots/compose.py [iphone] [ipad]

Reads build/store-screenshots/raw/<device>/*.png and captions.json, lays each
screenshot out as a web page (a caption above the screen in a drawn device)
and has headless Google Chrome render it at the size the App Store takes.
The results are build/store-screenshots/out/<device>/NN-<shot>.jpg.
"""

import html
import json
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent
WORK = ROOT / "build" / "store-screenshots"
FONTS = ROOT / "app" / "assets" / "fonts"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# The sizes App Store Connect takes for the 6.9-inch iPhone and the 13-inch
# iPad, which are also what the simulators' screenshots measure.
DEVICES = {
    "iphone": {"width": 1320, "height": 2868},
    "ipad": {"width": 2064, "height": 2752},
}

# Each shot in the order of the listing: its caption key, its layout, the raw
# screens it shows and the colour of the glow behind its caption.
SHOTS = [
    ("overview", "trio", ["look-editor-colour", "live-view", "library"], "#6EA8FF"),
    ("library", "single", ["library"], "#FFB454"),
    ("viewer", "single", ["viewer"], "#FF7A59"),
    ("live-view", "single", ["live-view"], "#5BD08B"),
    ("looks", "single", ["looks-loaded"], "#B48CFF"),
    ("look-editor", "single", ["look-editor-colour"], "#FFD166"),
    ("geotagging", "pair", ["viewer-map", "lock-screen"], "#4FD1C5"),
]

CSS = """
@font-face { font-family: Inter; font-weight: 400; src: url('%(fonts)s/Inter-Regular.ttf'); }
@font-face { font-family: Inter; font-weight: 500; src: url('%(fonts)s/Inter-Medium.ttf'); }
@font-face { font-family: Inter; font-weight: 600; src: url('%(fonts)s/Inter-SemiBold.ttf'); }
@font-face { font-family: Inter; font-weight: 700; src: url('%(fonts)s/Inter-Bold.ttf'); }
* { box-sizing: border-box; }
html, body { margin: 0; }
body {
  width: %(width)spx; height: %(height)spx; overflow: hidden; position: relative;
  display: flex; flex-direction: column;
  background: #0A0A0B; color: #F3F1EC; font-family: Inter, sans-serif;
  -webkit-font-smoothing: antialiased;
}
.glow {
  position: absolute; inset: 0;
  background:
    radial-gradient(ellipse 95%% 38%% at 50%% -4%%, color-mix(in srgb, %(glow)s 42%%, transparent), transparent 72%%),
    radial-gradient(ellipse 80%% 30%% at 50%% 108%%, color-mix(in srgb, %(glow)s 16%%, transparent), transparent 70%%);
}
.caption { position: relative; flex: none; padding: calc(var(--u) * 10.5) 6%% 0; text-align: center; }
h1 {
  margin: 0; font-weight: 700; font-size: calc(var(--u) * 9.1); line-height: 1.05;
  letter-spacing: -0.032em; text-wrap: balance;
}
p {
  margin: calc(var(--u) * 2.8) auto 0; max-width: 88%%; font-weight: 400;
  font-size: calc(var(--u) * 4.05); line-height: 1.32; color: #B4B2AC; text-wrap: balance;
}
.chips { margin-top: calc(var(--u) * 3.6); display: flex; justify-content: center; gap: calc(var(--u) * 1.4); }
.chip {
  padding: calc(var(--u) * 1.3) calc(var(--u) * 2.6); border-radius: 999px; font-weight: 600;
  font-size: calc(var(--u) * 3.1); background: rgba(255,255,255,.07);
  border: calc(var(--u) * .12) solid rgba(255,255,255,.13); color: #F3F1EC;
}
/* What the caption leaves of the canvas: the devices are sized by its height. */
.stage { position: relative; flex: 1; min-height: 0; container-type: size; }
.device {
  --w: calc(var(--h) * var(--aspect) * 1cqh);
  position: absolute; left: calc(var(--x) * 1cqw); top: calc(var(--y) * 1cqh); width: var(--w);
  transform: translateX(-50%%) rotate(var(--r, 0deg)); transform-origin: 50%% 30%%;
  padding: calc(var(--w) * var(--bezel)); background: #050506;
  border-radius: calc(var(--w) * var(--radius));
  box-shadow:
    0 0 0 calc(var(--w) * .0035) #4A4A50,
    0 0 0 calc(var(--w) * .0095) #19191C,
    0 calc(var(--w) * .05) calc(var(--w) * .16) rgba(0,0,0,.72);
}
.device img {
  display: block; width: 100%%;
  border-radius: calc(var(--w) * (var(--radius) - var(--bezel)));
}
.device.back { filter: brightness(.74); }
.iphone { --bezel: .021; --radius: .152; }
.ipad { --bezel: .028; --radius: .062; }
.iphone .island {
  position: absolute; left: 50%%; top: calc(var(--w) * (var(--bezel) + .0305));
  width: calc(var(--w) * .276); height: calc(var(--w) * .081);
  transform: translateX(-50%%); border-radius: 999px; background: #000;
}
"""

# Where the devices of each layout stand on the stage, the part of the canvas
# below the caption: centre x as a fraction of its width, top and height as
# fractions of its height, and a turn in degrees.
LAYOUTS = {
    "iphone": {
        "single": [(0.5, 0.035, 0.935, 0, "")],
        "trio": [
            (0.16, 0.185, 0.80, -8, "back"),
            (0.84, 0.185, 0.80, 8, "back"),
            (0.5, 0.085, 0.88, 0, ""),
        ],
        "pair": [(0.295, 0.03, 0.68, 0, ""), (0.705, 0.26, 0.68, 0, "")],
    },
    "ipad": {
        "single": [(0.5, 0.035, 0.935, 0, "")],
        "trio": [
            (0.16, 0.2, 0.71, -6, "back"),
            (0.84, 0.2, 0.71, 6, "back"),
            (0.5, 0.1, 0.82, 0, ""),
        ],
        "pair": [(0.3, 0.04, 0.58, 0, ""), (0.7, 0.35, 0.58, 0, "")],
    },
}


def page(device, caption, layout, screens, glow):
    size = DEVICES[device]
    width, height = size["width"], size["height"]
    css = CSS % {
        "fonts": FONTS.as_uri(),
        "width": width,
        "height": height,
        "glow": glow,
    }
    devices = []
    for screen, (x, y, h, turn, extra) in zip(screens, LAYOUTS[device][layout]):
        source = (WORK / "raw" / device / f"{screen}.png").as_uri()
        island = '<div class="island"></div>' if device == "iphone" else ""
        devices.append(
            f'<div class="device {device} {extra}" style="--x:{x * 100:.1f};'
            f'--y:{y * 100:.1f};--h:{h * 100:.1f};--r:{turn}deg">'
            f'<img src="{source}">{island}</div>'
        )
    chips = "".join(
        f'<span class="chip">{html.escape(c)}</span>' for c in caption.get("chips", [])
    )
    chips = f'<div class="chips">{chips}</div>' if chips else ""
    # The unit the type scales by: a hundredth of the canvas width on the
    # iPhone, less on the wider iPad so the caption keeps its proportions.
    unit = width / 100 * (1.0 if device == "iphone" else 0.7)
    return (
        f'<!doctype html><meta charset="utf-8"><style>{css}</style>'
        f'<body style="--u:{unit:.2f}px;--aspect:{width / height:.4f}">'
        f'<div class="glow"></div>'
        f'<div class="caption"><h1>{html.escape(caption["title"])}</h1>'
        f"<p>{html.escape(caption['subtitle'])}</p>{chips}</div>"
        f'<div class="stage">{"".join(devices)}</div></body>'
    )


def render(device):
    size = DEVICES[device]
    captions = json.loads((HERE / "captions.json").read_text())
    out = WORK / "out" / device
    out.mkdir(parents=True, exist_ok=True)
    for number, (shot, layout, screens, glow) in enumerate(SHOTS, start=1):
        caption = captions[shot]
        if device == "ipad":
            # The captions speak of the phone; on an iPad it is the iPad.
            caption = {
                key: [c.replace("phone", "iPad") for c in text]
                if isinstance(text, list)
                else text.replace("phone", "iPad")
                for key, text in caption.items()
            }
        source = out / f"{shot}.html"
        source.write_text(page(device, caption, layout, screens, glow))
        target = out / f"{number:02d}-{shot}.png"
        subprocess.run(
            [
                CHROME,
                "--headless=new",
                "--hide-scrollbars",
                "--force-device-scale-factor=1",
                f"--window-size={size['width']},{size['height']}",
                f"--screenshot={target}",
                source.as_uri(),
            ],
            check=True,
            capture_output=True,
        )
        source.unlink()
        # App Store Connect refuses screenshots with an alpha channel.
        subprocess.run(
            [
                "sips",
                "-s",
                "format",
                "jpeg",
                "-s",
                "formatOptions",
                "100",
                str(target),
                "--out",
                str(target.with_suffix(".jpg")),
            ],
            check=True,
            capture_output=True,
        )
        target.unlink()
        print(target.with_suffix(".jpg"))


if __name__ == "__main__":
    for name in sys.argv[1:] or list(DEVICES):
        render(name)
