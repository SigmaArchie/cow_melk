"""
make_props.py - baut Melkschemel, Melkeimer und Milch-Eimer als 3D-Teile in Blender.

Aufruf (im Projektordner):
    blender -b -P tools/make_props.py

Ergebnis:
    assets_src/props/Eimer_Schemel.blend   zum Weiterbearbeiten
    assets_src/props/PropParts.fbx         für den Roblox-3D-Importer (Modell "PropParts")
    assets_src/previews/props.png          Vorschau
    src/shared/PropMeshData.lua            Größe + Mittelpunkt jedes Teils (das Spiel baut damit zusammen)

Die Eimer bestehen aus Einzelteilen, die das Spiel zusammensetzt (so kann es jede Daube
und jeden Reifen nach der Mutation einfärben):
    Daube          eine Holzdaube (10 Stück im Kreis = Eimer, nach oben breiter)
    Boden          Eimerboden
    Reifen         ein Reifen mit Nieten (wird auf die Höhe skaliert)
    Henkel         Bügel mit Ösen
    Sitz / Beine   Melkschemel
    Sahne, Erdbeere, Erdbeer_Blatt, Schoko   Extras auf der Milch
Maße in "Eimer-Einheiten": oben Radius 0.55, unten 0.47, Höhe 1.0 (wie BuildMilkBucket bei Größe 1).
"""

import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT_DIR = os.path.join(ROOT, "assets_src", "props")
PREVIEW = os.path.join(ROOT, "assets_src", "previews", "props.png")
LUA_OUT = os.path.join(ROOT, "src", "shared", "PropMeshData.lua")

# Eimer-Maße (Blender: Z = oben)
TOP_R = 0.55
BOTTOM_R = 0.47
HEIGHT = 1.0
WALL = 0.09
STAVES = 10
BAND_H = 0.09
BAND_T = 0.03

# Schemel
SEAT_R = 0.75
SEAT_T = 0.3
SEAT_Z = 1.15  # Mitte des Sitzes über dem Boden


# ----------------------------------------------------------------------------- Helfer
def reset():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.curves, bpy.data.materials):
        for d in list(coll):
            coll.remove(d)


def link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


def bake(obj):
    """Modifier anwenden (ohne Operator-Kontext)."""
    dg = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
    old = obj.data
    obj.modifiers.clear()
    obj.data = mesh
    if isinstance(old, bpy.types.Mesh) and old.users == 0:
        bpy.data.meshes.remove(old)
    return obj


def bevel(obj, width, segments=2, angle=40):
    m = obj.modifiers.new("Bevel", "BEVEL")
    m.width = width
    m.segments = segments
    m.limit_method = "ANGLE"
    m.angle_limit = math.radians(angle)
    return bake(obj)


def solidify(obj, thickness):
    m = obj.modifiers.new("Solidify", "SOLIDIFY")
    m.thickness = thickness
    m.offset = -1
    m.use_even_offset = True
    return bake(obj)


def boolean_cut(obj, cutter):
    m = obj.modifiers.new("Cut", "BOOLEAN")
    m.operation = "DIFFERENCE"
    m.object = cutter
    m.solver = "EXACT"
    bake(obj)
    bpy.data.objects.remove(cutter, do_unlink=True)
    return obj


def from_bmesh(name, bm):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    return link(bpy.data.objects.new(name, mesh))


def primitive(kind, name, **kw):
    getattr(bpy.ops.mesh, "primitive_" + kind + "_add")(**kw)
    obj = bpy.context.active_object
    obj.name = name
    return obj


def apply_transform(obj):
    bpy.context.view_layer.update()  # sonst ist matrix_world noch alt
    obj.data.transform(obj.matrix_world)
    obj.matrix_world = Matrix.Identity(4)


def join(objs, name):
    bm = bmesh.new()
    for o in objs:
        apply_transform(o)
        bm.from_mesh(o.data)
    for o in objs:
        bpy.data.objects.remove(o, do_unlink=True)
    return from_bmesh(name, bm)


def smooth(obj, angle=40):
    for p in obj.data.polygons:
        p.use_smooth = True
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    try:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angle))
    except Exception:  # ältere Blender-Versionen
        pass
    obj.select_set(False)


def r_at(z):
    """Außenradius der Dauben in Höhe z."""
    return BOTTOM_R + (TOP_R - BOTTOM_R) * z / HEIGHT


# ----------------------------------------------------------------------------- Teile
def make_stave():
    """Eine gebogene Daube, mittig auf +X, Wand nach innen."""
    half = math.pi / STAVES - math.radians(0.4)
    na, nz = 8, 4
    bm = bmesh.new()
    grid = []
    for j in range(nz + 1):
        z = HEIGHT * j / nz
        row = []
        for i in range(na + 1):
            a = -half + 2 * half * i / na
            r = r_at(z)
            row.append(bm.verts.new((r * math.cos(a), r * math.sin(a), z)))
        grid.append(row)
    for j in range(nz):
        for i in range(na):
            # Reihenfolge so, dass die Normale nach außen zeigt
            bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
    obj = from_bmesh("Daube", bm)
    solidify(obj, WALL)
    bevel(obj, 0.012, 2)
    smooth(obj)
    return obj


def make_bottom():
    obj = primitive("cylinder", "Boden", vertices=40, radius=BOTTOM_R - 0.02, depth=WALL, location=(0, 0, WALL / 2))
    bevel(obj, 0.012, 2)
    smooth(obj)
    return obj


def make_band():
    """Reifen in der Höhe der unteren Bandposition; das Spiel skaliert ihn auf jede Höhe."""
    z = HEIGHT * 0.22
    r = r_at(z) + BAND_T
    ring = primitive("cylinder", "Reifen", vertices=48, radius=r, depth=BAND_H, end_fill_type="NOTHING", location=(0, 0, z))
    solidify(ring, BAND_T)
    bevel(ring, 0.008, 2)
    rivets = []
    for k in range(8):
        a = k / 8 * math.tau + math.pi / 16
        rivets.append(
            primitive("uv_sphere", "Niete", segments=10, ring_count=6, radius=0.018, location=(r * math.cos(a), r * math.sin(a), z))
        )
    obj = join([ring] + rivets, "Reifen")
    smooth(obj)
    return obj


def make_handle():
    """Bügel über der Öffnung + zwei Ösen außen an der Wand."""
    ra = TOP_R + 0.04
    curve = bpy.data.curves.new("HenkelKurve", "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = 0.024
    curve.bevel_resolution = 3
    spline = curve.splines.new("POLY")
    pts = []
    # Haken unten in den Ösen, dann der Bogen
    pts.append((ra, 0, HEIGHT - 0.06))
    for k in range(25):
        t = math.pi * k / 24
        pts.append((ra * math.cos(t), 0, HEIGHT + 0.02 + ra * 0.85 * math.sin(t)))
    pts.append((-ra, 0, HEIGHT - 0.06))
    spline.points.add(len(pts) - 1)
    for p, co in zip(spline.points, pts):
        p.co = (*co, 1)
    cobj = link(bpy.data.objects.new("HenkelKurve", curve))
    dg = bpy.context.evaluated_depsgraph_get()
    wire = link(bpy.data.objects.new("Draht", bpy.data.meshes.new_from_object(cobj.evaluated_get(dg))))
    bpy.data.objects.remove(cobj, do_unlink=True)
    bpy.data.curves.remove(curve)
    # Holzgriff in der Mitte des Bügels
    grip = primitive("cylinder", "Griff", vertices=16, radius=0.045, depth=0.34, location=(0, 0, HEIGHT + 0.02 + ra * 0.85))
    grip.rotation_euler = (0, math.radians(90), 0)
    bevel(grip, 0.015, 2)
    ears = []
    for side in (-1, 1):
        ear = primitive("cube", "Oese", size=1, location=(side * (r_at(HEIGHT - 0.06) + 0.025), 0, HEIGHT - 0.06))
        ear.scale = (0.05, 0.14, 0.16)
        apply_transform(ear)
        bevel(ear, 0.015, 2)
        ears.append(ear)
    obj = join([wire, grip] + ears, "Henkel")
    smooth(obj)
    return obj


def make_seat():
    seat = primitive("cylinder", "Sitz", vertices=48, radius=SEAT_R, depth=SEAT_T, location=(0, 0, SEAT_Z))
    bevel(seat, 0.05, 3)
    # Griffloch zum Tragen
    slot = primitive("cube", "Loch", size=1, location=(0, SEAT_R * 0.55, SEAT_Z))
    slot.scale = (0.38, 0.1, 1)
    bevel(slot, 0.045, 3, angle=80)
    boolean_cut(seat, slot)
    # zwei Fugen = drei Bretter
    for x in (-0.25, 0.25):
        groove = primitive("cube", "Fuge", size=1, location=(x, 0, SEAT_Z + SEAT_T / 2))
        groove.scale = (0.025, 2, 0.04)
        boolean_cut(seat, groove)
    smooth(seat, 35)
    return seat


def make_legs():
    parts = []
    tops = []
    for i in range(3):
        a = math.radians(i * 120 + 30)
        splay = math.radians(10)
        top = Vector((math.cos(a) * 0.4, math.sin(a) * 0.4, SEAT_Z - SEAT_T / 2 + 0.05))
        direction = Vector((math.cos(a) * math.sin(splay), math.sin(a) * math.sin(splay), -math.cos(splay)))
        length = (top.z) / math.cos(splay)
        mid = top + direction * (length / 2)
        leg = primitive("cone", "Bein", vertices=14, radius1=0.085, radius2=0.065, depth=length, location=mid)
        # Kegel zeigt mit radius1 nach unten (-Z) -> Richtung des Beins
        leg.rotation_euler = Vector((0, 0, -1)).rotation_difference(direction).to_euler()
        bevel(leg, 0.01, 1)
        parts.append(leg)
        tops.append((top, direction, length))
    # Querstreben auf halber Höhe
    for i in range(3):
        p1 = tops[i][0] + tops[i][1] * tops[i][2] * 0.6
        p2 = tops[(i + 1) % 3][0] + tops[(i + 1) % 3][1] * tops[(i + 1) % 3][2] * 0.6
        d = p2 - p1
        rung = primitive("cylinder", "Strebe", vertices=10, radius=0.028, depth=d.length, location=(p1 + p2) / 2)
        rung.rotation_euler = Vector((0, 0, 1)).rotation_difference(d).to_euler()
        parts.append(rung)
    obj = join(parts, "Beine")
    smooth(obj, 50)
    return obj


def make_cream():
    parts = []
    for k, (r, h) in enumerate(((0.17, 0.11), (0.13, 0.1), (0.085, 0.09))):
        s = primitive("uv_sphere", "Kringel", segments=24, ring_count=12, radius=1, location=(0, 0, 0.05 + k * 0.075))
        s.scale = (r, r, h / 2 * 1.2)
        parts.append(s)
    tip = primitive("cone", "Spitze", vertices=16, radius1=0.05, radius2=0.0, depth=0.12, location=(0, 0, 0.28))
    parts.append(tip)
    obj = join(parts, "Sahne")
    smooth(obj, 80)
    return obj


def make_strawberry():
    berry = primitive("uv_sphere", "Erdbeere", segments=24, ring_count=14, radius=0.13)
    for v in berry.data.vertices:
        z = v.co.z / 0.13  # -1..1
        f = 1 - max(0, -z) * 0.55
        v.co.x *= f
        v.co.y *= f
        v.co.z *= 1.15
    smooth(berry, 80)
    leaves = []
    for k in range(5):
        a = k / 5 * math.tau
        leaf = primitive("uv_sphere", "Blatt", segments=10, ring_count=6, radius=1, location=(math.cos(a) * 0.06, math.sin(a) * 0.06, 0.145))
        leaf.scale = (0.07, 0.03, 0.012)
        leaf.rotation_euler = (0, math.radians(-15), a)
        leaves.append(leaf)
    leaves.append(primitive("cylinder", "Stiel", vertices=8, radius=0.012, depth=0.07, location=(0, 0, 0.18)))
    obj = join(leaves, "Erdbeer_Blatt")
    smooth(obj, 80)
    return berry, obj


def make_choco():
    parts = [primitive("cube", "Platte", size=1, location=(0, 0, 0.015))]
    parts[0].scale = (0.3, 0.22, 0.03)
    for ix in range(3):
        for iy in range(2):
            c = primitive("cube", "Stueck", size=1, location=(-0.1 + ix * 0.1, -0.055 + iy * 0.11, 0.045))
            c.scale = (0.088, 0.098, 0.035)
            apply_transform(c)
            bevel(c, 0.012, 2, angle=60)
            parts.append(c)
    obj = join(parts, "Schoko")
    return obj


# ----------------------------------------------------------------------------- Vorschau
def mat(name, rgb, rough=0.6, metal=0.0, emit=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*[(c / 255) ** 2.2 for c in rgb], 1)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    return m


def set_mat(obj, m):
    obj.data.materials.clear()
    obj.data.materials.append(m)


def instance(src, name, matrix, material=None):
    mesh = src.data.copy()
    if material:
        mesh.materials.clear()
        mesh.materials.append(material)
    obj = link(bpy.data.objects.new(name, mesh))
    obj.matrix_world = matrix
    obj["preview"] = True
    return obj


def build_bucket(parts, origin, scale, stave_mats, band_mats, milk_mat, extras, materials, milk_level=0.94):
    m0 = Matrix.Translation(origin) @ Matrix.Diagonal((*scale, 1))
    for i in range(STAVES):
        instance(parts["Daube"], "pDaube", m0 @ Matrix.Rotation(i / STAVES * math.tau, 4, "Z"), stave_mats[i % len(stave_mats)])
    instance(parts["Boden"], "pBoden", m0, stave_mats[0])
    zs = (0.22, 0.74) if len(band_mats) <= 2 else (0.18, 0.46, 0.74)
    for z, bm in zip(zs, band_mats):
        k = (r_at(z) + BAND_T) / (r_at(0.22) + BAND_T)
        instance(parts["Reifen"], "pReifen", m0 @ Matrix.Translation((0, 0, z)) @ Matrix.Diagonal((k, k, 1, 1)) @ Matrix.Translation((0, 0, -0.22)), bm)
    instance(parts["Henkel"], "pHenkel", m0, materials["metal"])
    milk = primitive("cylinder", "pMilch", vertices=40, radius=r_at(HEIGHT * milk_level) - WALL, depth=0.03, location=(0, 0, HEIGHT * milk_level))
    milk.matrix_world = m0 @ milk.matrix_world
    set_mat(milk, milk_mat)
    milk["preview"] = True
    for name, offset, material in extras:
        instance(parts[name], "p" + name, m0 @ Matrix.Translation(offset), material)


def render_preview(parts):
    scn = bpy.context.scene
    M = {
        "wood": mat("Holz", (150, 100, 60), 0.75),
        "dark": mat("DunklesHolz", (105, 68, 40), 0.8),
        "metal": mat("Metall", (165, 170, 178), 0.35, 1.0),
        "milk": mat("Milch", (252, 252, 248), 0.3),
        "choco_milk": mat("Schokomilch", (140, 90, 60), 0.3),
        "gold": mat("Gold", (240, 190, 60), 0.25, 1.0),
        "pink": mat("Erdbeere", (220, 50, 70), 0.4),
        "green": mat("Gruen", (80, 170, 80), 0.6),
        "cream": mat("Sahne", (255, 250, 238), 0.5),
        "choco": mat("Schoko", (92, 56, 36), 0.4),
        "grass": mat("Wiese", (110, 160, 90), 0.9),
    }
    rainbow = [mat("R%d" % i, c, 0.5) for i, c in enumerate(((246, 128, 128), (246, 178, 104), (240, 224, 124), (132, 208, 144), (124, 182, 244), (186, 144, 240)))]

    # Schemel + Melkeimer (wie neben der Kuh), Melkeimer: Radius 0.5, Höhe 0.8
    off = Vector((-2.2, 0.4, 0))
    instance(parts["Sitz"], "pSitz", Matrix.Translation(off), M["wood"])
    instance(parts["Beine"], "pBeine", Matrix.Translation(off), M["dark"])
    k = 0.5 / TOP_R
    build_bucket(parts, Vector((-0.6, -0.6, 0)), (k, k, 0.8), [M["wood"]], [M["metal"], M["metal"]], M["milk"], [], M, 0.6)
    # Milch-Eimer: Schoko + Erdbeere + Sahne
    build_bucket(parts, Vector((1.0, 0.2, 0)), (1, 1, 1), [M["dark"]], [M["choco"], M["pink"], M["cream"]], M["choco_milk"],
                 [("Sahne", (0.15, 0.12, HEIGHT - 0.06), M["cream"]), ("Erdbeere", (-0.18, -0.1, HEIGHT + 0.03), M["pink"]),
                  ("Erdbeer_Blatt", (-0.18, -0.1, HEIGHT + 0.03), M["green"]), ("Schoko", (0.05, -0.25, HEIGHT - 0.04), M["choco"])], M)
    # Regenbogen-Eimer mit Goldreifen
    build_bucket(parts, Vector((2.7, 0.9, 0)), (1, 1, 1), rainbow, [M["gold"], M["gold"]], M["milk"], [], M)

    bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0, 0))
    ground = bpy.context.active_object
    ground["preview"] = True
    set_mat(ground, M["grass"])

    cam = link(bpy.data.objects.new("Kamera", bpy.data.cameras.new("Kamera")))
    cam["preview"] = True
    cam.location = (0.3, -7.2, 3.3)
    cam.rotation_euler = (math.radians(68), 0, 0)
    cam.data.lens = 42
    scn.camera = cam
    sun = link(bpy.data.objects.new("Sonne", bpy.data.lights.new("Sonne", "SUN")))
    sun["preview"] = True
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(45), math.radians(10), math.radians(35))
    world = bpy.data.worlds.new("Himmel") if not scn.world else scn.world
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
    scn.render.filepath = PREVIEW
    os.makedirs(os.path.dirname(PREVIEW), exist_ok=True)
    bpy.ops.render.render(write_still=True)

    for o in [o for o in bpy.data.objects if o.get("preview")]:
        bpy.data.objects.remove(o, do_unlink=True)


# ----------------------------------------------------------------------------- Export
def rbx(v):
    """Blender (Z oben) -> Roblox (Y oben): -x, z, y
    So legt der Roblox-3D-Importer die Meshes an (in Studio geprüft): wie (x, z, -y),
    aber um 180 Grad um die Hochachse gedreht. Blender +X wird Roblox -X, Blender +Y wird Roblox +Z."""
    return (-v.x, v.z, v.y)


def bounds(obj):
    pts = [obj.matrix_world @ v.co for v in obj.data.vertices]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return (lo + hi) / 2, hi - lo


def fmt(t):
    return "Vector3.new(%s)" % ", ".join("%.4f" % (0 if abs(c) < 5e-5 else c) for c in t)


def write_lua(info):
    lines = [
        "-- AUTOMATISCH ERZEUGT von tools/make_props.py – nicht von Hand ändern.",
        "-- Größe (Size) und Mittelpunkt (Center) jedes Teils aus assets/PropParts.rbxm,",
        "-- in Eimer-Einheiten (oben Radius TopRadius, Höhe Height; Schemel: Boden = 0).",
        "-- Der Mittelpunkt ist relativ zur Eimer-Achse unten bzw. zur Schemel-Mitte am Boden.",
        "return {",
        "\tTopRadius = %.4f," % TOP_R,
        "\tBottomRadius = %.4f," % BOTTOM_R,
        "\tHeight = %.4f," % HEIGHT,
        "\tWall = %.4f," % WALL,
        "\tStaves = %d," % STAVES,
        "\tBandRefY = %.4f, -- Höhe, für die der Reifen gebaut ist" % (HEIGHT * 0.22),
        "\tBandThickness = %.4f," % BAND_T,
        "\tParts = {",
    ]
    for name in sorted(info):
        c, s = info[name]
        lines.append("\t\t%s = { Size = %s, Center = %s }," % (name, fmt((s.x, s.z, s.y)), fmt(rbx(c))))
    lines += ["\t},", "}", ""]
    with open(LUA_OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))


def main():
    reset()
    parts = {}
    for o in (make_stave(), make_bottom(), make_band(), make_handle(), make_seat(), make_legs(), make_cream(), make_choco()):
        parts[o.name] = o
    berry, leaf = make_strawberry()
    # Erdbeere sitzt mit ihrer Unterseite auf z = 0
    for o in (berry, leaf):
        o.location.z += 0.13 * 1.15
        apply_transform(o)
    parts["Erdbeere"], parts["Erdbeer_Blatt"] = berry, leaf

    for name, o in parts.items():
        if o.name != name:
            o.name = name
        o.data.name = name
        apply_transform(o)  # Position/Drehung ins Mesh, damit Kopien an der richtigen Stelle sind

    for o in parts.values():
        o.hide_render = True
    render_preview(parts)
    for o in parts.values():
        o.hide_render = False

    info = {}
    for name, o in parts.items():
        info[name] = bounds(o)

    # Ursprung jedes Teils in seine Mitte, Teile nebeneinander legen
    os.makedirs(OUT_DIR, exist_ok=True)
    for i, (name, o) in enumerate(sorted(parts.items())):
        center, _ = info[name]
        o.data.transform(Matrix.Translation(-center))
        o.location = (i * 2.0, 0, 0)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "Eimer_Schemel.blend"))

    bpy.ops.object.select_all(action="DESELECT")
    for o in parts.values():
        o.select_set(True)
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(OUT_DIR, "PropParts.fbx"),
        use_selection=True,
        object_types={"MESH"},
        mesh_smooth_type="FACE",
        apply_scale_options="FBX_SCALE_ALL",
        bake_space_transform=True,  # Achsen-Drehung ins Mesh, Teile haben in Roblox keine Drehung
        axis_forward="-Z",
        axis_up="Y",
    )
    write_lua(info)
    for name in sorted(info):
        c, s = info[name]
        print("%-14s size %s  center %s  tris %d" % (name, tuple(round(x, 3) for x in s), tuple(round(x, 3) for x in c),
                                                    sum(len(p.vertices) - 2 for p in parts[name].data.polygons)))


if __name__ == "__main__":  # beim Import aus make_tools.py nicht ausführen
    main()
