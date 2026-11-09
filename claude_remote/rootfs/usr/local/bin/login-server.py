#!/usr/bin/env python3
"""Sign-in page behind ingress. Drives `claude auth login` through a pty,
so the user only clicks a link and pastes the code into a form."""
import fcntl
import html
import os
import pty
import re
import select
import signal
import struct
import subprocess
import termios
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs

ANSI = re.compile(rb"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07]*\x07")
URL = re.compile(r"https://\S+")
PROMPT = "Paste code here if prompted >"

login = None  # the running `claude auth login`: pid, fd, raw output, url, rc


def signed_in():
    return subprocess.run(["claude", "auth", "status"], capture_output=True).returncode == 0


def exit_code():
    """Exit code of the login process, or None while it runs."""
    if login["rc"] is None:
        pid, status = os.waitpid(login["pid"], os.WNOHANG)
        if pid:
            login["rc"] = os.waitstatus_to_exitcode(status)
    return login["rc"]


def read(timeout, done):
    """Collect login output until done(text) is true, the pty closes or timeout."""
    end = time.monotonic() + timeout
    text = ANSI.sub(b"", login["raw"]).decode(errors="replace")
    while not done(text) and time.monotonic() < end:
        if select.select([login["fd"]], [], [], 0.2)[0]:
            try:
                chunk = os.read(login["fd"], 65536)
            except OSError:  # EIO: the process closed the pty
                break
            if not chunk:
                break
            login["raw"] += chunk
            text = ANSI.sub(b"", login["raw"]).decode(errors="replace")
    return text


def stop():
    global login
    if login:
        if exit_code() is None:
            os.kill(login["pid"], signal.SIGKILL)
            os.waitpid(login["pid"], 0)
        os.close(login["fd"])
        login = None


def start():
    global login
    stop()
    pid, fd = pty.fork()
    if pid == 0:
        try:
            # Wide terminal, so the URL is printed on one line.
            fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", 50, 2000, 0, 0))
            os.execvp("claude", ["claude", "auth", "login", "--claudeai"])
        finally:
            os._exit(127)
    login = {"pid": pid, "fd": fd, "raw": b"", "rc": None}
    match = URL.search(read(20, lambda t: PROMPT in t))
    login["url"] = match.group(0) if match else None


def submit(code):
    """Send the code to the waiting login. Returns (ok, message)."""
    os.write(login["fd"], code.encode() + b"\r")
    text = read(60, lambda t: exit_code() is not None)
    for _ in range(10):  # the pty can close a moment before the process is reaped
        if exit_code() is not None:
            break
        time.sleep(0.2)
    ok = exit_code() == 0
    answer = text.split(PROMPT)[-1].strip() or "No answer from claude auth login."
    stop()
    return ok, answer.splitlines()[-1]


STYLE = """
:root { color-scheme: light dark; font-family: system-ui, sans-serif; }
body { max-width: 34rem; margin: 2rem auto; padding: 0 1rem; line-height: 1.5; }
a.button, button { display: inline-block; padding: .6rem 1rem; border-radius: .4rem; border: 0;
  background: #d97757; color: #fff; font-size: 1rem; text-decoration: none; cursor: pointer; }
button.link { background: none; color: inherit; text-decoration: underline; padding: 0; font-size: .9rem; }
input { width: 100%; box-sizing: border-box; padding: .6rem; font-size: 1rem; margin: .4rem 0 .8rem; }
.error { border-left: 4px solid #c0392b; padding-left: .8rem; }
small { opacity: .7; }
"""


def page(body):
    return (
        "<!doctype html><html><head><meta charset='utf-8'>"
        "<meta name='viewport' content='width=device-width, initial-scale=1'>"
        f"<title>Claude Remote</title><style>{STYLE}</style></head><body>"
        f"<h1>Claude Remote</h1>{body}"
        "<p><small><a href='terminal/'>Open terminal</a></small></p></body></html>"
    )


def signed_in_page():
    return page(
        "<p>✅ Signed in. Remote Control starts by itself within a few seconds. "
        "Open Claude Code in the Claude app or at claude.ai/code.</p>"
        "<form method='post' action='login'><button class='link'>Sign in again</button></form>"
    )


def form_page(error=""):
    if not login["url"]:
        return page(
            "<p class='error'>Could not start the sign-in. See the app log.</p>"
            "<form method='post' action='login'><button>Try again</button></form>"
        )
    error = f"<p class='error'>{html.escape(error)}</p>" if error else ""
    return page(
        f"{error}<p><b>1.</b> Sign in with your Claude account (Pro, Max, Ultra, Team or Enterprise):</p>"
        f"<p><a class='button' href='{html.escape(login['url'])}' target='_blank' rel='noopener'>"
        "Open Claude sign-in</a></p>"
        "<form method='post' action='code'><p><b>2.</b> Paste the code shown after sign-in:</p>"
        "<input name='code' autocomplete='off' required autofocus><button>Sign in</button></form>"
        "<form method='post' action='login'><button class='link'>Get a new link</button></form>"
    )


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.split("?")[0] != "/":
            return self.send_error(404)
        if login and exit_code() is None:
            return self.html(form_page())
        if signed_in():
            return self.html(signed_in_page())
        start()
        self.html(form_page())

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        fields = parse_qs(self.rfile.read(length).decode())
        if self.path == "/login":
            start()
            return self.redirect()
        if self.path != "/code":
            return self.send_error(404)
        code = re.sub(r"[^\x21-\x7e]", "", fields.get("code", [""])[0])
        if not (code and login and exit_code() is None):
            return self.redirect()
        ok, message = submit(code)
        if ok:
            return self.redirect()
        start()
        self.html(form_page(message))

    def html(self, body):
        data = body.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def redirect(self):
        self.send_response(303)
        self.send_header("Location", "./")  # relative: ingress serves us under a token path
        self.end_headers()

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", 7682), Handler).serve_forever()
