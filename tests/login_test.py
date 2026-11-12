#!/usr/bin/env python3
"""Self-check for login-server.py against a fake `claude` that mimics the real
`claude auth login` output (OSC 8 link, colour codes, code prompt)."""
import importlib.util
import os
import pathlib
import stat
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True  # keep __pycache__ out of the image rootfs
ROOT = pathlib.Path(__file__).resolve().parent.parent
FAKE = r"""#!/bin/sh
case "$1 $2" in
"auth status") [ -f "$FAKE_DIR/ok" ] ;;
"auth logout") rm -f "$FAKE_DIR/ok" ;;
"auth login")
    printf 'If the browser did not open, visit: \033]8;;https://claude.com/cai/oauth/authorize?code=true&state=abc\a\033[94mhttps://claude.com/cai/oauth/authorize?code=true&state=abc\033[39m\033]8;;\a\r\nPaste code here if prompted > '
    read -r code
    if [ "$code" = good ]; then touch "$FAKE_DIR/ok"; echo "Login successful."
    else echo "Login failed: That code wasn't accepted."; exit 1; fi ;;
*) exit 2 ;;
esac
"""

tmp = tempfile.mkdtemp()
fake = pathlib.Path(tmp, "claude")
fake.write_text(FAKE)
fake.chmod(fake.stat().st_mode | stat.S_IEXEC)
os.environ["PATH"] = f"{tmp}:{os.environ['PATH']}"
os.environ["FAKE_DIR"] = tmp

spec = importlib.util.spec_from_file_location(
    "login_server", ROOT / "claude_remote/rootfs/usr/local/bin/login-server.py")
srv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(srv)

assert not srv.signed_in(), "not signed in at first"

srv.start()
assert srv.login["url"] == "https://claude.com/cai/oauth/authorize?code=true&state=abc", srv.login["url"]
ok, msg = srv.submit("bad")
assert not ok and msg == "Login failed: That code wasn't accepted.", (ok, msg)
assert srv.login is None, "process cleaned up after an answer"

srv.start()
srv.start()  # a new link replaces the waiting login
ok, msg = srv.submit("good")
assert ok and msg == "Login successful.", (ok, msg)
assert srv.signed_in(), "signed in after a good code"

# Sign out stops Remote Control first (a uniquely named stand-in here), then logs out.
srv.REMOTE_CONTROL = f"fake-remote-control-{os.getpid()}"
rc = subprocess.Popen(["sh", "-c", "trap 'exit 0' TERM; while :; do sleep 0.1; done", srv.REMOTE_CONTROL])
srv.sign_out()
assert rc.wait(timeout=5) == 0, "Remote Control stopped by SIGTERM"
assert not srv.signed_in(), "signed out"

print("login_test: ok")
