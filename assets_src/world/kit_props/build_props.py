"""CITY 01 props kit generator (Blender 5.3, deterministic).

Run:  "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" --background --factory-startup --python build_props.py
Writes out/prop_<id>.glb (no embedded images), out/textures/*.png, out/materials.json,
out/catalog.json and out/report.json. Coordinates: Blender metres, Z up, props face -Y.
Catalog light positions and sizes are written in GODOT coords: godot = (bx, bz, -by).
"""
import bpy
import bmesh
import json
import math
import os
import random

import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
TEXD = os.path.join(OUT, "textures")
os.makedirs(TEXD, exist_ok=True)


def log(*a):
    print("[kit]", *a)


# ----------------------------------------------------------------------------- materials

MATS = {}


def mdef(name, base, rough=0.6, metal=0.0, emit=None, estr=0.0, tex=None, tiling=1.0):
    MATS[name] = dict(base=list(base), roughness=rough, metallic=metal,
                      emission=list(emit) if emit else None, emission_strength=estr,
                      texture=tex, uv_tiling_m=tiling)


def define_materials():
    mdef("M_Metal_Dark", (0.05, 0.055, 0.065), 0.45, 0.6)
    mdef("M_Metal_Grey", (0.32, 0.34, 0.36), 0.5, 0.5)
    mdef("M_Metal_Red", (0.55, 0.07, 0.05), 0.45, 0.2)
    mdef("M_Metal_Green", (0.08, 0.2, 0.14), 0.5, 0.3)
    mdef("M_Hydrant_Red", (0.7, 0.08, 0.05), 0.4, 0.1)
    mdef("M_Bollard", (0.8, 0.5, 0.08), 0.5, 0.1)
    mdef("M_Concrete", (0.36, 0.36, 0.37), 0.85)
    mdef("M_Wood_Dark", (0.16, 0.09, 0.05), 0.7)
    mdef("M_Foliage", (0.06, 0.22, 0.08), 0.8)
    mdef("M_Glass", (0.05, 0.09, 0.11), 0.05)
    mdef("M_Shutter", (0.3, 0.32, 0.34), 0.35, 0.6)
    mdef("M_Awning_A", (0.55, 0.08, 0.06), 0.7)
    mdef("M_Awning_B", (0.85, 0.82, 0.74), 0.7)
    mdef("M_Chevron_White", (0.92, 0.92, 0.9), 0.25)
    mdef("M_Chevron_Red", (0.85, 0.05, 0.04), 0.25)
    mdef("M_Cone_Orange", (1.0, 0.32, 0.05), 0.45)
    mdef("M_Cone_White", (0.95, 0.95, 0.95), 0.5)
    mdef("M_Collider", (0.5, 0.5, 0.5), 0.9)
    mdef("M_Crane", (0.04, 0.04, 0.05), 0.8, 0.3)
    mdef("M_Container_Red", (0.45, 0.07, 0.05), 0.6)
    mdef("M_Container_Blue", (0.05, 0.14, 0.3), 0.6)
    mdef("M_Container_Green", (0.07, 0.25, 0.12), 0.6)
    mdef("M_Container_Grey", (0.3, 0.31, 0.33), 0.6)
    mdef("M_SignBox", (0.02, 0.02, 0.025), 0.7)
    mdef("M_Lamp_Sodium", (1.0, 0.70, 0.42), 0.4, 0.0, (1.0, 0.70, 0.42), 14.0)
    mdef("M_Lamp_Cool", (0.75, 0.85, 1.0), 0.4, 0.0, (0.75, 0.85, 1.0), 10.0)
    mdef("M_Signal_Red", (0.3, 0.02, 0.02), 0.3, 0.0, (1.0, 0.23, 0.19), 10.0)
    mdef("M_Signal_Off", (0.05, 0.05, 0.05), 0.3)
    mdef("M_Bulb_Amber", (1.0, 0.7, 0.3), 0.4, 0.0, (1.0, 0.7, 0.3), 12.0)
    mdef("M_Bulb_Red", (1.0, 0.2, 0.15), 0.4, 0.0, (1.0, 0.2, 0.15), 12.0)
    neon = {
        "M_Neon_Cyan": (0.098, 0.902, 1.0),
        "M_Neon_Magenta": (1.0, 0.169, 0.839),
        "M_Neon_Amber": (1.0, 0.761, 0.239),
        "M_Neon_Red": (1.0, 0.231, 0.188),
        "M_Neon_White": (1.0, 0.95, 0.9),
    }
    for k, c in neon.items():
        mdef(k, [x * 0.25 for x in c], 0.35, 0.0, c, 9.0)
    for i in range(1, 7):
        mdef("M_Poster_%02d" % i, (0.5, 0.5, 0.5), 0.5, 0.0, (1, 1, 1), 2.2,
             tex="textures/poster_%02d.png" % i, tiling=2.0)
    mdef("M_Skyline", (0.5, 0.5, 0.5), 0.9, 0.0, (1, 1, 1), 1.6,
         tex="textures/skyline_night.png", tiling=400.0)


_bmat = {}


def bmat(name):
    if name in _bmat:
        return _bmat[name]
    s = MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    if s["texture"]:
        img = bpy.data.images.load(os.path.join(OUT, s["texture"]), check_existing=True)
        tn = nt.nodes.new("ShaderNodeTexImage")
        tn.image = img
        nt.links.new(tn.outputs["Color"], bsdf.inputs["Base Color"])
        if s["emission"]:
            nt.links.new(tn.outputs["Color"], bsdf.inputs["Emission Color"])
    else:
        bsdf.inputs["Base Color"].default_value = (s["base"][0], s["base"][1], s["base"][2], 1.0)
        if s["emission"]:
            bsdf.inputs["Emission Color"].default_value = (s["emission"][0], s["emission"][1], s["emission"][2], 1.0)
    bsdf.inputs["Roughness"].default_value = s["roughness"]
    bsdf.inputs["Metallic"].default_value = s["metallic"]
    if s["emission"]:
        bsdf.inputs["Emission Strength"].default_value = s["emission_strength"]
    _bmat[name] = m
    return m


# ----------------------------------------------------------------------------- geometry

class Geo:
    """Plain triangle-soup-like container: vertices, faces, per-face material name and smooth flag."""

    def __init__(self):
        self.v = []
        self.f = []
        self.m = []
        self.s = []

    def add(self, verts, faces, mat, smooth=False):
        base = len(self.v)
        self.v.extend(Vector(p) for p in verts)
        sml = smooth if isinstance(smooth, list) else [smooth] * len(faces)
        for fc, sm in zip(faces, sml):
            self.f.append(tuple(base + i for i in fc))
            self.m.append(mat)
            self.s.append(bool(sm))
        return self

    def merge(self, o, xf=None):
        if xf is None:
            xf = Matrix.Identity(4)
        flip = xf.to_3x3().determinant() < 0
        base = len(self.v)
        self.v.extend(xf @ p for p in o.v)
        for fc, mat, sm in zip(o.f, o.m, o.s):
            if flip:
                fc = tuple(reversed(fc))
            self.f.append(tuple(base + i for i in fc))
            self.m.append(mat)
            self.s.append(sm)
        return self


def put(dst, src, c=(0, 0, 0), rx=0.0, ry=0.0, rz=0.0):
    m = (Matrix.Translation(Vector(c)) @ Matrix.Rotation(math.radians(rz), 4, "Z")
         @ Matrix.Rotation(math.radians(ry), 4, "Y") @ Matrix.Rotation(math.radians(rx), 4, "X"))
    return dst.merge(src, m)


def box(size, c=(0, 0, 0), mat="M_Metal_Dark"):
    sx, sy, sz = (s / 2.0 for s in size)
    cx, cy, cz = c
    p = [(cx + dx * sx, cy + dy * sy, cz + dz * sz)
         for dx, dy, dz in ((-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1),
                            (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1))]
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    return Geo().add(p, faces, mat, False)


def cyl(r, h, mat, sides=12, rings=1, r2=None, cap=True, z0=0.0):
    """Cylinder along +Z from z0 to z0+h, optionally tapered to radius r2 (0 = cone)."""
    r2 = r if r2 is None else r2
    V = []
    F = []
    for j in range(rings + 1):
        t = j / float(rings)
        rr = r + (r2 - r) * t
        z = z0 + h * t
        for i in range(sides):
            a = 2 * math.pi * i / sides
            V.append((rr * math.cos(a), rr * math.sin(a), z))
    for j in range(rings):
        for i in range(sides):
            a = j * sides + i
            b = j * sides + (i + 1) % sides
            c = (j + 1) * sides + (i + 1) % sides
            d = (j + 1) * sides + i
            F.append((a, b, c, d))
    smf = [True] * len(F)
    if cap:
        bc = len(V)
        V.append((0, 0, z0))
        for i in range(sides):
            F.append((bc, (i + 1) % sides, i))
            smf.append(False)
        if r2 > 1e-9:
            tc = len(V)
            V.append((0, 0, z0 + h))
            top = rings * sides
            for i in range(sides):
                F.append((tc, top + i, top + (i + 1) % sides))
                smf.append(False)
    return Geo().add(V, F, mat, smf)


def tube(pts, r, mat, sides=6, closed=False):
    P = [Vector(p) for p in pts]
    n = len(P)
    T = []
    for i in range(n):
        if closed:
            d = P[(i + 1) % n] - P[(i - 1) % n]
        else:
            d = P[min(i + 1, n - 1)] - P[max(i - 1, 0)]
        T.append(d.normalized())
    ref = Vector((0, 0, 1)) if abs(T[0].z) < 0.9 else Vector((1, 0, 0))
    N = [(ref - T[0] * ref.dot(T[0])).normalized()]
    for i in range(1, n):
        N.append((N[-1] - T[i] * N[-1].dot(T[i])).normalized())
    V = []
    for i in range(n):
        B = T[i].cross(N[i])
        for k in range(sides):
            a = 2 * math.pi * k / sides
            V.append(P[i] + (N[i] * math.cos(a) + B * math.sin(a)) * r)
    F = []
    smf = []
    segs = n if closed else n - 1
    for i in range(segs):
        i2 = (i + 1) % n
        for k in range(sides):
            k2 = (k + 1) % sides
            F.append((i * sides + k, i * sides + k2, i2 * sides + k2, i2 * sides + k))
            smf.append(True)
    if not closed:
        c0 = len(V)
        V.append(P[0])
        for k in range(sides):
            F.append((c0, (k + 1) % sides, k))
            smf.append(False)
        c1 = len(V)
        V.append(P[-1])
        last = (n - 1) * sides
        for k in range(sides):
            F.append((c1, last + k, last + (k + 1) % sides))
            smf.append(False)
    return Geo().add(V, F, mat, smf)


def sphere(r, mat, seg=8, rings=5):
    V = []
    for j in range(rings + 1):
        phi = math.pi * j / rings
        for i in range(seg):
            th = 2 * math.pi * i / seg
            V.append((r * math.sin(phi) * math.cos(th), r * math.sin(phi) * math.sin(th), r * math.cos(phi)))
    F = []
    for j in range(rings):
        for i in range(seg):
            a = j * seg + i
            b = j * seg + (i + 1) % seg
            c = (j + 1) * seg + (i + 1) % seg
            d = (j + 1) * seg + i
            F.append((a, d, c, b))
    return Geo().add(V, F, mat, True)


def prism_x(poly, x0, x1, mat):
    """Extrude a convex CCW polygon given as (y, z) pairs along X from x0 to x1."""
    n = len(poly)
    V = [(x0, y, z) for y, z in poly] + [(x1, y, z) for y, z in poly]
    F = []
    for k in range(n):
        k2 = (k + 1) % n
        F.append((k, k2, n + k2, n + k))
    for i in range(1, n - 1):
        F.append((0, i + 1, i))
        F.append((n, n + i, n + i + 1))
    return Geo().add(V, F, mat, False)


def slab_x(p0, p1, x0, x1, t, mat):
    """Flat strip along X between two (y, z) points, thickness t, for wave / W-beam profiles."""
    (y0, z0), (y1, z1) = p0, p1
    L = x1 - x0
    sl = math.hypot(y1 - y0, z1 - z0)
    a = math.atan2(z1 - z0, y1 - y0)
    xm = (x0 + x1) / 2.0
    ym, zm = (y0 + y1) / 2.0, (z0 + z1) / 2.0
    g = box((L, sl, t), (0, 0, 0), mat)
    m = Matrix.Translation(Vector((xm, ym, zm))) @ Matrix.Rotation(a - math.pi / 2, 4, "X")
    return Geo().merge(g, m)


def strut(p0, p1, w, mat):
    a = Vector(p0)
    b = Vector(p1)
    d = b - a
    L = d.length
    q = Vector((0, 0, 1)).rotation_difference(d.normalized())
    m = Matrix.Translation((a + b) / 2.0) @ q.to_matrix().to_4x4()
    return Geo().merge(box((w, w, L), (0, 0, 0), mat), m)


def lerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)


# ----------------------------------------------------------------------------- text

_GC = {}


def glyph(s, extrude=0.0, bevel=0.0, res=None, fill="BOTH"):
    """Built-in Blender font -> mesh. Returns (verts, faces, width, height, zmin, zmax), normalised so minx=miny=0.
    fill="NONE" with a bevel gives a round tube along every outline (neon tube letters)."""
    key = (s, extrude, bevel, res, fill)
    if key in _GC:
        return _GC[key]
    if not s.strip():
        res = ([], [], 0.0, 0.0, 0.0, 0.0)
        _GC[key] = res
        return res
    cu = bpy.data.curves.new("glyph", "FONT")
    cu.body = s
    cu.extrude = extrude
    cu.bevel_depth = bevel
    cu.bevel_resolution = (BEVEL_RES if fill == "NONE" else 1) if bevel > 0 else 0
    cu.fill_mode = fill
    if res is not None:
        cu.resolution_u = res
    ob = bpy.data.objects.new("glyph", cu)
    sc = bpy.context.scene.collection
    sc.objects.link(ob)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    V = [tuple(v.co) for v in me.vertices]
    F = [tuple(p.vertices) for p in me.polygons]
    sc.objects.unlink(ob)
    bpy.data.objects.remove(ob)
    bpy.data.curves.remove(cu)
    bpy.data.meshes.remove(me)
    minx = min(v[0] for v in V)
    miny = min(v[1] for v in V)
    V = [(x - minx, y - miny, z) for x, y, z in V]
    W = max(v[0] for v in V)
    H = max(v[1] for v in V)
    zmin = min(v[2] for v in V)
    zmax = max(v[2] for v in V)
    if extrude > 0 or bevel > 0:
        vol = 0.0
        for f in F:
            for k in range(1, len(f) - 1):
                a, b, c = Vector(V[f[0]]), Vector(V[f[k]]), Vector(V[f[k + 1]])
                vol += a.dot(b.cross(c))
        if vol < 0:
            F = [tuple(reversed(f)) for f in F]
    res = (V, F, W, H, zmin, zmax)
    _GC[key] = res
    return res


NEON_RES = 3        # curve resolution: 1 turns O into a diamond
TUBE_R = 0.011      # neon tube radius in metres (about 22 mm tube)
BEVEL_RES = 0


def neon_lines(lines, w, h, depth, origin, U, V, N, gap=0.2, fill=0.92):
    """Tube-like neon letters: each line (text, material) stacked top to bottom inside a w x h box
    whose bottom-left corner is origin on the face. U, V = reading and up axes, N = face normal.
    Each glyph outline becomes a round tube of radius TUBE_R standing off the face by TUBE_R.
    depth is unused (kept for call-site compatibility)."""
    n = len(lines)
    U, V, N = Vector(U), Vector(V), Vector(N)
    href = glyph("H", res=NEON_RES)[3]
    line_h = h / (n + (n - 1) * gap)
    g = Geo()
    flat = Geo()  # LOD1 stand-in: flat glyphs (decimating the tubes cannot reach 35 percent)
    top = h
    for txt, mat in lines:
        if not txt.strip():
            top -= line_h * (1 + gap)
            continue
        W0 = glyph(txt, res=NEON_RES)[2]
        s = line_h / href
        if W0 * s > w * fill:
            s = w * fill / W0
        r = TUBE_R / s  # tube radius in glyph units so that it is TUBE_R metres after scaling
        V2, F2, W, Hh, zmin, zmax = glyph(txt, 0.0, r, res=NEON_RES, fill="NONE")
        if not F2:
            top -= line_h * (1 + gap)
            continue
        ox = (w - W * s) / 2.0
        oy = top - line_h
        pts = []
        for x, y, z in V2:
            u = ox + x * s
            vv = oy + y * s
            ww = (z - zmin) * s
            pts.append(Vector(origin) + U * u + V * vv + N * ww)
        g.add(pts, F2, mat, True)
        V3, F3, _W3, _H3, _z3min, _z3max = glyph(txt, 0.0, 0.0, res=NEON_RES)
        # caps only (no extrude): make the glyph normal +Z so it faces N
        nz = 0.0
        for f in F3:
            a, b, c = Vector(V3[f[0]]), Vector(V3[f[1]]), Vector(V3[f[2]])
            nz += (b - a).cross(c - a).z
        if nz < 0:
            F3 = [tuple(reversed(f)) for f in F3]
        pts3 = []
        for x, y, z in V3:
            pts3.append(Vector(origin) + U * (ox + TUBE_R + x * s) + V * (oy + TUBE_R + y * s))
        flat.add(pts3, F3, mat, False)
        top -= line_h * (1 + gap)
    g.lod = flat
    return g


def flat_text_len(txt, cap):
    W = glyph(txt)[2]
    return W * (cap / glyph("H")[3])


# ----------------------------------------------------------------------------- scene helpers

def clear_scene():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for me in list(bpy.data.meshes):
        if me.users == 0:
            bpy.data.meshes.remove(me)
    for cu in list(bpy.data.curves):
        if cu.users == 0:
            bpy.data.curves.remove(cu)


def make_object(name, geo, bevel=0.0, uv=None):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in geo.v], [], geo.f)
    me.update()
    if len(me.polygons) != len(geo.f):
        raise RuntimeError("polygon count mismatch in %s: %d vs %d" % (name, len(me.polygons), len(geo.f)))
    names = []
    for m in geo.m:
        if m not in names:
            names.append(m)
    for m in names:
        me.materials.append(bmat(m))
    idx = {m: i for i, m in enumerate(names)}
    for p, m, s in zip(me.polygons, geo.m, geo.s):
        p.material_index = idx[m]
        p.use_smooth = bool(s)
    bm = bmesh.new()
    bm.from_mesh(me)
    if bevel > 0:
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
        edges = [e for e in bm.edges if len(e.link_faces) == 2 and e.calc_face_angle() > math.radians(35)]
        if edges:
            bmesh.ops.bevel(bm, geom=edges, offset=bevel, offset_type="OFFSET", segments=2,
                            profile=0.5, affect="EDGES", clamp_overlap=True)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    me.update()
    uvl = me.uv_layers.new(name="UVMap")
    for p in me.polygons:
        n = p.normal
        ax = max(range(3), key=lambda k: abs(n[k]))
        for li in p.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            if uv is not None:
                u, vv = uv(co)
            elif ax == 0:
                u, vv = co.y, co.z
            elif ax == 1:
                u, vv = co.x, co.z
            else:
                u, vv = co.x, co.y
            uvl.data[li].uv = (u, vv)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def tri_count(ob):
    me = ob.data
    me.calc_loop_triangles()
    return len(me.loop_triangles)


def is_collider(name):
    return name.endswith("-colonly") or name.endswith("-convcolonly")


def export_glb(path):
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                              export_apply=True, export_tangents=True,
                              export_image_format="NONE", export_yup=True)


def build_prop(pid, spec):
    clear_scene()
    sc = bpy.context.scene.collection
    root = bpy.data.objects.new(pid, None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 0.5
    sc.objects.link(root)
    vis, cols = [], []
    for part in spec["parts"]:
        ob = make_object(part["name"], part["geo"], part.get("bevel", 0.0), part.get("uv"))
        ob.parent = root
        (cols if is_collider(part["name"]) else vis).append(ob)
    tris0 = sum(tri_count(o) for o in vis)
    lod1_tris = None
    lod_ratio = None
    lodgeo = {p["name"]: p["geo"].lod for p in spec["parts"] if getattr(p["geo"], "lod", None) is not None}
    if tris0 > 800:
        for ratio in (0.3, 0.22, 0.15, 0.1):
            lod = bpy.data.objects.new(pid + "_LOD1", None)
            sc.objects.link(lod)
            lod.parent = root
            made = []
            for o in vis:
                if o.name in lodgeo:
                    co = make_object(o.name + "_lod1", lodgeo[o.name])
                    co.parent = lod
                    made.append(co)
                    continue
                c = o.data.copy()
                co = bpy.data.objects.new(o.name + "_lod1", c)
                sc.objects.link(co)
                co.parent = lod
                mod = co.modifiers.new("dec", "DECIMATE")
                mod.decimate_type = "COLLAPSE"
                mod.ratio = ratio
                dg = bpy.context.evaluated_depsgraph_get()
                nm = bpy.data.meshes.new_from_object(co.evaluated_get(dg))
                co.modifiers.remove(mod)
                old = co.data
                co.data = nm
                bpy.data.meshes.remove(old)
                made.append(co)
            t1 = sum(tri_count(c) for c in made)
            if t1 <= 0.35 * tris0:
                lod1_tris, lod_ratio = t1, ratio
                break
            for c in made:
                bpy.data.objects.remove(c, do_unlink=True)
            bpy.data.objects.remove(lod, do_unlink=True)
    ctris = sum(tri_count(o) for o in cols)
    # bounds in Godot axes
    xs, ys, zs = [], [], []
    for o in vis:
        for v in o.data.vertices:
            xs.append(v.co.x)
            ys.append(v.co.y)
            zs.append(v.co.z)
    size_b = (max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))
    size_g = [round(size_b[0], 3), round(size_b[2], 3), round(size_b[1], 3)]
    mats = []
    for o in vis:
        for slot in o.data.materials:
            if slot.name not in mats:
                mats.append(slot.name)
    # main GLB: LOD0 visuals + colliders only
    lod_objs = [o for o in bpy.data.objects if o.name.endswith("_lod1") or o.name == pid + "_LOD1"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in [root] + vis + cols:
        o.select_set(True)
    bpy.context.view_layer.objects.active = root
    path = os.path.join(OUT, "prop_%s.glb" % pid)
    export_glb(path)
    # LOD1 goes to its own file, so the engine loads it as a separate LOD level
    lod_file = None
    if lod_objs:
        lod_file = "prop_%s_lod1.glb" % pid
        bpy.ops.object.select_all(action="DESELECT")
        for o in lod_objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = lod_objs[0]
        export_glb(os.path.join(OUT, lod_file))
    emissive = any(MATS[m]["emission"] is not None for m in mats)
    return {
        "id": pid,
        "category": spec["category"],
        "file": "prop_%s.glb" % pid,
        "size": size_g,
        "tris": tris0,
        "lod1_tris": lod1_tris,
        "lod1_ratio": lod_ratio,
        "lod1_file": lod_file,
        "collider_tris": ctris,
        "materials": mats,
        "emissive": bool(emissive),
        "mount": spec["mount"],
        "budget": spec.get("budget"),
        "lights": [light_out(l) for l in spec.get("lights", [])],
        "notes": spec.get("notes", ""),
    }


def light_out(l):
    p = l["pos"]
    d = l.get("dir")
    return {
        "pos_godot": [round(p[0], 3), round(p[2], 3), round(-p[1], 3)],
        "color": [round(c, 3) for c in l["color"]],
        "energy": l["energy"],
        "range": l["range"],
        "type": l["type"],
        "direction_godot": [round(d[0], 3), round(d[2], 3), round(-d[1], 3)] if d else None,
    }


def part(name, geo, bevel=0.0, uv=None):
    return {"name": name, "geo": geo, "bevel": bevel, "uv": uv}


def light(pos, color, energy, rng, typ="omni", d=None):
    return {"pos": pos, "color": color, "energy": energy, "range": rng, "type": typ, "dir": d}


# ----------------------------------------------------------------------------- raster for posters

def fill_tri(mask, a, b, c):
    Hh, Ww = mask.shape
    pa = (a[0], Hh - a[1])
    pb = (b[0], Hh - b[1])
    pc = (c[0], Hh - c[1])
    xmin = max(int(math.floor(min(pa[0], pb[0], pc[0]))), 0)
    xmax = min(int(math.ceil(max(pa[0], pb[0], pc[0]))), Ww - 1)
    ymin = max(int(math.floor(min(pa[1], pb[1], pc[1]))), 0)
    ymax = min(int(math.ceil(max(pa[1], pb[1], pc[1]))), Hh - 1)
    if xmax < xmin or ymax < ymin:
        return
    xs = np.arange(xmin, xmax + 1) + 0.5
    ys = np.arange(ymin, ymax + 1) + 0.5
    X, Y = np.meshgrid(xs, ys)
    d = (pb[1] - pc[1]) * (pa[0] - pc[0]) + (pc[0] - pb[0]) * (pa[1] - pc[1])
    if abs(d) < 1e-12:
        return
    l1 = ((pb[1] - pc[1]) * (X - pc[0]) + (pc[0] - pb[0]) * (Y - pc[1])) / d
    l2 = ((pc[1] - pa[1]) * (X - pc[0]) + (pa[0] - pc[0]) * (Y - pc[1])) / d
    l3 = 1 - l1 - l2
    inside = (l1 >= 0) & (l2 >= 0) & (l3 >= 0)
    sub = mask[ymin:ymax + 1, xmin:xmax + 1]
    sub[inside] = 1.0


def raster_text(mask, txt, x0, base_row, cap_px, maxw=None):
    """Draws txt with its baseline at image row base_row, left edge at x0. Returns drawn width."""
    V2, F2, W, Hh, _, _ = glyph(txt)
    if not F2:
        return 0.0
    s = cap_px / glyph("H")[3]
    if maxw and W * s > maxw:
        s = maxw / W
    Himg = mask.shape[0]
    for f in F2:
        pts = [(x0 + V2[i][0] * s, Himg - (base_row - V2[i][1] * s)) for i in f]
        for k in range(1, len(pts) - 1):
            fill_tri(mask, pts[0], pts[k], pts[k + 1])
    return W * s


def text_px_width(txt, cap_px, maxw=None):
    s = cap_px / glyph("H")[3]
    W = glyph(txt)[2] * s
    if maxw and W > maxw:
        W = maxw
    return W


POSTERS = [
    dict(name="HOTEL ARDEN", c1=(0.05, 0.02, 0.12), c2=(0.45, 0.05, 0.35), acc=(1.0, 0.76, 0.24),
         shape="circle", title=["HOTEL", "ARDEN"], sub="STAY LATE", glow=(0.78, 0.3)),
    dict(name="PIXEL ARCADE", c1=(0.02, 0.04, 0.12), c2=(0.02, 0.35, 0.45), acc=(0.1, 0.9, 1.0),
         shape="stripes", title=["PIXEL", "ARCADE"], sub="INSERT COIN", glow=(0.2, 0.6)),
    dict(name="AMPERE ENERGY", c1=(0.02, 0.02, 0.03), c2=(0.3, 0.02, 0.2), acc=(1.0, 0.17, 0.84),
         shape="bars", title=["AMPERE", "ENERGY"], sub="CHARGE UP", glow=(0.5, 0.25)),
    dict(name="BLUE HERON SUSHI", c1=(0.02, 0.05, 0.1), c2=(0.03, 0.2, 0.32), acc=(0.4, 0.85, 1.0),
         shape="circle", title=["BLUE HERON", "SUSHI"], sub="FRESH FROM THE DOCK", glow=(0.25, 0.7)),
    dict(name="ORBIT RECORDS", c1=(0.06, 0.02, 0.02), c2=(0.4, 0.12, 0.02), acc=(1.0, 0.76, 0.24),
         shape="stripes", title=["ORBIT", "RECORDS"], sub="NEW VINYL TONIGHT", glow=(0.8, 0.7)),
    dict(name="LUMEN CINEMA", c1=(0.01, 0.01, 0.05), c2=(0.12, 0.05, 0.3), acc=(0.75, 0.85, 1.0),
         shape="bars", title=["LUMEN", "CINEMA"], sub="LATE SHOW 2 AM", glow=(0.5, 0.75)),
]


def compose_poster(p):
    Wd, Ht = 1024, 512
    rows, cols = np.mgrid[0:Ht, 0:Wd]
    yy = rows / float(Ht - 1)
    xx = cols / float(Wd - 1)
    c1 = np.array(p["c1"])
    c2 = np.array(p["c2"])
    acc = np.array(p["acc"])
    img = c1[None, None, :] * (1 - yy[..., None]) + c2[None, None, :] * yy[..., None]
    gx, gy = p["glow"]
    g = np.exp(-(((xx - gx) * 1.6) ** 2 + ((yy - gy) * 1.2) ** 2) / 0.12)
    img = img + g[..., None] * acc[None, None, :] * 0.45
    if p["shape"] == "circle":
        cx, cy = 0.8 * Wd, 0.5 * Ht
        r = np.sqrt((cols - cx) ** 2 + (rows - cy) ** 2)
        ring = ((r > 0.3 * Ht) & (r < 0.33 * Ht)) | ((r > 0.36 * Ht) & (r < 0.37 * Ht))
        img[ring] = img[ring] * 0.2 + acc * 0.8
    elif p["shape"] == "stripes":
        st = (np.sin((cols + rows) * 0.06) > 0.55)
        img[st] = img[st] * 0.75 + acc * 0.25
    else:
        for k in range(6):
            x0 = int(Wd * (0.62 + 0.06 * k))
            h = int(Ht * (0.25 + 0.11 * ((k * 37) % 5)))
            img[Ht - h:Ht, x0:x0 + 26] = img[Ht - h:Ht, x0:x0 + 26] * 0.3 + acc * 0.7
    # text
    mask_main = np.zeros((Ht, Wd))
    mask_sub = np.zeros((Ht, Wd))
    title = p["title"]
    cap1 = 150 if len(title) == 2 else 190
    base = 250 if len(title) == 2 else 300
    maxw = Wd * 0.84
    for i, line in enumerate(title):
        w = text_px_width(line, cap1, maxw)
        raster_text(mask_main, line, (Wd - w) / 2.0, base + i * (cap1 * 1.25), cap1, maxw)
    subw = text_px_width(p["sub"], 52, maxw)
    raster_text(mask_sub, p["sub"], (Wd - subw) / 2.0, base + len(title) * cap1 * 1.25 + 90, 52, maxw)
    white = np.array([1.0, 0.97, 0.92])
    img = img * (1 - mask_main[..., None]) + mask_main[..., None] * white
    img = img * (1 - mask_sub[..., None]) + mask_sub[..., None] * acc
    return np.clip(img, 0.0, 1.0)


def save_png(rgb, name):
    h, w, _ = rgb.shape
    path = os.path.join(TEXD, name)
    img = bpy.data.images.new(os.path.splitext(name)[0], w, h, alpha=True)
    flat = np.flipud(rgb).astype(np.float32)
    rgba = np.concatenate([flat, np.ones((h, w, 1), np.float32)], axis=2)
    img.pixels.foreach_set(rgba.ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)
    return path


def skyline_texture():
    Wd, Ht = 2048, 512
    rng = np.random.default_rng(7)
    rows, cols = np.mgrid[0:Ht, 0:Wd]
    yy = rows / float(Ht - 1)
    top = np.array([0.02, 0.03, 0.07])
    bot = np.array([0.07, 0.09, 0.15])
    img = top[None, None, :] * (1 - yy[..., None]) + bot[None, None, :] * yy[..., None]
    x = 0
    while x < Wd:
        bw = int(rng.integers(40, 120))
        bh = int(rng.integers(120, 420))
        col = np.array([0.03, 0.035, 0.05]) * (0.8 + 0.4 * rng.random())
        img[Ht - bh:Ht, x:x + bw] = col
        for wy in range(Ht - bh + 10, Ht - 12, 12):
            for wx in range(x + 6, x + bw - 8, 9):
                if rng.random() < 0.35:
                    if rng.random() < 0.6:
                        lit = np.array([1.0, 0.72, 0.42])
                    else:
                        lit = np.array([0.7, 0.86, 1.0])
                    img[wy:wy + 6, wx:wx + 5] = lit * (0.55 + 0.45 * rng.random())
        x += bw
    return np.clip(img, 0, 1)


# ----------------------------------------------------------------------------- prop definitions

def p_lamp_sodium():
    pole = put(Geo(), cyl(0.16, 9.0, "M_Metal_Dark", sides=16, rings=10, r2=0.09))
    put(pole, cyl(0.26, 0.55, "M_Concrete", sides=16, rings=2))
    arm_pts = [(0.0, -1.8 * k / 10.0, 8.8 + 0.5 * math.sin(math.pi * 0.5 * k / 10.0)) for k in range(11)]
    pole.merge(tube(arm_pts, 0.045, "M_Metal_Dark", sides=8))
    head = put(Geo(), cyl(0.22, 0.16, "M_Metal_Dark", sides=14, rings=1, r2=0.15, z0=9.22), c=(0, -1.8, 0))
    put(head, cyl(0.25, 0.03, "M_Metal_Dark", sides=14, rings=1, z0=9.36), c=(0, -1.8, 0))
    lens = put(Geo(), cyl(0.19, 0.02, "M_Lamp_Sodium", sides=14, rings=1, z0=9.2), c=(0, -1.8, 0))
    put(lens, sphere(0.12, "M_Lamp_Sodium", seg=10, rings=6), c=(0, -1.8, 9.27))
    return dict(category="lamp", mount="ground", budget=(600, 1500), emissive=True,
                parts=[part("lamp_sodium_pole", pole), part("lamp_sodium_head", head, 0.0),
                       part("lamp_sodium_lens", lens)],
                lights=[light((0, -1.8, 9.1), [1.0, 0.70, 0.42], 14.0, 28.0, "spot", (0, 0, -1))],
                notes="Sodium single arm, 9 m pole, curved arm reaching -Y")


def p_lamp_led_double():
    pole = put(Geo(), cyl(0.13, 10.0, "M_Metal_Dark", sides=16, rings=10, r2=0.10))
    put(pole, cyl(0.24, 0.5, "M_Concrete", sides=16, rings=2))
    arms = Geo()
    arms.merge(tube([(0, 0, 9.8), (0.9, -0.2, 9.7)], 0.04, "M_Metal_Dark", sides=8))
    arms.merge(tube([(0, 0, 9.8), (-0.9, -0.2, 9.7)], 0.04, "M_Metal_Dark", sides=8))
    heads = Geo()
    for sx in (-0.9, 0.9):
        heads.merge(box((0.9, 0.45, 0.06), (sx, -0.2, 9.6), "M_Metal_Dark"))
    lenses = Geo()
    for sx in (-0.9, 0.9):
        lenses.merge(box((0.8, 0.36, 0.02), (sx, -0.2, 9.56), "M_Lamp_Cool"))
    return dict(category="lamp", mount="ground", budget=(600, 1500), emissive=True,
                parts=[part("lamp_led_pole", pole), part("lamp_led_arms", arms),
                       part("lamp_led_heads", heads, 0.01), part("lamp_led_lenses", lenses)],
                lights=[light((-0.9, -0.2, 9.5), [0.75, 0.85, 1.0], 10.0, 26.0, "spot", (0, 0, -1)),
                        light((0.9, -0.2, 9.5), [0.75, 0.85, 1.0], 10.0, 26.0, "spot", (0, 0, -1))],
                notes="Cool double-head LED, 10 m pole, two flat heads")


def p_traffic_light():
    mast = put(Geo(), cyl(0.09, 6.0, "M_Metal_Dark", sides=12, rings=6, r2=0.07))
    put(mast, cyl(0.2, 0.4, "M_Concrete", sides=12, rings=2))
    mast.merge(tube([(0, 0, 5.7), (0, -1.6, 5.7), (0, -3.2, 5.7)], 0.06, "M_Metal_Dark", sides=10))
    head = box((0.36, 0.3, 1.0), (0, -2.7, 4.7), "M_Metal_Dark")
    visors = Geo()
    lenses = {"red": Geo(), "amber": Geo(), "green": Geo()}
    zs = {"red": 5.05, "amber": 4.7, "green": 4.35}
    for k, z in zs.items():
        visors.merge(box((0.34, 0.14, 0.03), (0, -2.93, z + 0.2), "M_Metal_Dark"))
        mat = "M_Signal_Red" if k == "red" else "M_Signal_Off"
        put(lenses[k], cyl(0.12, 0.04, mat, sides=20, rings=1), c=(0, -2.85, z), rx=90)
    parts = [part("signal_mast", mast), part("signal_head", head, 0.01), part("signal_visors", visors, 0.005)]
    for k in ("red", "amber", "green"):
        parts.append(part("signal_lens_%s" % k, lenses[k]))
    return dict(category="lamp", mount="ground", budget=(600, 1500), emissive=True,
                parts=parts,
                lights=[light((0, -2.95, 5.05), [1.0, 0.23, 0.19], 6.0, 10.0, "omni")],
                notes="Baked state RED (only red lens emissive)")


def blade_sign(pid, lines, wp=1.4, hh=2.6, thick=0.12):
    """Vertical blade sign: a plate perpendicular to the wall (normal +X faces the street-side viewer
    on +X). Text reads along +Y on the +X face."""
    body = box((thick, wp, hh), (0, -wp / 2.0, 0), "M_SignBox")
    brackets = Geo()
    for z in (-hh / 2 + 0.25, hh / 2 - 0.25):
        brackets.merge(box((0.04, wp * 0.9, 0.04), (-0.12, -wp * 0.45, z), "M_Metal_Dark"))
    plate = box((0.25, 0.02, 0.7), (0, 0.01, 0), "M_Metal_Dark")
    m = 0.07 * wp
    txt = neon_lines(lines, wp - 2 * m, hh - 2 * m, 0.03,
                     (thick / 2 + 0.01, -wp + m, -hh / 2 + m), (0, 1, 0), (0, 0, 1), (1, 0, 0))
    first = lines[0][1]
    return dict(category="sign", mount="wall", budget=(400, 3000), emissive=True,
                parts=[part(pid + "_blade", body, 0.012), part(pid + "_neon", txt),
                       part(pid + "_brackets", brackets), part(pid + "_plate", plate)],
                lights=[light((0.5, -wp / 2, 0), MATS[first]["emission"], 1.5, 9.0)],
                notes="Blade sign, text on +X face, reads toward +Y")


def box_sign(pid, lines, width, h=1.0, d=0.22):
    body = box((width, d, h), (0, -d / 2.0, h / 2.0), "M_SignBox")
    m = 0.12
    txt = neon_lines(lines, width - 2 * m, h - 2 * m, 0.04,
                     (-width / 2 + m, -d - 0.012, m), (1, 0, 0), (0, 0, 1), (0, -1, 0))
    first = lines[0][1]
    return dict(category="sign", mount="wall", budget=(400, 3000), emissive=True,
                parts=[part(pid + "_box", body, 0.015), part(pid + "_neon", txt)],
                lights=[light((0, -d - 0.3, h / 2), MATS[first]["emission"], 2.0, 9.0)],
                notes="Fascia box sign %.0f m wide" % width)


def arrow_sign(pid):
    cz = 1.3
    pts = [(-1.0, -0.34), (0.2, -0.34), (0.2, -0.62), (1.0, 0.0), (0.2, 0.62), (0.2, 0.34), (-1.0, 0.34)]
    P = [(x, -0.22, cz + z) for x, z in pts]
    tube_g = tube(P, 0.045, "M_Neon_Amber", sides=6, closed=True)
    back = box((2.1, 0.1, 1.4), (0, -0.12, cz), "M_SignBox")
    txt = neon_lines([("NIGHT OWL", "M_Neon_Red"), ("DINER", "M_Neon_Red")], 0.8, 0.4, 0.03,
                     (-0.86, -0.27, cz - 0.2), (1, 0, 0), (0, 0, 1), (0, -1, 0))
    return dict(category="sign", mount="wall", budget=(400, 3000), emissive=True,
                parts=[part(pid + "_backing", back, 0.01), part(pid + "_arrow_tube", tube_g),
                       part(pid + "_neon", txt)],
                lights=[light((0.0, -0.6, cz), [1.0, 0.76, 0.24], 2.0, 9.0)],
                notes="Arrow sign pointing +X, neon tube outline")


def open24_sign(pid):
    body = box((1.6, 0.14, 0.9), (0, -0.07, 0.45), "M_SignBox")
    txt = neon_lines([("MOTO GARAGE", "M_Neon_Cyan"), ("24H", "M_Neon_Red"), ("OPEN", "M_Neon_White")],
                     1.46, 0.78, 0.03, (-0.73, -0.15, 0.06), (1, 0, 0), (0, 0, 1), (0, -1, 0))
    return dict(category="sign", mount="wall", budget=(400, 3000), emissive=True,
                parts=[part(pid + "_box", body, 0.01), part(pid + "_neon", txt)],
                lights=[light((0, -0.5, 0.45), [1.0, 0.23, 0.19], 2.0, 8.0)],
                notes="Open / 24H sign")


def billboard_sign(pid):
    panel = box((12.0, 0.18, 5.0), (0, -0.6, 6.5), "M_SignBox")
    g = Geo()
    g.merge(box((12.4, 0.2, 0.2), (0, 0.4, 4.0), "M_Metal_Grey"))
    g.merge(box((12.4, 0.2, 0.2), (0, 0.4, 9.0), "M_Metal_Grey"))
    for x in (-6.0, -3.0, 0.0, 3.0, 6.0):
        g.merge(box((0.2, 0.2, 5.0), (x, 0.4, 6.5), "M_Metal_Grey"))
    for x0 in (-6.0, -3.0, 0.0, 3.0):
        g.merge(strut((x0, 0.4, 4.0), (x0 + 3.0, 0.4, 9.0), 0.14, "M_Metal_Grey"))
        g.merge(strut((x0, 0.4, 9.0), (x0 + 3.0, 0.4, 4.0), 0.14, "M_Metal_Grey"))
    legs = Geo()
    for x in (-5.6, 5.6):
        legs.merge(box((0.3, 0.3, 4.4), (x, 0.4, 2.2), "M_Metal_Grey"))
        legs.merge(strut((x, 0.4, 0.0), (x, 0.4, 4.0), 0.02, "M_Metal_Grey"))
    cat = Geo()
    cat.merge(box((12.0, 1.0, 0.1), (0, -1.1, 3.9), "M_Metal_Grey"), None)
    for x in (-5.8, -2.9, 0.0, 2.9, 5.8):
        cat.merge(box((0.08, 0.08, 0.7), (x, -1.1, 4.25), "M_Metal_Grey"))
    cat.merge(tube([(-6.0, -1.6, 4.6), (6.0, -1.6, 4.6)], 0.03, "M_Metal_Grey", sides=6))
    txt = neon_lines([("ZENITH TOWER", "M_Neon_Cyan")], 11.2, 1.5, 0.05,
                     (-5.6, -0.71, 7.25), (1, 0, 0), (0, 0, 1), (0, -1, 0))
    return dict(category="sign", mount="roof", budget=(400, 3000), emissive=True,
                parts=[part(pid + "_panel", panel, 0.02), part(pid + "_neon", txt),
                       part(pid + "_lattice", g), part(pid + "_legs", legs),
                       part(pid + "_catwalk", cat, 0.01)],
                lights=[light((0, -1.4, 9.4), [0.1, 0.9, 1.0], 1.0, 14.0)],
                notes="12 x 5 m rooftop billboard, lattice, catwalk")


def poster_prop(i):
    u = (lambda co: ((co.x + 1.0) / 2.0, (co.z) / 1.0))
    quad = Geo().add([(-1, -0.03, 0), (1, -0.03, 0), (1, -0.03, 1.0), (-1, -0.03, 1.0)],
                     [(0, 1, 2, 3)], "M_Poster_%02d" % i, False)
    frame = box((2.1, 0.05, 1.1), (0, 0.0, 0.5), "M_Metal_Dark")
    return dict(category="poster", mount="wall", budget=None, emissive=True,
                parts=[part("poster_%02d_plane" % i, quad, 0.0, u), part("poster_%02d_frame" % i, frame, 0.01)],
                lights=[], notes="Billboard poster plane 2 x 1 m, back-lit")


def p_bus_shelter():
    g = Geo()
    for x in (-1.55, 1.55):
        for y in (0.15, -0.65):
            g.merge(box((0.07, 0.07, 2.6), (x, y, 1.3), "M_Metal_Dark"))
    roof = box((3.4, 1.6, 0.12), (0, -0.25, 2.66), "M_Metal_Dark")
    back = box((3.0, 0.02, 1.9), (0, 0.13, 1.25), "M_Glass")
    front = box((3.0, 0.02, 1.9), (0, -0.67, 1.25), "M_Glass")
    side = box((0.02, 1.4, 1.9), (1.55, -0.25, 1.25), "M_Glass")
    ad = box((1.5, 0.08, 1.6), (0, 0.05, 1.5), "M_Metal_Dark")
    uvn = (lambda co: ((co.x + 0.75) / 1.5, (co.z - 0.7) / 1.6))
    poster = Geo().add([(-0.75, -0.02, 0.7), (0.75, -0.02, 0.7), (0.75, -0.02, 2.3), (-0.75, -0.02, 2.3)],
                       [(0, 1, 2, 3)], "M_Poster_01", False)
    bench = box((2.6, 0.45, 0.08), (0, -0.25, 0.45), "M_Wood_Dark")
    for x in (-1.1, 1.1):
        bench.merge(box((0.08, 0.4, 0.42), (x, -0.25, 0.21), "M_Metal_Dark"))
    return dict(category="furniture", mount="ground", budget=(200, 1200), emissive=True,
                parts=[part("bus_shelter_frame", g), part("bus_shelter_roof", roof, 0.01),
                       part("bus_shelter_glass_back", back), part("bus_shelter_glass_front", front),
                       part("bus_shelter_glass_side", side), part("bus_shelter_ad_box", ad, 0.01),
                       part("bus_shelter_ad_panel", poster, 0.0, uvn), part("bus_shelter_bench", bench, 0.005)],
                lights=[light((0, -0.1, 2.2), [1.0, 0.92, 0.8], 3.0, 6.0)],
                notes="Bus shelter, lit advert panel on the back wall")


def p_bollard():
    g = put(Geo(), cyl(0.12, 0.85, "M_Bollard", sides=24, rings=4, r2=0.12))
    put(g, cyl(0.12, 0.08, "M_Metal_Dark", sides=24, rings=2, r2=0.1), c=(0, 0, 0.85))
    put(g, cyl(0.2, 0.1, "M_Metal_Dark", sides=24, rings=1, r2=0.12), c=(0, 0, 0.0))
    return dict(category="furniture", mount="ground", budget=(200, 1200), emissive=False,
                parts=[part("bollard", g)], lights=[], notes="Bollard")


def p_litter_bin():
    g = put(Geo(), cyl(0.3, 0.9, "M_Metal_Green", sides=16, rings=3, r2=0.27))
    put(g, cyl(0.31, 0.06, "M_Metal_Dark", sides=16, rings=1), c=(0, 0, 0.9))
    slot = box((0.3, 0.02, 0.06), (0, -0.28, 0.9), "M_Metal_Dark")
    g.merge(slot)
    return dict(category="furniture", mount="ground", budget=(200, 1200), emissive=False,
                parts=[part("litter_bin", g, 0.0)], lights=[], notes="Litter bin")


def p_bench():
    g = Geo()
    for k in range(5):
        g.merge(box((1.8, 0.07, 0.04), (0, -0.28 + k * 0.1, 0.45), "M_Wood_Dark"))
    for k in range(3):
        g.merge(box((1.8, 0.05, 0.06), (0, -0.4, 0.8 + k * 0.1), "M_Wood_Dark"))
    for x in (-0.75, 0.75):
        g.merge(box((0.07, 0.07, 0.45), (x, -0.25, 0.225), "M_Metal_Dark"))
        g.merge(box((0.07, 0.5, 0.07), (x, -0.25, 0.04), "M_Metal_Dark"))
        g.merge(box((0.07, 0.07, 0.4), (x, 0.0, 0.8), "M_Metal_Dark"))
        g.merge(box((0.07, 0.07, 0.16), (x, -0.45, 0.55), "M_Metal_Dark"))
        g.merge(box((0.07, 0.42, 0.07), (x, -0.25, 0.55), "M_Metal_Dark"))
    for k in range(3):
        g.merge(box((0.12, 0.03, 0.06), (-0.6 + 0.6 * k, 0.09, 0.9), "M_Wood_Dark"))
    return dict(category="furniture", mount="ground", budget=(200, 1200), emissive=False,
                parts=[part("bench", g, 0.0)], lights=[], notes="Bench")


def p_planter():
    g = box((1.2, 0.5, 0.5), (0, 0, 0.25), "M_Concrete")
    shrub = Geo()
    for (x, y, z, r) in ((-0.35, 0.0, 0.85, 0.3), (0.0, 0.05, 0.95, 0.36), (0.35, 0.0, 0.85, 0.3),
                         (-0.15, -0.1, 0.65, 0.25), (0.2, -0.05, 0.7, 0.24)):
        put(shrub, sphere(r, "M_Foliage", seg=10, rings=6), c=(x, y, z))
    return dict(category="furniture", mount="ground", budget=(200, 1200), emissive=False,
                parts=[part("planter_box", g, 0.01), part("planter_shrub", shrub)], lights=[],
                notes="Planter with low-poly shrub")


def p_newspaper_box():
    g = box((0.55, 0.5, 1.1), (0, 0, 0.55), "M_Metal_Red")
    g.merge(box((0.4, 0.02, 0.4), (0, -0.26, 0.7), "M_Glass"))
    g.merge(box((0.45, 0.05, 0.06), (0, -0.27, 0.45), "M_Metal_Dark"))
    return dict(category="furniture", mount="ground", budget=(200, 1200), emissive=False,
                parts=[part("newspaper_box", g, 0.01)], lights=[], notes="Newspaper box")


def p_fire_hydrant():
    g = put(Geo(), cyl(0.14, 0.1, "M_Metal_Dark", sides=16, rings=1))
    put(g, cyl(0.11, 0.55, "M_Hydrant_Red", sides=16, rings=3, r2=0.1), c=(0, 0, 0.1))
    put(g, cyl(0.1, 0.1, "M_Hydrant_Red", sides=16, rings=2, r2=0.07), c=(0, 0, 0.65))
    for y in (-0.13, 0.13):
        put(g, cyl(0.04, 0.14, "M_Metal_Grey", sides=12, rings=1), c=(0, y, 0.38), rx=90 * (1 if y < 0 else -1))
    return dict(category="furniture", mount="ground", budget=(200, 1200), emissive=False,
                parts=[part("fire_hydrant", g)], lights=[], notes="Fire hydrant")


def p_utility_cabinet():
    g = box((1.1, 0.45, 1.5), (0, -0.225, 0.75), "M_Metal_Green")
    for z in (0.3, 1.2):
        g.merge(box((1.0, 0.02, 0.02), (0, -0.46, z), "M_Metal_Dark"))
    for k in range(5):
        g.merge(box((0.6, 0.03, 0.03), (0, -0.46, 0.5 + k * 0.12), "M_Metal_Dark"))
    g.merge(box((0.2, 0.02, 0.2), (0.35, -0.47, 0.8), "M_Metal_Grey"))
    return dict(category="furniture", mount="ground", budget=(200, 1200), emissive=False,
                parts=[part("utility_cabinet", g, 0.012)], lights=[], notes="Utility cabinet")


def p_market_stall():
    g = Geo()
    for x in (-1.1, 1.1):
        for y in (0.9, -0.9):
            put(g, cyl(0.04, 2.5, "M_Metal_Dark", sides=10, rings=1), c=(x, y, 0))
    g.merge(box((2.2, 0.6, 0.9), (0, 0.1, 0.45), "M_Wood_Dark"))
    g.merge(box((2.4, 0.04, 0.08), (0, -0.8, 1.0), "M_Wood_Dark"))
    n = 6
    for k in range(n):
        x0 = -1.3 + 2.6 * k / n
        x1 = -1.3 + 2.6 * (k + 1) / n
        mat = "M_Awning_A" if k % 2 == 0 else "M_Awning_B"
        g.add([(x0, -1.3, 2.5), (x1, -1.3, 2.5), (x1, -0.5, 2.1), (x0, -0.5, 2.1)],
              [(0, 1, 2, 3)], mat, False)
    g.merge(box((2.6, 0.04, 0.12), (0, -0.5, 2.1), "M_Awning_A"))
    for k in range(4):
        g.merge(box((0.3, 0.3, 0.2), (-0.8 + k * 0.55, 0.25, 0.1 + 0.2 * (k % 2)), "M_Wood_Dark"))
    return dict(category="furniture", mount="ground", budget=(200, 1200), emissive=False,
                parts=[part("market_stall", g, 0.0)], lights=[], notes="Market stall with striped awning")


def p_roller_shutter():
    g = box((2.4, 0.08, 2.2), (0, 0, 1.1), "M_Shutter")
    for k in range(22):
        g.merge(box((2.36, 0.06, 0.05), (0, -0.07, 0.1 + k * 0.095), "M_Shutter"))
    g.merge(box((2.5, 0.12, 0.1), (0, -0.04, 2.25), "M_Metal_Grey"))
    for x in (-1.25, 1.25):
        g.merge(box((0.1, 0.12, 2.3), (x, -0.04, 1.15), "M_Metal_Grey"))
    return dict(category="furniture", mount="ground", budget=(200, 1200), emissive=False,
                parts=[part("roller_shutter", g, 0.0)], lights=[], notes="Roller shutter panel")


def p_jersey_barrier():
    g = prism_x([(-0.30, 0.0), (0.30, 0.0), (0.30, 0.25), (-0.30, 0.25)], -1.0, 1.0, "M_Concrete")
    g.merge(prism_x([(-0.30, 0.25), (0.30, 0.25), (0.10, 0.74), (-0.10, 0.74)], -1.0, 1.0, "M_Concrete"))
    g.merge(prism_x([(-0.13, 0.74), (0.13, 0.74), (0.13, 0.80), (-0.13, 0.80)], -1.0, 1.0, "M_Concrete"))
    return dict(category="circuit", mount="ground", budget=None, emissive=False,
                parts=[part("jersey_barrier", g),
                       part("jersey_barrier-colonly", box((2.0, 0.6, 0.8), (0, 0, 0.4), "M_Collider"))],
                lights=[], notes="Jersey barrier 2 m, box collider -colonly")


def p_guardrail():
    g = Geo()
    prof = [(-0.10, 0.66), (-0.035, 0.72), (0.035, 0.66), (0.10, 0.72)]
    for x0 in (0.0, 2.0):
        for i in range(3):
            g.merge(slab_x(prof[i], prof[i + 1], x0, x0 + 2.0, 0.006, "M_Metal_Grey"))
    for x in (0.0, 2.0, 4.0):
        g.merge(box((0.12, 0.12, 0.85), (x, 0.0, 0.425), "M_Metal_Grey"))
    return dict(category="circuit", mount="ground", budget=None, emissive=False,
                parts=[part("guardrail_segment", g, 0.0),
                       part("guardrail_segment-colonly", box((4.0, 0.2, 0.8), (2.0, 0.0, 0.4), "M_Collider"))],
                lights=[], notes="Steel guardrail 4 m, box collider -colonly")


def p_chevron_board():
    g = box((0.7, 0.05, 1.0), (0, -0.12, 1.8), "M_Chevron_White")
    red = Geo()
    for zc in (1.55, 1.9):
        for sx, ang in ((-0.12, 40), (0.12, -40)):
            xf = Matrix.Translation(Vector((sx, -0.16, zc))) @ Matrix.Rotation(math.radians(ang), 4, "Y")
            red.merge(box((0.42, 0.04, 0.1), (0, 0, 0), "M_Chevron_Red"), xf)
    post = box((0.06, 0.06, 1.6), (0, 0.1, 0.8), "M_Metal_Grey")
    return dict(category="circuit", mount="ground", budget=None, emissive=False,
                parts=[part("chevron_board", g, 0.005), part("chevron_stripes", red), part("chevron_post", post)],
                lights=[], notes="Chevron board, reflective red/white")


def p_traffic_cone():
    g = cyl(0.2, 0.7, "M_Cone_Orange", sides=16, rings=4, r2=0.03)
    band1 = cyl(0.17, 0.08, "M_Cone_White", sides=16, rings=1, r2=0.15, z0=0.3)
    band2 = cyl(0.1, 0.05, "M_Cone_White", sides=16, rings=1, r2=0.085, z0=0.5)
    base = box((0.5, 0.5, 0.04), (0, 0, 0.02), "M_Collider")
    return dict(category="circuit", mount="ground", budget=None, emissive=False,
                parts=[part("traffic_cone", g), part("traffic_cone_bands", band1.merge(band2)),
                       part("traffic_cone_base", base, 0.005)],
                lights=[], notes="Traffic cone")


def p_quay_railing():
    g = Geo()
    for x in (0.0, 1.0, 2.0):
        g.merge(box((0.06, 0.06, 1.0), (x, 0.0, 0.5), "M_Metal_Grey"))
    g.merge(tube([(0.0, 0.0, 1.0), (2.0, 0.0, 1.0)], 0.03, "M_Metal_Grey", sides=8))
    g.merge(tube([(0.0, 0.0, 0.5), (2.0, 0.0, 0.5)], 0.02, "M_Metal_Grey", sides=8))
    for k in range(20):
        x = 0.05 + k * 0.1
        g.merge(box((0.02, 0.02, 0.85), (x, 0.0, 0.575), "M_Metal_Grey"))
    return dict(category="circuit", mount="ground", budget=None, emissive=False,
                parts=[part("quay_railing", g, 0.0)], lights=[], notes="Quay railing 2 m")


def p_tunnel_fan():
    housing = put(Geo(), cyl(0.7, 0.45, "M_Metal_Grey", sides=24, rings=2), rx=90)
    grille = put(Geo(), cyl(0.62, 0.03, "M_Metal_Dark", sides=24, rings=1), c=(0, -0.45, 0), rx=90)
    blades = Geo()
    for k in range(6):
        blade = box((0.08, 0.03, 0.55), (0, 0.0, 0.3), "M_Metal_Dark")
        blades.merge(blade, Matrix.Translation(Vector((0, -0.22, 0))) @ Matrix.Rotation(math.radians(60 * k), 4, "Y"))
    return dict(category="circuit", mount="wall", budget=None, emissive=False,
                parts=[part("tunnel_fan_housing", housing, 0.0), part("tunnel_fan_grille", grille),
                       part("tunnel_fan_blades", blades)],
                lights=[], notes="Tunnel ventilation fan, origin on wall")


def p_tunnel_wall_light():
    plate = box((1.2, 0.06, 0.12), (0, -0.03, 0.0), "M_Metal_Grey")
    strip = box((1.0, 0.012, 0.03), (0, -0.07, 0.0), "M_Lamp_Cool")
    return dict(category="circuit", mount="wall", budget=None, emissive=True,
                parts=[part("tunnel_wall_light_plate", plate, 0.01), part("tunnel_wall_light_strip", strip)],
                lights=[light((0, -0.12, 0.0), [0.75, 0.85, 1.0], 6.0, 14.0)],
                notes="Tunnel wall light fixture, origin on wall")


def p_cable_span():
    g = Geo()
    g.merge(box((0.25, 0.25, 7.0), (0, 0, 3.5), "M_Metal_Dark"))
    g.merge(box((0.25, 0.25, 7.0), (20.0, 0, 3.5), "M_Metal_Dark"))
    cable = []
    for k in range(41):
        x = 20.0 * k / 40.0
        z = 6.9 - 1.0 * (1 - ((x - 10.0) / 10.0) ** 2)
        cable.append((x, 0.0, z))
    g.merge(tube(cable, 0.025, "M_Metal_Dark", sides=6))
    for x in (5.0, 10.0, 15.0):
        z = 6.9 - 1.0 * (1 - ((x - 10.0) / 10.0) ** 2)
        g.merge(tube([(x, 0, z), (x, 0, z - 1.0)], 0.012, "M_Metal_Dark", sides=6))
    return dict(category="overhead", mount="span", budget=None, emissive=False,
                parts=[part("cable_span", g)], lights=[],
                notes="Cable span 20 m, origin at left anchor base")


def p_string_lights():
    wire = []
    for k in range(33):
        x = 16.0 * k / 32.0
        z = -0.6 - 0.9 * (1 - ((x - 8.0) / 8.0) ** 2)
        wire.append((x, 0.0, z))
    g = tube(wire, 0.012, "M_Metal_Dark", sides=6)
    bulbs = Geo()
    lights = []
    for i in range(16):
        x = 0.5 + i
        z = -0.6 - 0.9 * (1 - ((x - 8.0) / 8.0) ** 2) - 0.1
        mat = "M_Bulb_Amber" if i % 2 == 0 else "M_Bulb_Red"
        put(bulbs, sphere(0.06, mat, seg=6, rings=4), c=(x, 0.0, z))
        if i % 4 == 0:
            col = [1.0, 0.7, 0.3] if i % 2 == 0 else [1.0, 0.2, 0.15]
            lights.append(light((x, 0.0, z), col, 0.4, 5.0))
    return dict(category="overhead", mount="span", budget=None, emissive=True,
                parts=[part("string_lights_wire", g), part("string_lights_bulbs", bulbs)],
                lights=lights, notes="String lights 16 m, origin at left anchor; 4 representative lights")


def p_container_stack():
    g = Geo()
    rng = random.Random(11)
    mats = ["M_Container_Red", "M_Container_Blue", "M_Container_Green", "M_Container_Grey"]
    for i in range(3):
        for j in range(2):
            for k in range(2):
                x = (i - 1) * 6.06
                y = (j - 0.5) * 2.44
                z = 1.295 + k * 2.59
                m = mats[(i + 2 * j + k) % 4]
                g.merge(box((6.06, 2.44, 2.59), (x, y, z), m))
                for r in range(6):
                    xr = x - 2.5 + r * 1.0
                    for side in (-1, 1):
                        g.merge(box((0.1, 0.05, 2.3), (xr, y + side * 1.245, z), m))
    return dict(category="bay", mount="ground", budget=None, emissive=False,
                parts=[part("container_stack", g, 0.0)], lights=[],
                notes="Container stack 3x2x2, four colours")


def p_gantry_crane():
    g = Geo()
    H = 45.0
    bays = 9
    dz = H / bays

    def corners(z, hw):
        return [(hw, hw, z), (-hw, hw, z), (-hw, -hw, z), (hw, -hw, z)]

    base = corners(0.0, 2.0)
    top = corners(H, 0.9)
    for i in range(4):
        g.merge(strut(base[i], top[i], 0.3, "M_Crane"))
    for b in range(1, bays + 1):
        z = b * dz
        hw = 2.0 + (0.9 - 2.0) * (b / float(bays))
        cs = corners(z, hw)
        zb = (b - 1) * dz
        hwb = 2.0 + (0.9 - 2.0) * ((b - 1) / float(bays))
        cb = corners(zb, hwb)
        for i in range(4):
            g.merge(strut(cs[i], cs[(i + 1) % 4], 0.2, "M_Crane"))
            g.merge(strut(cb[i], cs[(i + 1) % 4], 0.12, "M_Crane"))
            g.merge(strut(cb[(i + 1) % 4], cs[i], 0.12, "M_Crane"))
    boom_len = 52.0
    nb = 10
    bl = boom_len / nb
    for k in range(nb):
        x0 = k * bl
        x1 = (k + 1) * bl
        for y in (-0.9, 0.9):
            g.merge(strut((x0, y, H), (x1, y, H), 0.2, "M_Crane"))
            g.merge(strut((x0, y, H - 1.8), (x1, y, H - 1.8), 0.16, "M_Crane"))
            g.merge(strut((x0, y, H), (x0, y, H - 1.8), 0.14, "M_Crane"))
        g.merge(strut((x0, -0.9, H), (x1, 0.9, H - 1.8), 0.1, "M_Crane"))
        g.merge(strut((x0, 0.9, H), (x1, -0.9, H - 1.8), 0.1, "M_Crane"))
    g.merge(box((3.0, 2.2, 1.6), (-4.0, 0.0, H - 1.2), "M_Crane"))
    g.merge(strut((0.0, 0.0, H - 1.2), (-2.5, 0.0, H - 1.2), 0.4, "M_Crane"))
    tips = Geo()
    put(tips, sphere(0.3, "M_Neon_Red", seg=8, rings=4), c=(0, 0, H + 0.6))
    put(tips, sphere(0.3, "M_Neon_Red", seg=8, rings=4), c=(boom_len, 0, H - 0.9))
    return dict(category="bay", mount="ground", budget=(0, 4000), emissive=True,
                parts=[part("gantry_crane_lattice", g, 0.0), part("gantry_crane_tip_lights", tips)],
                lights=[light((0, 0, H + 0.6), [1.0, 0.23, 0.19], 4.0, 40.0),
                        light((boom_len, 0, H - 0.9), [1.0, 0.23, 0.19], 4.0, 40.0)],
                notes="Gantry crane silhouette 45 m, red tip lights")


def p_skyline_card():
    Rc = 900.0
    L = 400.0
    a = L / Rc
    N = 40
    Hh = 120.0
    V = []
    for i in range(N + 1):
        th = -a / 2 + a * i / N
        x = Rc * math.sin(th)
        y = -Rc + Rc * math.cos(th)
        V.append((x, y, 0.0))
    for i in range(N + 1):
        x, y, _ = V[i]
        V.append((x, y, Hh))
    F = []
    for i in range(N):
        F.append((i, i + 1, N + 2 + i, N + 1 + i))
    g = Geo().add(V, F, "M_Skyline", False)
    uv = (lambda co: ((co.x + 200.0) / 400.0, co.z / Hh))
    return dict(category="bay", mount="ground", budget=None, emissive=True,
                parts=[part("skyline_card", g, 0.0, uv)], lights=[],
                notes="Far skyline curved card, 400 m long, night texture")


def prop_registry():
    reg = {}
    reg["lamp_sodium"] = p_lamp_sodium()
    reg["lamp_led_double"] = p_lamp_led_double()
    reg["traffic_light"] = p_traffic_light()
    sign_defs = [
        ("sign_blade_kirin_noodle_bar", "blade", [("KOI", "M_Neon_Cyan"), ("NOODLE", "M_Neon_Cyan"), ("BAR", "M_Neon_Magenta")]),
        ("sign_blade_hotel_arden", "blade", [("HOTEL", "M_Neon_Magenta"), ("ARDEN", "M_Neon_Magenta")]),
        ("sign_blade_pixel_arcade", "blade", [("PIXEL", "M_Neon_Cyan"), ("ARCADE", "M_Neon_Amber")]),
        ("sign_blade_syndicate_club", "blade", [("SYNDICATE", "M_Neon_Magenta"), ("CLUB", "M_Neon_Cyan")]),
        ("sign_blade_kapi_doner", "blade", [("KAPI", "M_Neon_Amber"), ("DONER", "M_Neon_Red")]),
        ("sign_box_lumen_cinema_4m", "box4", [("LUMEN CINEMA", "M_Neon_Amber")]),
        ("sign_box_volt_energy_4m", "box4", [("AMPERE ENERGY", "M_Neon_Magenta")]),
        ("sign_box_orbit_records_8m", "box8", [("ORBIT RECORDS", "M_Neon_Cyan")]),
        ("sign_box_blue_heron_sushi_8m", "box8", [("BLUE HERON SUSHI", "M_Neon_Cyan")]),
    ]
    for sid, kind, lines in sign_defs:
        if kind == "blade":
            reg[sid] = blade_sign(sid, lines)
        elif kind == "box4":
            reg[sid] = box_sign(sid, lines, 4.0)
        else:
            reg[sid] = box_sign(sid, lines, 8.0)
    reg["sign_arrow_night_owl_diner"] = arrow_sign("sign_arrow_night_owl_diner")
    reg["sign_open24h_moto_garage"] = open24_sign("sign_open24h_moto_garage")
    reg["sign_billboard_zenith_tower_12x5"] = billboard_sign("sign_billboard_zenith_tower_12x5")
    for i in range(1, 7):
        reg["poster_%02d" % i] = poster_prop(i)
    reg["bus_shelter"] = p_bus_shelter()
    reg["bollard"] = p_bollard()
    reg["litter_bin"] = p_litter_bin()
    reg["bench"] = p_bench()
    reg["planter_shrub"] = p_planter()
    reg["newspaper_box"] = p_newspaper_box()
    reg["fire_hydrant"] = p_fire_hydrant()
    reg["utility_cabinet"] = p_utility_cabinet()
    reg["market_stall"] = p_market_stall()
    reg["roller_shutter"] = p_roller_shutter()
    reg["jersey_barrier"] = p_jersey_barrier()
    reg["guardrail_segment"] = p_guardrail()
    reg["chevron_board"] = p_chevron_board()
    reg["traffic_cone"] = p_traffic_cone()
    reg["quay_railing"] = p_quay_railing()
    reg["tunnel_fan"] = p_tunnel_fan()
    reg["tunnel_wall_light"] = p_tunnel_wall_light()
    reg["cable_span"] = p_cable_span()
    reg["string_lights_span"] = p_string_lights()
    reg["container_stack"] = p_container_stack()
    reg["gantry_crane"] = p_gantry_crane()
    reg["skyline_card"] = p_skyline_card()
    return reg


def main():
    define_materials()
    # generated, project-owned textures first (materials load them)
    for i, p in enumerate(POSTERS, start=1):
        save_png(compose_poster(p), "poster_%02d.png" % i)
    save_png(skyline_texture(), "skyline_night.png")
    log("textures written")

    reg = prop_registry()
    records = []
    for pid, spec in reg.items():
        rec = build_prop(pid, spec)
        records.append(rec)
        log("%-34s tris=%5d lod1=%s col=%d size=%s" % (pid, rec["tris"], rec["lod1_tris"],
                                                      rec["collider_tris"], rec["size"]))

    # materials.json: every material slot the props reference, with its intended look
    used = set()
    for r in records:
        used.update(r["materials"])
    mats_out = {}
    for name in sorted(used):
        s = MATS[name]
        mats_out[name] = {
            "base_color": [round(c, 3) for c in s["base"]],
            "roughness": s["roughness"],
            "metallic": s["metallic"],
            "emission_color": [round(c, 3) for c in s["emission"]] if s["emission"] else None,
            "emission_strength": s["emission_strength"],
            "texture": s["texture"],
            "uv_tiling_m": s["uv_tiling_m"],
            "source": "generated, project-owned" if s["texture"] else "flat colour",
        }
    with open(os.path.join(OUT, "materials.json"), "w", encoding="utf-8") as f:
        json.dump({"textures_relative_to": "out/", "materials": mats_out}, f, indent=2)

    catalog = {"coords": "godot_y_up", "source": "assets_src/world/kit_props/build_props.py",
               "items": []}
    for r in records:
        catalog["items"].append({
            "id": r["id"], "category": r["category"], "file": r["file"], "size": r["size"],
            "tris": r["tris"], "lod1_tris": r["lod1_tris"], "lod1_file": r["lod1_file"],
            "collider_tris": r["collider_tris"], "materials": r["materials"],
            "lights": r["lights"], "emissive": r["emissive"], "mount": r["mount"], "notes": r["notes"],
        })
    with open(os.path.join(OUT, "catalog.json"), "w", encoding="utf-8") as f:
        json.dump(catalog, f, indent=2)

    checks = []
    for r in records:
        b = r["budget"]
        if b is not None:
            ok = b[0] <= r["tris"] <= b[1]
            checks.append({"id": r["id"], "check": "tri_budget", "tris": r["tris"], "range": list(b), "pass": ok})
        if r["tris"] > 800:
            ok = r["lod1_tris"] is not None and r["lod1_tris"] <= 0.35 * r["tris"]
            checks.append({"id": r["id"], "check": "lod1_le_35pct", "lod1": r["lod1_tris"], "pass": bool(ok)})
    report = {"props": records, "checks": checks,
              "all_pass": all(c["pass"] for c in checks),
              "generated_textures": ["textures/poster_%02d.png" % i for i in range(1, 7)] + ["textures/skyline_night.png"]}
    with open(os.path.join(OUT, "report.json"), "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    log("done: %d props, all_pass=%s" % (len(records), report["all_pass"]))


if __name__ == "__main__":
    main()
