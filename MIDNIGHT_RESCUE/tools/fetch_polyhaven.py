"""Fetch selected photo-based texture maps from documented Poly Haven API. No API key."""
import argparse, hashlib, json, re, urllib.request
from pathlib import Path
from urllib.parse import urlparse
UA={'User-Agent':'MidnightSyndicate-LocalAssetRescue/2.0'}
MAX=64*1024*1024

def fetch(url,limit=MAX):
    if urlparse(url).scheme!='https': raise ValueError('HTTPS required')
    with urllib.request.urlopen(urllib.request.Request(url,headers=UA),timeout=45) as r:
        data=r.read(limit+1)
    if len(data)>limit: raise ValueError('download exceeds size cap')
    return data

def select(meta, key, res):
    for alias in {'diff':['diff','albedo','color'],'nor_gl':['nor_gl','normal_gl'],'rough':['rough','roughness']}[key]:
        formats=meta.get(alias,{}).get(res,{})
        for fmt in ('jpg','png'):
            item=formats.get(fmt)
            if isinstance(item,dict) and item.get('url') and item.get('md5'): return fmt,item
    raise ValueError('missing '+key+' at '+res+'; inspect API response or download manually')

def run(asset, res, dest):
    if not re.fullmatch(r'[a-z0-9_]+',asset): raise ValueError('invalid asset id')
    meta=json.loads(fetch('https://api.polyhaven.com/files/'+asset,4*1024*1024)); picks=[(k,*select(meta,k,res)) for k in ('diff','nor_gl','rough')]
    folder=dest/asset; folder.mkdir(parents=True,exist_ok=True); records=[]
    for k,fmt,item in picks:
        url=item['url']; host=urlparse(url).hostname or ''
        if not (host=='polyhaven.com' or host.endswith('.polyhaven.com') or host=='polyhaven.org' or host.endswith('.polyhaven.org')): raise ValueError('unexpected file host')
        target=folder/f'{asset}_{k}_{res}.{fmt}'
        if target.exists():
            data=target.read_bytes()
            if hashlib.md5(data).hexdigest()!=item['md5'].lower(): raise ValueError('existing file hash mismatch; will not overwrite '+str(target))
        else:
            data=fetch(url)
            if hashlib.md5(data).hexdigest()!=item['md5'].lower() or ('size' in item and len(data)!=item['size']): raise ValueError('download hash/size mismatch')
            with target.open('xb') as f: f.write(data)
        records.append({'path':str(target),'url':url,'sha256':hashlib.sha256(data).hexdigest()})
    receipt={'asset':asset,'source':'https://polyhaven.com/a/'+asset,'license':'CC0','license_url':'https://polyhaven.com/license','files':records}
    (folder/'source_receipt.json').write_text(json.dumps(receipt,indent=2),encoding='utf-8'); return receipt
if __name__=='__main__':
    p=argparse.ArgumentParser(); p.add_argument('asset'); p.add_argument('--resolution',choices=('1k','2k','4k'),default='2k'); p.add_argument('--out',type=Path,default=Path('asset_inbox/polyhaven')); a=p.parse_args()
    try: print(json.dumps(run(a.asset,a.resolution,a.out),indent=2))
    except Exception as e: p.exit(1,'Download not completed: '+str(e)+'\n')
