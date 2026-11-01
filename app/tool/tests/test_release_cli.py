"""Verify release sequencing without building or publishing to a real service."""
import base64
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]


class ReleaseCliTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in ['publish_new_version.sh', 'app/scripts/workflow_common.sh',
                     'app/tool/workflow_support.py']:
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, target)
        # Stub only external API boundaries; keep actual config/version helpers.
        helper = self.root / 'app/tool/workflow_support.py'
        original = helper.read_text()
        helper.write_text(original.replace("if __name__ == '__main__':", '''
def fixture_api(*args):
    with open(os.environ['RELEASE_TEST_API_LOG'], 'a') as log:
        log.write(json.dumps(args) + '\\n')
check_pgyer = lambda path: fixture_api('check')
upload = lambda apk, note: fixture_api('upload', apk, note)

if __name__ == '__main__':'''))
        payload = base64.urlsafe_b64encode(b'{"role":"anon"}').decode().rstrip('=')
        (self.root / 'app/env.json').write_text(json.dumps({
            'SUPABASE_URL': 'https://example.supabase.co',
            'SUPABASE_ANON_KEY': 'test.' + payload + '.signature',
        }))
        self.pubspec = self.root / 'app/pubspec.yaml'
        self.pubspec.write_text('name: fixture\nversion: 1.6.3+1900000000\n')
        bin_dir = self.root / 'bin'; bin_dir.mkdir()
        fake = bin_dir / 'flutter'
        fake.write_text('''#!/usr/bin/env python3
import json,os,pathlib,sys
args=sys.argv[1:]
with open(os.environ['RELEASE_TEST_LOG'],'a') as log: log.write(json.dumps(args)+'\\n')
if args[:1] == ['test'] and os.environ.get('RELEASE_TEST_FAIL_TEST'): sys.exit(1)
if args[:2] == ['build','apk']:
 # Model the Flutter regression: --no-pub retains a dev plugin registrant.
 if '--no-pub' in args or os.environ.get('RELEASE_TEST_FAIL_BUILD'): sys.exit(1)
 apk=pathlib.Path('build/app/outputs/flutter-apk/app-release.apk')
 apk.parent.mkdir(parents=True,exist_ok=True); apk.write_bytes(b'new-apk')
''')
        fake.chmod(0o755)
        self.log = self.root / 'flutter.jsonl'
        self.api_log = self.root / 'api.jsonl'
        self.env = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ['PATH'],
                        RELEASE_TEST_LOG=str(self.log), RELEASE_TEST_API_LOG=str(self.api_log))

    def invoke(self, *options):
        return subprocess.run([str(self.root / 'publish_new_version.sh'), '1.6.3', '全面优化', *options],
                              env=self.env, capture_output=True, text=True)

    def api_calls(self):
        return [json.loads(line)[0] for line in self.api_log.read_text().splitlines()] if self.api_log.exists() else []

    def test_release_regenerates_plugins_after_tests_then_uploads(self):
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = [json.loads(line) for line in self.log.read_text().splitlines()]
        self.assertEqual(calls[-2][0], 'test')
        self.assertEqual(calls[-1][:2], ['build', 'apk'])
        self.assertNotIn('--no-pub', calls[-1])
        self.assertEqual(self.api_calls(), ['check', 'upload'])

    def test_build_failure_never_uploads_existing_apk(self):
        apk = self.root / 'app/build/app/outputs/flutter-apk/app-release.apk'
        apk.parent.mkdir(parents=True); apk.write_bytes(b'old-apk')
        self.env['RELEASE_TEST_FAIL_BUILD'] = '1'
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Android 正式版构建失败', result.stderr)
        self.assertEqual(self.api_calls(), ['check'])
        self.assertEqual(apk.read_bytes(), b'old-apk')

    def test_test_failure_keeps_version_and_stops_before_build(self):
        before = self.pubspec.read_text()
        self.env['RELEASE_TEST_FAIL_TEST'] = '1'
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('自动化测试失败', result.stderr)
        self.assertEqual(self.pubspec.read_text(), before)
        self.assertNotIn('build', self.log.read_text())
        self.assertEqual(self.api_calls(), ['check'])

    def test_build_only_does_not_upload(self):
        result = self.invoke('--build-only')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.api_calls(), [])
        self.assertIn('未上传蒲公英', result.stdout)

    def test_check_does_not_build_or_change_version(self):
        before = self.pubspec.read_text()
        result = self.invoke('--check')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.log.exists())
        self.assertEqual(self.pubspec.read_text(), before)
        self.assertEqual(self.api_calls(), ['check'])
