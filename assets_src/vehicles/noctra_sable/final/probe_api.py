import bpy, bmesh, sys
print("VERSION", bpy.app.version_string)
sc = bpy.context.scene
ok = []
for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT", "BLENDER_WORKBENCH", "CYCLES"):
    try:
        sc.render.engine = eng; ok.append(eng)
    except Exception as e:
        print("ENGINE_FAIL", eng, str(e)[:120])
print("ENGINES_OK", ok)
m = bpy.data.materials.new("p"); m.use_nodes = True
b = m.node_tree.nodes["Principled BSDF"]
print("PBSDF_INPUTS", [i.name for i in b.inputs if any(k in i.name for k in ("Coat", "Metal", "Rough", "Alpha", "Base"))])
for attr in ("surface_render_method", "blend_method", "use_backface_culling"):
    print("MAT_ATTR", attr, hasattr(m, attr))
me = bpy.data.meshes.new("t")
a = me.attributes.new("s", "FLOAT", "POINT")
print("ATTR_OK", a.name, a.domain, a.data_type)
mod_types = [t for t in dir(bpy.types) if "Weighted" in t or "Smooth" in t]
print("TYPES", mod_types)
ob = bpy.data.objects.new("t", me)
bpy.context.collection.objects.link(ob)
print("OPS_SHADE", hasattr(bpy.ops.object, "shade_smooth_by_angle"), hasattr(bpy.ops.object, "shade_auto_smooth"))
try:
    md = ob.modifiers.new("wn", "WEIGHTED_NORMAL"); print("WN_OK", md.type)
except Exception as e: print("WN_FAIL", str(e)[:200])
print("BMOPS_BEVEL", "bevel" in dir(bmesh.ops))
print("NUMPY", end=" ")
try:
    import numpy; print("ok", numpy.__version__)
except Exception as e: print("fail", e)
print("PROBE_DONE")
