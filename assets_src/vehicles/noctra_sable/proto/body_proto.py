"""Lead's proof of the body surface spec (docs/art/CAR_01_BODY_SURFACE_SPEC.md).
Clay body only: evaluates the surface, cuts arches, renders 4 views. Not the final generator.
blender --background --factory-startup --python body_proto.py
"""
import bpy, bmesh, math, os
import numpy as np

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "renders")
os.makedirs(OUT, exist_ok=True)


def pchip(pts):
    xs = np.array([p[0] for p in pts], float)
    ys = np.array([p[1] for p in pts], float)
    h = np.diff(xs)
    d = np.diff(ys) / h
    m = np.zeros_like(xs)
    m[0], m[-1] = d[0], d[-1]
    for i in range(1, len(xs) - 1):
        if d[i - 1] * d[i] > 0:
            w1, w2 = 2 * h[i] + h[i - 1], h[i] + 2 * h[i - 1]
            m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])

    def f(x):
        x = np.clip(x, xs[0], xs[-1])
        i = np.clip(np.searchsorted(xs, x) - 1, 0, len(xs) - 2)
        t = (x - xs[i]) / h[i]
        return ((2 * t**3 - 3 * t**2 + 1) * ys[i] + (t**3 - 2 * t**2 + t) * h[i] * m[i]
                + (-2 * t**3 + 3 * t**2) * ys[i + 1] + (t**3 - t**2) * h[i] * m[i + 1])
    return f


Z_TOP = pchip([(0, .400), (.10, .470), (.40, .575), (.95, .670), (1.28, .760), (1.60, .950), (1.90, 1.130),
               (2.05, 1.190), (2.40, 1.170), (2.80, 1.080), (3.30, .975), (3.80, .905), (4.20, .888),
               (4.38, .905), (4.45, .895)])
Z_BOT = pchip([(0, .220), (.15, .135), (.50, .110), (3.70, .110), (4.05, .165), (4.45, .300)])
W_MAX = pchip([(0, .620), (.06, .775), (.25, .880), (.95, .972), (1.50, .930), (2.30, .918), (3.00, .952),
               (3.61, .980), (4.10, .950), (4.40, .900), (4.45, .860)])
Z_SH = pchip([(0, .380), (.12, .495), (.50, .655), (.95, .772), (1.40, .760), (2.00, .742), (2.70, .780),
              (3.20, .850), (3.61, .888), (4.10, .880), (4.45, .872)])
N_TOP = pchip([(0, 2.0), (1.10, 2.2), (1.45, 3.4), (2.05, 3.6), (3.00, 3.3), (3.70, 2.4), (4.45, 2.0)])
SHELF = pchip([(0, 0), (1.20, 0), (1.55, .055), (3.00, .060), (3.70, 0), (4.45, 0)])


def catmull(P, n):
    P = np.array(P, float)
    Q = np.vstack([2 * P[0] - P[1], P, 2 * P[-1] - P[-2]])
    out = []
    segs = len(P) - 1
    for k in range(n):
        u = k / (n - 1) * segs
        i = min(int(u), segs - 1)
        t = u - i
        p0, p1, p2, p3 = Q[i], Q[i + 1], Q[i + 2], Q[i + 3]
        out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                          + (-p0 + 3 * p1 - 3 * p2 + p3) * t**3))
    return np.array(out)


N_SIDE, N_TOPPTS = 22, 26


def section(s):
    zt, zb, w, zs, n, sh = (float(f(s)) for f in (Z_TOP, Z_BOT, W_MAX, Z_SH, N_TOP, SHELF))
    H = zs - zb
    xs_ = w - 0.115
    side = catmull([(0.0, zb), (w - .130, zb), (w - .065, zb + .045), (w - .022, zb + .30 * H),
                    (w, zb + .62 * H), (w - .018, zs - .060), (w - .060, zs - .012), (xs_, zs)], N_SIDE)
    side[0] = (0.0, zb)
    xg = xs_ - sh
    top = []
    for k in range(1, N_TOPPTS + 1):
        u = k / N_TOPPTS
        u = u ** 0.75  # denser near the shoulder
        x = xs_ * (1 - u)
        if x > xg:
            z = zs - 0.005 * (xs_ - x) / max(sh, 1e-6)
        else:
            q = (xg - x) / xg
            z = (zs - (0.005 if sh > 1e-6 else 0.0)) + (zt - zs) * (1 - (1 - q) ** n)
        top.append((x, z))
    return np.vstack([side, np.array(top)])


def stations():
    a = np.linspace(0, 0.30, 16)
    b = np.linspace(0.30, 1.20, 22)[1:]
    c = np.linspace(1.20, 2.10, 30)[1:]
    d = np.linspace(2.10, 4.20, 44)[1:]
    e = np.linspace(4.20, 4.45, 12)[1:]
    return np.concatenate([a, b, c, d, e])


def build_body():
    S = stations()
    rings = [(s, section(s)) for s in S]
    # nose closure
    s0, sec0 = rings[0]
    c = sec0.mean(axis=0)
    pre = []
    for scale, fwd in ((0.5, 0.040), (0.82, 0.025)):
        sec = c + (sec0 - c) * scale
        sec[:, 0] = np.maximum(sec[:, 0], 0)
        sec[0, 0] = 0
        sec[-1, 0] = 0
        pre.append((s0 - fwd, sec))
    sN, secN = rings[-1]
    cN = secN.mean(axis=0)
    post = cN + (secN - cN) * 0.965
    post[0, 0] = 0
    post[-1, 0] = 0
    rings = pre + rings + [(sN + 0.018, post)]

    bm = bmesh.new()
    grid = []
    npts = N_SIDE + N_TOPPTS
    for s, sec in rings:
        y = s - 2.28
        row_r = [bm.verts.new((float(x), y, float(z))) for x, z in sec]
        row_l = [row_r[0]] + [bm.verts.new((-float(x), y, float(z))) for x, z in sec[1:-1]] + [row_r[-1]]
        grid.append((row_r, row_l))
    for i in range(len(grid) - 1):
        for side in (0, 1):
            a, b = grid[i][side], grid[i + 1][side]
            for j in range(npts - 1):
                vs = (a[j], a[j + 1], b[j + 1], b[j]) if side == 1 else (a[j], b[j], b[j + 1], a[j + 1])
                try:
                    bm.faces.new(vs)
                except ValueError:
                    pass
    # caps
    for idx in (0, len(grid) - 1):
        loop = grid[idx][0] + grid[idx][1][-2:0:-1]
        try:
            f = bm.faces.new(loop)
            if idx == 0:
                pass
        except ValueError:
            pass
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("body")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("body", me)
    bpy.context.collection.objects.link(ob)
    for p in me.polygons:
        p.use_smooth = True
    dims = ob.dimensions
    print("DIMS length %.3f width %.3f height(max z) %.3f" % (dims.y, dims.x, max(v.co.z for v in me.vertices)))
    return ob


def cut_arches(body):
    for y_axle, r in ((-1.33, 0.335), (1.33, 0.35)):
        for sx in (1, -1):
            bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=r + 0.048, depth=0.80,
                                                location=(sx * 0.90, y_axle, r), rotation=(0, math.pi / 2, 0))
            cyl = bpy.context.active_object
            mod = body.modifiers.new("arch", "BOOLEAN")
            mod.operation = "DIFFERENCE"
            mod.object = cyl
            mod.solver = "EXACT"
            bpy.context.view_layer.objects.active = body
            bpy.ops.object.modifier_apply(modifier=mod.name)
            bpy.data.objects.remove(cyl, do_unlink=True)


def wheel(y_axle, r, width, sx):
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=r, depth=width,
                                        location=(sx * (0.83 if y_axle < 0 else 0.82), y_axle, r),
                                        rotation=(0, math.pi / 2, 0))
    w = bpy.context.active_object
    bpy.ops.object.shade_smooth()
    m = bpy.data.materials.new("tyre")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.02, 0.02, 0.022, 1)
    b.inputs["Roughness"].default_value = 0.8
    w.data.materials.append(m)


def setup_render(body):
    sc = bpy.context.scene
    for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            sc.render.engine = eng
            break
        except TypeError:
            continue
    print("ENGINE", sc.render.engine)
    sc.render.resolution_x, sc.render.resolution_y = 1280, 720
    sc.world = bpy.data.worlds.new("w")
    sc.world.use_nodes = True
    sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.012, 0.014, 0.02, 1)
    m = bpy.data.materials.new("paint")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.27, 0.012, 0.02, 1)
    b.inputs["Metallic"].default_value = 0.7
    b.inputs["Roughness"].default_value = 0.3
    for nm in ("Coat Weight", "Clearcoat"):
        if nm in b.inputs:
            b.inputs[nm].default_value = 1.0
    body.data.materials.append(m)
    bpy.ops.mesh.primitive_plane_add(size=60)
    fl = bpy.context.active_object
    fm = bpy.data.materials.new("floor")
    fm.use_nodes = True
    fb = fm.node_tree.nodes["Principled BSDF"]
    fb.inputs["Base Color"].default_value = (0.02, 0.02, 0.025, 1)
    fb.inputs["Roughness"].default_value = 0.25
    fl.data.materials.append(fm)

    def area(name, loc, rot, size, energy, col, sy=None):
        l = bpy.data.lights.new(name, "AREA")
        l.energy, l.color = energy, col
        l.shape = "RECTANGLE"
        l.size, l.size_y = size, sy or size
        o = bpy.data.objects.new(name, l)
        o.location, o.rotation_euler = loc, rot
        sc.collection.objects.link(o)
    area("key", (-3.5, -4.5, 5.0), (math.radians(50), 0, math.radians(-35)), 6, 2600, (0.85, 0.92, 1.0))
    area("strip", (5.0, 0, 2.2), (0, math.radians(72), 0), 1.2, 3200, (1, 1, 1), 9.0)
    area("strip2", (-5.0, 0, 2.2), (0, math.radians(-72), 0), 1.2, 2200, (1, 1, 1), 9.0)
    area("rim", (3.0, 5.5, 3.0), (math.radians(-60), 0, math.radians(150)), 3, 1800, (1.0, 0.75, 0.5))
    area("top", (0, 0, 6.0), (0, 0, 0), 2.0, 1500, (1, 1, 1), 10.0)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = 60
    sc.collection.objects.link(cam)
    sc.camera = cam
    tgt = bpy.data.objects.new("tgt", None)
    tgt.location = (0, 0, 0.55)
    sc.collection.objects.link(tgt)
    c = cam.constraints.new("TRACK_TO")
    c.target = tgt
    views = {"front34": (-4.6, -6.2, 1.25), "rear34": (4.8, 6.0, 1.35), "side": (-9.0, 0.0, 0.85),
             "top": (0.0, -0.01, 11.5), "front_low": (-1.6, -7.4, 0.42)}
    for name, loc in views.items():
        cam.location = loc
        sc.render.filepath = os.path.join(OUT, "proto_%s.png" % name)
        bpy.ops.render.render(write_still=True)


bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete()
body = build_body()
cut_arches(body)
try:
    bpy.context.view_layer.objects.active = body
    body.select_set(True)
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35))
except Exception as e:
    print("smooth_by_angle failed", e)
for ya, r, w in ((-1.33, 0.335, 0.255), (1.33, 0.35, 0.315)):
    for sx in (1, -1):
        wheel(ya, r, w, sx)
setup_render(body)
print("PROTO_DONE")
