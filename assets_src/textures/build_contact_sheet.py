"""Builds assets_src/textures/contact_sheet.png: every shipped base colour, labelled.

Run (Blender 5.3, background):
  "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" --background --factory-startup
      --python assets_src/textures/build_contact_sheet.py

The sheet is a real Blender render: each basecolor.jpg is an emissive image plane seen from a
top-down orthographic camera (Standard view transform, so the colours are the file colours).
Labels use Blender's built-in default font. Texture list and material names come from
tools/cc0_assets.json. The HDRIs are not base colours and are left out.
"""
import bpy
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(ROOT, "game", "assets", "textures", "cc0")
OUT = os.path.join(HERE, "contact_sheet.png")
CFG = os.path.join(ROOT, "tools", "cc0_assets.json")

COLS = 5
TILE = 1.1
PITCH_X = 1.75
PITCH_Y = 1.95


def log(msg):
    print("[contact_sheet] " + msg, file=sys.stdout, flush=True)


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def emission_material(name, image=None, colour=(1.0, 1.0, 1.0)):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Strength"].default_value = 1.0
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    if image is not None:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = image
        nt.links.new(tex.outputs["Color"], em.inputs["Color"])
    else:
        em.inputs["Color"].default_value = (*colour, 1.0)
    return mat


def add_text(text, x, y, size, colour=(0.92, 0.95, 1.0)):
    bpy.ops.object.text_add(location=(x, y, 0.001))
    obj = bpy.context.object
    obj.data.body = text
    obj.data.size = size
    obj.data.align_x = "CENTER"
    obj.data.align_y = "TOP"
    obj.data.materials.append(emission_material("TXT_" + text[:24], colour=colour))
    return obj


def main():
    with open(CFG, encoding="utf-8") as f:
        cfg = json.load(f)
    items = [a for a in cfg["assets"] if a["kind"] == "texture"]
    clear_scene()
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in dir(bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items) else "BLENDER_EEVEE"
    log("engine " + scene.render.engine)
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.render.resolution_x = 2000
    scene.render.resolution_y = 1900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    world = bpy.data.worlds.new("SheetWorld")
    world.color = (0.035, 0.04, 0.06)
    scene.world = world

    rows = (len(items) + COLS - 1) // COLS
    total_w = (COLS - 1) * PITCH_X + TILE
    total_h = (rows - 1) * PITCH_Y + TILE + 0.5
    top = 0.0
    for i, a in enumerate(items):
        c, r = i % COLS, i // COLS
        x = c * PITCH_X
        y = -r * PITCH_Y
        path = os.path.join(SRC, a["id"], "basecolor.jpg")
        img = bpy.data.images.load(path, check_existing=False)
        img.colorspace_settings.name = "sRGB"
        bpy.ops.mesh.primitive_plane_add(size=TILE, location=(x, y, 0.0))
        plane = bpy.context.object
        plane.name = "TILE_" + a["id"]
        plane.data.materials.append(emission_material("EM_" + a["id"], image=img))
        add_text(a["id"], x, y - TILE / 2 - 0.12, 0.13)
        add_text(a["material"], x, y - TILE / 2 - 0.36, 0.1, colour=(0.6, 0.95, 1.0))
        top = max(top, y)
        log("tile %-26s %s" % (a["id"], os.path.relpath(path, ROOT)))

    add_text("MIDNIGHT SYNDICATE - CC0 base colours as shipped (Poly Haven, 1K and 2K)",
             -0.5, 0.75, 0.14, colour=(1.0, 0.8, 0.3))
    add_text("Rainy night city palette check. Normal and roughness maps are not shown here.",
             -0.5, 0.52, 0.09, colour=(0.7, 0.75, 0.85))

    cx = (COLS - 1) * PITCH_X / 2.0  # tiles run from -TILE/2 to (COLS-1)*PITCH_X + TILE/2
    cy = -(rows - 1) * PITCH_Y / 2.0 + 0.1
    bpy.ops.object.camera_add(location=(cx, cy, 20.0), rotation=(0.0, 0.0, 0.0))
    cam = bpy.context.object
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = max(total_w + 0.6, total_h + 0.6) * 1.0
    scene.camera = cam
    scene.render.filepath = OUT
    bpy.ops.render.render(write_still=True)
    log("wrote " + OUT)


if __name__ == "__main__":
    main()
