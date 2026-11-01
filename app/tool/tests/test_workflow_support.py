import base64
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

HELPER = Path(__file__).resolve().parents[1] / 'workflow_support.py'
spec = importlib.util.spec_from_file_location('workflow_support', HELPER)
workflow = importlib.util.module_from_spec(spec)
spec.loader.exec_module(workflow)


def public_config():
    payload = base64.urlsafe_b64encode(json.dumps({'role': 'anon'}).encode()).decode().rstrip('=')
    return {'SUPABASE_URL': 'https://example.supabase.co',
            'SUPABASE_ANON_KEY': 'test.' + payload + '.signature',
            'PGYER_API_KEY': 'private-test-key', 'PGYER_APP_KEY': 'app-key'}


class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)

    def choose(self, mode, devices):
        path = self.path / 'devices.json'
        path.write_text(json.dumps(devices))
        output = io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(io.StringIO()):
            workflow.select_device(path, mode)
        return output.getvalue().strip()

    def test_auto_prefers_physical_android_over_emulator_and_chrome(self):
        devices = [
            {'id': 'chrome', 'name': 'Chrome', 'isSupported': True},
            {'id': 'emulator', 'name': 'Emulator', 'targetPlatform': 'android-arm64', 'isSupported': True, 'emulator': True},
            {'id': 'phone-id', 'name': 'Phone', 'targetPlatform': 'android-arm64', 'isSupported': True, 'emulator': False},
        ]
        self.assertEqual(self.choose('auto', devices), 'phone-id')
        self.assertEqual(self.choose('web', devices), 'chrome')

    def test_auto_falls_back_to_web(self):
        self.assertEqual(self.choose('auto', [{'id': 'chrome', 'name': 'Chrome', 'isSupported': True}]), 'chrome')

    def test_phone_never_silently_runs_browser(self):
        with self.assertRaises(ValueError):
            self.choose('phone', [{'id': 'chrome', 'name': 'Chrome', 'isSupported': True}])

    def test_multiple_phones_require_selection(self):
        phones = [{'id': str(i), 'name': 'Phone', 'targetPlatform': 'android-arm64', 'isSupported': True} for i in range(2)]
        with self.assertRaisesRegex(ValueError, '多台手机'):
            self.choose('auto', phones)

    def test_browser_config_contains_only_public_supabase_fields(self):
        source = self.path / 'env.json'; target = self.path / 'web.json'
        source.write_text(json.dumps(public_config()))
        subprocess.run(['python3', str(HELPER), 'web-config', str(source), str(target)], check=True)
        self.assertEqual(set(json.loads(target.read_text())), {'SUPABASE_URL', 'SUPABASE_ANON_KEY'})
        self.assertNotIn('private-test-key', target.read_text())

    def test_server_secret_and_placeholder_rejected(self):
        for key in ['sb_secret_forbidden', 'REPLACE_ME']:
            data = public_config(); data['SUPABASE_ANON_KEY'] = key
            path = self.path / 'env.json'; path.write_text(json.dumps(data))
            with self.assertRaises(ValueError): workflow.config(path)

    def test_gateway_web_config_preserves_session_key_without_private_fields(self):
        source = self.path / 'env.json'; target = self.path / 'web.json'
        data = public_config()
        data['SUPABASE_AUTH_STORAGE_KEY'] = 'sb-original-project-auth-token'
        source.write_text(json.dumps(data))
        subprocess.run(['python3', str(HELPER), 'web-config', str(source), str(target)], check=True)
        result = json.loads(target.read_text())
        self.assertEqual(result['SUPABASE_AUTH_STORAGE_KEY'], data['SUPABASE_AUTH_STORAGE_KEY'])
        self.assertNotIn('PGYER_API_KEY', result)
        for invalid in [123, 'Bearer private-token']:
            data['SUPABASE_AUTH_STORAGE_KEY'] = invalid
            source.write_text(json.dumps(data))
            with self.assertRaises(ValueError): workflow.config(source)

    def test_version_increases_build_number_and_rejects_shell_text(self):
        path = self.path / 'pubspec.yaml'
        path.write_text('name: test\nversion: 1.6.3+1900000000\n')
        with contextlib.redirect_stdout(io.StringIO()): workflow.set_version(path, '1.6.3')
        self.assertIn('version: 1.6.3+1900000001', path.read_text())
        with self.assertRaises(ValueError): workflow.check_version('1.6.3; dangerous')

    def test_api_error_is_not_reported_as_success(self):
        with self.assertRaises(ValueError): workflow.api_response('{"code": 1216, "message": "failed"}')

    def test_failed_upload_never_prints_success_and_credentials_are_not_in_argv(self):
        apk = self.path / 'app.apk'; apk.write_bytes(b'fake')
        calls = []
        def fake_run(argv, **kwargs):
            calls.append((argv, kwargs))
            return subprocess.CompletedProcess(argv, 22, '', '')
        with patch.dict('os.environ', {'PGYER_API_KEY': 'private-key'}), patch.object(workflow.subprocess, 'run', fake_run):
            with self.assertRaises(ValueError): workflow.upload(str(apk), 'note')
        self.assertEqual(calls[0][0], ['curl', '--config', '-'])
        self.assertNotIn('private-key', ' '.join(calls[0][0]))
        self.assertIn('private-key', calls[0][1]['input'])


if __name__ == '__main__':
    unittest.main()
