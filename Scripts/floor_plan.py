"""Draw a dimensioned top-down floor plan (SVG) from a RoomScan scan.json."""
import json
import math
import sys
from pathlib import Path

scan_dir = Path(sys.argv[1])
WITH_FURNITURE = "--furniture" in sys.argv[2:]
scan = json.loads((scan_dir / "scan.json").read_text())
meta = json.loads((scan_dir / "room.json").read_text())

S = 90.0  # pixels per metre
MARGIN = 120.0
PANEL_W = 400.0
HEADER_H = 70.0

walls = scan["walls"]
ref_yaw = walls[0]["yaw"]  # longest wall becomes horizontal
c, s = math.cos(ref_yaw), math.sin(ref_yaw)


def rot(x, z):
    return (x * c - z * s, x * s + z * c)


def fmt(m):
    return f"{m:.2f}".replace(".", ",")


# Wall segments in the rotated frame.
segs = []
for w in walls:
    cx, cz = w["center"][0], w["center"][2]
    h = w["width"] / 2
    dx, dz = math.cos(w["yaw"]) * h, -math.sin(w["yaw"]) * h
    a, b = rot(cx - dx, cz - dz), rot(cx + dx, cz + dz)
    segs.append({"a": a, "b": b, "len": w["width"], "yaw": w["yaw"], "openings": []})

# Order walls into a closed polygon.
poly = [segs[0]]
remaining = segs[1:]
while remaining:
    end = poly[-1]["b"]
    best = min(remaining, key=lambda g: min(math.dist(end, g["a"]), math.dist(end, g["b"])))
    if math.dist(end, best["b"]) < math.dist(end, best["a"]):
        best["a"], best["b"] = best["b"], best["a"]
    poly.append(best)
    remaining.remove(best)
pts = [g["a"] for g in poly]
area = 0.5 * sum(p[0] * q[1] - q[0] * p[1] for p, q in zip(pts, pts[1:] + pts[:1]))
orient = 1 if area > 0 else -1
area = abs(area)
perimeter = sum(g["len"] for g in poly)

floor_y = walls[0]["center"][1] - walls[0]["height"] / 2
ceiling = walls[0]["height"]

KIND = {"door": "Porte", "window": "Fenêtre", "opening": "Passage"}
openings = []
for o in scan["openings"]:
    p = rot(o["center"][0], o["center"][2])
    host, t_best, d_best = None, 0, 1e9
    for g in poly:
        ux, uz = (g["b"][0] - g["a"][0]) / g["len"], (g["b"][1] - g["a"][1]) / g["len"]
        vx, vz = p[0] - g["a"][0], p[1] - g["a"][1]
        t = vx * ux + vz * uz
        d = abs(vx * uz - vz * ux)
        if -0.05 <= t <= g["len"] + 0.05 and d < d_best:
            host, t_best, d_best = g, t, d
    sill = (o["center"][1] - o["height"] / 2) - floor_y
    item = {"kind": o["kind"], "w": o["width"], "h": o["height"], "t": t_best, "sill": sill}
    host["openings"].append(item)
    openings.append(item)

# Number openings around the room.
counters = {}
for g in poly:
    g["openings"].sort(key=lambda o: o["t"])
    for o in g["openings"]:
        prefix = {"door": "P", "window": "F", "opening": "O"}[o["kind"]]
        counters[prefix] = counters.get(prefix, 0) + 1
        o["label"] = f"{prefix}{counters[prefix]}"

xs = [p[0] for p in pts]
zs = [p[1] for p in pts]
minx, minz = min(xs), min(zs)
W = (max(xs) - minx) * S + 2 * MARGIN
H = (max(zs) - minz) * S + 2 * MARGIN
SVG_W, SVG_H = W + PANEL_W, max(H, 760) + HEADER_H


def P(x, z):
    return ((x - minx) * S + MARGIN, (z - minz) * S + MARGIN + HEADER_H)


out = []
add = out.append
add(f'<svg xmlns="http://www.w3.org/2000/svg" width="{SVG_W:.0f}" height="{SVG_H:.0f}" '
    f'viewBox="0 0 {SVG_W:.0f} {SVG_H:.0f}" font-family="-apple-system, Helvetica, Arial, sans-serif">')
add(f'<rect x="0" y="0" width="{SVG_W:.0f}" height="{SVG_H:.0f}" fill="#ffffff"/>')
add(f'<text x="{MARGIN - 60}" y="42" font-size="26" font-weight="700" fill="#1d1d1f">'
    f'{meta["name"]} — plan vu du dessus</text>')
add(f'<text x="{MARGIN - 60}" y="66" font-size="14" fill="#6e6e73">Scan RoomPlan du '
    f'{meta["createdAt"][:10]} · cotes en mètres · précision ± quelques cm</text>')

# Floor.
add('<polygon points="' + " ".join(f"{P(*p)[0]:.1f},{P(*p)[1]:.1f}" for p in pts)
    + '" fill="#f5f5f7" stroke="none"/>')

# Furniture.
CAT = {"television": "TV", "chair": "Chaise", "table": "Table", "storage": "Rangement",
       "sofa": "Canapé", "bed": "Lit", "refrigerator": "Frigo", "sink": "Évier"}
furn = sorted(scan["furniture"], key=lambda f: (CAT.get(f["category"], f["category"]), -f["footprint"][0]))
if not WITH_FURNITURE:
    furn = []
badges = []
for i, f in enumerate(furn, 1):
    cx, cz = rot(f["center"][0], f["center"][2])
    yaw = f["yaw"] - ref_yaw
    fw, fd = f["footprint"]
    ux, uz = math.cos(yaw), -math.sin(yaw)
    vx, vz = -uz, ux
    corners = [(cx + sx * ux * fw / 2 + sz * vx * fd / 2, cz + sx * uz * fw / 2 + sz * vz * fd / 2)
               for sx, sz in [(-1, -1), (1, -1), (1, 1), (-1, 1)]]
    op = {"high": 0.55, "medium": 0.4, "low": 0.25}[f["confidence"]]
    add('<polygon points="' + " ".join(f"{P(*q)[0]:.1f},{P(*q)[1]:.1f}" for q in corners)
        + f'" fill="#4a90d9" fill-opacity="{op}" stroke="#2f6fb5" stroke-width="1"/>')
    px, py = P(cx, cz)
    while any(math.dist((px, py), q) < 24 for q in badges):
        py += 24
    badges.append((px, py))
    add(f'<circle cx="{px:.1f}" cy="{py:.1f}" r="10" fill="#ffffff" stroke="#2f6fb5"/>')
    add(f'<text x="{px:.1f}" y="{py + 4:.1f}" font-size="11" font-weight="600" text-anchor="middle" '
        f'fill="#2f6fb5">{i}</text>')
    f["n"] = i


def dim_line(a, b, offset, label, size=13, color="#1d1d1f", weight="600"):
    """Dimension line parallel to a-b, offset outward (metres)."""
    ux, uz = (b[0] - a[0]), (b[1] - a[1])
    L = math.hypot(ux, uz)
    ux, uz = ux / L, uz / L
    nx, nz = uz * orient, -ux * orient  # outward normal
    a2 = (a[0] + nx * offset, a[1] + nz * offset)
    b2 = (b[0] + nx * offset, b[1] + nz * offset)
    (x1, y1), (x2, y2) = P(*a2), P(*b2)
    add(f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" stroke="{color}" stroke-width="1"/>')
    for (x, y) in [(x1, y1), (x2, y2)]:
        tx, ty = (ux - uz * 0) * 0, 0
        add(f'<line x1="{x - (ux + nx) * 5:.1f}" y1="{y - (uz + nz) * 5:.1f}" '
            f'x2="{x + (ux + nx) * 5:.1f}" y2="{y + (uz + nz) * 5:.1f}" stroke="{color}" stroke-width="1.5"/>')
    # Extension lines back to the wall.
    for p, q in [(a, (x1, y1)), (b, (x2, y2))]:
        wx, wy = P(p[0] + nx * 0.08, p[1] + nz * 0.08)
        add(f'<line x1="{wx:.1f}" y1="{wy:.1f}" x2="{q[0]:.1f}" y2="{q[1]:.1f}" stroke="#c7c7cc" stroke-width="0.8"/>')
    gap = 6 + size * 0.6
    mx, my = (x1 + x2) / 2 + nx * gap, (y1 + y2) / 2 + nz * gap
    angle = math.degrees(math.atan2(uz, ux))
    if angle > 90 or angle <= -90:
        angle -= 180 if angle > 0 else -180
    add(f'<text x="{mx:.1f}" y="{my:.1f}" dy="0.35em" font-size="{size}" font-weight="{weight}" fill="{color}" '
        f'text-anchor="middle" transform="rotate({angle:.1f} {mx:.1f} {my:.1f})">{label}</text>')


placed_labels = []
poly_draw = sorted(poly, key=lambda g: abs(g["b"][1] - g["a"][1]) > abs(g["b"][0] - g["a"][0]))
COL = {"door": "#d9822b", "window": "#2bb3d9", "opening": "#8e8e93"}
for g in poly_draw:
    a, b, L = g["a"], g["b"], g["len"]
    ux, uz = (b[0] - a[0]) / L, (b[1] - a[1]) / L
    # Wall with gaps for openings.
    cuts = [0.0]
    for o in g["openings"]:
        cuts += [max(0, o["t"] - o["w"] / 2), min(L, o["t"] + o["w"] / 2)]
    cuts.append(L)
    for i in range(0, len(cuts), 2):
        p1 = P(a[0] + ux * cuts[i], a[1] + uz * cuts[i])
        p2 = P(a[0] + ux * cuts[i + 1], a[1] + uz * cuts[i + 1])
        add(f'<line x1="{p1[0]:.1f}" y1="{p1[1]:.1f}" x2="{p2[0]:.1f}" y2="{p2[1]:.1f}" '
            f'stroke="#1d1d1f" stroke-width="7" stroke-linecap="square"/>')
    for o in g["openings"]:
        t1, t2 = o["t"] - o["w"] / 2, o["t"] + o["w"] / 2
        p1 = P(a[0] + ux * t1, a[1] + uz * t1)
        p2 = P(a[0] + ux * t2, a[1] + uz * t2)
        dash = ' stroke-dasharray="4 3"' if o["kind"] == "opening" else ""
        add(f'<line x1="{p1[0]:.1f}" y1="{p1[1]:.1f}" x2="{p2[0]:.1f}" y2="{p2[1]:.1f}" '
            f'stroke="{COL[o["kind"]]}" stroke-width="5"{dash}/>')
        nx, nz = -uz * orient, ux * orient  # inward normal
        off = 0.28
        while True:
            lx, ly = P(a[0] + ux * o["t"] + nx * off, a[1] + uz * o["t"] + nz * off)
            if all(math.dist((lx, ly), q) > 40 for q in placed_labels) or off > 1.5:
                break
            off += 0.12
        placed_labels.append((lx, ly))
        add(f'<text x="{lx:.1f}" y="{ly + 4:.1f}" font-size="12" font-weight="700" text-anchor="middle" '
            f'fill="{COL[o["kind"]]}">{o["label"]}</text>')
    # Total length (outer line).
    dim_line(a, b, 0.6 if g["openings"] else 0.35, fmt(L), size=14)
    # Chain dimensions along the wall (inner line).
    if g["openings"]:
        for t1, t2 in zip(cuts, cuts[1:]):
            if t2 - t1 < 0.04:
                continue
            p1 = (a[0] + ux * t1, a[1] + uz * t1)
            p2 = (a[0] + ux * t2, a[1] + uz * t2)
            dim_line(p1, p2, 0.28, fmt(t2 - t1), size=11, color="#6e6e73", weight="500")

# Side panel.
x0 = W + 10
y = HEADER_H + 40
add(f'<rect x="{x0 - 20}" y="{HEADER_H + 10}" width="{PANEL_W - 10}" height="{SVG_H - HEADER_H - 30}" '
    f'rx="14" fill="#f5f5f7"/>')


def line(text, size=13, weight="400", color="#1d1d1f", dy=20, x=None):
    global y
    add(f'<text x="{x if x is not None else x0}" y="{y}" font-size="{size}" font-weight="{weight}" '
        f'fill="{color}">{text}</text>')
    y += dy


line("Pièce", 15, "700", dy=24)
line(f"Surface au sol : {fmt(area)} m²")
line(f"Périmètre : {fmt(perimeter)} m")
line(f"Hauteur sous plafond : {fmt(ceiling)} m", dy=30)
line("Ouvertures (largeur × hauteur)", 15, "700", dy=24)
for g in poly:
    for o in g["openings"]:
        extra = f" · allège {fmt(o['sill'])}" if o["kind"] == "window" else ""
        add(f'<rect x="{x0}" y="{y - 10}" width="10" height="10" rx="2" fill="{COL[o["kind"]]}"/>')
        line(f'{o["label"]}  {KIND[o["kind"]]} {fmt(o["w"])} × {fmt(o["h"])}{extra}', x=x0 + 16)
y += 10
if furn:
    line("Meubles détectés (L × P × H)", 15, "700", dy=24)
    CONF = {"high": "sûr", "medium": "moyen", "low": "incertain"}
    for f in furn:
        fw, fd = f["footprint"]
        line(f'{f["n"]}. {CAT.get(f["category"], f["category"])} {fmt(fw)} × {fmt(fd)} × {fmt(f["height"])}'
             f'  ({CONF[f["confidence"]]})', 12, dy=18)
    line("Plus le bleu est foncé, plus la détection est sûre.", 11, color="#6e6e73", dy=16)
y += 12
line("Cotes grises : distances angle → ouverture", 11, color="#6e6e73", dy=16)
line("le long de chaque mur. Cote noire : mur entier.", 11, color="#6e6e73", dy=16)

add("</svg>")
(scan_dir / ("plan-meubles.svg" if WITH_FURNITURE else "plan.svg")).write_text("\n".join(out))
print(f"area={area:.2f} perimeter={perimeter:.2f} size={SVG_W:.0f}x{SVG_H:.0f}")
