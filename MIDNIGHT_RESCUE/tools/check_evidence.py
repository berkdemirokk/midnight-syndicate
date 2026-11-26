"""Check required artifacts exist, are distinct PNGs, and basic review fields are present."""
import argparse, json, struct, hashlib
from pathlib import Path
from validate_assets import within

def check(root, manifest):
    root=root.resolve(); m=json.loads(manifest.read_text(encoding='utf-8-sig')); errors=[]; hashes=set()
    for key in ('commit','engine','run_command','visual_review','device'):
        val=m.get(key)
        if not isinstance(val,str) or not val.strip() or 'REPLACE' in val: errors.append('missing '+key)
    for key in ('before','day','night','gameplay'):
        try:
            p=within(root,m['captures'][key]); data=p.read_bytes()
            if data[:8]!=b'\x89PNG\r\n\x1a\n' or len(data)<33 or data[12:16]!=b'IHDR': raise ValueError('not a PNG header')
            w,h=struct.unpack_from('>II',data,16)
            if min(w,h)<300: raise ValueError('capture too small')
            digest=hashlib.sha256(data).hexdigest()
            if digest in hashes: raise ValueError('duplicate capture')
            hashes.add(digest)
            reference=root/'MIDNIGHT_RESCUE/reference/ORTAKOY_CONCEPT.png'
            if reference.is_file() and hashlib.sha256(reference.read_bytes()).hexdigest()==digest: raise ValueError('concept reused as screenshot')
        except (KeyError, ValueError,OSError,TypeError) as e: errors.append(key+': '+str(e))
    try: within(root,m['test_log'])
    except (KeyError,ValueError,OSError,TypeError) as e: errors.append('test_log: '+str(e))
    for k in ('fps','frame_time_ms'):
        x=m.get(k)
        if not isinstance(x,(int,float)) or isinstance(x,bool) or not 0<x<10000: errors.append('missing measured '+k)
    if m.get('ios_test') not in ('not_run','passed','failed'): errors.append('invalid ios_test')
    return {'errors':errors,'note':'Does not prove authenticity, rendering quality, or test success. Review actual captures and logs.'}
if __name__=='__main__':
    p=argparse.ArgumentParser(); p.add_argument('root',type=Path); p.add_argument('manifest',type=Path); a=p.parse_args()
    try: r=check(a.root,a.manifest)
    except (ValueError,OSError,TypeError) as e: r={'errors':[str(e)]}
    print(json.dumps(r,indent=2)); raise SystemExit(bool(r['errors']))
