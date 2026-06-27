#!/usr/bin/env python3
"""Generates a 3D folder icon for FinderFlow at all required macOS sizes."""

import os, sys, math
import Quartz as Q

ICONSET_DIR = "FinderFlow/Assets.xcassets/AppIcon.appiconset"

# ── drawing ────────────────────────────────────────────────────────────────

def make_color(r, g, b, a=1.0):
    return Q.CGColorCreate(Q.CGColorSpaceCreateDeviceRGB(), [r, g, b, a])

def rounded_rect_path(x, y, w, h, r):
    path = Q.CGPathCreateMutable()
    Q.CGPathMoveToPoint(path, None, x + r, y)
    Q.CGPathAddLineToPoint(path, None, x + w - r, y)
    Q.CGPathAddArcToPoint(path, None, x + w, y,     x + w, y + r,     r)
    Q.CGPathAddLineToPoint(path, None, x + w, y + h - r)
    Q.CGPathAddArcToPoint(path, None, x + w, y + h, x + w - r, y + h, r)
    Q.CGPathAddLineToPoint(path, None, x + r, y + h)
    Q.CGPathAddArcToPoint(path, None, x, y + h, x, y + h - r, r)
    Q.CGPathAddLineToPoint(path, None, x, y + r)
    Q.CGPathAddArcToPoint(path, None, x, y, x + r, y, r)
    Q.CGPathCloseSubpath(path)
    return path

def draw_folder(ctx, s):
    """Draw a 3D-style folder into a CGContext of size s×s."""
    pad   = s * 0.06
    br    = s * 0.07   # corner radius for body

    # ── body geometry ────────────────────────────────────────────────────
    bx = pad
    by = pad * 2.2
    bw = s - pad * 2
    bh = s - pad * 4.5

    # ── 1. drop shadow ────────────────────────────────────────────────────
    Q.CGContextSaveGState(ctx)
    shadow_color = make_color(0, 0, 0, 0.38)
    Q.CGContextSetShadowWithColor(ctx, (0, -s * 0.03), s * 0.09, shadow_color)
    Q.CGContextAddPath(ctx, rounded_rect_path(bx, by, bw, bh, br))
    Q.CGContextSetFillColorWithColor(ctx, make_color(0.18, 0.46, 0.92))
    Q.CGContextFillPath(ctx)
    Q.CGContextRestoreGState(ctx)

    # ── 2. body gradient (top-light, bottom-dark) ─────────────────────────
    Q.CGContextSaveGState(ctx)
    Q.CGContextAddPath(ctx, rounded_rect_path(bx, by, bw, bh, br))
    Q.CGContextClip(ctx)
    cs = Q.CGColorSpaceCreateDeviceRGB()
    grad = Q.CGGradientCreateWithColorComponents(
        cs,
        # top color              bottom color
        [0.38, 0.68, 1.0, 1.0,  0.09, 0.30, 0.80, 1.0],
        [0.0, 1.0], 2
    )
    Q.CGContextDrawLinearGradient(
        ctx, grad,
        (s / 2, by + bh),   # start (top)
        (s / 2, by),         # end   (bottom)
        0
    )
    Q.CGContextRestoreGState(ctx)

    # ── 3. tab (above body top-left) ──────────────────────────────────────
    tab_w = bw * 0.40
    tab_h = s * 0.17
    tx = bx
    ty = by + bh - s * 0.01   # sits just above body top

    Q.CGContextSaveGState(ctx)
    tab_path = Q.CGPathCreateMutable()
    Q.CGPathMoveToPoint(tab_path, None, tx, ty)
    Q.CGPathAddLineToPoint(tab_path, None, tx + tab_w - s * 0.06, ty)
    Q.CGPathAddArcToPoint(tab_path, None,
        tx + tab_w, ty, tx + tab_w, ty + tab_h * 0.55, s * 0.05)
    Q.CGPathAddLineToPoint(tab_path, None, tx + tab_w, ty + tab_h)
    Q.CGPathAddLineToPoint(tab_path, None, tx, ty + tab_h)
    Q.CGPathCloseSubpath(tab_path)

    Q.CGContextAddPath(ctx, tab_path)
    Q.CGContextClip(ctx)
    tab_grad = Q.CGGradientCreateWithColorComponents(
        cs,
        [0.55, 0.78, 1.0, 1.0,  0.32, 0.60, 0.98, 1.0],
        [0.0, 1.0], 2
    )
    Q.CGContextDrawLinearGradient(
        ctx, tab_grad,
        (tx, ty + tab_h), (tx, ty), 0)
    Q.CGContextRestoreGState(ctx)

    # ── 4. inner top-edge ridge (3-D depth line) ──────────────────────────
    Q.CGContextSaveGState(ctx)
    Q.CGContextAddPath(ctx, rounded_rect_path(bx, by, bw, bh, br))
    Q.CGContextClip(ctx)
    ridge_rect = ((bx, by + bh - s * 0.055), (bw, s * 0.04))
    Q.CGContextSetFillColorWithColor(ctx, make_color(1, 1, 1, 0.18))
    Q.CGContextFillRect(ctx, ridge_rect)
    Q.CGContextRestoreGState(ctx)

    # ── 5. bottom-right inner shadow (depth illusion) ─────────────────────
    Q.CGContextSaveGState(ctx)
    Q.CGContextAddPath(ctx, rounded_rect_path(bx, by, bw, bh, br))
    Q.CGContextClip(ctx)
    depth_grad = Q.CGGradientCreateWithColorComponents(
        cs,
        [0, 0, 0, 0.0,  0, 0, 0, 0.18],
        [0.0, 1.0], 2
    )
    Q.CGContextDrawLinearGradient(
        ctx, depth_grad,
        (bx, by + bh * 0.35), (bx, by), 0)
    Q.CGContextRestoreGState(ctx)

    # ── 6. gloss highlight (top strip) ────────────────────────────────────
    Q.CGContextSaveGState(ctx)
    Q.CGContextAddPath(ctx, rounded_rect_path(bx, by, bw, bh, br))
    Q.CGContextClip(ctx)
    gloss_h = bh * 0.30
    gloss_grad = Q.CGGradientCreateWithColorComponents(
        cs,
        [1, 1, 1, 0.28,  1, 1, 1, 0.0],
        [0.0, 1.0], 2
    )
    Q.CGContextDrawLinearGradient(
        ctx, gloss_grad,
        (s / 2, by + bh),
        (s / 2, by + bh - gloss_h), 0)
    Q.CGContextRestoreGState(ctx)

    # ── 7. right-edge 3-D bevel ───────────────────────────────────────────
    Q.CGContextSaveGState(ctx)
    Q.CGContextAddPath(ctx, rounded_rect_path(bx, by, bw, bh, br))
    Q.CGContextClip(ctx)
    bevel_w = bw * 0.06
    bevel_grad = Q.CGGradientCreateWithColorComponents(
        cs,
        [0, 0, 0, 0.0,  0, 0, 0, 0.14],
        [0.0, 1.0], 2
    )
    Q.CGContextDrawLinearGradient(
        ctx, bevel_grad,
        (bx + bw - bevel_w, by + bh / 2),
        (bx + bw,           by + bh / 2), 0)
    Q.CGContextRestoreGState(ctx)

    # ── 8. thin border outline ────────────────────────────────────────────
    Q.CGContextSaveGState(ctx)
    Q.CGContextAddPath(ctx, rounded_rect_path(bx, by, bw, bh, br))
    Q.CGContextSetStrokeColorWithColor(ctx, make_color(0.06, 0.22, 0.60, 0.45))
    Q.CGContextSetLineWidth(ctx, max(1, s * 0.012))
    Q.CGContextStrokePath(ctx)
    Q.CGContextRestoreGState(ctx)


def render(size):
    cs = Q.CGColorSpaceCreateDeviceRGB()
    ctx = Q.CGBitmapContextCreate(
        None, size, size, 8, 0, cs,
        Q.kCGImageAlphaPremultipliedLast | Q.kCGBitmapByteOrder32Big
    )
    Q.CGContextClearRect(ctx, ((0, 0), (size, size)))
    draw_folder(ctx, size)
    return Q.CGBitmapContextCreateImage(ctx)


def save_png(image, path):
    url = Q.CFURLCreateFromFileSystemRepresentation(None, path.encode(), len(path), False)
    dest = Q.CGImageDestinationCreateWithURL(url, "public.png", 1, None)
    Q.CGImageDestinationAddImage(dest, image, None)
    Q.CGImageDestinationFinalize(dest)


# ── sizes: pixel_size → (logical_size, scale_label) ───────────────────────
ICON_SIZES = [
    (16,   "16x16",   "1x"),
    (32,   "16x16",   "2x"),
    (32,   "32x32",   "1x"),
    (64,   "32x32",   "2x"),
    (128,  "128x128", "1x"),
    (256,  "128x128", "2x"),
    (256,  "256x256", "1x"),
    (512,  "256x256", "2x"),
    (512,  "512x512", "1x"),
    (1024, "512x512", "2x"),
]

os.makedirs(ICONSET_DIR, exist_ok=True)

cache = {}
images_json = []

for (px, logical, scale) in ICON_SIZES:
    if px not in cache:
        cache[px] = render(px)
    fname = f"icon_{px}.png"
    save_png(cache[px], os.path.join(ICONSET_DIR, fname))
    images_json.append(
        f'    {{"filename": "{fname}", "idiom": "mac", "scale": "{scale}", "size": "{logical}"}}'
    )
    print(f"  {fname}  ({logical} @{scale})")

# write Contents.json
contents = '{\n  "images": [\n'
contents += ",\n".join(images_json)
contents += '\n  ],\n  "info": {"author": "xcode", "version": 1}\n}\n'

with open(os.path.join(ICONSET_DIR, "Contents.json"), "w") as f:
    f.write(contents)

print(f"\nDone — icons written to {ICONSET_DIR}/")
