"""Regenerates every launcher icon and splash asset from the master art.

    python tool/generate_branding.py

Source of truth is `assets/branding/app_icon_art.png` — the bare Proteinix
wordmark and P-mark on transparency, with no plate and no corner rounding. Keep
it that way. An adaptive icon supplies its own background layer and Android
applies its own mask, so art that already carries a black tile and rounded
corners gets masked twice: the corners are clipped a second time and the plate
fights whatever shape the launcher wanted.

## Why the launcher icon drops the wordmark

An adaptive icon is 108dp, of which only the centre 72dp survives masking — and
on a launcher that masks to a circle, only a 66dp circle does. The full lockup
does not fit that. PROTEINIX is the widest element in the art and sits at the
bottom, exactly where a circle is narrowest, so a full-lockup foreground came
out reading "ROTEIN" on Pixel's circle mask and "ROTEINI" on a squircle.

Shrinking the whole lockup to fit would leave the art at ~42% of the canvas
against the ~70% it was composed at: a small, weak mark adrift in black. So the
launcher gets the P-mark alone, which fits the circle at essentially native
resolution, and the wordmark is dropped — it is four pixels tall at 48dp and
illegible anyway, and the launcher already prints "Proteinix" underneath.

The Play Console icon and the legacy plate keep the full lockup, because
neither is ever circle-masked and both are shown large enough to read it.

## Why there are two splash assets

Android 11 and below treat the window background as the launch screen, so
`launch_background.xml` composites a centred bitmap over a solid colour with no
masking at all — the full lockup fits, and it is emitted per density.

Android 12+ ignores that entirely and draws its own splash, masking
`windowSplashScreenAnimatedIcon` to a circle: the drawable occupies a 288dp box
of which only the middle 192dp survives. That is the same constraint the
launcher icon faces, so it gets the same inscribed P-mark.
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "assets" / "branding" / "app_icon_art.png"
RES = ROOT / "android" / "app" / "src" / "main" / "res"
STORE = ROOT / "assets" / "branding" / "play_store_icon.png"

#: The plate colour. Also written into `values/ic_launcher_background.xml`.
BACKGROUND = (0, 0, 0, 255)

#: Diameter of the guaranteed-visible circle, as a fraction of the adaptive
#: canvas. The foreground is fitted so the mark's own enclosing circle clears
#: this, which is the only way to be safe on a launcher that masks to a circle.
SAFE_CIRCLE = 66 / 108

#: Set False to put the full lockup on the launcher too. Expect the wordmark to
#: be clipped on circle and squircle masks — see the module docstring.
MARK_ONLY = True

#: Row where the P-mark ends and the wordmark begins, in master-art pixels.
#: There is a clean 22px empty band there; `python -c` over the alpha channel
#: will find it again if the art is ever redrawn.
WORDMARK_TOP = 215

#: Legacy icons are never masked, so the art can sit larger on its own plate.
LEGACY_FRACTION = 0.70

#: Corner radius of the legacy plate, as a fraction of its width. Matches the
#: squircle in the original artwork closely enough to be indistinguishable at
#: launcher sizes.
LEGACY_RADIUS = 0.22

#: dp sizes are fixed by the platform: 48dp legacy, 108dp adaptive.
DENSITIES = {
    "mdpi": 1,
    "hdpi": 1.5,
    "xhdpi": 2,
    "xxhdpi": 3,
    "xxxhdpi": 4,
}

#: Width of the pre-Android-12 splash lockup, in dp. Nothing masks it, so this
#: is purely a composition choice — wide enough to read the wordmark, narrow
#: enough to leave air on a small phone.
SPLASH_LOCKUP_DP = 160

#: Android 12's splash box, and the circle inside it that survives masking.
SPLASH_BOX_DP = 288
SPLASH_CIRCLE_DP = 192

#: Authoring density for the Android 12 icon: one file, scaled by the system.
#: 4x covers xxxhdpi without the platform having to upscale it further.
SPLASH_ICON_SCALE = 4


def fitted(art: Image.Image, canvas: int, fraction: float) -> Image.Image:
    """Centres [art] on a transparent square, scaled to [fraction] of it."""
    box = canvas * fraction
    scale = min(box / art.width, box / art.height)
    w, h = max(1, round(art.width * scale)), max(1, round(art.height * scale))
    out = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    out.paste(art.resize((w, h), Image.LANCZOS),
              ((canvas - w) // 2, (canvas - h) // 2))
    return out


def enclosing_circle(art: Image.Image) -> tuple[float, float, float]:
    """Smallest circle covering every opaque pixel, as `(cx, cy, radius)`.

    Measured against the pixels rather than the bounding box. The box's
    half-diagonal is the safe answer only if there is artwork in all four
    corners, and there isn't — the P-mark's corners are mostly empty, so
    assuming otherwise threw away 12% of the available diameter and left the
    icon smaller than it needed to be.
    """
    alpha = np.asarray(art)[:, :, 3]
    ys, xs = np.where(alpha > 20)
    w, h = art.width, art.height

    # A coarse sweep around the box centre, then a fine one around the winner.
    # The true minimum-enclosing-circle algorithm is not worth it here: the
    # function is convex and this lands within a pixel of the optimum.
    best = (float("inf"), w / 2, h / 2)
    for step, span in ((3, 20), (1, 4)):
        _, bx, by = best
        for cy in np.arange(by - span, by + span + 1, step):
            for cx in np.arange(bx - span, bx + span + 1, step):
                r = np.sqrt((xs - cx) ** 2 + (ys - cy) ** 2).max()
                if r < best[0]:
                    best = (float(r), float(cx), float(cy))
    return best[1], best[2], best[0]


def inscribed(art: Image.Image, canvas: int, fraction: float) -> Image.Image:
    """Places [art] so every pixel of it survives a circular mask.

    Fitting by width or height is not enough: a mark measuring 66% across still
    has artwork outside a 66% circle, and on the P-mark that artwork is the
    ascender and the outermost arc.

    The art is centred on *its* circle, not on its bounding box — those differ
    by 14px here, and using the box would leave the mark visibly off-centre
    inside the mask.
    """
    cx, cy, radius = enclosing_circle(art)
    scale = (canvas * fraction / 2) / radius
    w, h = max(1, round(art.width * scale)), max(1, round(art.height * scale))

    out = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    out.paste(
        art.resize((w, h), Image.LANCZOS),
        (round(canvas / 2 - cx * scale), round(canvas / 2 - cy * scale)),
    )
    return out


def plated(art: Image.Image, canvas: int) -> Image.Image:
    """The legacy icon: art on a rounded plate, shape already baked in."""
    # Supersampled, because a rounded rectangle drawn straight into a 48px
    # bitmap has visibly stepped corners and ImageDraw does no antialiasing.
    ss = 4
    big = canvas * ss
    plate = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    ImageDraw.Draw(plate).rounded_rectangle(
        (0, 0, big - 1, big - 1), radius=int(big * LEGACY_RADIUS), fill=BACKGROUND
    )
    plate = plate.resize((canvas, canvas), Image.LANCZOS)
    layer = fitted(art, canvas, LEGACY_FRACTION)
    return Image.alpha_composite(plate, layer)


def splash(art: Image.Image, mark: Image.Image) -> None:
    """The two launch screens: pre-12 lockup, and the Android 12 masked icon."""
    for name, factor in DENSITIES.items():
        out = RES / f"drawable-{name}"
        out.mkdir(parents=True, exist_ok=True)
        width = round(SPLASH_LOCKUP_DP * factor)
        height = max(1, round(art.height * width / art.width))
        art.resize((width, height), Image.LANCZOS).save(out / "splash_logo.png")
    print(f"  pre-12 lockup: {SPLASH_LOCKUP_DP}dp wide, 5 densities")

    # Authored on the full 288dp box, not cropped to the circle: the box is
    # what the system scales, and art drawn edge-to-edge inside a smaller
    # canvas would be blown up past the mask.
    box = SPLASH_BOX_DP * SPLASH_ICON_SCALE
    icon = inscribed(mark, box, SPLASH_CIRCLE_DP / SPLASH_BOX_DP)
    (RES / "drawable-nodpi").mkdir(parents=True, exist_ok=True)
    icon.save(RES / "drawable-nodpi" / "splash_icon.png")
    print(f"  android 12 icon: {box}px box, mark inscribed in the "
          f"{SPLASH_CIRCLE_DP}dp circle")

    colour = "#%02X%02X%02X" % BACKGROUND[:3]
    (RES / "values" / "splash.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<resources>\n"
        "    <!-- Black, matching AppColors.background. The logo is drawn for a\n"
        "         black plate — its P stem is white and would vanish on light —\n"
        "         and matching the app's own background is what makes the\n"
        "         handover from splash to first frame invisible. -->\n"
        f'    <color name="splash_background">{colour}</color>\n'
        "</resources>\n",
        encoding="utf-8",
    )
    print(f"  splash background -> {colour}")


def main() -> None:
    art = Image.open(ART).convert("RGBA")
    print(f"master art {art.size[0]}x{art.size[1]}")

    if MARK_ONLY:
        mark = art.crop((0, 0, art.width, WORDMARK_TOP))
        mark = mark.crop(mark.split()[3].point(lambda v: 255 if v > 20 else 0).getbbox())
    else:
        mark = art
    print(f"launcher mark {mark.size[0]}x{mark.size[1]}"
          f"{' (wordmark dropped)' if MARK_ONLY else ''}")

    for name, factor in DENSITIES.items():
        out = RES / f"mipmap-{name}"
        out.mkdir(parents=True, exist_ok=True)

        adaptive = round(108 * factor)
        legacy = round(48 * factor)

        inscribed(mark, adaptive, SAFE_CIRCLE).save(out / "ic_launcher_foreground.png")
        plate = plated(art, legacy)
        plate.save(out / "ic_launcher.png")
        # Some launchers and OEM skins still ask for the round variant by name.
        plate.save(out / "ic_launcher_round.png")
        print(f"  {name}: foreground {adaptive}px, legacy {legacy}px")

    # Play Console artwork. Full-bleed and square by requirement — the Console
    # rounds it itself — so it uses the legacy plate at full size.
    store = Image.new("RGBA", (512, 512), BACKGROUND)
    store = Image.alpha_composite(store, fitted(art, 512, LEGACY_FRACTION))
    store.convert("RGB").save(STORE)
    print(f"play store icon -> {STORE.relative_to(ROOT)}")

    colour = "#%02X%02X%02X" % BACKGROUND[:3]
    (RES / "values" / "ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<resources>\n"
        f'    <color name="ic_launcher_background">{colour}</color>\n'
        "</resources>\n",
        encoding="utf-8",
    )
    print(f"background colour -> {colour}")

    print("splash:")
    splash(art, mark)


if __name__ == "__main__":
    main()
