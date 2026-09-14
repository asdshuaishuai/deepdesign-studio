#!/usr/bin/env python3
"""Build the engine codec and launch ddpView without mutation routes."""
import os
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parent
engine = Path(os.environ.get('MOONVIZ_DIR', root.parent / 'moonviz'))
subprocess.run(['cargo', 'build', '--manifest-path', str(engine / 'ddp/Cargo.toml'), '--bin', 'ddp_codec'], check=True)
os.execv(sys.executable, [sys.executable, str(root / 'server.py'), '--readonly', '--port', os.environ.get('MOONVIZ_PORT', '8902'), *sys.argv[1:]])
