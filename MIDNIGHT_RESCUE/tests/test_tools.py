import sys, unittest, tempfile, json, struct
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from validate_assets import glb_info, within, audit
from fetch_polyhaven import select
from check_evidence import check
class Tests(unittest.TestCase):
    def test_glb(self):
        j={'asset':{'version':'2.0'},'accessors':[{'count':6}],'meshes':[{'primitives':[{'attributes':{'POSITION':0}}]}]}
        d=json.dumps(j).encode(); d+=b' '*((-len(d))%4)
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'a.glb'; p.write_bytes(struct.pack('<4sII',b'glTF',2,20+len(d))+struct.pack('<I4s',len(d),b'JSON')+d); self.assertEqual(glb_info(p)['mesh_triangles_not_instanced'],2)
            p.write_bytes(b'garbage'); self.assertRaises(ValueError,glb_info,p)
    def test_traversal(self):
        with tempfile.TemporaryDirectory() as t: self.assertRaises(ValueError,within,Path(t).resolve(),'../outside')
    def test_template_fails(self):
        root=Path(__file__).resolve().parents[1]; self.assertTrue(audit(root,root/'templates/ASSET_MANIFEST.example.json')['errors'])
    def test_evidence_template_fails(self):
        root=Path(__file__).resolve().parents[1]; self.assertTrue(check(root,root/'templates/EVIDENCE.example.json')['errors'])
    def test_select(self):
        v={'rough':{'2k':{'jpg':{'url':'https://example.org/a.jpg','md5':'x'}}}}; self.assertEqual(select(v,'rough','2k')[0],'jpg'); self.assertRaises(ValueError,select,v,'diff','2k')
if __name__=='__main__': unittest.main()
