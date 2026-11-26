"""Read-only quick engine/asset inventory; no secrets or file content printed."""
import sys, os, json, shutil
from pathlib import Path
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve()
ignore={'.git','.godot','node_modules','Library','Temp','build','dist','MIDNIGHT_RESCUE','Pods','venv','.venv'}
engines=[]; counts={}; large=[]
for d, dirs, files in os.walk(root):
    dirs[:]=[x for x in dirs if x not in ignore and not x.startswith('.')]
    for f in files:
        p=Path(d)/f; e=p.suffix.lower()
        if f in ('project.godot','ProjectVersion.txt','package.json','Cargo.toml') or e in ('.uproject','.xcodeproj'):
            engines.append(str(p.relative_to(root)))
        if e in ('.glb','.gltf','.fbx','.obj','.blend','.png','.jpg','.jpeg','.ktx2','.hdr','.exr','.gdshader','.shader'):
            counts[e]=counts.get(e,0)+1
            if e in ('.glb','.gltf','.fbx','.obj','.blend'):
                large.append((p.stat().st_size,str(p.relative_to(root))))
print(json.dumps({'root':str(root),'engine_markers':engines[:30],'asset_counts':counts,'largest_models':sorted(large,reverse=True)[:15],'tools':{x:shutil.which(x) for x in ('blender','godot','godot4','git','claude','nvidia-smi')}},indent=2))
