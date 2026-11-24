"""SafeLoot logo: the painter. Repaints the render of safeloot_chest.py with curved brush strokes and exports it.

    uv run --with opencv-python-headless --with numpy --with pillow python art/logo/paint.py RAW.png OUT_DIR

Stroke-based painting (big brushes first, then smaller ones only where the picture still differs; every stroke follows
the shapes under it), over a painted vault. The eye and the edges keep more of the drawing, the background less.
"""
import os
import struct
import sys

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

RAW, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
S = 1280
K = S / 1024
BASE = 1024
rng = np.random.default_rng(4)
raw = np.asarray(Image.open(RAW).convert("RGBA").resize((S, S), Image.LANCZOS), np.float32) / 255
rgb, alpha = raw[..., :3], raw[..., 3:]
yy, xx = np.mgrid[0:S, 0:S].astype(np.float32) / S
g = lambda a, s: cv2.GaussianBlur(a, (0, 0), s * K)  # noqa: E731


# Colour grade of the subject: deeper shadows, warmer lights ---------------------------------------------------------
lum = (rgb @ np.array([0.2126, 0.7152, 0.0722], np.float32))[..., None]
rgb = np.clip(rgb * (0.8 + 0.42 * lum), 0, 1)
rgb = np.clip(lum + (rgb - lum) * 1.08, 0, 1)

# Background: a dark treasure vault, painted ---------------------------------------------------------------------------
noise = np.zeros((S, S), np.float32)
for o, amp in ((4, 1.0), (8, 0.6), (16, 0.35), (32, 0.18)):
    noise += cv2.resize(rng.random((o, o)).astype(np.float32), (S, S), interpolation=cv2.INTER_CUBIC) * amp
noise = (noise - noise.min()) / (noise.max() - noise.min())
d = np.sqrt(((xx - 0.5) / 0.5) ** 2 + ((yy - 0.47) / 0.5) ** 2)
col = lambda h: np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)], np.float32)  # noqa: E731
mix = lambda a, b, t: a * (1 - t[..., None]) + b * t[..., None]  # noqa: E731
bg = np.ones((S, S, 3), np.float32) * col("0a0912")
bg = mix(bg, col("251c40"), np.clip(1.2 - d * 0.9, 0, 1))
ang = np.arctan2(yy - 0.5, xx - 0.5)
rays = np.zeros_like(d)
for k in range(7):
    rays += np.sin(ang * rng.integers(4, 22) + rng.uniform(0, 6.28))
rays = np.clip(rays / 2.6, -1, 1) * 0.5 + 0.5
up = np.sqrt(((xx - 0.5) / 0.46) ** 2 + ((yy - 0.3) / 0.36) ** 2)
bg = mix(bg, col("54348f"), np.clip(1.08 - up * 0.92, 0, 1) ** 1.2 * (0.6 + 0.4 * rays))
bg = mix(bg, col("8f5fca"), np.clip(0.86 - up, 0, 1) ** 1.2 * (0.45 + 0.75 * rays) * 1.1)
bg = mix(bg, col("e0b8f5"), np.clip(0.5 - up, 0, 1) ** 1.2 * (0.4 + 0.8 * rays))
warm = np.exp(-(((xx - 0.5) / 0.4) ** 2 + ((yy - 0.93) / 0.12) ** 2))
bg = mix(bg, col("8a5420"), warm * 0.85)
bg *= (0.5 + 0.95 * noise)[..., None]
bg *= np.clip(1.22 - d * 0.5, 0.2, 1.1)[..., None]
# floor shadow under the chest
foot = np.exp(-(((xx - 0.5) / 0.4) ** 2 + ((yy - 0.885) / 0.06) ** 2))
bg = mix(bg, col("080509"), foot * 0.85)
# halo around the silhouette (the painted glow of the game's icons)
halo = g(alpha[..., 0], 26) * (1 - alpha[..., 0])
bg = 1 - (1 - np.clip(bg, 0, 1)) * (1 - halo[..., None] * col("7a48c8") * 0.5)
halo2 = g(alpha[..., 0], 7) * (1 - alpha[..., 0])
bg = 1 - (1 - np.clip(bg, 0, 1)) * (1 - halo2[..., None] * col("b48cf0") * 0.16)
ref = np.clip(bg * (1 - alpha) + rgb * alpha, 0, 1).astype(np.float32)

# light of the eye and of the gold on the air
hot = ref * np.clip((ref.max(-1, keepdims=True) - 0.66) / 0.34, 0, 1)
purple = np.clip(ref[..., 2] - ref[..., 1] - 0.22, 0, 1)[..., None] * ref * alpha
ref = 1 - (1 - ref) * (1 - np.clip(g(purple, 22) * 0.7 + g(hot, 12) * 0.16, 0, 1))
ref = np.clip(ref, 0, 1).astype(np.float32)


# The painter ----------------------------------------------------------------------------------------------------------
def paint(canvas, target, base_radius, where, threshold, opacity, jitter, max_len, seed, bristle=True, flow=None):
    r = np.random.default_rng(seed)
    radius = max(2, int(round(base_radius * K)))
    blurred = g(target, max(0.6, base_radius * 0.45))
    gray = blurred @ np.array([0.3, 0.59, 0.11], np.float32)
    gx, gy = cv2.Sobel(gray, cv2.CV_32F, 1, 0, ksize=3), cv2.Sobel(gray, cv2.CV_32F, 0, 1, ksize=3)
    gx, gy = g(gx, base_radius * 0.6), g(gy, base_radius * 0.6)
    step = max(2, int(radius * 0.85))
    diff = np.sqrt(((canvas - blurred) ** 2).sum(-1))
    pts = [(x, y) for y in range(step // 2, S, step) for x in range(step // 2, S, step)]
    r.shuffle(pts)
    acc = canvas
    for x, y in pts:
        x = int(np.clip(x + r.integers(-step // 2, step // 2 + 1), 0, S - 1))
        y = int(np.clip(y + r.integers(-step // 2, step // 2 + 1), 0, S - 1))
        if where[y, x] < r.random() or diff[y, x] < threshold:
            continue
        c = blurred[y, x]
        line, px, py, lx, ly = [(x, y)], float(x), float(y), 0.0, 0.0
        for i in range(max_len):
            ix, iy = int(np.clip(px, 0, S - 1)), int(np.clip(py, 0, S - 1))
            if i > 2 and np.abs(blurred[iy, ix] - c).sum() > np.abs(acc[iy, ix] - c).sum() + 0.06:
                break
            vx, vy = -gy[iy, ix], gx[iy, ix]
            n = np.hypot(vx, vy)
            if flow is not None and flow[0][iy, ix] < 0.35:
                a = flow[1][iy, ix]  # background: free, swirling brush
                vx, vy, n = np.cos(a), np.sin(a), 1.0
            elif n < 1e-4:
                a = 0.6 + 0.8 * np.sin(px * 0.004 + py * 0.006 + seed)
                vx, vy, n = np.cos(a), np.sin(a), 1.0
            vx, vy = vx / n, vy / n
            if lx * vx + ly * vy < 0:
                vx, vy = -vx, -vy
            vx, vy = 0.55 * vx + 0.45 * lx, 0.55 * vy + 0.45 * ly
            m = np.hypot(vx, vy) + 1e-6
            lx, ly = vx / m, vy / m
            px, py = px + lx * radius * 0.9, py + ly * radius * 0.9
            line.append((int(px), int(py)))
        if len(line) < 2:
            line.append((x + 1, y))
        hsv_j = r.normal(0, jitter, 3).astype(np.float32)
        colr = np.clip(c * (1 + r.normal(0, jitter)) + hsv_j * 0.4, 0, 1)
        arr = np.array(line, np.int32).reshape(-1, 1, 2)
        x0, y0 = arr[..., 0].min() - radius - 3, arr[..., 1].min() - radius - 3
        x1, y1 = arr[..., 0].max() + radius + 4, arr[..., 1].max() + radius + 4
        x0, y0, x1, y1 = max(0, x0), max(0, y0), min(S, x1), min(S, y1)
        if x1 <= x0 or y1 <= y0:
            continue
        mask = np.zeros((y1 - y0, x1 - x0), np.uint8)
        cv2.polylines(mask, [arr - np.array([[x0, y0]])], False, 255, max(1, int(radius * 2)), cv2.LINE_AA)
        a = mask.astype(np.float32) / 255
        if bristle and radius >= 4:
            hair = r.random((max(2, (y1 - y0) // 2), max(2, (x1 - x0) // 2))).astype(np.float32)
            hair = cv2.resize(cv2.GaussianBlur(hair, (0, 0), 0.8), (x1 - x0, y1 - y0))
            a *= np.clip(0.55 + 1.1 * (hair - 0.3), 0.25, 1)
        a = (a * opacity)[..., None]
        acc[y0:y1, x0:x1] = acc[y0:y1, x0:x1] * (1 - a) + colr * a
    return acc


subject = np.clip(g(alpha[..., 0], 2) * 1.2, 0, 1)
detail = np.clip(g(np.abs(cv2.Laplacian(g(ref, 1.2).mean(-1), cv2.CV_32F)), 3) * 26, 0, 1)
swirl = np.zeros((S, S), np.float32)
for o, amp in ((5, 1.0), (10, 0.5)):
    swirl += cv2.resize(rng.random((o, o)).astype(np.float32), (S, S), interpolation=cv2.INTER_CUBIC) * amp
flow = (subject, (swirl / swirl.max()) * 5.2 + np.arctan2(yy - 0.35, xx - 0.5) * 0.6)
canvas = (g(ref, 30) * 0.9).astype(np.float32)
canvas = paint(canvas, ref, 22, 1 - 0.75 * subject, 0.0, 0.7, 0.11, 6, 1, True, flow)
canvas = paint(canvas, ref, 11, np.clip(1 - 0.2 * subject, 0, 1), 0.02, 0.62, 0.09, 6, 2, True, flow)
canvas = paint(canvas, ref, 6, np.clip(0.35 + subject, 0, 1), 0.04, 0.72, 0.06, 7, 3, True, flow)
canvas = paint(canvas, ref, 3, np.clip(0.12 + subject * 0.88, 0, 1), 0.045, 0.8, 0.03, 8, 4, False, flow)
canvas = paint(canvas, ref, 2, np.clip(subject * (0.25 + detail), 0, 1), 0.055, 0.85, 0.02, 8, 5, False)

# keep the drawing where the eye looks: ink, edges and the eye itself
keep = np.clip(0.42 * subject + 0.42 * detail * subject, 0, 0.78)
iris = np.clip(g(np.clip(purple.max(-1) * 4, 0, 1), 10) * 1.5, 0, 1)
keep = np.maximum(keep, iris * 0.6)[..., None]
art = canvas * (1 - keep) + ref * keep
# impasto: the relief of the strokes catches a little light
h = g(canvas.mean(-1), 0.8)
relief = cv2.Sobel(h, cv2.CV_32F, 1, 0) * -0.6 + cv2.Sobel(h, cv2.CV_32F, 0, 1) * -0.8
art = np.clip(art * (1 + np.clip(relief, -0.16, 0.16)[..., None] * 0.5), 0, 1)
# paint-like contrast, painted sparks
art = art + 0.1 * (art - 0.5) * 4 * art * (1 - art)
sparks = np.zeros_like(art)
for _ in range(46):
    x, y = int(S * (0.5 + rng.normal(0, 0.27))), int(S * rng.uniform(0.04, 0.92))
    if not (4 < x < S - 4 and 4 < y < S - 4) or alpha[y, x, 0] > 0.3:
        continue
    c = col("ffc46a") if rng.random() < 0.65 else col("c88aff")
    sz = rng.uniform(1.0, 2.6) * K
    cv2.ellipse(sparks, (x, y), (max(1, int(sz)), max(1, int(sz * rng.uniform(1, 1.8)))), rng.uniform(0, 180), 0, 360, tuple(float(v) for v in c * rng.uniform(0.6, 1.1)), -1, cv2.LINE_AA)
art = 1 - (1 - np.clip(art, 0, 1)) * (1 - np.clip(sparks + g(sparks, 5) * 1.3, 0, 1))
hot = art * np.clip((art.max(-1, keepdims=True) - 0.72) / 0.28, 0, 1)
art = 1 - (1 - art) * (1 - np.clip(g(hot.astype(np.float32), 9) * 0.12 + g(hot.astype(np.float32), 34) * 0.16, 0, 1))
vig = np.clip(1.14 - 0.55 * np.clip(np.sqrt(((xx - .5) / .5) ** 2 + ((yy - .5) / .5) ** 2) - 0.55, 0, 1) ** 1.2, 0, 1)
art = np.clip(art * vig[..., None], 0, 1)

full = art
art = cv2.resize(art.astype(np.float32), (BASE, BASE), interpolation=cv2.INTER_AREA)
alpha = cv2.resize(alpha, (BASE, BASE), interpolation=cv2.INTER_AREA)[..., None]
noise = cv2.resize(noise, (BASE, BASE), interpolation=cv2.INTER_AREA)
S = BASE
K = 1.0
yy, xx = np.mgrid[0:S, 0:S].astype(np.float32) / S
img = Image.fromarray((np.clip(art, 0, 1) * 255).astype(np.uint8), "RGB").filter(ImageFilter.UnsharpMask(1.3, 45, 2))


# Frame: the dark bevel of a game icon, a little worn ---------------------------------------------------------------------
def framed(im):
    w = im.size[0]
    a = np.asarray(im, np.float32) / 255
    u = np.minimum(np.minimum(xx, 1 - xx), np.minimum(yy, 1 - yy)) if w == S else None
    light = np.clip(0.55 + 0.8 * (0.5 - yy) + 0.5 * (0.5 - xx), 0.12, 1.1)
    fine = cv2.resize(np.random.default_rng(9).random((S // 5, S // 5)).astype(np.float32), (S, S), interpolation=cv2.INTER_CUBIC)
    worn = 0.5 + 0.8 * noise + 0.35 * (fine - 0.5)
    out = (u < 0.0075).astype(np.float32)[..., None]
    gold = np.clip(1 - np.abs(u - 0.0125) / 0.0055, 0, 1)[..., None] ** 0.7
    inner = np.exp(-(np.clip(u - 0.018, 0, 1) / 0.012) ** 2)[..., None] * 0.8
    a = a * (1 - inner)
    a = a * (1 - gold) + col("b5822f") * (light * worn)[..., None] * 1.15 * gold
    a = a * (1 - out) + col("0a0706") * out
    return Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8), "RGB")


logo = framed(img)
for size in (1024, 512, 400):
    im = logo if size == S else logo.resize((size, size), Image.LANCZOS).filter(ImageFilter.UnsharpMask(1.0, 60, 2))
    im.save(os.path.join(OUT, "logo-%d.png" % size), optimize=True)
a = np.concatenate([art, np.clip(g(alpha[..., 0], 0.8), 0, 1)[..., None]], -1)
Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "emblem-1024.png"), optimize=True)

ICON = tuple(float(v) for v in os.environ.get("ICON", "0.415,0.6,0.2").split(","))
half, ex, ey = int(S * ICON[2]), int(S * ICON[0]), int(S * ICON[1])
icon = img.crop((ex - half, ey - half, ex + half, ey + half)).resize((256, 256), Image.LANCZOS).filter(ImageFilter.UnsharpMask(1.4, 60, 2))
icon.save(os.path.join(OUT, "icon-256.png"), optimize=True)


def tga(name, size):
    im = icon.resize((size, size), Image.LANCZOS).filter(ImageFilter.UnsharpMask(0.8, 60, 1)).convert("RGBA")
    with open(os.path.join(OUT, name), "wb") as f:
        f.write(struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 0x28))
        f.write(np.asarray(im)[..., [2, 1, 0, 3]].tobytes())


tga("Icon.tga", 64)
tga("Portrait.tga", 128)
pv = Image.new("RGB", (900, 300), (34, 34, 34))
x = 20
for size in (256, 129, 96, 64):
    pv.paste(logo.resize((size, size), Image.LANCZOS), (x, 22))
    x += size + 18
for size in (64, 48, 32, 20):
    pv.paste(icon.resize((size, size), Image.LANCZOS), (x, 22))
    x += size + 14
pv.save(os.path.join(OUT, "preview.png"))
print("painted in", OUT)
