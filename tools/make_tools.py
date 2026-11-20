"""
make_tools.py - baut die Werkzeuge für den Werkzeug-Shop und den Werkzeug-Schuppen in Blender.

Aufruf (im Projektordner):
    blender -b -P tools/make_tools.py

Ergebnis:
    assets_src/tools/Werkzeuge.blend     zum Weiterbearbeiten
    assets_src/tools/ToolParts.fbx       für den Roblox-3D-Importer -> als assets/ToolParts.rbxm speichern
    assets_src/previews/werkzeuge.png    Vorschau der drei Werkzeuge
    assets_src/previews/schuppen.png     Vorschau des Schuppens
    src/shared/ToolMeshData.lua          Größe + Mittelpunkt jedes Teils, welche Teile zu welchem Werkzeug gehören

Jedes Werkzeug besteht aus Teilen, die das Spiel einzeln einfärbt (ToolModelBuilder.lua):
    Futtereimer   Futtereimer (Metall), Futter (Körner)
    Kuhglocke     Glocke_Pfosten (Holz), Glocke_Band (Leder), Glocke (Messing)
    Buerste       Buersten_Pfosten (Holz), Buersten_Halter (Metall), Buerste_Rolle (Borsten, dreht sich)
    Schuppen      Schuppen_Wand, Schuppen_Dach, Schuppen_Rahmen, Schuppen_Tuer, Schuppen_Glas, Schuppen_Schild
Ursprung jedes Werkzeugs: Boden-Mitte. Die Schuppen-Tür liegt in den Daten bei Roblox +Z,
ToolModelBuilder dreht ihn um, damit sie wie bei den Shops nach vorne (-Z) zeigt.
Maße in Studs (1 Blender-Einheit = 1 Stud).
"""

import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_props as mp  # noqa: E402  (Helfer: bevel, join, smooth, mat ...)

ROOT = mp.ROOT
OUT_DIR = os.path.join(ROOT, "assets_src", "tools")
PREVIEW_TOOLS = os.path.join(ROOT, "assets_src", "previews", "werkzeuge.png")
PREVIEW_SHED = os.path.join(ROOT, "assets_src", "previews", "schuppen.png")
LUA_OUT = os.path.join(ROOT, "src", "shared", "ToolMeshData.lua")

TOOLS = {
    "Futtereimer": ["Futtereimer", "Futter"],
    "Kuhglocke": ["Glocke_Pfosten", "Glocke_Band", "Glocke"],
    "Buerste": ["Buersten_Pfosten", "Buersten_Halter", "Buerste_Rolle"],
    "Schuppen": ["Schuppen_Wand", "Schuppen_Dach", "Schuppen_Rahmen", "Schuppen_Tuer", "Schuppen_Glas", "Schuppen_Schild"],
}


# ----------------------------------------------------------------------------- Helfer
def box(name, size, loc, bev=0.0, rot=None):
    o = mp.primitive("cube", name, size=1, location=loc)
    o.scale = size
    if rot:
        o.rotation_euler = rot
    mp.apply_transform(o)
    if bev:
        mp.bevel(o, bev, 2, angle=60)
    return o


def cyl(name, r, depth, loc, verts=24, rot=None, r2=None):
    if r2 is None:
        o = mp.primitive("cylinder", name, vertices=verts, radius=r, depth=depth, location=loc)
    else:
        o = mp.primitive("cone", name, vertices=verts, radius1=r, radius2=r2, depth=depth, location=loc)
    if rot:
        o.rotation_euler = rot
    mp.apply_transform(o)
    return o


def finish(bm):
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)


def lathe(name, profile, segments=32):
    """Dreht ein geschlossenes Profil [(r, z), ...] um die Z-Achse."""
    bm = bmesh.new()
    rings = []
    for k in range(segments):
        a = k / segments * math.tau
        rings.append([bm.verts.new((r * math.cos(a), r * math.sin(a), z)) for r, z in profile])
    for k in range(segments):
        ring_a, ring_b = rings[k], rings[(k + 1) % segments]
        for i in range(len(profile) - 1):
            quad = [ring_a[i], ring_a[i + 1], ring_b[i + 1], ring_b[i]]
            if len(set(quad)) >= 3:
                try:
                    bm.faces.new(quad)
                except ValueError:
                    pass
    finish(bm)
    return mp.from_bmesh(name, bm)


def wire(name, points, radius):
    curve = bpy.data.curves.new(name + "Kurve", "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = 3
    spline = curve.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for p, co in zip(spline.points, points):
        p.co = (*co, 1)
    cobj = mp.link(bpy.data.objects.new(name + "Kurve", curve))
    dg = bpy.context.evaluated_depsgraph_get()
    obj = mp.link(bpy.data.objects.new(name, bpy.data.meshes.new_from_object(cobj.evaluated_get(dg))))
    bpy.data.objects.remove(cobj, do_unlink=True)
    bpy.data.curves.remove(curve)
    return obj


def prism(name, front_pts, y0, y1):
    """Dreieck/Vieleck in der XZ-Ebene, von y0 bis y1 ausgezogen."""
    bm = bmesh.new()
    a = [bm.verts.new((x, y0, z)) for x, z in front_pts]
    b = [bm.verts.new((x, y1, z)) for x, z in front_pts]
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    n = len(front_pts)
    for i in range(n):
        bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]))
    finish(bm)
    return mp.from_bmesh(name, bm)


# ----------------------------------------------------------------------------- Futtereimer
def make_feed_bucket():
    h = 1.0
    profile = [(0, 0), (0.5, 0), (0.53, 0.04), (0.64, h), (0.68, h + 0.02), (0.68, h + 0.06), (0.6, h + 0.05),
               (0.47, 0.1), (0, 0.1)]
    pail = lathe("Futtereimer", profile, 36)
    ribs = []
    for z in (0.3, 0.68):
        r = 0.5 + (0.64 - 0.5) * z / h + 0.012
        bpy.ops.mesh.primitive_torus_add(major_radius=r, minor_radius=0.025, major_segments=36, minor_segments=8,
                                         location=(0, 0, z))
        ribs.append(bpy.context.active_object)
    pts = [(0.7, 0, h - 0.04)]
    for k in range(21):
        t = math.pi * k / 20
        pts.append((0.7 * math.cos(t), 0, h + 0.05 + 0.55 * math.sin(t)))
    pts.append((-0.7, 0, h - 0.04))
    handle = wire("Buegel", pts, 0.025)
    ears = [box("Oese", (0.06, 0.16, 0.18), (s * 0.66, 0, h - 0.06), 0.02) for s in (-1, 1)]
    pail = mp.join([pail, handle] + ribs + ears, "Futtereimer")
    mp.smooth(pail, 50)

    rng = random.Random(7)
    heap = mp.primitive("uv_sphere", "Haufen", segments=32, ring_count=16, radius=1, location=(0, 0, h - 0.02))
    heap.scale = (0.6, 0.6, 0.28)
    mp.apply_transform(heap)
    pellets = []
    for _ in range(40):
        a = rng.random() * math.tau
        d = math.sqrt(rng.random()) * 0.52
        z = h - 0.02 + 0.28 * math.sqrt(max(0.0, 1 - (d / 0.6) ** 2))
        p = cyl("Korn", 0.045, 0.1, (d * math.cos(a), d * math.sin(a), z), 8,
                rot=(rng.random() * 3, rng.random() * 3, 0))
        pellets.append(p)
    feed = mp.join([heap] + pellets, "Futter")
    mp.smooth(feed, 60)
    return [pail, feed]


# ----------------------------------------------------------------------------- Kuhglocke
def make_cowbell():
    post = [
        box("Pfosten", (0.32, 0.32, 4.0), (0, 0, 2.0), 0.04),
        box("Arm", (1.7, 0.24, 0.24), (0.7, 0, 3.8), 0.03),
        box("Fuss", (0.9, 0.9, 0.16), (0, 0, 0.08), 0.04),
        box("Kappe", (0.42, 0.42, 0.12), (0, 0, 4.06), 0.03),
    ]
    # schräge Stütze vom Pfosten zum Arm
    brace_len = math.hypot(0.7, 0.7)
    post.append(box("Stuetze", (brace_len, 0.16, 0.16), (0.35, 0, 3.35), 0.02, rot=(0, math.radians(-45), 0)))
    post_obj = mp.join(post, "Glocke_Pfosten")
    mp.smooth(post_obj, 40)

    bx, top = 1.3, 3.45
    bpy.ops.mesh.primitive_torus_add(major_radius=0.2, minor_radius=0.035, major_segments=24, minor_segments=8,
                                     location=(bx, 0, 3.8), rotation=(0, math.radians(90), 0))
    ring = bpy.context.active_object
    strap = box("Riemen", (0.12, 0.07, 0.2), (bx, 0, 3.53), 0.02)
    band = mp.join([ring, strap], "Glocke_Band")
    mp.smooth(band, 50)

    profile = [(0, top), (0.16, top), (0.24, top - 0.07), (0.28, top - 0.35), (0.34, top - 0.68), (0.43, top - 0.88),
               (0.43, top - 0.92), (0.38, top - 0.92), (0.3, top - 0.72), (0.23, top - 0.36), (0.18, top - 0.12),
               (0, top - 0.12)]
    bell = lathe("Glocke", profile, 32)
    bell.location.x = bx
    mp.apply_transform(bell)
    clapper = mp.primitive("uv_sphere", "Kloeppel", segments=12, ring_count=8, radius=0.09, location=(bx, 0, top - 0.8))
    stem = cyl("Stiel", 0.025, 0.65, (bx, 0, top - 0.45), 8)
    bell = mp.join([bell, clapper, stem], "Glocke")
    mp.smooth(bell, 50)
    return [post_obj, band, bell]


# ----------------------------------------------------------------------------- Bürste
def fuzzy_roll(name, radius, height, z0, x):
    """Borstenrolle: Zylinder mit gezackter Oberfläche (sieht flauschig aus)."""
    seg, rows = 48, 12
    bm = bmesh.new()
    rings = []
    for j in range(rows + 1):
        z = z0 + height * j / rows
        ring = []
        for i in range(seg):
            a = i / seg * math.tau
            r = radius + (0.05 if (i + j) % 2 == 0 else -0.03)
            if j in (0, rows):
                r = radius - 0.06
            ring.append(bm.verts.new((x + r * math.cos(a), r * math.sin(a), z)))
        rings.append(ring)
    for j in range(rows):
        for i in range(seg):
            bm.faces.new((rings[j][i], rings[j][(i + 1) % seg], rings[j + 1][(i + 1) % seg], rings[j + 1][i]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    finish(bm)
    return mp.from_bmesh(name, bm)


def make_brush():
    x = 1.05
    post = mp.join([
        box("Pfosten", (0.4, 0.4, 4.4), (0, 0, 2.2), 0.05),
        box("FussA", (1.5, 0.32, 0.26), (0, 0, 0.13), 0.04),
        box("FussB", (0.32, 1.5, 0.26), (0, 0, 0.13), 0.04),
        box("Arm", (1.45, 0.32, 0.32), (0.6, 0, 4.05), 0.04),
        box("Kappe", (0.52, 0.52, 0.14), (0, 0, 4.47), 0.03),
    ], "Buersten_Pfosten")
    mp.smooth(post, 40)
    holder = mp.join([
        cyl("Achse", 0.06, 0.45, (x, 0, 3.85), 12),
        box("Platte", (0.42, 0.38, 0.06), (x, 0, 3.86), 0.015),
        cyl("Kern", 0.14, 1.85, (x, 0, 2.85), 16),
        box("Schelle", (0.08, 0.5, 0.5), (0.24, 0, 4.05), 0.015),
    ], "Buersten_Halter")
    mp.smooth(holder, 40)
    roll = fuzzy_roll("Buerste_Rolle", 0.5, 1.6, 2.05, x)
    mp.smooth(roll, 70)
    return [post, holder, roll]


# ----------------------------------------------------------------------------- Werkzeug-Schuppen
W, D, H, RIDGE = 16.0, 12.0, 8.0, 12.0  # Breite (X), Tiefe (Y), Wandhöhe, Firsthöhe
FRONT = D / 2  # Blender +Y = vorne (in Roblox -Z)


def make_shed():
    # Wände aus waagrechten Brettern (mit Lücken für Tür und Fenster) + Giebel
    openings_front = [(-1.8, 1.8, 0.0, 5.6), (-6.1, -3.9, 3.6, 5.6), (3.9, 6.1, 3.6, 5.6)]  # (von, bis, unten, oben)
    openings_side = [(-1.1, 1.1, 3.6, 5.6)]
    planks = []
    row_h = 0.8

    def plank_row(z0, z1, start, end, openings, place):
        cuts = sorted((a0, a1) for a0, a1, b0, b1 in openings if b0 < z1 - 0.01 and b1 > z0 + 0.01)
        x = start
        for a0, a1 in cuts + [(end, end)]:
            if a0 - x > 0.05:
                planks.append(place(x, a0, z0, z1))
            x = max(x, a1)

    def front_back(y):
        return lambda x0, x1, z0, z1: box("Brett", (x1 - x0, 0.5, z1 - z0 - 0.04), ((x0 + x1) / 2, y, (z0 + z1) / 2), 0.04)

    def side(x):
        return lambda y0, y1, z0, z1: box("Brett", (0.5, y1 - y0, z1 - z0 - 0.04), (x, (y0 + y1) / 2, (z0 + z1) / 2), 0.04)

    z = 0.0
    while z < H - 0.01:
        z1 = min(H, z + row_h)
        plank_row(z, z1, -W / 2, W / 2, openings_front, front_back(FRONT - 0.25))
        plank_row(z, z1, -W / 2, W / 2, [], front_back(-FRONT + 0.25))
        plank_row(z, z1, -D / 2, D / 2, openings_side, side(-W / 2 + 0.25))
        plank_row(z, z1, -D / 2, D / 2, openings_side, side(W / 2 - 0.25))
        z = z1
    gables = [
        prism("GiebelV", [(-W / 2, H), (W / 2, H), (0, RIDGE)], FRONT - 0.5, FRONT),
        prism("GiebelH", [(-W / 2, H), (W / 2, H), (0, RIDGE)], -FRONT, -FRONT + 0.5),
    ]
    wall = mp.join(planks + gables, "Schuppen_Wand")

    # Dach: zwei Platten + Schindel-Reihen + First
    over = 0.9
    dx, dz = W / 2 + over, (RIDGE + 0.3) - (H - 0.45)
    length = math.hypot(dx, dz)
    angle = math.atan2(dz, dx)
    roof = []
    for side in (-1, 1):
        mid = Vector((side * dx / 2, 0, (H - 0.45) + dz / 2))
        roof.append(box("Platte", (length, D + 1.6, 0.35), mid, 0.05, rot=(0, side * angle, 0)))
        for k in range(1, 9):
            t = k / 9
            p = Vector((side * dx * (1 - t), 0, (H - 0.45) + dz * t)) + Vector((0, 0, 0.22))
            roof.append(box("Schindel", (length / 9 + 0.05, D + 1.6, 0.12), p, 0.03, rot=(0, side * angle, 0)))
    roof.append(cyl("First", 0.32, D + 1.8, (0, 0, RIDGE + 0.42), 16, rot=(math.radians(90), 0, 0)))
    roof_obj = mp.join(roof, "Schuppen_Dach")
    mp.smooth(roof_obj, 30)

    # Rahmen (weiß): Eckpfosten, Türrahmen, Fensterrahmen + Sprossen, Giebelbretter
    trim = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            trim.append(box("Ecke", (0.7, 0.7, H), (sx * (W / 2 - 0.25), sy * (D / 2 - 0.25), H / 2), 0.05))
        trim.append(box("Tuerpfosten", (0.35, 0.6, 5.8), (sx * 1.95, FRONT + 0.05, 2.9), 0.04))
    trim.append(box("Sturz", (4.6, 0.68, 0.4), (0, FRONT + 0.05, 5.75), 0.04))

    def window(cx, cy, along_x):
        w, hh, z = 2.2, 2.0, 4.6
        size = (lambda a, b, c: (a, b, c)) if along_x else (lambda a, b, c: (b, a, c))
        pos = (lambda a, b, c: (cx + a, cy + b, c)) if along_x else (lambda a, b, c: (cx + b, cy + a, c))
        out = 0.08 if (along_x and cy > 0) or (not along_x and cx > 0) else -0.08
        trim.append(box("Rahmen", size(w + 0.5, 0.5, 0.3), pos(0, out, z + hh / 2 + 0.1), 0.04))
        trim.append(box("Rahmen", size(w + 0.7, 0.6, 0.3), pos(0, out * 2, z - hh / 2 - 0.1), 0.04))
        for s in (-1, 1):
            trim.append(box("Rahmen", size(0.25, 0.42, hh + 0.4), pos(s * (w / 2 + 0.1), out, z), 0.03))
        trim.append(box("Sprosse", size(w, 0.2, 0.1), pos(0, 0, z)))
        trim.append(box("Sprosse", size(0.1, 0.2, hh), pos(0, 0, z)))

    window(-5.0, FRONT - 0.25, True)
    window(5.0, FRONT - 0.25, True)
    window(-W / 2 + 0.25, 0, False)
    window(W / 2 - 0.25, 0, False)
    g_len = math.hypot(W / 2 + 0.3, RIDGE - H)
    g_ang = math.atan2(RIDGE - H, W / 2 + 0.3)
    for sy in (-1, 1):
        for side in (-1, 1):
            mid = (side * (W / 2 + 0.3) / 2, sy * (FRONT + 0.15), H + (RIDGE - H) / 2 - 0.2)
            trim.append(box("Giebelbrett", (g_len, 0.3, 0.45), mid, 0.04, rot=(0, side * g_ang, 0)))
    trim_obj = mp.join(trim, "Schuppen_Rahmen")

    # Tür: zwei Flügel mit Z-Strebe
    door = []
    for s in (-1, 1):
        cx = s * 0.9
        door.append(box("Fluegel", (1.75, 0.25, 5.5), (cx, FRONT - 0.15, 2.75), 0.03))
        for z in (0.6, 4.9):
            door.append(box("Riegel", (1.55, 0.14, 0.32), (cx, FRONT + 0.02, z), 0.03))
        diag = math.hypot(1.4, 4.0)
        door.append(box("Strebe", (diag, 0.14, 0.3), (cx, FRONT + 0.02, 2.75), 0.03,
                        rot=(0, s * math.atan2(4.0, 1.4), 0)))
        door.append(cyl("Griff", 0.07, 0.6, (cx - s * 0.6, FRONT + 0.12, 2.8), 10))
    door_obj = mp.join(door, "Schuppen_Tuer")

    glass = mp.join([
        box("Glas", (2.2, 0.06, 2.0), (-5.0, FRONT - 0.25, 4.6)),
        box("Glas", (2.2, 0.06, 2.0), (5.0, FRONT - 0.25, 4.6)),
        box("Glas", (0.06, 2.2, 2.0), (-W / 2 + 0.25, 0, 4.6)),
        box("Glas", (0.06, 2.2, 2.0), (W / 2 - 0.25, 0, 4.6)),
    ], "Schuppen_Glas")

    sign = box("Schuppen_Schild", (6.0, 0.3, 1.4), (0, FRONT + 0.2, 9.3), 0.08)
    return [wall, roof_obj, trim_obj, door_obj, glass, sign]


# ----------------------------------------------------------------------------- Vorschau
def camera_look(cam, target):
    direction = Vector(target) - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def render(parts, layout, materials, cam_pos, target, lens, path):
    scn = bpy.context.scene
    made = []
    for name, offset in layout:
        made.append(mp.instance(parts[name], "p" + name, Matrix.Translation(offset), materials[name]))
    bpy.ops.mesh.primitive_plane_add(size=80, location=(0, 0, 0))
    ground = bpy.context.active_object
    ground["preview"] = True
    mp.set_mat(ground, materials["_grass"])
    cam = mp.link(bpy.data.objects.new("Kamera", bpy.data.cameras.new("Kamera")))
    cam["preview"] = True
    cam.location = cam_pos
    cam.data.lens = lens
    camera_look(cam, target)
    scn.camera = cam
    sun = mp.link(bpy.data.objects.new("Sonne", bpy.data.lights.new("Sonne", "SUN")))
    sun["preview"] = True
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(45), math.radians(10), math.radians(-35))
    world = scn.world or bpy.data.worlds.new("Himmel")
    scn.world = world
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = (0.55, 0.7, 0.9, 1)
    bg.inputs["Strength"].default_value = 0.8
    scn.render.engine = "CYCLES"
    scn.cycles.samples = 48
    scn.cycles.use_denoising = True
    scn.render.resolution_x = 1280
    scn.render.resolution_y = 720
    scn.render.filepath = path
    bpy.ops.render.render(write_still=True)
    for o in [o for o in bpy.data.objects if o.get("preview")]:
        bpy.data.objects.remove(o, do_unlink=True)


def write_lua(info):
    lines = [
        "-- AUTOMATISCH ERZEUGT von tools/make_tools.py – nicht von Hand ändern.",
        "-- Größe (Size) und Mittelpunkt (Center, relativ zur Boden-Mitte des Werkzeugs) jedes Teils",
        "-- aus assets/ToolParts.rbxm. Tools = welche Teile zu welchem Werkzeug gehören.",
        "return {",
        "\tParts = {",
    ]
    for name in sorted(info):
        c, s = info[name]
        lines.append("\t\t%s = { Size = %s, Center = %s }," % (name, mp.fmt((s.x, s.z, s.y)), mp.fmt(mp.rbx(c))))
    lines.append("\t},")
    lines.append("\tTools = {")
    for tool, names in TOOLS.items():
        lines.append("\t\t%s = { %s }," % (tool, ", ".join('"%s"' % n for n in names)))
    lines += ["\t},", "}", ""]
    with open(LUA_OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))


def main():
    mp.reset()
    parts = {}
    for o in make_feed_bucket() + make_cowbell() + make_brush() + make_shed():
        o.data.name = o.name
        mp.apply_transform(o)
        parts[o.name] = o
    missing = [n for names in TOOLS.values() for n in names if n not in parts]
    assert not missing, missing

    M = mp.mat
    materials = {
        "Futtereimer": M("Blech", (170, 176, 184), 0.35, 1.0),
        "Futter": M("Koerner", (214, 170, 92), 0.8),
        "Glocke_Pfosten": M("Holz", (130, 86, 52), 0.8),
        "Glocke_Band": M("Leder", (170, 50, 40), 0.6),
        "Glocke": M("Messing", (222, 176, 64), 0.3, 1.0),
        "Buersten_Pfosten": M("Holz2", (130, 86, 52), 0.8),
        "Buersten_Halter": M("Metall", (90, 96, 106), 0.4, 1.0),
        "Buerste_Rolle": M("Borsten", (54, 120, 200), 0.9),
        "Schuppen_Wand": M("Bretter", (150, 100, 60), 0.85),
        "Schuppen_Dach": M("Dach", (170, 60, 48), 0.7),
        "Schuppen_Rahmen": M("Weiss", (244, 238, 222), 0.6),
        "Schuppen_Tuer": M("TuerGruen", (64, 116, 72), 0.7),
        "Schuppen_Glas": M("Glas", (170, 214, 240), 0.1),
        "Schuppen_Schild": M("Schild", (196, 140, 80), 0.7),
        "_grass": M("Wiese", (110, 160, 90), 0.9),
    }
    for o in parts.values():
        o.hide_render = True
    os.makedirs(os.path.dirname(PREVIEW_TOOLS), exist_ok=True)
    tool_layout = [(n, (-3.2, 0, 0)) for n in TOOLS["Futtereimer"]]
    tool_layout += [(n, (-1.0, 0.6, 0)) for n in TOOLS["Kuhglocke"]]
    tool_layout += [(n, (2.0, 0, 0)) for n in TOOLS["Buerste"]]
    render(parts, tool_layout, materials, (0.2, -10.5, 4.2), (0.0, 0.2, 1.9), 45, PREVIEW_TOOLS)
    render(parts, [(n, (0, 0, 0)) for n in TOOLS["Schuppen"]], materials, (14, 30, 9), (0, 0, 5.5), 40, PREVIEW_SHED)
    for o in parts.values():
        o.hide_render = False

    info = {name: mp.bounds(o) for name, o in parts.items()}
    os.makedirs(OUT_DIR, exist_ok=True)
    for i, (name, o) in enumerate(sorted(parts.items())):
        center, _ = info[name]
        o.data.transform(Matrix.Translation(-center))
        o.location = (i * 20.0, 0, 0)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "Werkzeuge.blend"))
    bpy.ops.object.select_all(action="DESELECT")
    for o in parts.values():
        o.select_set(True)
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(OUT_DIR, "ToolParts.fbx"),
        use_selection=True,
        object_types={"MESH"},
        mesh_smooth_type="FACE",
        apply_scale_options="FBX_SCALE_ALL",
        bake_space_transform=True,
        axis_forward="-Z",
        axis_up="Y",
    )
    write_lua(info)
    for name in sorted(info):
        c, s = info[name]
        tris = sum(len(p.vertices) - 2 for p in parts[name].data.polygons)
        print("%-18s size %s  center %s  tris %d" % (name, tuple(round(x, 2) for x in s), tuple(round(x, 2) for x in c), tris))


if __name__ == "__main__":
    main()
