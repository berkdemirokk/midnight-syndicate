"""Per-vertex ambient occlusion for kit meshes (Blender 5.x, deterministic, no downloads).

The Mobile renderer has no SSAO, so the building and landmark materials multiply their albedo by the vertex colour.
bake_ao() writes that colour into the meshes just before glTF export:

  1. Big faces (any edge over 2.5 m) are cut into a grid of about cell_m cells, so one occluded corner cannot smear a
     gradient across a whole wall. Only edges longer than cell_m are split; UVs, materials and smoothing are kept.
  2. Every face corner gets its own hemisphere test (origin 2 cm off the vertex along the FACE normal, cosine-weighted
     rays, fixed Fibonacci set rotated per vertex, rays that hit within distance_m count with weight 1 - d/distance_m).
     The ground plane z = ground_z is an occluder too, so wall bases get a soft contact darkening.
  3. Corners of one vertex are averaged only with faces whose normal is within 30 degrees: an eave or a window reveal
     that meets a wall keeps its own value instead of turning into mud.
  4. AO = max(floor, 1 - strength * occluded). Faces of glowing materials (window panes, lamps) are written white.

Result: a linear grey FLOAT_COLOR attribute "Col" (CORNER domain), active and render colour, alpha 1. The export
helper writes it as COLOR_0. check_glb_colour() reads a GLB back and reports the COLOR_0 values per file.
"""
import json
import math
import struct

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

COLOR_NAME = "Col"
GLOW_MATERIALS = frozenset({"M_Glass", "M_Lamp", "M_WindowAtlas", "M_ShopGlass", "M_ShopInterior", "M_CeilingStrip"})
SURF_EPS = 0.02                       # ray origin off the surface, m
SHARE_COS = math.cos(math.radians(30.0))
GOLDEN = math.pi * (3.0 - math.sqrt(5.0))
_DIRS = {}


def _dirs(samples):
    """Cosine-weighted hemisphere set (r, phi, z) in the local frame, Fibonacci spiral, fixed for a sample count."""
    if samples not in _DIRS:
        _DIRS[samples] = [(math.sqrt((i + 0.5) / samples), i * GOLDEN, math.sqrt(1.0 - (i + 0.5) / samples))
                          for i in range(samples)]
    return _DIRS[samples]


def _subdivide(me, cell_m, trigger_m=2.5, rounds=8):
    """Cut edges longer than cell_m on faces that have an edge over trigger_m (grid fill keeps the quads square)."""
    bm = bmesh.new()
    bm.from_mesh(me)
    for _ in range(rounds):
        big = [f for f in bm.faces if max(e.calc_length() for e in f.edges) > trigger_m]
        edges = list({e for f in big for e in f.edges if e.calc_length() > cell_m * 1.05})
        if not edges:
            break
        bmesh.ops.subdivide_edges(bm, edges=edges, cuts=1, use_grid_fill=True)
    bm.to_mesh(me)
    bm.free()
    me.update()


def _frame(n):
    helper = Vector((1.0, 0.0, 0.0)) if abs(n.x) < 0.9 else Vector((0.0, 1.0, 0.0))
    t = n.cross(helper).normalized()
    return t, n.cross(t)


def _occluded(origin, n, bvh, samples, distance_m, ground_z, rot):
    """Occluded fraction in [0, 1] of the cosine-weighted hemisphere above n."""
    t, b = _frame(n)
    occ = 0.0
    for r, phi, z in _dirs(samples):
        a = phi + rot
        d = t * (r * math.cos(a)) + b * (r * math.sin(a)) + n * z
        best = distance_m
        loc, _nor, _idx, hd = bvh.ray_cast(origin, d, distance_m)
        if loc is not None:
            best = min(best, hd)
        if d.z < -1e-6 and origin.z > ground_z:
            tg = (origin.z - ground_z) / -d.z
            best = min(best, tg)
        if best < distance_m:
            occ += 1.0 - best / distance_m
    return occ / samples


def bake_ao(objects, samples=48, distance_m=3.0, strength=1.0, floor=0.35, ground_z=0.0, cell_m=1.25,
            glow_materials=GLOW_MATERIALS):
    """Bake the AO colour attribute into each mesh object in place. Returns min/mean/max per object name.
    cell_m=None skips the subdivision (use it where the triangle budget is tight)."""
    if cell_m:
        for obj in objects:
            _subdivide(obj.data, cell_m)
    # one world-space BVH over every object, so the parts occlude each other
    verts, tris, offs = [], [], []
    for obj in objects:
        mw = obj.matrix_world
        base = len(verts)
        offs.append(base)
        tmp = bmesh.new()
        tmp.from_mesh(obj.data)
        bmesh.ops.triangulate(tmp, faces=list(tmp.faces))
        verts += [mw @ v.co for v in tmp.verts]
        tris += [tuple(base + v.index for v in f.verts) for f in tmp.faces]
        tmp.free()
    # triangulation adds no vertices, so the BVH vertex index of loop vi is off + vi
    bvh = BVHTree.FromPolygons(verts, tris)
    report = {}
    for obj, off in zip(objects, offs):
        me = obj.data
        nm = obj.matrix_world.to_3x3().inverted_safe().transposed()
        loop_n = [None] * len(me.loops)
        glow = set()
        for p in me.polygons:
            n = (nm @ p.normal).normalized()
            for li in p.loop_indices:
                loop_n[li] = n
            if 0 <= p.material_index < len(me.materials) and me.materials[p.material_index] is not None \
                    and me.materials[p.material_index].name in glow_materials:
                glow.update(p.loop_indices)
        vloops = [[] for _ in me.vertices]
        for loop in me.loops:
            vloops[loop.vertex_index].append(loop.index)
        raw = [1.0] * len(me.loops)
        for li, loop in enumerate(me.loops):
            if li in glow:
                continue
            vi = loop.vertex_index
            origin = verts[off + vi] + loop_n[li] * SURF_EPS
            rot = ((vi * 0.6180339887) % 1.0) * 2.0 * math.pi
            raw[li] = 1.0 - strength * _occluded(origin, loop_n[li], bvh, samples, distance_m, ground_z, rot)
        final = [1.0] * len(me.loops)
        for vi, lis in enumerate(vloops):
            for li in lis:
                if li in glow:
                    continue
                acc, cnt = 0.0, 0
                for lj in lis:
                    if loop_n[li].dot(loop_n[lj]) >= SHARE_COS:
                        acc += raw[lj]
                        cnt += 1
                final[li] = max(floor, min(1.0, acc / cnt))
        if COLOR_NAME in me.color_attributes:
            me.color_attributes.remove(me.color_attributes[COLOR_NAME])
        ca = me.color_attributes.new(COLOR_NAME, "FLOAT_COLOR", "CORNER")
        flat = []
        for v in final:
            flat += [v, v, v, 1.0]
        ca.data.foreach_set("color", flat)
        idx = me.color_attributes.find(COLOR_NAME)
        me.color_attributes.active_color_index = idx
        me.color_attributes.render_color_index = idx
        me.update()
        vals = final if final else [1.0]
        report[obj.name] = dict(min=round(min(vals), 3), mean=round(sum(vals) / len(vals), 3), max=round(max(vals), 3),
                                loops=len(final), tris=sum(len(p.vertices) - 2 for p in me.polygons))
    return report


def export_glb_ao(path, objects, root=None, apply=False, tangents=False):
    """glTF export that writes the active colour attribute as COLOR_0 (Blender 5.3 option names). apply / tangents
    follow the caller's export settings."""
    bpy.ops.object.select_all(action="DESELECT")
    sel = list(objects) + ([root] if root is not None else [])
    for o in sel:
        o.select_set(True)
    bpy.context.view_layer.objects.active = sel[-1]
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_apply=apply, export_tangents=tangents,
        export_yup=True, export_image_format="NONE", export_materials="EXPORT", export_cameras=False,
        export_lights=False, export_extras=False, export_vertex_color="ACTIVE",
        export_active_vertex_color_when_no_material=True)


_COMP = {5126: ("f", 4), 5121: ("B", 1), 5123: ("H", 2)}


def check_glb_colour(path):
    """Read a GLB back: per mesh primitive, whether COLOR_0 exists and the min / mean / max of its values (R channel,
    the colour is grey). Returns (summary dict, list of primitives without COLOR_0 with their material name)."""
    with open(path, "rb") as fh:
        data = fh.read()
    _magic, _ver, length = struct.unpack_from("<III", data, 0)
    off, doc, blob = 12, None, b""
    while off < length:
        clen, ctype = struct.unpack_from("<II", data, off)
        body = data[off + 8: off + 8 + clen]
        if ctype == 0x4E4F534A:
            doc = json.loads(body.decode("utf-8"))
        elif ctype == 0x004E4942:
            blob = body
        off += 8 + clen
    vals, missing = [], []
    for mesh in doc.get("meshes", []):
        for prim in mesh["primitives"]:
            attrs = prim["attributes"]
            mat = doc["materials"][prim["material"]]["name"] if "material" in prim else "-"
            if "COLOR_0" not in attrs:
                missing.append("%s/%s" % (mesh.get("name", "?"), mat))
                continue
            acc = doc["accessors"][attrs["COLOR_0"]]
            bv = doc["bufferViews"][acc["bufferView"]]
            fmt, size = _COMP[acc["componentType"]]
            base = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
            stride = bv.get("byteStride", size * 4)
            scale = {"f": 1.0, "B": 1.0 / 255.0, "H": 1.0 / 65535.0}[fmt]
            for i in range(acc["count"]):
                vals.append(struct.unpack_from("<" + fmt, blob, base + i * stride)[0] * scale)
    if not vals:
        return dict(values=0), missing
    return dict(values=len(vals), min=round(min(vals), 3), mean=round(sum(vals) / len(vals), 3),
                max=round(max(vals), 3)), missing
