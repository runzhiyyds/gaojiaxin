"""Exercise the real shell entry against an isolated fake Flutter tool."""
import base64
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]


class WorkflowCliTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in ['test_app.sh', 'app/scripts/workflow_common.sh', 'app/tool/workflow_support.py']:
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, target)
        payload = base64.urlsafe_b64encode(b'{"role":"anon"}').decode().rstrip('=')
        (self.root / 'app/env.json').write_text(json.dumps({
            'SUPABASE_URL': 'https://example.supabase.co',
            'SUPABASE_ANON_KEY': 'test.' + payload + '.signature',
            'PGYER_API_KEY': 'private-fixture',
        }))
        (self.root / 'app/web').mkdir()
        (self.root / 'app/web/index.html').write_text('<html></html>')
        bin_dir = self.root / 'bin'; bin_dir.mkdir()
        fake = bin_dir / 'flutter'
        fake.write_text('''#!/usr/bin/env python3
import sys,json,os,pathlib
args=sys.argv[1:]
with open(os.environ['WORKFLOW_TEST_LOG'],'a') as log: log.write(json.dumps(args)+'\\n')
if args[:1] == ['devices']:
 print(json.dumps([
  {'id':'phone-id','name':'Test phone','targetPlatform':'android-arm64','isSupported':True,'emulator':False},
  {'id':'chrome','name':'Chrome','isSupported':True}]))
if args[:1] == ['pub'] and os.environ.get('WORKFLOW_TEST_FAIL_PUB'): sys.exit(1)
if args[:1] == ['run']:
 cfg=next(a.split('=',1)[1] for a in args if a.startswith('--dart-define-from-file='))
 fields=list(json.loads(pathlib.Path(cfg).read_text()))
 pathlib.Path(os.environ['WORKFLOW_TEST_FIELDS']).write_text(json.dumps(fields))
''')
        fake.chmod(0o755)
        self.log = self.root / 'calls.jsonl'
        self.fields = self.root / 'fields.json'
        self.env = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ['PATH'],
                        WORKFLOW_TEST_LOG=str(self.log), WORKFLOW_TEST_FIELDS=str(self.fields))

    def invoke(self, mode):
        return subprocess.run([str(self.root / 'test_app.sh'), mode], env=self.env,
                              capture_output=True, text=True)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_auto_runs_phone_without_web_only_flags(self):
        result = self.invoke('auto')
        self.assertEqual(result.returncode, 0, result.stderr)
        args = self.calls()[-1]
        self.assertEqual(args[0], 'run')
        self.assertEqual(args[args.index('-d') + 1], 'phone-id')
        self.assertNotIn('--no-web-resources-cdn', args)

    def test_web_uses_local_renderer_and_public_only_config(self):
        result = self.invoke('web')
        self.assertEqual(result.returncode, 0, result.stderr)
        args = self.calls()[-1]
        self.assertIn('--no-web-resources-cdn', args)
        self.assertEqual(args[args.index('-d') + 1], 'chrome')
        self.assertEqual(set(json.loads(self.fields.read_text())), {'SUPABASE_URL', 'SUPABASE_ANON_KEY'})

    def test_failed_dependency_setup_cannot_start_app(self):
        self.env['WORKFLOW_TEST_FAIL_PUB'] = '1'
        result = self.invoke('auto')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(args[0] == 'run' for args in self.calls()))

    def test_smoke_keeps_the_installed_app_and_local_data(self):
        result = self.invoke('smoke')
        self.assertEqual(result.returncode, 0, result.stderr)
        args = self.calls()[-1]
        self.assertEqual(args[0], 'drive')
        self.assertIn('--keep-app-running', args)
        self.assertIn('--target=integration_test/app_test.dart', args)
        self.assertIn('--driver=test_driver/integration_driver.dart', args)
        self.assertEqual(args[args.index('-d') + 1], 'phone-id')


if __name__ == '__main__':
    unittest.main()
