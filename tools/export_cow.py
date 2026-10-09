"""
Exportiert NUR die Kuh aus CowModell.blend als FBX für den Roblox-3D-Importer.

Aufruf (im Projektordner, Blender muss installiert sein):
    blender CowModell.blend --background --python tools/export_cow.py

Ergebnis: assets_src/CowModell.fbx
Die Hände, Arme, der Eimer, Milchtropfen, Kamera und Licht werden NICHT exportiert
(den Eimer und die Effekte baut das Spiel selbst).
Die Teile behalten ihre Namen (Koerper, Kopf, Zitze_..., Fleck_... usw.) – das Spiel
erkennt sie daran.
"""

import os

import bpy

# Teile der Kuh (Name beginnt mit einem dieser Wörter)
COW_PREFIXES = (
    "Koerper", "Kopf", "Schnauze", "Nase_", "Auge_", "Ohr_", "Horn_",
    "Bein_", "Euter", "Zitze_", "Schwanz", "Fleck_",
)

project_dir = os.path.dirname(bpy.data.filepath)
out_dir = os.path.join(project_dir, "assets_src")
os.makedirs(out_dir, exist_ok=True)
out_path = os.path.join(out_dir, "CowModell.fbx")

bpy.ops.object.select_all(action="DESELECT")
selected = []
for obj in bpy.data.objects:
    if obj.type == "MESH" and obj.name.startswith(COW_PREFIXES):
        obj.select_set(True)
        selected.append(obj.name)

if not selected:
    raise SystemExit("Keine Kuh-Teile gefunden – stimmen die Objektnamen?")

# Animationen auf Frame 1 zurücksetzen, damit die Kuh in Ruhestellung exportiert wird
bpy.context.scene.frame_set(1)

bpy.ops.export_scene.fbx(
    filepath=out_path,
    use_selection=True,
    object_types={"MESH"},
    apply_unit_scale=True,
    apply_scale_options="FBX_SCALE_ALL",
    axis_forward="-Z",
    axis_up="Y",
    bake_anim=False,
    use_mesh_modifiers=True,
    mesh_smooth_type="FACE",
)

print(f"Exportiert: {len(selected)} Teile -> {out_path}")
print(", ".join(sorted(selected)))
