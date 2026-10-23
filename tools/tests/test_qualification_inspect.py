import importlib.util
from pathlib import Path
import unittest

spec=importlib.util.spec_from_file_location('inspect_qualification',Path(__file__).resolve().parents[1]/'pvfd_qualification_inspect.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)

class InspectionTests(unittest.TestCase):
    def test_queue_only_allows_fixed_nonclinical_fields(self):
        import json
        valid={'version':1,'revision':1,'operation':'save','recoveryKeyId':'a'*64,'recoverySha256':'b'*64}
        self.assertEqual(module.metadata(json.dumps(valid)),valid)
        for update in [{'patient':'TEST ONLY'},{'recoveryKeyId':'TEST PATIENT NAME'},{'operation':'narrative'},{'revision':True}]:
            with self.assertRaises(module.InspectionBlocked):module.metadata(json.dumps({**valid,**update}))
    def test_filenames_cannot_escape_or_select_plaintext_payloads(self):
        self.assertTrue(module.LEGACY.fullmatch('app_flutter/pcr_TEST-ONLY.json'))
        self.assertFalse(module.RECORD.fullmatch('app_flutter/../private.pem'))
        self.assertFalse(module.RECORD.fullmatch('app_flutter/protected_epcr_v1/'+'a'*32+'/rev_0000000000000001/patient.json'))
