import bpy, sys
print("VER", bpy.app.version_string)
ops = bpy.ops.export_scene.gltf.get_rna_type().properties
names = [p.identifier for p in ops]
for k in ["export_format","export_yup","export_apply","export_tangents","export_image_format","use_selection","export_texcoords","export_normals","export_materials","export_cameras","export_lights","export_extras","use_visible","export_hierarchy_flatten_objs","export_keep_originals","export_try_sparse_sparse_accessors","export_vertex_color","export_all_vertex_colors"]:
    print("EXPPROP", k, k in names)
print("EXPALL", sorted(names)[:200])
ps = bpy.types.ShaderNodeBsdfPrincipled.bl_rna.properties
print("PRIN", [p.identifier for p in ps if 'Coat' in p.identifier or 'Emission' in p.identifier or p.identifier in ('Alpha','Normal')][:40])
m = bpy.data.materials.new("t"); m.use_nodes=True
b = m.node_tree.nodes["Principled BSDF"]
print("INPUTS", [i.name for i in b.inputs][:60])
print("NODEREG", hasattr(bpy.types, "ShaderNodeNormalMap"), hasattr(bpy.types, "ShaderNodeTexImage"))
print("DEC", [p.identifier for p in bpy.types.DecimateModifier.bl_rna.properties if p.identifier in ('decimate_type','ratio','use_collapse_triangulate','use_symmetry')])
print("GLTFAVAIL", hasattr(bpy.ops.export_scene,'gltf'))
imp = bpy.ops.import_scene.gltf.get_rna_type().properties
print("IMPOK", 'filepath' in [p.identifier for p in imp])
print("PREFS", [p.identifier for p in bpy.context.preferences.addons['cycles'].preferences.bl_rna.properties if p.identifier in ('compute_device_type',)] if 'cycles' in bpy.context.preferences.addons else "no cycles addon")
print("ENGINES", [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items])
