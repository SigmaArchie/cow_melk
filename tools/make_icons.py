"""
make_icons.py - rendert die UI-Icons (realistischer Stil) in assets_src/icons/*.png

Läuft IN Blender (z. B. über den Blender-MCP: exec(open(pfad).read()); build(["coin", ...]))
oder headless:  blender -b -P tools/make_icons.py
Cycles, 512x512, transparenter Hintergrund, weicher Schatten (Shadow Catcher).
"""
import math
import os

import bmesh
import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

ROOT = r"C:\LokalSchule\5teKlasse\GD\cow_melk"
OUT = os.path.join(ROOT, "assets_src", "icons")
SIZE = 512
R90 = math.radians(90)


# ----------------------------------------------------------------------------- Helfer
def srgb(r, g, b):
    f = lambda c: (c / 255 / 12.92) if c / 255 <= 0.04045 else ((c / 255 + 0.055) / 1.055) ** 2.4
    return (f(r), f(g), f(b), 1.0)


def reset():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for coll in (bpy.data.materials, bpy.data.meshes, bpy.data.curves, bpy.data.metaballs):
        for d in list(coll):
            coll.remove(d)


def setp(node, name, value):
    if name in node.inputs:
        node.inputs[name].default_value = value


def new_mat(name, color, rough=0.5, metal=0.0, **extra):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    setp(b, "Base Color", srgb(*color))
    setp(b, "Roughness", rough)
    setp(b, "Metallic", metal)
    for k, v in extra.items():
        setp(b, k.replace("_", " "), v)
    return m


def principled(m):
    return next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")


def add_bump(m, scale, strength, detail=6.0, stretch=(1, 1, 1)):
    nt = m.node_tree
    b = principled(m)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = stretch
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = scale
    noise.inputs["Detail"].default_value = detail
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = strength
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
    nt.links.new(mp.outputs["Vector"], noise.inputs["Vector"])
    nt.links.new(noise.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    return noise


def wood_mat(name, dark, light, rough=0.62):
    """Maserung: gestrecktes Rauschen entlang X -> Farbverlauf + Bump."""
    m = new_mat(name, light, rough)
    nt = m.node_tree
    b = principled(m)
    noise = add_bump(m, 5.0, 0.35, 10.0, stretch=(0.25, 7, 7))
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = srgb(*dark)
    ramp.color_ramp.elements[1].color = srgb(*light)
    ramp.color_ramp.elements[0].position = 0.3
    ramp.color_ramp.elements[1].position = 0.7
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], b.inputs["Base Color"])
    return m


def metal_mat(name, color, rough=0.35, bump=0.0):
    m = new_mat(name, color, rough, 1.0)
    if bump:
        add_bump(m, 60.0, bump, 4.0)
    return m


def smooth(o):
    for p in o.data.polygons:
        p.use_smooth = True


def add_mod(o, kind, **kw):
    md = o.modifiers.new(kind, kind)
    for k, v in kw.items():
        setattr(md, k, v)
    return md


def box(loc, scale, m, bevel=0.03, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(location=loc, size=1, rotation=rot)
    o = bpy.context.active_object
    o.scale = scale
    add_mod(o, "BEVEL", width=bevel, segments=4)
    o.data.materials.append(m)
    smooth(o)
    return o


def sphere(loc, radius, m, scale=(1, 1, 1), rot=(0, 0, 0), segs=48):
    bpy.ops.mesh.primitive_uv_sphere_add(location=loc, radius=radius, segments=segs, ring_count=segs // 2, rotation=rot)
    o = bpy.context.active_object
    o.scale = scale
    o.data.materials.append(m)
    smooth(o)
    return o


def cylinder(loc, radius, depth, m, rot=(0, 0, 0), verts=64, bevel=0.0):
    bpy.ops.mesh.primitive_cylinder_add(location=loc, radius=radius, depth=depth, vertices=verts, rotation=rot)
    o = bpy.context.active_object
    if bevel:
        add_mod(o, "BEVEL", width=bevel, segments=4)
    o.data.materials.append(m)
    smooth(o)
    return o


def torus(loc, major, minor, m, rot=(0, 0, 0), scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_torus_add(location=loc, major_radius=major, minor_radius=minor, major_segments=96, minor_segments=16, rotation=rot)
    o = bpy.context.active_object
    o.scale = scale
    o.data.materials.append(m)
    smooth(o)
    return o


def lathe(name, profile, m, steps=96, subsurf=1):
    """Dreht ein (radius, hoehe)-Profil um die Z-Achse."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    vs = [bm.verts.new((r, 0, z)) for r, z in profile]
    es = [bm.edges.new((vs[i], vs[i + 1])) for i in range(len(vs) - 1)]
    bmesh.ops.spin(bm, geom=vs + es, cent=(0, 0, 0), axis=(0, 0, 1), angle=2 * math.pi, steps=steps, use_duplicate=False)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(m)
    smooth(o)
    if subsurf:
        add_mod(o, "SUBSURF", levels=subsurf, render_levels=subsurf)
    return o


def tube(name, points, radius, m, radii=None, res=12):
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = radius
    cu.bevel_resolution = res // 2
    cu.use_fill_caps = True
    sp = cu.splines.new("POLY")
    sp.points.add(len(points) - 1)
    for i, p in enumerate(points):
        sp.points[i].co = (p[0], p[1], p[2], 1)
        if radii:
            sp.points[i].radius = radii[i]
    o = bpy.data.objects.new(name, cu)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(m)
    return o


# ----------------------------------------------------------------------------- Szene
def scene_setup():
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    cy = sc.cycles
    cy.samples = 96
    cy.use_denoising = True
    cy.device = "CPU"
    sc.render.resolution_x = sc.render.resolution_y = SIZE
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.view_settings.exposure = -0.45
    w = bpy.data.worlds.get("World") or bpy.data.worlds.new("World")
    sc.world = w
    w.use_nodes = True
    nt = w.node_tree
    bg = next(n for n in nt.nodes if n.type == "BACKGROUND")
    # Himmelverlauf: dunkler Boden, heller Himmel -> Metall bekommt Kontrast in den Spiegelungen
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.38
    ramp.color_ramp.elements[0].color = (0.14, 0.15, 0.19, 1)
    ramp.color_ramp.elements[1].position = 0.62
    ramp.color_ramp.elements[1].color = (0.85, 0.92, 1.0, 1)
    nt.links.new(tc.outputs["Generated"], sep.inputs["Vector"])
    nt.links.new(sep.outputs["Z"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 0.9


def lights_and_camera(objs, az=-22, el=20, lens=85, fill=0.88, catcher=False):
    sc = bpy.context.scene
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in objs:
        if o.type == "CURVE":  # bound_box von Kurven mit Bevel ist unbrauchbar -> Kontrollpunkte nehmen
            pad = o.data.bevel_depth
            for sp in o.data.splines:
                for pt in sp.points:
                    c = o.matrix_world @ Vector(pt.co[:3])
                    pts += [c + Vector((sx * pad, sy * pad, sz * pad)) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
            continue
        eo = o.evaluated_get(dg)
        pts += [eo.matrix_world @ Vector(c) for c in eo.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    center = (lo + hi) / 2
    size = max(hi - lo)

    if catcher:
        bpy.ops.mesh.primitive_plane_add(size=40, location=(center.x, center.y, lo.z))
        pl = bpy.context.active_object
        pl.is_shadow_catcher = True

    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.lens = lens
    d = size * 4
    dirv = Vector((math.sin(math.radians(az)) * math.cos(math.radians(el)), -math.cos(math.radians(az)) * math.cos(math.radians(el)), math.sin(math.radians(el))))
    for _ in range(10):
        cam.location = center + dirv * d
        cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
        bpy.context.view_layer.update()
        ext = 0
        for p in pts:
            v = world_to_camera_view(sc, cam, p)
            ext = max(ext, abs(v.x - 0.5) * 2, abs(v.y - 0.5) * 2)
        d *= ext / fill

    def area(name, loc, energy, sz, color=(1, 1, 1)):
        ld = bpy.data.lights.new(name, "AREA")
        ld.energy = energy
        ld.size = sz
        ld.color = color
        lo_ = bpy.data.objects.new(name, ld)
        sc.collection.objects.link(lo_)
        lo_.location = center + Vector(loc) * size
        lo_.rotation_euler = (center - lo_.location).to_track_quat("-Z", "Y").to_euler()

    area("Key", (1.4, -1.8, 2.2), 620 * size * size, size * 2.2, (1.0, 0.96, 0.9))
    area("Fill", (-2.0, -1.2, 0.8), 250 * size * size, size * 3.0, (0.85, 0.92, 1.0))
    area("Rim", (0.2, 2.0, 1.6), 500 * size * size, size * 1.6)


def render(name):
    sc = bpy.context.scene
    sc.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)


# ----------------------------------------------------------------------------- Icons
def make_coin():
    gold = metal_mat("gold", (255, 200, 72), 0.26, 0.02)
    deep = metal_mat("gold_deep", (222, 160, 40), 0.34)
    objs = []
    disc = cylinder((0, 0, 0), 0.9, 0.13, gold, rot=(R90, 0, 0), bevel=0.03)
    objs.append(disc)
    # Rillenrand
    objs.append(torus((0, 0, 0), 0.9, 0.012, deep, rot=(R90, 0, 0)))
    # erhabener Rand + vertieftes Feld
    objs.append(torus((0, -0.062, 0), 0.76, 0.04, gold, rot=(R90, 0, 0)))
    objs.append(cylinder((0, -0.066, 0), 0.72, 0.014, deep, rot=(R90, 0, 0)))
    # Stern
    me = bpy.data.meshes.new("star")
    bm = bmesh.new()
    pts = []
    for i in range(10):
        r = 0.46 if i % 2 == 0 else 0.19
        a = math.pi / 2 + i * math.pi / 5
        pts.append(bm.verts.new((r * math.cos(a), 0, r * math.sin(a))))
    bm.faces.new(pts)
    bm.to_mesh(me)
    bm.free()
    star = bpy.data.objects.new("star", me)
    bpy.context.scene.collection.objects.link(star)
    star.location = (0, -0.072, 0)
    add_mod(star, "SOLIDIFY", thickness=0.05, offset=1)
    add_mod(star, "BEVEL", width=0.012, segments=3)
    star.data.materials.append(gold)
    star.rotation_euler = (0, 0, 0)
    objs.append(star)
    # Sicht von vorn, leicht gedreht
    return objs, dict(az=-24, el=12, lens=100)


def make_milk():
    glass = new_mat("glass", (255, 255, 255), 0.02, 0.0, Transmission_Weight=1.0, IOR=1.46)
    milk = new_mat("milk", (236, 232, 218), 0.22, 0.0, Subsurface_Weight=0.35, Coat_Weight=0.4)
    foil = metal_mat("foil", (78, 150, 214), 0.28, 0.05)
    paper = new_mat("paper", (226, 220, 204), 0.7)

    outer = [(0, 0), (0.40, 0), (0.48, 0.035), (0.50, 0.11), (0.50, 1.10), (0.47, 1.28), (0.36, 1.45), (0.25, 1.60), (0.215, 1.72), (0.215, 1.92), (0.235, 1.96), (0.235, 2.0)]
    inner = [(0.2, 2.0), (0.18, 1.92), (0.18, 1.72), (0.21, 1.6), (0.33, 1.45), (0.44, 1.28), (0.465, 1.1), (0.465, 0.16), (0.44, 0.10), (0.36, 0.08), (0, 0.08)]
    bottle = lathe("bottle", outer + inner, glass, subsurf=1)
    fill = lathe("fill", [(0, 0.085), (0.355, 0.085), (0.44, 0.105), (0.463, 0.17), (0.463, 1.1), (0.455, 1.2), (0, 1.2)], milk, subsurf=1)
    cap = lathe("cap", [(0, 2.18), (0.22, 2.18), (0.262, 2.15), (0.268, 2.0), (0.27, 1.9), (0.255, 1.86), (0.0, 1.86)], foil, subsurf=1)
    # Etikett mit Farbband
    label = lathe("label", [(0.503, 0.38), (0.512, 0.38), (0.512, 0.92), (0.503, 0.92)], paper, subsurf=0)
    nt = paper.node_tree
    b = principled(paper)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = 0.38
    mr.inputs["From Max"].default_value = 0.92
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    ramp.color_ramp.elements[0].color = srgb(226, 220, 204)
    ramp.color_ramp.elements[1].color = srgb(78, 164, 232)
    ramp.color_ramp.elements[1].position = 0.28
    e = ramp.color_ramp.elements.new(0.62)
    e.color = srgb(226, 220, 204)
    nt.links.new(tc.outputs["Object"], sep.inputs["Vector"])
    nt.links.new(sep.outputs["Z"], mr.inputs["Value"])
    nt.links.new(mr.outputs["Result"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], b.inputs["Base Color"])
    return [bottle, fill, cap, label], dict(az=-18, el=10, lens=90)


def make_bucket():
    zinc = metal_mat("zinc", (176, 182, 190), 0.38, 0.12)
    steel = metal_mat("steel", (96, 100, 108), 0.4, 0.05)
    milk = new_mat("milk", (236, 232, 218), 0.2, 0.0, Subsurface_Weight=0.35, Coat_Weight=0.5)
    prof = [(0, 0.02), (0.50, 0.02), (0.54, 0.06), (0.56, 0.14), (0.80, 1.40), (0.84, 1.45), (0.875, 1.48), (0.88, 1.54), (0.84, 1.585), (0.80, 1.56), (0.79, 1.5),
            (0.77, 1.42), (0.53, 0.16), (0.50, 0.11), (0, 0.11)]
    body = lathe("bucket", prof, zinc, subsurf=1)
    objs = [body]
    objs.append(lathe("bucket_milk", [(0, 1.22), (0.725, 1.22)], milk, steps=96, subsurf=0))
    for z in (0.55, 1.0):
        r = 0.56 + 0.24 * (z - 0.14) / 1.26 + 0.008
        objs.append(torus((0, 0, z), r, 0.02, zinc))
    pts = [(0.90 * math.cos(t), 0, 1.38 + 0.78 * math.sin(t)) for t in [i * math.pi / 40 for i in range(41)]]
    objs.append(tube("handle", pts, 0.028, steel))
    for sx in (-1, 1):
        objs.append(sphere((sx * 0.845, 0, 1.38), 0.055, steel))
    return objs, dict(az=-24, el=22, lens=85)


def make_crate(tier):
    cfg = {
        "normal": dict(dark=(52, 34, 22), light=(108, 74, 46), band=(100, 104, 112), lock=(184, 190, 200), gem=None),
        "super": dict(dark=(30, 24, 24), light=(74, 54, 46), band=(130, 168, 226), lock=(255, 205, 90), gem=(60, 150, 255)),
        "premium": dict(dark=(46, 14, 12), light=(98, 30, 24), band=(255, 200, 72), lock=(255, 214, 90), gem=(190, 70, 255)),
    }[tier]
    wood = wood_mat("wood", cfg["dark"], cfg["light"])
    groove = new_mat("groove", (24, 16, 12), 0.9)
    band = metal_mat("band", cfg["band"], 0.3 if tier != "normal" else 0.45, 0.04)
    lockm = metal_mat("lock", cfg["lock"], 0.28)
    objs = []
    # Korpus aus Planken
    objs.append(box((0, 0, 0.5), (1.42, 0.98, 0.92), wood, 0.03))
    for z in (0.22, 0.5, 0.78):
        objs.append(box((0, -0.492, z), (1.4, 0.012, 0.014), groove, 0.004))
    # Deckel: halber Zylinder entlang X
    lid = cylinder((0, 0, 0.96), 0.5, 1.5, wood, rot=(0, R90, 0), verts=48)
    lid.scale = (0.5, 1.0, 1.0)   # Z der Rotation -> Hoehe 0.5
    lid.scale = (0.62, 1.0, 1.0)
    objs.append(lid)
    # Metallbänder um Korpus und Deckel
    for x in (-0.52, 0.52):
        objs.append(box((x, 0, 0.5), (0.15, 1.02, 0.94), band, 0.02))
        c = cylinder((x, 0, 0.96), 0.52, 0.15, band, rot=(0, R90, 0), verts=48)
        c.scale = (0.62 * 1.0, 1.0, 1.0)
        objs.append(c)
        for z in (0.18, 0.42, 0.66, 0.86):
            objs.append(sphere((x, -0.514, z), 0.022, band, segs=16))
    # Eckbeschläge unten
    for x in (-0.72, 0.72):
        objs.append(box((x, 0, 0.06), (0.06, 1.0, 0.12), band, 0.012))
    # Schloss
    objs.append(box((0, -0.52, 0.86), (0.26, 0.05, 0.32), lockm, 0.015))
    objs.append(sphere((0, -0.552, 0.88), 0.032, groove, segs=16))
    objs.append(box((0, -0.552, 0.82), (0.016, 0.01, 0.07), groove, 0.002))
    if cfg["gem"]:
        gem = new_mat("gem", cfg["gem"], 0.04, 0.0, Transmission_Weight=0.6, IOR=1.7, Emission_Strength=0.6)
        setp(principled(gem), "Emission Color", srgb(*cfg["gem"]))
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.1, location=(0, -0.57, 1.14))
        g = bpy.context.active_object
        g.scale = (1, 0.7, 1.15)
        g.data.materials.append(gem)
        objs.append(g)
    return objs, dict(az=-26, el=22, lens=85)


def make_cow():
    fur = new_mat("fur", (226, 220, 206), 0.82, 0.0, Sheen_Weight=0.5, Subsurface_Weight=0.15)
    nt = fur.node_tree
    b = principled(fur)
    # Bump aus feinem Rauschen (Fell)
    add_bump(fur, 260.0, 0.25, 3.0)
    # Fleck (dunkel) und rosa Maul als Masken auf Objekt-Koordinaten
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sep.inputs["Vector"])
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 5.0
    nt.links.new(tc.outputs["Object"], noise.inputs["Vector"])
    nvec = nt.nodes.new("ShaderNodeVectorMath")
    nvec.operation = "ADD"
    nt.links.new(tc.outputs["Object"], nvec.inputs[0])
    nscale = nt.nodes.new("ShaderNodeVectorMath")
    nscale.operation = "SCALE"
    nscale.inputs["Scale"].default_value = 0.35
    nt.links.new(noise.outputs["Color"], nscale.inputs[0])
    nt.links.new(nscale.outputs["Vector"], nvec.inputs[1])
    dist = nt.nodes.new("ShaderNodeVectorMath")
    dist.operation = "DISTANCE"
    dist.inputs[1].default_value = (0.38, -0.2, 1.33)
    nt.links.new(nvec.outputs["Vector"], dist.inputs[0])
    patch = nt.nodes.new("ShaderNodeMapRange")
    patch.inputs["From Min"].default_value = 0.56
    patch.inputs["From Max"].default_value = 0.50
    nt.links.new(dist.outputs["Value"], patch.inputs["Value"])
    pmask = nt.nodes.new("ShaderNodeMapRange")  # Maul: y klein UND z klein
    pmask.inputs["From Min"].default_value = -0.50
    pmask.inputs["From Max"].default_value = -0.68
    nt.links.new(sep.outputs["Y"], pmask.inputs["Value"])
    zmask = nt.nodes.new("ShaderNodeMapRange")
    zmask.inputs["From Min"].default_value = 0.95
    zmask.inputs["From Max"].default_value = 0.78
    nt.links.new(sep.outputs["Z"], zmask.inputs["Value"])
    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    nt.links.new(pmask.outputs["Result"], mul.inputs[0])
    nt.links.new(zmask.outputs["Result"], mul.inputs[1])
    mix1 = nt.nodes.new("ShaderNodeMix")
    mix1.data_type = "RGBA"
    mix1.inputs["A"].default_value = srgb(226, 220, 206)
    mix1.inputs["B"].default_value = srgb(18, 17, 20)
    nt.links.new(patch.outputs["Result"], mix1.inputs["Factor"])
    mix2 = nt.nodes.new("ShaderNodeMix")
    mix2.data_type = "RGBA"
    mix2.inputs["B"].default_value = srgb(238, 150, 160)
    nt.links.new(mul.outputs["Value"], mix2.inputs["Factor"])
    nt.links.new(mix1.outputs["Result"], mix2.inputs["A"])
    nt.links.new(mix2.outputs["Result"], b.inputs["Base Color"])
    # Maul glatter/feuchter
    rmix = nt.nodes.new("ShaderNodeMath")
    rmix.operation = "MULTIPLY_ADD"
    rmix.inputs[1].default_value = -0.55
    rmix.inputs[2].default_value = 0.82
    nt.links.new(mul.outputs["Value"], rmix.inputs[0])
    nt.links.new(rmix.outputs["Value"], b.inputs["Roughness"])

    mb = bpy.data.metaballs.new("head")
    mb.resolution = 0.025
    mb.render_resolution = 0.025
    mb.threshold = 0.6
    el = [  # (x, y, z, radius, sx, sy, sz)
        (0, 0.00, 1.05, 0.62, 1.35, 1.05, 1.1),     # Schädel
        (0, -0.30, 1.30, 0.40, 1.2, 0.9, 0.9),     # Stirn
        (0, -0.55, 0.80, 0.42, 1.0, 1.1, 1.0),    # Nasenrücken
        (0, -0.80, 0.52, 0.36, 1.35, 0.9, 0.8),    # Maul
        (0, -0.55, 0.38, 0.28, 1.0, 1.0, 0.8),     # Kinn
        (-0.34, -0.18, 0.78, 0.30, 0.8, 0.9, 0.9), # Wange L
        (0.34, -0.18, 0.78, 0.30, 0.8, 0.9, 0.9),  # Wange R
    ]
    for x, y, z, r, sx, sy, sz in el:
        e = mb.elements.new(type="ELLIPSOID")
        e.co = (x, y, z)
        e.radius = r
        e.size_x, e.size_y, e.size_z = sx, sy, sz
        e.stiffness = 2.0
    head = bpy.data.objects.new("head", mb)
    bpy.context.scene.collection.objects.link(head)
    head.data.materials.append(fur)
    objs = [head]

    ink = new_mat("ink", (10, 10, 14), 0.08, 0.0, Coat_Weight=1.0)
    pink = new_mat("ear_in", (232, 150, 160), 0.6, 0.0, Subsurface_Weight=0.3)
    horn = new_mat("horn", (232, 218, 176), 0.38, 0.0, Coat_Weight=0.3)
    add_bump(horn, 40.0, 0.1, 2.0, stretch=(1, 1, 0.2))
    for sx in (-1, 1):
        # Ohren
        ear = sphere((sx * 0.62, 0.06, 1.22), 0.34, fur, scale=(1.0, 0.28, 0.55), rot=(0, sx * math.radians(18), sx * math.radians(-12)))
        objs.append(ear)
        inner = sphere((sx * 0.63, -0.02, 1.22), 0.27, pink, scale=(0.9, 0.12, 0.42), rot=(0, sx * math.radians(18), sx * math.radians(-12)))
        objs.append(inner)
        # Hörner
        pts = [(sx * (0.26 + 0.24 * t), 0.10, 1.40 + 0.55 * t - 0.12 * t * t) for t in [i / 8 for i in range(9)]]
        radii = [1.0 - 0.8 * (i / 8) for i in range(9)]
        objs.append(tube("horn", pts, 0.095, horn, radii=radii))
        # Augen
        objs.append(sphere((sx * 0.38, -0.36, 1.12), 0.075, ink, scale=(0.8, 0.7, 1.0)))
        # Nüstern
        objs.append(sphere((sx * 0.17, -1.04, 0.56), 0.05, ink, scale=(0.7, 0.4, 1.0), rot=(0, sx * math.radians(-20), 0)))
    return objs, dict(az=-14, el=6, lens=90)


MAKERS = {
    "coin": make_coin,
    "milk": make_milk,
    "bucket": make_bucket,
    "cow": make_cow,
    "crate_normal": lambda: make_crate("normal"),
    "crate_super": lambda: make_crate("super"),
    "crate_premium": lambda: make_crate("premium"),
}


def build(names=None):
    os.makedirs(OUT, exist_ok=True)
    for name in names or MAKERS:
        reset()
        scene_setup()
        objs, cam = MAKERS[name]()
        bpy.context.view_layer.update()
        lights_and_camera(objs, **cam)
        render(name)
        print("gerendert:", name)


if __name__ == "__main__":
    build()
