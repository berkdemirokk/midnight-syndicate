"""Blender-only: import an actual GLB, create neutral studio lights, render three camera angles. Never modifies input."""
import argparse, sys, math
from pathlib import Path
import bpy
from mathutils import Vector
p=argparse.ArgumentParser(); p.add_argument('--model',required=True,type=Path); p.add_argument('--out',required=True,type=Path); a=p.parse_args(sys.argv[sys.argv.index('--')+1:])
a.out.mkdir(parents=True,exist_ok=True)
if not a.model.is_file(): raise FileNotFoundError(a.model)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(a.model.resolve()))
meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']; assert meshes,'No mesh'
verts=[o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
lo=Vector(tuple(min(v[i] for v in verts) for i in range(3))); hi=Vector(tuple(max(v[i] for v in verts) for i in range(3)))
center=(lo+hi)/2; span=max(hi-lo); assert span>0,'Invalid bounds'
scene=bpy.context.scene; scene.render.engine='CYCLES'; scene.cycles.samples=24; scene.cycles.use_denoising=True
scene.render.resolution_x=1280; scene.render.resolution_y=720; scene.render.resolution_percentage=100
scene.world=bpy.data.worlds.new('Neutral world'); scene.world.use_nodes=True; scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.18,.18,.18,1); scene.world.node_tree.nodes['Background'].inputs[1].default_value=.45
# neutral ground and lights for diagnostic purposes only
bpy.ops.mesh.primitive_plane_add(size=span*12,location=(center.x,center.y,lo.z-span*.005)); plane=bpy.context.object; mat=bpy.data.materials.new('Neutral preview floor'); mat.diffuse_color=(.12,.12,.12,1); plane.data.materials.append(mat)
def point(obj,at): obj.rotation_euler=(at-obj.location).to_track_quat('-Z','Y').to_euler()
for name,delta,power,size in [('Key',(1,-1,2),500,1.8),('Fill',(-1,0,1),250,2),('Rim',(0,1,1.5),400,1.4)]:
    data=bpy.data.lights.new(name,'AREA'); data.energy=power*span**2/4; data.shape='DISK'; data.size=size*span; obj=bpy.data.objects.new(name,data); scene.collection.objects.link(obj); obj.location=center+Vector(delta)*span; point(obj,center)
bpy.ops.object.camera_add(); cam=bpy.context.object; scene.camera=cam; cam.data.lens=48
for label,offset in [('three_quarter_a',(1.6,-1.6,.8)),('three_quarter_b',(-1.6,1.6,.8)),('side',(2.2,0,.45))]:
    cam.location=center+Vector(offset)*span; point(cam,center); scene.render.filepath=str((a.out/(label+'.png')).resolve()); bpy.ops.render.render(write_still=True)
print('PREVIEW_RENDERED',len(meshes),'mesh objects; bounds',tuple(hi-lo),'meters if source units are meters')
