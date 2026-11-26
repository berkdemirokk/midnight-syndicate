"""Conservative manifest/GLB sanity check, not a legal or visual certification."""
import argparse, hashlib, json, struct
from pathlib import Path

def within(root, rel):
    p=(root/rel).resolve()
    if not p.is_relative_to(root): raise ValueError('path outside project')
    if not p.is_file() or not p.stat().st_size: raise ValueError('missing or empty file: '+str(rel))
    return p

def glb_info(p):
    data=p.read_bytes()
    if len(data)<20: raise ValueError('GLB too short')
    magic,ver,total=struct.unpack_from('<4sII',data)
    if magic!=b'glTF' or ver!=2 or total!=len(data): raise ValueError('bad GLB header')
    n,typ=struct.unpack_from('<I4s',data,12)
    if typ!=b'JSON' or n%4 or 20+n>len(data): raise ValueError('invalid JSON chunk')
    j=json.loads(data[20:20+n]); access=j.get('accessors',[]); tris=0; primitive_count=0
    if j.get('asset',{}).get('version')!='2.0': raise ValueError('bad glTF version')
    for mesh in j.get('meshes',[]):
        for prim in mesh.get('primitives',[]):
            primitive_count+=1
            pos=prim.get('attributes',{}).get('POSITION')
            if pos is None: raise ValueError('missing POSITION')
            count=access[prim.get('indices',pos)]['count']; mode=prim.get('mode',4)
            if mode==4: tris+=count//3
            elif mode in (5,6): tris+=max(0,count-2)
    if not tris: raise ValueError('no triangle geometry')
    off=20+n
    while off<len(data):
        if off+8>len(data): raise ValueError('truncated chunk header')
        size,kind=struct.unpack_from('<I4s',data,off)
        if size%4 or off+8+size>len(data): raise ValueError('truncated/unaligned chunk')
        off+=8+size
    return {'mesh_triangles_not_instanced':tris,'primitives':primitive_count,'nodes':len(j.get('nodes',[])),'materials':len(j.get('materials',[])),'images':len(j.get('images',[]))}

def audit(root, manifest):
    root=root.resolve(); entries=json.loads(manifest.read_text(encoding='utf-8-sig')).get('assets',[])
    if not isinstance(entries,list) or not entries: raise ValueError('no manifest assets')
    seen=set(); results=[]; errors=[]
    for a in entries:
        try:
            for k in ('id','path','role','source_url','author','license','license_evidence','attribution'):
                v=a.get(k); assert isinstance(v,str) and v.strip() and 'REPLACE' not in v.upper(), 'missing/template '+k
            if a['id'] in seen: raise ValueError('duplicate id')
            seen.add(a['id'])
            if a['license'].upper() in ('UNKNOWN','NC','EDITORIAL','UNLICENSED'): raise ValueError('unacceptable license flag')
            if not a['source_url'].startswith('https://'): raise ValueError('source URL must be HTTPS')
            p=within(root,a['path']); within(root,a['license_evidence']); digest=hashlib.sha256(p.read_bytes()).hexdigest()
            if a.get('sha256') and a['sha256'].lower()!=digest: raise ValueError('hash mismatch')
            r={'id':a['id'],'sha256':digest,'bytes':p.stat().st_size}
            if p.suffix.lower()=='.glb': r.update(glb_info(p))
            results.append(r)
        except (ValueError, KeyError, IndexError, TypeError, AssertionError, OSError) as exc: errors.append({'id':a.get('id','?'),'error':str(exc)})
    return {'checked':results,'errors':errors,'note':'Technical checks only; inspect actual license and visual quality.'}

if __name__=='__main__':
    ap=argparse.ArgumentParser(); ap.add_argument('root',type=Path); ap.add_argument('manifest',type=Path); args=ap.parse_args()
    try: report=audit(args.root,args.manifest)
    except (ValueError,OSError,TypeError) as e: report={'errors':[str(e)]}
    print(json.dumps(report,indent=2)); raise SystemExit(bool(report['errors']))
