#!/usr/bin/env python3
"""Studio server, or render-only ddpView with --readonly."""
import argparse
import base64
import binascii
import http.server
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent
MOONVIZ_DIR = Path(os.environ.get('MOONVIZ_DIR', ROOT.parent / 'moonviz')).resolve()
CODEC_DIR = MOONVIZ_DIR / 'ddp'
PORT = int(os.environ.get('MOONVIZ_PORT', '8901'))
MAX_REQUEST_BYTES = 24 * 1024 * 1024
MOON = shutil.which('moon') or str(Path.home() / '.moon/bin/moon')
USER_LIB_DIR = ROOT / '.moonviz' / 'components'
# 触发库同步的命令前缀（编译/导入/删除后把注册表快照落盘）
LIB_MUTATING = ('component-compile-b64', 'component-import', 'component-delete')


def user_lib_b64s():
    """项目级用户组件库 → 声明 b64 列表（宿主持久化侧）。"""
    if not USER_LIB_DIR.is_dir():
        return []
    out = []
    for f in sorted(USER_LIB_DIR.glob('*.mbt.md')):
        try:
            out.append(base64.b64encode(f.read_bytes()).decode('ascii'))
        except OSError:
            continue
    return out


def sync_user_lib(snap):
    """用同批命令尾部的 library-snapshot 结果全量重写本地库（幂等）。

    注意 snapshot 必须与变更命令同进程：跨进程注入的 restore 读的是磁盘
    旧库，首次注册时会得到空快照（鸡生蛋）。snap 为 None（引擎失败/无
    快照输出）时绝不清库——一次瞬时引擎故障不得抹掉用户组件数据。"""
    if not isinstance(snap, dict) or not snap.get('ok'):
        return
    USER_LIB_DIR.mkdir(parents=True, exist_ok=True)
    keep = set()
    for item in (snap or {}).get('components', []):
        cid, src = item.get('id'), item.get('source_b64')
        if not isinstance(cid, str) or not isinstance(src, str) or not cid or '/' in cid or '..' in cid:
            continue
        keep.add(cid + '.mbt.md')
        try:
            USER_LIB_DIR.joinpath(cid + '.mbt.md').write_bytes(base64.b64decode(src))
        except (OSError, binascii.Error, ValueError):
            continue
    for f in USER_LIB_DIR.glob('*.mbt.md'):
        if f.name not in keep:
            try:
                f.unlink()
            except OSError:
                pass

class MoonVizHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def _same_origin(self):
        port = self.server.server_port
        host = self.headers.get('Host')
        return host in (f'127.0.0.1:{port}', f'localhost:{port}') and self.headers.get('Origin') in (None, f'http://{host}')

    def do_GET(self):
        if not self._same_origin():
            self.send_json(403, {'ok': False, 'error': 'origin_forbidden'})
            return
        path = self.path.split('?', 1)[0]
        allowed = {'/': 'ddpView.html' if self.server.readonly else 'index.html', '/ddpView.html': 'ddpView.html'}
        if not self.server.readonly:
            allowed.update({'/index.html': 'index.html', '/frontend/index.html': 'frontend/index.html'})
        if path not in allowed:
            self.send_json(404, {'ok': False, 'error': 'not_found'})
            return
        data = (ROOT / allowed[path]).read_bytes()
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(data)

    def do_HEAD(self):
        self.send_json(405, {'ok': False, 'error': 'method_not_allowed'})

    def do_POST(self):
        if not self._same_origin():
            self.send_json(403, {'ok': False, 'error': 'origin_forbidden'})
            return
        allowed = {'/api/ddp/view', '/api/mbt/render'}
        if not self.server.readonly:
            allowed.update({'/api/exec', '/api/ddp/encrypt', '/api/ddp/decrypt', '/api/fx/ask', '/api/fx/agent', '/api/fx/models'})
        if self.path not in allowed:
            self.send_json(403 if self.server.readonly else 404, {'ok': False, 'error': 'readonly' if self.server.readonly else 'not_found'})
            return
        try:
            size = int(self.headers.get('Content-Length', '0'))
            if size <= 0 or size > MAX_REQUEST_BYTES:
                raise ValueError('request_too_large')
            data = json.loads(self.rfile.read(size))
            if not isinstance(data, dict):
                raise ValueError('request_invalid_json')
            if self.path == '/api/exec':
                commands = data.get('commands')
                if not isinstance(commands, list) or not all(isinstance(c, str) and '\n' not in c and '\r' not in c for c in commands):
                    raise ValueError('commands_invalid')
                if any(c.split()[:1] and c.split()[0] in LIB_MUTATING for c in commands):
                    commands = list(commands) + ['library-snapshot']
                result = self.run_cli_static(commands)
                if commands[-1] == 'library-snapshot':
                    sync_user_lib(next((r for r in result if isinstance(r, dict) and r.get('op') == 'library-snapshot'), None))
            elif self.path in ('/api/ddp/encrypt', '/api/ddp/decrypt'):
                result = self.run_ddp_codec(self.path.rsplit('/', 1)[1], data)
            elif self.path == '/api/fx/ask':
                result = self.run_fx(data)
            elif self.path == '/api/fx/agent':
                result = self.run_fx_sdk(data)
            elif self.path == '/api/fx/models':
                result = self.run_fx_models(data)
            else:
                if self.path == '/api/ddp/view':
                    decoded = self.run_ddp_codec('decrypt', data)
                    if not decoded.get('ok'):
                        self.send_json(400, decoded)
                        return
                    payload = decoded.get('mbt_b64')
                else:
                    payload = data.get('mbt_b64')
                # Strict Base64 forbids CLI newline/command injection, including in readonly mode.
                if not isinstance(payload, str) or not payload:
                    raise ValueError('mbt_payload_invalid')
                source = base64.b64decode(payload, validate=True)
                if len(source) > 8 * 1024 * 1024:
                    raise ValueError('mbt_request_too_large')
                rendered = self.run_cli_static(['render-mbt-b64 ' + payload])
                view = next((r for r in rendered if isinstance(r, dict) and r.get('ok') is True and 'artboards' in r), None)
                if view is None:
                    error = next((r.get('error') for r in rendered if isinstance(r, dict) and r.get('error')), 'render_failed')
                    self.send_json(400, {'ok': False, 'error': error})
                    return
                # Never send source, node editing data, or mutation state to ddpView.
                result = {'ok': True, 'entry': view.get('entry'), 'flows': view.get('flows', []), 'artboards': [{k: a[k] for k in ('id', 'name', 'width', 'height', 'svg') if k in a} for a in view['artboards']]}
            self.send_json(200, result)
        except (ValueError, binascii.Error, UnicodeError) as exc:
            self.send_json(400, {'ok': False, 'error': str(exc)})

    def run_fx(self, data):
        prompt = data.get('prompt')
        fx_path = data.get('fx_path', 'fx')
        cwd = data.get('cwd') or str(MOONVIZ_DIR)
        if not isinstance(prompt, str) or not prompt.strip() or '\n' in prompt or '\r' in prompt:
            return {'ok': False, 'error': 'fx_prompt_invalid'}
        if not isinstance(fx_path, str) or not isinstance(cwd, str):
            return {'ok': False, 'error': 'fx_config_invalid'}
        try:
            proc = subprocess.run([fx_path or 'fx', 'ask', '--no-save', prompt], cwd=cwd, capture_output=True, text=True, timeout=120)
            if proc.returncode != 0:
                return {'ok': False, 'error': 'fx_failed', 'detail': proc.stderr[-400:]}
            return {'ok': True, 'output': proc.stdout.strip(), 'base': 'fx'}
        except (OSError, subprocess.TimeoutExpired):
            return {'ok': False, 'error': 'fx_unavailable'}

    def run_fx_models(self, data):
        # 模型列表：GET {base}/models（经 node 桥，鉴权同 run 路径）。
        api_key = data.get('api_key')
        base_url = data.get('base_url')
        if api_key is not None and not isinstance(api_key, str):
            return {'ok': False, 'error': 'fx_api_key_invalid'}
        if not isinstance(base_url, str) or not base_url.strip():
            return {'ok': False, 'error': 'models_base_url_required'}
        bridge = ROOT / 'agent' / 'fx-agent.mjs'
        if not bridge.exists():
            return {'ok': False, 'error': 'fx_bridge_missing'}
        import shutil as _shutil
        node = _shutil.which('node')
        if not node:
            return {'ok': False, 'error': 'node_unavailable'}
        env = dict(os.environ)
        if api_key:
            env['AI_GATEWAY_API_KEY'] = api_key
        payload = {'mode': 'models', 'base_url': base_url.strip()}
        try:
            proc = subprocess.run([node, str(bridge)], input=json.dumps(payload), capture_output=True, text=True, cwd=str(ROOT), timeout=60, env=env)
            if proc.returncode != 0:
                return {'ok': False, 'error': 'fx_bridge_failed', 'detail': proc.stderr[-300:]}
            result = json.loads(proc.stdout.strip() or '{}')
            return result if isinstance(result, dict) else {'ok': False, 'error': 'fx_bridge_response_invalid'}
        except subprocess.TimeoutExpired:
            return {'ok': False, 'error': 'fx_timeout'}
        except (OSError, ValueError):
            return {'ok': False, 'error': 'fx_bridge_unavailable'}

    def run_fx_sdk(self, data):
        # Embedded fx agent via libfx: fx proposes ops through tools; every op is
        # executed by MoonViz (AgentGate) inside the bridge and returns canonical MBT.
        instruction = data.get('instruction')
        mbt_b64 = data.get('mbt_b64')
        api_key = data.get('api_key')
        model = data.get('model')
        if not isinstance(instruction, str) or not instruction.strip() or len(instruction) > 16000:
            return {'ok': False, 'error': 'fx_instruction_invalid'}
        if not isinstance(mbt_b64, str) or not mbt_b64:
            return {'ok': False, 'error': 'fx_mbt_required'}
        if api_key is not None and not isinstance(api_key, str):
            return {'ok': False, 'error': 'fx_api_key_invalid'}
        if model is not None and not isinstance(model, str):
            return {'ok': False, 'error': 'fx_model_invalid'}
        bridge = ROOT / 'agent' / 'fx-agent.mjs'
        if not bridge.exists():
            return {'ok': False, 'error': 'fx_bridge_missing'}
        import shutil as _shutil
        node = _shutil.which('node')
        if not node:
            return {'ok': False, 'error': 'node_unavailable'}
        env = dict(os.environ)
        if api_key:
            env['AI_GATEWAY_API_KEY'] = api_key
        payload = {'mode': 'run', 'instruction': instruction, 'mbt_b64': mbt_b64}
        if model:
            payload['model'] = model
        base_url = data.get('base_url')
        if isinstance(base_url, str) and base_url.strip():
            payload['base_url'] = base_url.strip()
        thinking_level = data.get('thinking_level')
        if thinking_level in ('auto', 'adaptive', 'off', 'disabled', 'on', 'enabled', 'low', 'medium', 'high'):
            payload['thinking_level'] = thinking_level
        try:
            proc = subprocess.run([node, str(bridge)], input=json.dumps(payload), capture_output=True, text=True, cwd=str(ROOT), timeout=180, env=env)
            if proc.returncode != 0:
                return {'ok': False, 'error': 'fx_bridge_failed', 'detail': proc.stderr[-400:]}
            result = json.loads(proc.stdout.strip() or '{}')
            return result if isinstance(result, dict) else {'ok': False, 'error': 'fx_bridge_response_invalid'}
        except subprocess.TimeoutExpired:
            return {'ok': False, 'error': 'fx_timeout'}
        except (OSError, ValueError):
            return {'ok': False, 'error': 'fx_bridge_unavailable'}

    @staticmethod
    def run_cli_static(commands):
        lib = user_lib_b64s()
        if lib:
            commands = ['library-restore-b64 ' + ' '.join(lib)] + list(commands)
        try:
            proc = subprocess.run(
                [MOON, 'run', '--target', 'native', 'cli'],
                input='\n'.join(commands) + '\nexit\n',
                capture_output=True,
                text=True,
                cwd=MOONVIZ_DIR,
                timeout=60,
            )
            results = []
            for line in proc.stdout.splitlines():
                try:
                    value = json.loads(line)
                    if isinstance(value, (dict, list)):
                        results.append(value)
                except json.JSONDecodeError:
                    pass
            return results or [{'ok': False, 'error': 'engine_failed'}]
        except (OSError, subprocess.TimeoutExpired):
            return [{'ok': False, 'error': 'engine_unavailable'}]

    def run_ddp_codec(self, operation, data):
        key = 'mbt_b64' if operation == 'encrypt' else 'ddp_b64'
        if not isinstance(data.get('password'), str) or not isinstance(data.get(key), str):
            return {'ok': False, 'error': 'ddp_request_invalid'}
        helper = Path(os.environ.get('MOONVIZ_DDP_HELPER', CODEC_DIR / 'target/debug/ddp_codec'))
        try:
            proc = subprocess.run(
                [str(helper)],
                input=json.dumps({'operation': operation, 'password': data['password'], key: data[key]}),
                capture_output=True,
                text=True,
                cwd=CODEC_DIR,
                timeout=60,
            )
            result = json.loads(proc.stdout)
            return result if proc.returncode == 0 and isinstance(result, dict) else {'ok': False, 'error': 'ddp_codec_failed'}
        except (OSError, ValueError, subprocess.TimeoutExpired):
            return {'ok': False, 'error': 'ddp_codec_unavailable'}

    def send_json(self, code, data):
        body = json.dumps(data, ensure_ascii=False).encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.end_headers()
        self.wfile.write(body)


    def do_OPTIONS(self):
        self.send_json(405, {'ok': False, 'error': 'method_not_allowed'})

    def log_message(self, format, *args):
        pass

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--readonly', action='store_true', help='serve ddpView without mutation APIs')
    parser.add_argument('--port', type=int, default=PORT)
    args = parser.parse_args()
    server = http.server.ThreadingHTTPServer(('127.0.0.1', args.port), MoonVizHandler)
    server.readonly = args.readonly
    print(f'{"ddpView (read-only)" if args.readonly else "Studio"}: http://127.0.0.1:{server.server_port}', flush=True)
    server.serve_forever()
