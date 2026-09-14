#!/usr/bin/env python3
"""Real encrypted UTF-8 MBT → read-only HTTP renderer regression."""
import base64
import hashlib
import http.client
import json
from pathlib import Path
import subprocess
import tempfile
import threading
import unittest
import server

class ViewerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.http = server.http.server.ThreadingHTTPServer(('127.0.0.1', 0), server.MoonVizHandler)
        cls.http.readonly = True
        cls.thread = threading.Thread(target=cls.http.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.http.shutdown()
        cls.http.server_close()
        cls.thread.join()

    def request(self, path, data, headers=None):
        conn = http.client.HTTPConnection('127.0.0.1', self.http.server_port, timeout=90)
        conn.request('POST', path, json.dumps(data), {'Content-Type': 'application/json', **(headers or {})})
        response = conn.getresponse()
        result = response.status, json.loads(response.read())
        conn.close()
        return result

    def test_encrypted_chinese_mbt_render_and_source_unchanged(self):
        proc = subprocess.run([server.MOON, 'run', '--target', 'native', 'cli'], cwd=server.MOONVIZ_DIR, input='create chinese 390 844\nplace chinese body_text title - 20 20\nupdate chinese title text="中文标题"\ncreate second 800 600\nexport-mbt-human\nexit\n', text=True, capture_output=True, check=True)
        exports = [json.loads(line) for line in proc.stdout.splitlines() if line.startswith('{') and '"mbt"' in line]
        self.assertTrue(exports, 'Engine failed to export fixture: ' + (proc.stdout + proc.stderr)[:2000])
        result = exports[0]
        source = result['mbt'] + '\n\n中文说明：只读查看，不改变源文件。\n'
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / '中文项目.mbt.md'
            path.write_text(source)
            before = hashlib.sha256(path.read_bytes()).hexdigest()
            helper = server.CODEC_DIR / 'target/debug/ddp_codec'
            proc = subprocess.run([str(helper)], input=json.dumps({'operation': 'encrypt', 'password': '测试密码', 'mbt_b64': base64.b64encode(path.read_bytes()).decode()}), capture_output=True, text=True, check=True)
            encrypted = json.loads(proc.stdout)
            self.assertTrue(encrypted['ok'])
            ddp = Path(tmp) / '中文项目.ddp'
            ddp.write_bytes(base64.b64decode(encrypted['ddp_b64']))
            ddp_hash = hashlib.sha256(ddp.read_bytes()).hexdigest()
            payload = {'ddp_b64': base64.b64encode(ddp.read_bytes()).decode(), 'password': '测试密码'}
            code, view = self.request('/api/ddp/view', payload)
            self.assertEqual(code, 200, view)
            self.assertTrue(view['ok'])
            self.assertEqual([a['id'] for a in view['artboards']], ['chinese', 'second'])
            self.assertTrue(all('<svg' in a['svg'] for a in view['artboards']))
            self.assertNotIn('mbt', view)
            self.assertNotIn('mbt_b64', view)
            self.assertNotIn('nodes', view['artboards'][0])
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), before)
            self.assertEqual(hashlib.sha256(ddp.read_bytes()).hexdigest(), ddp_hash)
            payload['password'] = 'wrong'
            code, error = self.request('/api/ddp/view', payload)
            self.assertEqual(code, 400)
            self.assertEqual(error['error'], 'ddp_authentication_failed')

    def test_readonly_routes_and_origin(self):
        for path in ['/api/exec', '/api/ddp/encrypt', '/api/ddp/decrypt', '/api/save', '/api/project/write']:
            self.assertEqual(self.request(path, {'commands': ['create evil 10 10']})[0], 403)
        self.assertEqual(self.request('/api/mbt/render', {'mbt_b64': 'AAAA\ncreate evil 10 10'})[0], 400)
        self.assertEqual(self.request('/api/ddp/view', {}, {'Origin': 'https://evil.example'})[0], 403)
        self.assertEqual(self.request('/api/ddp/view', {}, {'Host': 'evil.example'})[0], 403)
        self.assertEqual(self.request('/api/ddp/view', {}, {'Origin': f'http://localhost:{self.http.server_port}'})[0], 403)
        conn = http.client.HTTPConnection('127.0.0.1', self.http.server_port)
        conn.request('GET', '/server.py')
        self.assertEqual(conn.getresponse().status, 404)
        conn.close()

if __name__ == '__main__':
    unittest.main()
