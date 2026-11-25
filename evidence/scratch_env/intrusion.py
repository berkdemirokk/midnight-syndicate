import json, math, sys
C=json.load(open('game/assets/world/city_01/city_01_centerline.json'))
L=json.load(open('game/assets/world/city_01/city_01_layout.json'))
cat=json.load(open('game/assets/world/kits/buildings/catalog.json'))
cols={b['id']:b for b in cat['buildings']}
samp=C['samples']; edges=C['edges']; n=len(samp)
P=[(s['pos'][0],s['pos'][2]) for s in samp]
R=[(s['right'][0],s['right'][2]) for s in samp]
HALF=[]
for e,s in zip(edges,samp):
    lk=math.hypot(e['left_kerb'][0]-s['pos'][0], e['left_kerb'][2]-s['pos'][2])
    rk=math.hypot(e['right_kerb'][0]-s['pos'][0], e['right_kerb'][2]-s['pos'][2])
    HALF.append(max(lk,rk)+0.5)
def nearest(x,z):
    best=1e18;bi=0
    for i,(px,pz) in enumerate(P):
        d=(x-px)**2+(z-pz)**2
        if d<best: best=d;bi=i
    return bi, math.sqrt(best)
def lat_at(x,z,i):
    px,pz=P[i]; rx,rz=R[i]
    return (x-px)*rx+(z-pz)*rz
def violation(x,z):
    """returns (margin, s_index) margin = HALF - |lat| at nearest sample; negative = inside kerb+0.5"""
    i,_=nearest(x,z)
    return HALF[i]-abs(lat_at(x,z,i)), i
def corners_of(cx,cy,cz,sx,sz,px,pz,yaw):
    out=[]
    for dx in (-sx/2,sx/2):
        for dz in (-sz/2,sz/2):
            lx,lz=cx+dx,cz+dz
            out.append((px+lx*math.cos(yaw)+lz*math.sin(yaw), pz-lx*math.sin(yaw)+lz*math.cos(yaw)))
    return out
def footprint_samples(cs):
    p0,p1,p2,p3=cs[0],cs[1],cs[2],cs[3]
    ux=(p2[0]-p0[0],p2[1]-p0[1]); uz=(p1[0]-p0[0],p1[1]-p0[1])
    for a in range(0,9):
        for b in range(0,9):
            fa,fb=a/8,b/8
            yield (p0[0]+ux[0]*fa+uz[0]*fb, p0[1]+ux[1]*fa+uz[1]*fb)
if __name__=='__main__':
    res=[]
    for ins in L['instances']:
        if ins['kind']!='building': continue
        b=cols[ins['asset']]; c=b['collider']
        cx,cy,cz=c['center']; sx,sy,sz=c['size']
        px,py,pz=ins['position']
        cs=corners_of(cx,cy,cz,sx,sz,px,pz,ins['yaw'])
        worst=(1e9,None,None)
        for (x,z) in footprint_samples(cs):
            m,i=violation(x,z)
            if m<worst[0]: worst=(m,i,(x,z))
        res.append((worst[0],ins['asset'],ins.get('s_offset_m'),ins['position'],ins['yaw'],worst[1],worst[2],ins.get('side'),ins['district']))
    res.sort()
    for r in res[:40]:
        if r[0]<0.5: print('margin %.2f %s s=%.1f pos=%s yaw=%.3f idx=%s side=%s %s'%(r[0],r[1],r[2],[round(v,2) for v in r[3]],r[4],r[5],r[7],r[8]))
    print('count',len(res),'violations(<0)',sum(1 for r in res if r[0]<0))
