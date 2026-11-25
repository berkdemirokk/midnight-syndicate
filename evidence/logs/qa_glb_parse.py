import json, struct, sys, glob, os
paths = sys.argv[1:]
for p in paths:
    with open(p, 'rb') as f:
        magic, ver, length = struct.unpack('<III', f.read(12))
        clen, ctype = struct.unpack('<II', f.read(8))
        j = json.loads(f.read(clen).decode('utf-8'))
    tris = 0
    mats = set()
    for m in j.get('meshes', []):
        for prim in m.get('primitives', []):
            mode = prim.get('mode', 4)
            acc = j['accessors'][prim['indices']] if 'indices' in prim else None
            if acc is None:
                continue
            n = acc['count']
            if mode == 4:
                tris += n // 3
            elif mode == 5:
                tris += n - 2
            if 'material' in prim:
                mi = prim['material']
                mats.add(j['materials'][mi].get('name', '?'))
    print(os.path.basename(p), 'tris=%d' % tris, 'materials=%s' % sorted(mats), 'meshes=%d' % len(j.get('meshes', [])))
