#!/usr/bin/env bash
# =============================================================================
#  BRAIN FREEDOM  v5 (a)  ·  Mantra Productions
#  One file, one keypress. No switches, no flags, nothing to remember.
#  Run it:   bash 5sh_brain_freedom_v5_macos.sh
# =============================================================================
G=$'\033[38;2;224;163;64m'; C=$'\033[38;2;77;214;232m'; Y=$'\033[38;2;242;193;105m'
D=$'\033[38;2;138;133;120m'; W=$'\033[38;2;233;227;212m'; R=$'\033[0m'
APP="$HOME/brain_freedom"; CFG="$HOME/.brain_freedom"; BIN="$HOME/.local/bin"
say(){ printf "  %s\n" "$1"; }
ok(){  printf "  ${G}▍${R} %s\n" "$1"; }
warn(){ printf "  ${Y}▍${R} %s\n" "$1"; }

logo(){
clear 2>/dev/null || true
echo
printf "${G}████████    ████████      ██████    ██████████  ██      ██  ${R}\n"
printf "${G}██      ██  ██      ██  ██      ██      ██      ████    ██  ${R}\n"
printf "${G}████████    ████████    ██      ██      ██      ██  ██  ██  ${R}\n"
printf "${G}██      ██  ████        ██████████      ██      ██    ████  ${R}\n"
printf "${G}██      ██  ██  ████    ██      ██      ██      ██      ██  ${R}\n"
printf "${G}████████    ██    ████  ██      ██  ██████████  ██      ██  ${R}\n"
printf "${C}██████████  ████████    ██████████  ██████████  ████████      ██████    ██      ██  ${R}\n"
printf "${C}██          ██      ██  ██          ██          ██      ██  ██      ██  ████  ████  ${R}\n"
printf "${C}████████    ████████    ████████    ████████    ██      ██  ██      ██  ██  ██  ██  ${R}\n"
printf "${C}██          ████        ██          ██          ██      ██  ██      ██  ██      ██  ${R}\n"
printf "${C}██          ██  ████    ██          ██          ██      ██  ██      ██  ██      ██  ${R}\n"
printf "${C}██          ██    ████  ██████████  ██████████  ████████      ██████    ██      ██  ${R}\n"

echo
printf "  ${D}left brain speaks · right brain works · one golden key${R}\n\n"
}

menu(){
  logo
  if [ -x "$APP/bf_server.py" ]; then printf "  ${D}installed at %s${R}\n\n" "$APP"; fi
  printf "  ${G}[I]${R}  install, or update if it is already here\n"
  printf "  ${G}[S]${R}  start it now\n"
  printf "  ${G}[U]${R}  uninstall everything\n"
  printf "  ${G}[Q]${R}  quit\n\n"
  printf "  ${D}one key, no enter${R}  "
}

install_all(){
logo
[ "$(uname)" = "Darwin" ] || warn "not macOS, installing anyway"
command -v python3 >/dev/null || { say "python3 is required, install the Xcode command line tools first"; return 1; }
ok "python3 $(python3 -V 2>&1 | cut -d' ' -f2)"
mkdir -p "$APP" "$CFG" "$BIN" "$APP/inbox"; chmod 700 "$CFG"
[ -d "$APP/venv" ] && ok "environment exists, updating" || say "creating a private environment, nothing system wide"
python3 -m venv "$APP/venv" >/dev/null 2>&1 || python3 -m venv --system-site-packages "$APP/venv"
"$APP/venv/bin/pip" install -q --upgrade pip >/dev/null 2>&1 || true
"$APP/venv/bin/pip" install -q flask flask-sock simple-websocket requests pillow
ok "flask · websockets · pillow"

cat > "$APP/bf_server.py" <<'BF_SERVER_EOF'
#!/usr/bin/env python3
"""
BRAIN FREEDOM  ·  bf_server.py
Split screen studio for THE BRAIN BRAKE.
Left brain, spoken commands and gallery.  Right brain, a real Claude Code terminal.
"""
import os, sys, json, time, glob, socket, select, signal, subprocess, threading, termios, struct, fcntl, shutil, tty, pty
from pathlib import Path

APP      = Path(__file__).resolve().parent
HOME     = Path.home()
CFG_DIR  = HOME / ".brain_freedom"
CFG      = CFG_DIR / "config.json"
INBOX    = APP / "inbox"
BASE_PORT= 8770
VERSION  = "v5 (a)"

for d in (CFG_DIR, INBOX):
    d.mkdir(parents=True, exist_ok=True)

# ---------------------------------------------------------------- config
DEFAULTS = {
    "browser": "",
    "assemblyai_key": "",
    "github_token": "",
    "repo_path": str(HOME / "brain_freedom" / "BRAIN_BRAKE"),
    "repo_slug": "markoboskoauroville/BRAIN_BRAKE",
    "branch": "main",
    "claude_cmd": os.environ.get("BF_CMD","claude"),
    "voice_lang": "en",
}
def cfg_load():
    d = dict(DEFAULTS)
    if CFG.exists():
        try: d.update(json.loads(CFG.read_text()))
        except Exception: pass
    return d
def cfg_save(d):
    CFG.write_text(json.dumps(d, indent=2)); os.chmod(CFG, 0o600)
C = cfg_load()


# ---------------------------------------------------------------- quiet flask
import logging
logging.getLogger("werkzeug").setLevel(logging.ERROR)
import flask.cli
flask.cli.show_server_banner = lambda *a, **k: None
from flask import Flask, request, jsonify, send_file, Response
from flask_sock import Sock

app = Flask(__name__, static_folder=None)
app.config["SOCK_SERVER_OPTIONS"] = {"ping_interval": 25}
sock = Sock(app)

# ---------------------------------------------------------------- key manager
KEYS = CFG_DIR / "keys.json"
PROVIDERS = {
    "assemblyai": {"label": "AssemblyAI", "hint": "32 hex characters"},
    "github":     {"label": "GitHub",     "hint": "ghp_ or github_pat_"},
    "anthropic":  {"label": "Anthropic",  "hint": "sk-ant-"},
    "gemini":     {"label": "Gemini",     "hint": "AQ. or AIza"},
    "other":      {"label": "Other",      "hint": ""},
}
def keys_load():
    if KEYS.exists():
        try: return json.loads(KEYS.read_text())
        except Exception: pass
    return {k: [] for k in PROVIDERS}
def keys_save(d):
    KEYS.write_text(json.dumps(d, indent=2)); os.chmod(KEYS, 0o600)

import re
def guess_provider(tok):
    """Shape only ranks a key, it never rejects one. Providers rebrand formats."""
    t = tok.strip()
    if t.startswith("sk-ant-"): return "anthropic"
    if t.startswith("ghp_") or t.startswith("github_pat_") or t.startswith("gho_"): return "github"
    if t.startswith("AQ.") or t.startswith("AIza"): return "gemini"
    if re.fullmatch(r"[0-9a-f]{32}", t): return "assemblyai"
    return "other"

def harvest(text):
    """Pull every plausible key out of a messy file. Never discard on shape alone."""
    found = []
    for tok in re.findall(r"[A-Za-z0-9_\-\.]{20,200}", text or ""):
        t = tok.strip(" .,;:'\"")
        if len(t) < 20: continue
        if t.lower().startswith(("http", "www.")): continue
        if "/" in t: continue
        found.append(t)
    seen = set(); out = []
    for t in found:
        if t in seen: continue
        seen.add(t); out.append({"key": t, "provider": guess_provider(t)})
    return out

@app.get("/api/keys")
def keys_get():
    d = keys_load()
    def mask(k):
        return k[:6] + "…" + k[-4:] if len(k) > 12 else "…"
    return jsonify(providers=PROVIDERS, keys={p: [
        {"i": i, "mask": mask(e["key"]), "label": e.get("label",""), "state": e.get("state","untested"),
         "fails": e.get("fails",0), "used": e.get("used",0)}
        for i, e in enumerate(v)] for p, v in d.items()})

@app.post("/api/keys/import")
def keys_import():
    raw = ""
    f = request.files.get("file")
    if f: raw = f.read().decode("utf-8", "ignore")
    else: raw = (request.json or {}).get("text", "")
    cand = harvest(raw)
    d = keys_load()
    added = 0
    for c in cand:
        p = c["provider"]
        if any(e["key"] == c["key"] for e in d.get(p, [])): continue
        d.setdefault(p, []).append({"key": c["key"], "label": "", "state": "untested", "fails": 0, "used": 0})
        added += 1
    keys_save(d)
    counts = {p: len(v) for p, v in d.items() if v}
    return jsonify(ok=True, found=len(cand), added=added, counts=counts)

@app.post("/api/keys/act")
def keys_act():
    o = request.json or {}
    p, i, act = o.get("provider"), o.get("i"), o.get("act")
    d = keys_load(); lst = d.get(p, [])
    if not (0 <= (i or 0) < len(lst)): return jsonify(ok=False, error="no such key")
    if act == "delete": lst.pop(i)
    elif act == "up" and i > 0: lst[i-1], lst[i] = lst[i], lst[i-1]
    elif act == "down" and i < len(lst)-1: lst[i+1], lst[i] = lst[i], lst[i+1]
    elif act == "first": lst.insert(0, lst.pop(i))
    elif act == "label": lst[i]["label"] = o.get("label", "")
    elif act == "test" and p == "assemblyai":
        import requests as rq
        r = rq.get("https://api.assemblyai.com/v2/transcript?limit=1",
                   headers={"authorization": lst[i]["key"]}, timeout=20)
        lst[i]["state"] = "ok" if r.status_code == 200 else "failed"
    keys_save(d)
    return jsonify(ok=True)

def key_list(provider):
    """Ordered candidates. Config key first if present, for backward compatibility."""
    d = keys_load(); out = []
    c = cfg_load()
    legacy = c.get(provider + "_key") or (c.get("github_token") if provider == "github" else "")
    if legacy: out.append(legacy)
    out += [e["key"] for e in d.get(provider, [])]
    seen = set(); ordered = []
    for k in out:
        if k and k not in seen: seen.add(k); ordered.append(k)
    return ordered

def key_result(provider, key, ok):
    d = keys_load()
    for e in d.get(provider, []):
        if e["key"] == key:
            e["state"] = "ok" if ok else "failed"
            e["fails"] = 0 if ok else e.get("fails", 0) + 1
            e["used"] = e.get("used", 0) + (1 if ok else 0)
    keys_save(d)



FAVICON = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
<stop offset="0" stop-color="#f7d38a"/><stop offset=".45" stop-color="#e0a340"/><stop offset="1" stop-color="#a86f1c"/>
</linearGradient></defs>
<rect width="64" height="64" rx="13" fill="#0b0e13"/>
<g transform="rotate(-18 32 32)">
<circle cx="32" cy="19" r="10.5" fill="none" stroke="url(#g)" stroke-width="5.5"/>
<circle cx="32" cy="19" r="4.2" fill="#0b0e13"/>
<rect x="29.4" y="27" width="5.2" height="26" rx="1.6" fill="url(#g)"/>
<rect x="34.6" y="40" width="7.5" height="4.6" rx="1.4" fill="url(#g)"/>
<rect x="34.6" y="48.4" width="5.6" height="4.6" rx="1.4" fill="url(#g)"/>
</g></svg>"""

@app.get("/favicon.svg")
def favicon():
    return Response(FAVICON, mimetype="image/svg+xml")

BROWSER_HINTS = ["Firefox", "Firefox Developer Edition", "LibreWolf", "Zen Browser", "Waterfox",
                 "Safari", "Google Chrome", "Chromium", "Brave Browser", "Microsoft Edge", "Arc", "Vivaldi", "Opera"]

def browsers_found():
    out = []
    for d in ("/Applications", str(HOME / "Applications")):
        if not os.path.isdir(d): continue
        for app_name in sorted(os.listdir(d)):
            if not app_name.endswith(".app"): continue
            name = app_name[:-4]
            if any(h.lower() in name.lower() for h in BROWSER_HINTS):
                out.append(name)
    seen = set(); res = []
    for n in out:
        if n not in seen: seen.add(n); res.append(n)
    return res

@app.get("/api/browsers")
def api_browsers():
    found = browsers_found()
    return jsonify(found=found, chosen=cfg_load().get("browser", ""), preferred=pick_browser(found))

def pick_browser(found=None):
    """Firefox family first, always. macOS defaults are ignored on purpose."""
    c = cfg_load()
    if c.get("browser"): return c["browser"]
    found = found if found is not None else browsers_found()
    for want in ("Firefox", "LibreWolf", "Waterfox", "Zen Browser"):
        for f in found:
            if f.lower().startswith(want.lower()): return f
    return found[0] if found else ""

def open_in_browser(url):
    b = pick_browser()
    if b:
        try:
            subprocess.Popen(["open", "-a", b, url]); return b
        except Exception: pass
    try: subprocess.Popen(["open", url])
    except Exception: pass
    return b or "default"

# ---------------------------------------------------------------- pty
class Term:
    def __init__(self):
        self.fd = None; self.pid = None; self.lock = threading.Lock()
        self.buf = bytearray(); self.clients = []
    def start(self, cmd=None, cols=120, rows=32):
        if self.pid: return
        cmd = cmd or C.get("claude_cmd") or "claude"
        pid, fd = pty.fork()
        if pid == 0:
            os.environ["TERM"] = "xterm-256color"
            os.environ["COLORTERM"] = "truecolor"
            wd = C.get("repo_path")
            try: os.chdir(wd if wd and os.path.isdir(wd) else str(HOME))
            except Exception: pass
            shell = os.environ.get("SHELL") or ""
            if not os.path.exists(shell):
                for cand in ("/bin/zsh", "/bin/bash", "/bin/sh"):
                    if os.path.exists(cand):
                        shell = cand; break
            try:
                # login shell, so the agent inherits the PATH the user actually has
                os.execvp(shell, [shell, "-lc", cmd])
            except Exception as e:
                sys.stdout.write("\r\n  could not start %r in %s\r\n  %s\r\n" % (cmd, shell, e))
                sys.stdout.flush()
                os._exit(1)
        self.pid, self.fd = pid, fd
        self.resize(cols, rows)
        threading.Thread(target=self._pump, daemon=True).start()
    def resize(self, cols, rows):
        if self.fd is None: return
        try: fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
        except Exception: pass
    def _pump(self):
        while True:
            fd = self.fd
            if fd is None: break
            try:
                r,_,_ = select.select([fd], [], [], 0.2)
                if not r: continue
                data = os.read(fd, 65536)
                if not data: break
            except (OSError, ValueError, TypeError):
                break
            self.buf.extend(data); del self.buf[:-200000]
            dead=[]
            for ws in list(self.clients):
                try: ws.send(data.decode("utf-8","replace"))
                except Exception: dead.append(ws)
            for d in dead:
                if d in self.clients: self.clients.remove(d)
        try: os.close(fd)
        except Exception: pass
        self.pid = None; self.fd = None
    def write(self, s):
        if self.fd is None: self.start()
        with self.lock:
            os.write(self.fd, s.encode())
    def type(self, text, cps=90, enter=True):
        """The invisible hand. Types character by character so it can be watched."""
        if self.fd is None: self.start(); time.sleep(1.2)
        delay = 1.0/max(cps,1)
        for ch in text:
            with self.lock:
                try: os.write(self.fd, ch.encode())
                except OSError: return
            time.sleep(delay)
        if enter:
            time.sleep(.25)
            with self.lock: os.write(self.fd, b"\r")
    def kill(self):
        if self.pid:
            try: os.kill(self.pid, signal.SIGTERM)
            except Exception: pass
        self.pid=None; self.fd=None

TERM = Term()

@sock.route("/ws/term")
def ws_term(ws):
    TERM.start()
    TERM.clients.append(ws)
    try:
        if TERM.buf:
            ws.send(bytes(TERM.buf[-40000:]).decode("utf-8","replace"))
        while True:
            msg = ws.receive()
            if msg is None: break
            try:
                o = json.loads(msg)
                if o.get("t") == "resize": TERM.resize(o["cols"], o["rows"]); continue
                if o.get("t") == "in": TERM.write(o["d"]); continue
            except Exception:
                TERM.write(msg)
    finally:
        if ws in TERM.clients: TERM.clients.remove(ws)

# ---------------------------------------------------------------- api
@app.get("/")
def index():
    return send_file(APP / "bf.html")

@app.get("/api/state")
def state():
    c = cfg_load()
    return jsonify({
        "version": VERSION,
        "port": PORT,
        "repo_path": c["repo_path"],
        "repo_slug": c["repo_slug"],
        "branch": c["branch"],
        "has_key": bool(key_list("assemblyai")),
        "has_token": bool(key_list("github")),
        "repo_ok": os.path.isdir(os.path.join(c["repo_path"], ".git")),
        "browser": pick_browser(),
        "term_alive": TERM.pid is not None,
    })

@app.post("/api/config")
def set_config():
    c = cfg_load(); c.update({k:v for k,v in request.json.items() if k in DEFAULTS})
    cfg_save(c); globals()["C"] = c
    return jsonify(ok=True)

@app.post("/api/say")
def say():
    """Send text to the agent, typed visibly."""
    d = request.json or {}
    txt = (d.get("text") or "").strip()
    if not txt: return jsonify(ok=False, error="empty")
    threading.Thread(target=TERM.type, args=(txt,), kwargs={"cps": int(d.get("cps",90))}, daemon=True).start()
    return jsonify(ok=True, chars=len(txt))

@app.post("/api/key")
def key():
    TERM.write(request.json.get("d",""))
    return jsonify(ok=True)

@app.post("/api/restart")
def restart():
    TERM.kill(); time.sleep(.4); TERM.start()
    return jsonify(ok=True)

# ---------------------------------------------------------------- voice
@app.post("/api/transcribe")
def transcribe():
    import requests
    f = request.files.get("audio")
    if not f: return jsonify(ok=False, error="no audio")
    raw = f.read()
    cands = key_list("assemblyai")
    if not cands:
        return jsonify(ok=False, error="No AssemblyAI key yet. Open the gear and import your keys file.")
    t0 = time.time(); tried = []
    for n, k in enumerate(cands):
        h = {"authorization": k}
        try:
            up = requests.post("https://api.assemblyai.com/v2/upload", headers=h, data=raw, timeout=180)
            if up.status_code in (401, 403, 429, 402):
                key_result("assemblyai", k, False); tried.append("key %d rejected (%d)" % (n+1, up.status_code)); continue
            if up.status_code != 200:
                tried.append("key %d upload %d" % (n+1, up.status_code)); continue
            url = up.json()["upload_url"]
            body = {"audio_url": url, "language_code": "en_us", "punctuate": True,
                    "format_text": True, "disfluencies": False, "speech_model": "best"}
            tr = requests.post("https://api.assemblyai.com/v2/transcript", headers=h, json=body, timeout=60)
            tid = tr.json().get("id")
            if not tid:
                key_result("assemblyai", k, False); tried.append("key %d refused the job" % (n+1)); continue
            for _ in range(360):
                time.sleep(1.0)
                p = requests.get("https://api.assemblyai.com/v2/transcript/" + tid, headers=h, timeout=30).json()
                st = p.get("status")
                if st == "completed":
                    key_result("assemblyai", k, True)
                    return jsonify(ok=True, text=p.get("text") or "", bytes=len(raw),
                                   seconds=round(time.time()-t0, 1), key_index=n+1, tried=tried)
                if st == "error":
                    key_result("assemblyai", k, False); tried.append("key %d: %s" % (n+1, p.get("error"))); break
        except Exception as e:
            tried.append("key %d: %s" % (n+1, str(e)[:80]))
    return jsonify(ok=False, error="every key failed", tried=tried)

# ---------------------------------------------------------------- images and github
def sh(cmd, cwd=None):
    if cwd and not os.path.isdir(cwd):
        return 127, "no such directory: %s" % cwd
    try:
        p = subprocess.run(cmd, cwd=cwd, shell=True, capture_output=True, text=True)
    except Exception as e:
        return 127, str(e)
    return p.returncode, (p.stdout or "") + (p.stderr or "")

def ensure_repo():
    """Make sure the checkout exists. Create the folder and clone it if it does not."""
    c = cfg_load()
    path = c.get("repo_path") or str(HOME / "brain_freedom" / "BRAIN_BRAKE")
    slug = c.get("repo_slug") or "markoboskoauroville/BRAIN_BRAKE"
    br   = c.get("branch") or "main"
    if os.path.isdir(os.path.join(path, ".git")):
        return True, "ready", path
    toks = key_list("github")
    if not toks:
        return False, "No GitHub token yet. Tap the gold gear and import your keys file.", path
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    if os.path.isdir(path) and os.listdir(path):
        return False, "%s exists and is not a git checkout. Empty it or point the gear somewhere else." % path, path
    url = "https://x-access-token:%s@github.com/%s.git" % (toks[0], slug)
    rc, out = sh("git clone -q --branch %s %s %s" % (br, url, json.dumps(path)))
    if rc != 0:
        return False, "clone failed: " + out[-300:], path
    return True, "cloned", path

@app.post("/api/image")
def image_in():
    """Take a dropped render, name it properly, commit and push, hand back the raw URL."""
    c = cfg_load()
    f = request.files.get("file")
    name = (request.form.get("name") or "").strip()
    sub  = (request.form.get("folder") or "assets/HERO_V3").strip("/")
    if not f or not name: return jsonify(ok=False, error="need file and name")
    okr, msg, path = ensure_repo()
    if not okr: return jsonify(ok=False, error=msg)
    repo = Path(path)
    dst_dir = repo/sub; dst_dir.mkdir(parents=True, exist_ok=True)
    ext = os.path.splitext(f.filename)[1].lower() or ".png"
    master = dst_dir/(name+ext)
    f.save(master)
    web = None
    try:
        from PIL import Image as PImage
        im = PImage.open(master).convert("RGB"); w=1800
        if im.width > w: im = im.resize((w, int(im.height*w/im.width)), PImage.LANCZOS)
        web = dst_dir/(name+"_web.jpg"); im.save(web, quality=88, optimize=True)
    except Exception:
        pass
    toks = key_list("github")
    tok = toks[0] if toks else ""
    slug = c["repo_slug"]; br = c["branch"]
    rc, out = sh("git add -A && git -c user.name='Brain Freedom' -c user.email='bf@local' commit -q -m %s" %
                 json.dumps("frame "+name), cwd=repo)
    push = ""
    if tok:
        rc2, push = sh("git push -q https://x-access-token:%s@github.com/%s.git %s" % (tok, slug, br), cwd=repo)
    raw = "https://raw.githubusercontent.com/%s/%s/%s/%s%s" % (slug, br, sub, name, ext)
    site= "https://%s.github.io/%s/%s/%s%s" % (slug.split("/")[0], slug.split("/")[1], sub, name, ext)
    return jsonify(ok=True, master=str(master), web=str(web) if web else None, raw=raw, site=site, git=out[-400:], push=push[-200:])

@app.get("/api/gallery")
def gallery():
    c = cfg_load(); repo = Path(c["repo_path"])
    items=[]
    if not repo.is_dir(): return jsonify(items=items)
    for p in sorted(glob.glob(str(repo/"assets/**/*_web.jpg"), recursive=True)):
        rel = os.path.relpath(p, repo)
        items.append({"name": os.path.basename(p).replace("_web.jpg",""), "rel": rel,
                      "url": "/api/file?p="+rel, "mtime": os.path.getmtime(p)})
    items.sort(key=lambda x:-x["mtime"])
    return jsonify(items=items)

@app.get("/api/file")
def file_get():
    c = cfg_load(); repo = Path(c["repo_path"]).resolve()
    p = (repo/request.args.get("p","")).resolve()
    if not str(p).startswith(str(repo)) or not p.exists(): return ("no", 404)
    return send_file(p)

@app.post("/api/repo")
def repo_ensure():
    ok, msg, path = ensure_repo()
    return jsonify(ok=ok, msg=msg, path=path)

@app.post("/api/push")
def push_now():
    ok, msg, path = ensure_repo()
    if not ok: return jsonify(ok=False, out=msg)
    c = cfg_load()
    rc, out = sh("git add -A && git -c user.name='Brain Freedom' -c user.email='bf@local' commit -q -m 'session update' ; git push -q https://x-access-token:%s@github.com/%s.git %s"
                 % ((key_list("github") or [""])[0], c["repo_slug"], c["branch"]), cwd=path)
    return jsonify(ok=rc == 0, out=(out[-600:] or "nothing to push"))

# ---------------------------------------------------------------- usage estimate
@app.get("/api/usage")
def usage():
    """Honest estimate read from local Claude Code session logs. Not an official figure."""
    root = HOME/".claude"/"projects"
    day = {}; total_in=total_out=0; files=0
    now = time.time()
    for p in glob.glob(str(root/"**"/"*.jsonl"), recursive=True):
        if now - os.path.getmtime(p) > 30*86400: continue
        files += 1
        try:
            with open(p, "r", errors="ignore") as fh:
                for line in fh:
                    if '"usage"' not in line: continue
                    try: o = json.loads(line)
                    except Exception: continue
                    u = (o.get("message") or {}).get("usage") or o.get("usage") or {}
                    i = (u.get("input_tokens") or 0) + (u.get("cache_read_input_tokens") or 0) + (u.get("cache_creation_input_tokens") or 0)
                    ot = u.get("output_tokens") or 0
                    if not (i or ot): continue
                    ts = (o.get("timestamp") or "")[:10] or time.strftime("%Y-%m-%d")
                    d = day.setdefault(ts, {"in":0,"out":0})
                    d["in"] += i; d["out"] += ot
                    total_in += i; total_out += ot
        except Exception: continue
    days = sorted(day.items())[-14:]
    today = time.strftime("%Y-%m-%d")
    t = day.get(today, {"in":0,"out":0})
    recent = [v["in"]+v["out"] for k,v in days[-7:]] or [0]
    avg = sum(recent)/max(len(recent),1)
    return jsonify(ok=True, files=files, today=t, total_in=total_in, total_out=total_out,
                   days=[{"d":k,"in":v["in"],"out":v["out"]} for k,v in days],
                   avg7=int(avg), note="Estimate from local session logs, not an official account figure.")

# ---------------------------------------------------------------- banner
G="\033[38;2;224;163;64m"; C2="\033[38;2;77;214;232m"; D="\033[38;2;140;135;120m"; W="\033[38;2;231;226;214m"; R="\033[0m"
def banner(port, url):
    tty_ok = sys.stdout.isatty()
    def c(x, col): return (col+x+R) if tty_ok else x
    BRAIN = [
        '████████    ████████      ██████    ██████████  ██      ██  ',
        '██      ██  ██      ██  ██      ██      ██      ████    ██  ',
        '████████    ████████    ██      ██      ██      ██  ██  ██  ',
        '██      ██  ████        ██████████      ██      ██    ████  ',
        '██      ██  ██  ████    ██      ██      ██      ██      ██  ',
        '████████    ██    ████  ██      ██  ██████████  ██      ██  ',
    ]
    FREE = [
        '██████████  ████████    ██████████  ██████████  ████████      ██████    ██      ██  ',
        '██          ██      ██  ██          ██          ██      ██  ██      ██  ████  ████  ',
        '████████    ████████    ████████    ████████    ██      ██  ██      ██  ██  ██  ██  ',
        '██          ████        ██          ██          ██      ██  ██      ██  ██      ██  ',
        '██          ██  ████    ██          ██          ██      ██  ██      ██  ██      ██  ',
        '██          ██    ████  ██████████  ██████████  ████████      ██████    ██      ██  ',
    ]
    print()
    for r in BRAIN: print("  " + c(r, G))
    for r in FREE:  print("  " + c(r, C2))
    print()
    box = [
        ("version", VERSION),
        ("address", url),
        ("port",    str(port)),
        ("repo",    cfg_load()["repo_path"]),
        ("branch",  cfg_load()["branch"]),
        ("browser", pick_browser() or "none found"),
        ("voice",   ("AssemblyAI, %d keys, opus 24k mono" % len(key_list("assemblyai"))) if key_list("assemblyai") else "no key yet, open the gear"),
    ]
    w = max(len(k) for k,_ in box)
    print("  "+c("┌"+"─"*58+"┐", D))
    for k,v in box:
        line = " %s  %s" % (k.ljust(w), v)
        print("  "+c("│", D)+c(line.ljust(58)[:58], W)+c("│", D))
    print("  "+c("└"+"─"*58+"┘", D))
    print()
    print("  "+c("q", G)+c(" quit    ", D)+c("o", G)+c(" open in browser    ", D)+c("b", G)+c(" background", D))
    print()

def free_port(start):
    for p in range(start, start+60):
        s = socket.socket()
        try:
            s.bind(("127.0.0.1", p)); s.close(); return p
        except OSError:
            s.close()
    return start

def hotkeys(port, url):
    if not sys.stdin.isatty(): return
    fd = sys.stdin.fileno(); old = termios.tcgetattr(fd)
    try:
        tty.setcbreak(fd)
        while True:
            r,_,_ = select.select([sys.stdin],[],[],0.4)
            if not r: continue
            ch = sys.stdin.read(1).lower()
            if ch == "q":
                print("\n  "+G+"closing"+R+"\n"); TERM.kill(); os._exit(0)
            if ch == "o":
                b = open_in_browser(url)
                print("\n  " + D + "opened in " + b + R + "\n")
            if ch == "b":
                print("\n  "+D+"backgrounded, still serving on "+url+R+"\n")
                termios.tcsetattr(fd, termios.TCSADRAIN, old); return
    except Exception:
        pass
    finally:
        try: termios.tcsetattr(fd, termios.TCSADRAIN, old)
        except Exception: pass

PORT = free_port(BASE_PORT)
if __name__ == "__main__":
    url = "http://127.0.0.1:%d" % PORT
    (APP/"port").write_text(str(PORT))
    banner(PORT, url)
    b = open_in_browser(url)
    print("  " + D + "opening " + (b or "your browser") + R + "\n")
    threading.Thread(target=hotkeys, args=(PORT,url), daemon=True).start()
    from werkzeug.serving import make_server
    srv = make_server("127.0.0.1", PORT, app, threaded=True)
    srv.serve_forever()

BF_SERVER_EOF
ok "engine written"

cat > "$APP/bf.html" <<'BF_HTML_EOF'
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Brain Freedom</title>
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@xterm/xterm@5.5.0/css/xterm.min.css">
<style>
:root{
 --ink:#08090c; --panel:#0e1014; --panel2:#14171c; --line:#23272f; --edge:#2e2a20;
 --paper:#e9e3d4; --dim:#8a8578; --gold:#e0a340; --gold2:#f2c169; --red:#c9453c; --green:#7fb069;
 --mono:'SF Mono',ui-monospace,Menlo,Consolas,monospace; --ui:var(--mono);
}
*{box-sizing:border-box}
html,body{height:100%;margin:0;background:var(--ink);color:var(--paper);font-family:var(--mono);
 font-size:13px;overflow:hidden;-webkit-font-smoothing:antialiased}
button{font-family:var(--mono);cursor:pointer;color:var(--paper)}
.pill,nav button,.btn{background:var(--panel2);border:1px solid var(--line);border-radius:999px;
 padding:9px 18px;font-size:11px;letter-spacing:.14em;text-transform:uppercase;transition:.14s;color:var(--paper)}
.pill:hover,nav button:hover,.btn:hover{border-color:var(--edge);color:var(--gold2)}
.pill.on,nav button.a,.btn.g{background:var(--gold);border-color:var(--gold);color:#0a0a0a;font-weight:600}
.pill.sm{padding:6px 12px;font-size:10px}
#app{display:flex;height:100vh;width:100vw}
#left{width:46%;min-width:340px;display:flex;flex-direction:column;border-right:1px solid var(--line)}
#drag{width:5px;cursor:col-resize;background:var(--line);flex:0 0 5px}
#drag:hover{background:var(--gold)}
header{display:flex;align-items:center;gap:10px;padding:12px 14px;border-bottom:1px solid var(--line)}
.logo{color:var(--gold);font-size:12px;letter-spacing:.24em;text-transform:uppercase}
.sub,.k,label{color:var(--dim);font-size:10px;letter-spacing:.16em;text-transform:uppercase}
.spacer{flex:1}
.dot{width:7px;height:7px;border-radius:50%;background:var(--red)}.dot.on{background:var(--green)}
#gear{width:36px;height:36px;border-radius:50%;background:var(--gold);border:0;color:#0a0a0a;font-size:17px;
 display:flex;align-items:center;justify-content:center;box-shadow:0 0 18px rgba(224,163,64,.3)}
nav{display:flex;gap:8px;padding:12px 14px 0;border:0}
main{flex:1;overflow-y:auto;padding:14px}
section{display:none}section.a{display:block}
.msg{margin:0 0 12px;line-height:1.65;font-size:13.5px}
.msg .who{color:var(--gold);font-size:9px;letter-spacing:.2em;text-transform:uppercase;display:block;margin-bottom:3px}
.msg.sys{color:var(--dim)}.msg.sys b{color:var(--gold2);font-weight:400}
footer{border-top:1px solid var(--line);padding:12px 14px;background:transparent}
#box{width:100%;background:var(--panel);border:1px solid var(--edge);border-radius:16px;color:var(--paper);
 padding:14px;font-size:14px;font-family:var(--mono);resize:none;min-height:88px;line-height:1.55}
#box:focus{outline:0;border-color:var(--gold)}
.tools{display:flex;align-items:center;gap:8px;margin-top:10px;position:static;padding:0}
.icon{width:54px;height:54px;border-radius:50%;background:var(--gold);border:0;color:#0a0a0a;
 font-size:12px;letter-spacing:.08em;font-weight:700;display:flex;align-items:center;justify-content:center;
 box-shadow:0 0 22px rgba(224,163,64,.25)}
.icon.rec{background:var(--red);color:#fff}
.icon.small{width:auto;height:auto;border-radius:999px;background:var(--panel2);color:var(--paper);
 border:1px solid var(--line);padding:9px 16px;font-size:10px;box-shadow:none;letter-spacing:.14em}
.send{margin-left:0;background:var(--gold);color:#0a0a0a;border:0;border-radius:999px;padding:10px 20px;
 font-weight:700;font-size:11px;letter-spacing:.16em;text-transform:uppercase}
.meter{color:var(--dim);font-size:10px;letter-spacing:.06em;min-width:186px;text-align:right}
.wave{height:26px;flex:1;display:flex;align-items:center;gap:2px;overflow:hidden;background:var(--panel);
 border:1px solid var(--edge);border-radius:10px;padding:0 8px}
.wave i{width:3px;background:var(--gold);height:2px;border-radius:2px}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:10px}
.card{border:1px solid var(--edge);border-radius:14px;overflow:hidden;background:var(--panel)}
.card img{width:100%;display:block}
.card .cap{padding:8px 10px;display:flex;gap:8px;align-items:center;font-size:10px;color:var(--dim)}
.card .cap b{color:var(--paper);font-weight:400;flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.drop{border:1px dashed var(--edge);border-radius:16px;padding:24px;text-align:center;color:var(--dim);
 font-size:11px;letter-spacing:.06em;margin-bottom:12px}
.drop.hot{border-color:var(--gold);color:var(--gold)}
input[type=text],input[type=password]{width:100%;background:var(--ink);border:1px solid var(--edge);
 border-radius:12px;color:var(--paper);padding:11px 13px;font-family:var(--mono);font-size:12px;margin:5px 0 12px}
input:focus{outline:0;border-color:var(--gold)}
.row{display:flex;gap:8px;flex-wrap:wrap}
.bar{height:5px;background:var(--panel2);border-radius:3px;overflow:hidden;margin:5px 0 12px}
.bar i{display:block;height:100%;background:var(--gold)}
.v{font-size:26px;color:var(--gold2);font-family:var(--mono)}
.two{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-bottom:16px}
.two>div{border:1px solid var(--edge);border-radius:16px;padding:14px;background:var(--panel)}
#modal{position:fixed;inset:0;background:rgba(4,5,7,.88);display:none;align-items:center;justify-content:center;
 z-index:80;padding:24px}
#modal.on{display:flex}
.sheet{width:min(780px,96vw);max-height:88vh;overflow-y:auto;background:var(--panel);border:1px solid var(--edge);
 border-radius:22px;padding:22px}
.sheet h2{margin:22px 0 6px;font-size:11px;letter-spacing:.22em;text-transform:uppercase;color:var(--gold)}
.sheet h2:first-child{margin-top:0}
.keyrow{display:flex;align-items:center;gap:8px;padding:9px 12px;border:1px solid var(--line);border-radius:12px;
 margin-bottom:7px;background:var(--ink)}
.keyrow .m{flex:1;font-size:11px;color:var(--paper);letter-spacing:.04em}
.st{font-size:9px;letter-spacing:.14em;text-transform:uppercase;padding:3px 9px;border-radius:999px;
 border:1px solid var(--line);color:var(--dim)}
.st.ok{color:var(--green);border-color:#2c3a2c}.st.failed{color:var(--red);border-color:#3a2626}
.prov{margin:16px 0 8px;display:flex;align-items:center;gap:10px}
.prov b{color:var(--gold2);font-weight:400;font-size:11px;letter-spacing:.18em;text-transform:uppercase}
.note{color:var(--dim);font-size:11px;line-height:1.8;letter-spacing:.03em;text-transform:none}
#reader{position:fixed;inset:auto 0 0 0;height:46%;background:#0a0b0e;border-top:1px solid var(--gold);
 display:none;flex-direction:column;z-index:60}
#reader.on{display:flex}
#rtxt{flex:1;overflow-y:auto;padding:26px 30px;font-size:19px;line-height:1.9;color:#efe9dc;font-family:var(--mono)}
#rtxt span.on{background:var(--gold);color:#0a0a0a;border-radius:3px}
.rbar{display:flex;gap:8px;padding:10px 14px;border-top:1px solid var(--line);align-items:center}
#right{flex:1;display:flex;flex-direction:column;background:#06070a;min-width:0}
#rhead{display:flex;align-items:center;gap:8px;padding:10px 14px;border-bottom:1px solid var(--line)}
#term{flex:1;padding:8px 10px;min-height:0}

:root{--fsL:13.5px; --fsT:13px}
.msg,.msg .who{font-size:inherit}
#chat,#gal,#use{font-size:var(--fsL)}
.msg{font-size:var(--fsL)}
#box{font-size:calc(var(--fsL) + 0.5px)}
#mic{background:#2a0f0d;border:2px solid var(--red);color:#ff8f86;box-shadow:0 0 20px rgba(201,69,60,.22)}
#mic.rec{background:var(--red);border-color:#ff6b60;color:#fff}
#read{background:#0c1a2a;border:2px solid #3d7fbf;color:#8fc4ff;box-shadow:0 0 18px rgba(61,127,191,.18);
 border-radius:999px;padding:10px 18px;font-size:10px;letter-spacing:.16em;text-transform:uppercase;width:auto;height:auto}
.fs{display:flex;align-items:center;gap:6px}
.fs button{width:30px;height:30px;border-radius:50%;background:var(--panel2);border:1px solid var(--line);
 color:var(--paper);font-size:14px;line-height:1;display:flex;align-items:center;justify-content:center}
.fs button:hover{border-color:var(--gold);color:var(--gold)}
.fs span{color:var(--dim);font-size:9px;letter-spacing:.14em;min-width:30px;text-align:center}
#right{padding:0}
#term{padding:14px 22px 14px 18px}
.xterm-viewport{scrollbar-width:thin}
#rhead{padding:10px 22px 10px 16px}
</style></head>
<body>
<div id="app">
 <div id="left">
  <header>
    <span class="logo">Brain Freedom</span>
    <span class="sub" id="ver"></span>
    <span class="spacer"></span>
    <span class="dot" id="live"></span>
    <span class="sub" id="repo"></span>
    <button id="gear" title="Settings and keys">&#9881;</button>
  </header>
  <nav>
    <button class="a" data-t="chat">Command</button>
    <button data-t="gal">Frames</button>
    <button data-t="use">Usage</button>
    
  </nav>
  <main>
    <section id="chat" class="a"></section>

    <section id="gal">
      <div class="drop" id="drop">Drop a render here, or click to choose.<br>
        <span class="k">It is named, optimised, committed and pushed, and you get the link back.</span></div>
      <label>Name</label><input type="text" id="iname" placeholder="HERO_V3_1">
      <label>Folder in repo</label><input type="text" id="ifolder" value="assets/HERO_V3">
      <div class="grid" id="grid"></div>
    </section>

    <section id="use">
      <div class="two">
        <div><div class="k">Today, tokens</div><div class="v" id="uToday">0</div></div>
        <div><div class="k">Daily average, 7 days</div><div class="v" id="uAvg">0</div></div>
      </div>
      <div class="k">Last 14 days</div>
      <div id="uDays"></div>
      <p class="k" id="uNote" style="margin-top:16px;line-height:1.6"></p>
    </section>

    
  </main>

  <footer>
    <textarea id="box" placeholder="Speak or type. This goes to the agent on the right, typed one character at a time."></textarea>
    <div class="tools">
      <button class="icon" id="mic" title="Record">REC</button>
      <button class="icon small" id="read" title="Read aloud">Read</button>
      <div class="fs" title="Text size, left side">
      <button id="lminus">&minus;</button><span id="lsize">13</span><button id="lplus">+</button>
    </div>
    <div class="wave" id="wave"></div>
      <span class="meter" id="meter">ready</span>
      <button class="send" id="send">Send</button>
    </div>
  </footer>
 </div>

 <div id="drag"></div>

 <div id="right">
   <div id="rhead">
     <span class="logo" style="color:var(--cyan)">Engine</span>
     <span class="sub">claude code, live pty</span>
     <span class="spacer"></span>
     <div class="fs" title="Text size, terminal">
       <button id="tminus">&minus;</button><span id="tsize">13</span><button id="tplus">+</button>
     </div>
     <button class="btn" id="esc">esc</button>
     <button class="btn" id="ctrlc">ctrl c</button>
     <button class="btn" id="clr">clear</button>
   </div>
   <div id="term"></div>
 </div>
</div>


<div id="modal"><div class="sheet">
  <h2>Keys</h2>
  <p class="note">Point at any file. Notes, exports, a mess, it does not matter. Every key inside is found,
  sorted by provider and queued. Transcription walks the queue until one answers, so a dead key costs you a
  second rather than a session. Shape is only used to sort, never to reject, because providers change their
  formats without telling anybody.</p>
  <div class="row" style="margin:12px 0 10px">
    <button class="pill on" id="kimport">Import from file</button>
    <button class="pill" id="kpaste">Paste text</button>
    <button class="pill" id="krefresh">Refresh</button>
  </div>
  <div id="klist"></div>
  <h2>Browser</h2>
  <p class="note">Brain Freedom opens itself in the browser you pick here, ignoring whatever macOS thinks the
  default is. Firefox is chosen first when it is present, because its recorder produces Opus, which is the
  right format for speech.</p>
  <div class="row" id="brow" style="margin:10px 0 4px"></div>

  <h2>Repository</h2>
  <label>Path on this Mac</label><input type="text" id="cRepo">
  <label>Slug</label><input type="text" id="cSlug">
  <label>Branch</label><input type="text" id="cBr">
  <label>Agent command</label><input type="text" id="cCmd">
  <div class="row" style="margin-top:4px">
    <button class="pill on" id="save">Save</button>
    <button class="pill" id="restart">Restart agent</button>
    <button class="pill" id="clone">Create or clone repository</button>
    <button class="pill" id="pushnow">Push now</button>
    <span class="spacer"></span><button class="pill" id="close">Close</button>
  </div>
</div></div>

<div id="reader">
  <div id="rtxt"></div>
  <div class="rbar">
    <button class="btn" id="rplay">Pause</button>
    <button class="btn" id="rslow">Slower</button>
    <button class="btn" id="rfast">Faster</button>
    <span class="spacer"></span><span class="k" id="rstat"></span>
    <button class="btn" id="rclose">Close</button>
  </div>
</div>

<script src="https://cdn.jsdelivr.net/npm/@xterm/xterm@5.5.0/lib/xterm.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/@xterm/addon-fit@0.10.0/lib/addon-fit.min.js"></script>
<script>
const $=s=>document.querySelector(s), $$=s=>[...document.querySelectorAll(s)];
let ST={};

/* ---------------- terminal ---------------- */
const term=new Terminal({
  fontFamily:"'SF Mono',Menlo,monospace", fontSize:13, lineHeight:1.25, cursorBlink:true,
  allowProposedApi:true, scrollback:8000, macOptionIsMeta:true,
  theme:{background:'#0a0c11',foreground:'#e7e2d6',cursor:'#e0a340',selectionBackground:'#243044',
    black:'#0a0c11',red:'#d2453c',green:'#7fb069',yellow:'#e0a340',blue:'#4dd6e8',magenta:'#9b8cf5',
    cyan:'#4dd6e8',white:'#e7e2d6',brightBlack:'#5a5c63'}
});
const fit=new FitAddon.FitAddon(); term.loadAddon(fit);
term.open($('#term')); fit.fit();
let ws;
function connect(){
  ws=new WebSocket((location.protocol==='https:'?'wss':'ws')+'://'+location.host+'/ws/term');
  ws.onopen=()=>{ $('#live').classList.add('on'); sendSize(); };
  ws.onmessage=e=>term.write(e.data);
  ws.onclose=()=>{ $('#live').classList.remove('on'); setTimeout(connect,1500); };
}
function sendSize(){ if(ws&&ws.readyState===1) ws.send(JSON.stringify({t:'resize',cols:term.cols,rows:term.rows})); }
term.onData(d=>{ if(ws&&ws.readyState===1) ws.send(JSON.stringify({t:'in',d})); });
new ResizeObserver(()=>{ fit.fit(); sendSize(); }).observe($('#term'));
connect();
$('#esc').onclick=()=>fetch('/api/key',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({d:'\x1b'})});
$('#ctrlc').onclick=()=>fetch('/api/key',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({d:'\x03'})});
$('#clr').onclick=()=>term.clear();

/* ---------------- tabs ---------------- */
$$('nav button').forEach(b=>b.onclick=()=>{
  $$('nav button').forEach(x=>x.classList.remove('a')); b.classList.add('a');
  $$('main section').forEach(s=>s.classList.remove('a'));
  $('#'+b.dataset.t).classList.add('a');
  if(b.dataset.t==='gal') loadGallery();
  if(b.dataset.t==='use') loadUsage();
});

/* ---------------- log ---------------- */
function log(who,text,cls){
  const d=document.createElement('div'); d.className='msg '+(cls||'');
  d.innerHTML='<span class="who">'+who+'</span>'+text;
  $('#chat').appendChild(d); $('#chat').parentElement.scrollTop=1e9; return d;
}

/* ---------------- send ---------------- */
async function send(){
  const t=$('#box').value.trim(); if(!t) return;
  log('you',t.replace(/</g,'&lt;'),'me'); $('#box').value='';
  const r=await(await fetch('/api/say',{method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify({text:t,cps:110})})).json();
  log('engine','typing '+r.chars+' characters into the agent','sys');
}
$('#send').onclick=send;
$('#box').addEventListener('keydown',e=>{ if(e.key==='Enter'&&(e.metaKey||e.ctrlKey)) send(); });

/* ---------------- voice ---------------- */
let rec,chunks=[],t0,tick,analyser,actx;
const bars=[...Array(28)].map(()=>{const i=document.createElement('i');$('#wave').appendChild(i);return i;});
$('#mic').onclick=async()=>{
  if(rec&&rec.state==='recording'){ rec.stop(); return; }
  let stream;
  try{ stream=await navigator.mediaDevices.getUserMedia({audio:{channelCount:1,noiseSuppression:true,echoCancellation:true}}); }
  catch(e){ log('mic','microphone refused. Firefox asks once per site, allow it in the address bar.','sys'); return; }
  actx=new AudioContext(); const src=actx.createMediaStreamSource(stream);
  analyser=actx.createAnalyser(); analyser.fftSize=64; src.connect(analyser);
  const mime=MediaRecorder.isTypeSupported('audio/ogg;codecs=opus')?'audio/ogg;codecs=opus':'audio/webm;codecs=opus';
  rec=new MediaRecorder(stream,{mimeType:mime,audioBitsPerSecond:24000});
  chunks=[]; t0=Date.now();
  rec.ondataavailable=e=>{ if(e.data.size) chunks.push(e.data); };
  rec.onstop=async()=>{
    clearInterval(tick); stream.getTracks().forEach(t=>t.stop()); try{actx.close()}catch(e){}
    $('#mic').classList.remove('rec'); $('#mic').textContent='REC'; bars.forEach(b=>b.style.height='2px');
    const blob=new Blob(chunks,{type:mime});
    const kb=(blob.size/1024).toFixed(0), secs=((Date.now()-t0)/1000).toFixed(0);
    $('#meter').textContent='uploading '+kb+' KB · '+secs+'s';
    const fd=new FormData(); fd.append('audio',blob,'v.'+(mime.includes('ogg')?'ogg':'webm'));
    const up=Date.now();
    try{
      const r=await(await fetch('/api/transcribe',{method:'POST',body:fd})).json();
      if(!r.ok){ $('#meter').textContent='failed';
        log('voice',r.error+((r.tried&&r.tried.length)?'<br>'+r.tried.join('<br>'):''),'sys'); return; }
      const rate=(blob.size/1024/((Date.now()-up)/1000)).toFixed(0);
      $('#meter').textContent=kb+' KB · '+rate+' KB/s · '+r.seconds+'s · key '+r.key_index;
      if(r.tried&&r.tried.length) log('voice','key 1 rejected, fell through to key '+r.key_index,'sys');
      $('#box').value=($('#box').value?$('#box').value+' ':'')+r.text; $('#box').focus();
    }catch(e){ $('#meter').textContent='network error'; }
  };
  rec.start(250); $('#mic').classList.add('rec'); $('#mic').textContent='STOP';
  const buf=new Uint8Array(analyser.frequencyBinCount);
  tick=setInterval(()=>{
    analyser.getByteFrequencyData(buf);
    bars.forEach((b,i)=>{ b.style.height=Math.max(2,(buf[i%buf.length]/255)*22)+'px'; });
    const s=((Date.now()-t0)/1000).toFixed(0);
    const est=(chunks.reduce((a,c)=>a+c.size,0)/1024).toFixed(0);
    $('#meter').textContent='recording · '+s+'s · '+est+' KB';
  },120);
};

/* ---------------- reader ---------------- */
let words=[],wi=0,rate=1,utt;
function readAloud(text){
  const box=$('#rtxt'); box.innerHTML='';
  words=text.split(/(\s+)/);
  words.forEach((w,i)=>{ const s=document.createElement('span'); s.textContent=w;
    if(w.trim()) s.className='w'; s.dataset.i=i; box.appendChild(s); });
  $('#reader').classList.add('on');
  speechSynthesis.cancel();
  utt=new SpeechSynthesisUtterance(text); utt.rate=rate; utt.lang='en-GB';
  const v=speechSynthesis.getVoices().find(v=>/en-GB|Daniel|Serena|Karen/.test(v.name+v.lang));
  if(v) utt.voice=v;
  utt.onboundary=e=>{
    if(e.name!=='word'&&e.charIndex==null) return;
    let acc=0,idx=0;
    for(let i=0;i<words.length;i++){ acc+=words[i].length; if(acc>e.charIndex){ idx=i; break; } }
    $$('#rtxt span.on').forEach(s=>s.classList.remove('on'));
    const s=$('#rtxt span[data-i="'+idx+'"]'); if(s){ s.classList.add('on'); s.scrollIntoView({block:'center',behavior:'smooth'}); }
    $('#rstat').textContent='rate '+rate.toFixed(1)+'x';
  };
  utt.onend=()=>{ $('#rstat').textContent='finished'; };
  speechSynthesis.speak(utt);
}
$('#read').onclick=()=>{
  const sel=window.getSelection().toString().trim();
  const last=[...$$('#chat .msg')].pop();
  readAloud(sel|| (last?last.innerText.replace(/^\w+\n/,''):'Nothing to read yet.'));
};
$('#rclose').onclick=()=>{ speechSynthesis.cancel(); $('#reader').classList.remove('on'); };
$('#rplay').onclick=()=>{ if(speechSynthesis.paused){speechSynthesis.resume();$('#rplay').textContent='Pause';}
  else {speechSynthesis.pause();$('#rplay').textContent='Play';} };
$('#rslow').onclick=()=>{ rate=Math.max(.5,rate-.1); restartRead(); };
$('#rfast').onclick=()=>{ rate=Math.min(2.2,rate+.1); restartRead(); };
function restartRead(){ const t=$('#rtxt').innerText; speechSynthesis.cancel(); readAloud(t); }

/* ---------------- gallery ---------------- */
async function loadGallery(){
  const r=await(await fetch('/api/gallery')).json();
  $('#grid').innerHTML=r.items.map(i=>`<div class="card"><img loading="lazy" src="${i.url}">
   <div class="cap"><b>${i.name}</b><button class="btn" style="padding:3px 7px;font-size:11px"
   onclick="copyRaw('${i.rel}')">link</button></div></div>`).join('');
}
function copyRaw(rel){
  const url='https://raw.githubusercontent.com/'+ST.repo_slug+'/'+ST.branch+'/'+rel.replace('_web.jpg','.png');
  navigator.clipboard.writeText(url); log('link',url,'sys');
}
const drop=$('#drop');
drop.onclick=()=>{ const i=document.createElement('input'); i.type='file'; i.onchange=e=>upload(e.target.files[0]); i.click(); };
['dragover','dragenter'].forEach(e=>drop.addEventListener(e,ev=>{ev.preventDefault();drop.classList.add('hot')}));
['dragleave','drop'].forEach(e=>drop.addEventListener(e,ev=>{ev.preventDefault();drop.classList.remove('hot')}));
drop.addEventListener('drop',ev=>{ if(ev.dataTransfer.files[0]) upload(ev.dataTransfer.files[0]); });
async function upload(f){
  const name=$('#iname').value.trim(); if(!name){ log('frames','give it a name first','sys'); return; }
  const fd=new FormData(); fd.append('file',f); fd.append('name',name); fd.append('folder',$('#ifolder').value.trim());
  log('frames','uploading '+(f.size/1048576).toFixed(1)+' MB','sys');
  const r=await(await fetch('/api/image',{method:'POST',body:fd})).json();
  if(!r.ok){ log('frames',r.error,'sys'); return; }
  navigator.clipboard.writeText(r.raw);
  log('frames','<b>'+name+'</b> committed and pushed. Link copied.<br>'+r.raw,'sys');
  loadGallery();
}

/* ---------------- usage ---------------- */
async function loadUsage(){
  const r=await(await fetch('/api/usage')).json();
  $('#uToday').textContent=((r.today.in+r.today.out)/1000).toFixed(0)+'k';
  $('#uAvg').textContent=(r.avg7/1000).toFixed(0)+'k';
  const max=Math.max(1,...r.days.map(d=>d.in+d.out));
  $('#uDays').innerHTML=r.days.map(d=>`<div class="k">${d.d} · ${((d.in+d.out)/1000).toFixed(0)}k</div>
   <div class="bar"><i style="width:${((d.in+d.out)/max*100).toFixed(0)}%"></i></div>`).join('');
  let advice='';
  if(r.avg7>0){
    const t=(r.today.in+r.today.out);
    advice = t > r.avg7*1.6 ? 'You are well above your usual pace today. A break would be sensible.' :
             t > r.avg7 ? 'Slightly above your usual pace.' : 'Comfortably within your usual pace.';
  }
  $('#uNote').textContent=advice+' '+r.note;
}



/* ---------------- text size ---------------- */
function setFS(which,val){
  if(which==='L'){ FSL=Math.max(11,Math.min(30,val));
    document.documentElement.style.setProperty('--fsL',FSL+'px');
    $('#lsize').textContent=FSL; localStorage.setItem('fsL',FSL); }
  else { FST=Math.max(9,Math.min(28,val));
    term.options.fontSize=FST; $('#tsize').textContent=FST; localStorage.setItem('fsT',FST);
    setTimeout(()=>{fit.fit();size()},30); }
}
let FSL=parseInt(localStorage.getItem('fsL')||'14'), FST=parseInt(localStorage.getItem('fsT')||'13');
$('#lplus').onclick=()=>setFS('L',FSL+1); $('#lminus').onclick=()=>setFS('L',FSL-1);
$('#tplus').onclick=()=>setFS('T',FST+1); $('#tminus').onclick=()=>setFS('T',FST-1);
setFS('L',FSL); setFS('T',FST);

/* ---------------- browser ---------------- */
async function browsers(){
  const r=await(await fetch('/api/browsers')).json();
  $('#brow').innerHTML = (r.found.length? r.found : ['none found']).map(b=>
    '<button class="pill'+(b===r.chosen||(!r.chosen&&b===r.preferred)?' on':'')+'" onclick="pickBrowser(\''+b.replace(/'/g,"")+'\')">'+b+'</button>').join('');
}
async function pickBrowser(b){
  await fetch('/api/config',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({browser:b})});
  log('browser',b+' will be used from now on','sys'); browsers();
}

/* ---------------- keys ---------------- */
async function keys(){
  const r=await(await fetch('/api/keys')).json();
  let h='';
  for(const p in r.providers){
    const list=r.keys[p]||[];
    if(!list.length && p==='other') continue;
    h+='<div class="prov"><b>'+r.providers[p].label+'</b><span class="k">'+list.length+' key(s)</span></div>';
    h+= list.length ? list.map(e=>'<div class="keyrow"><span class="m">'+e.mask+'</span>'+
        '<span class="st '+e.state+'">'+e.state+'</span>'+
        '<button class="pill sm" onclick="kact(\''+p+'\','+e.i+',\'first\')">first</button>'+
        (p==='assemblyai'?'<button class="pill sm" onclick="kact(\''+p+'\','+e.i+',\'test\')">test</button>':'')+
        '<button class="pill sm" onclick="kact(\''+p+'\','+e.i+',\'delete\')">&times;</button></div>').join('')
      : '<span class="k">none</span>';
  }
  $('#klist').innerHTML=h;
}
async function kact(p,i,act){
  await fetch('/api/keys/act',{method:'POST',headers:{'Content-Type':'application/json'},
   body:JSON.stringify({provider:p,i:i,act:act})}); keys();
}
$('#kimport').onclick=()=>{const inp=document.createElement('input');inp.type='file';
  inp.onchange=async e=>{const fd=new FormData();fd.append('file',e.target.files[0]);
   const r=await(await fetch('/api/keys/import',{method:'POST',body:fd})).json();
   log('keys','found '+r.found+', added '+r.added,'sys');keys();boot();};inp.click();};
$('#kpaste').onclick=async()=>{const t=prompt('Paste anything that contains keys');if(!t)return;
  const r=await(await fetch('/api/keys/import',{method:'POST',headers:{'Content-Type':'application/json'},
   body:JSON.stringify({text:t})})).json();log('keys','found '+r.found+', added '+r.added,'sys');keys();boot();};
$('#krefresh').onclick=keys;
$('#gear').onclick=()=>{$('#modal').classList.add('on');keys();browsers();};
$('#close').onclick=()=>$('#modal').classList.remove('on');
$('#modal').addEventListener('click',e=>{if(e.target.id==='modal')$('#modal').classList.remove('on')});

/* ---------------- settings ---------------- */
async function boot(){
  ST=await(await fetch('/api/state')).json();
  $('#ver').textContent=ST.version; $('#repo').textContent=ST.repo_slug+' · '+ST.branch;
  $('#cRepo').value=ST.repo_path; $('#cSlug').value=ST.repo_slug; $('#cBr').value=ST.branch;
  $('#cCmd').value='claude';
  log('brain freedom','Left brain, one thing at a time. Right brain, the whole forest, a real terminal running the agent inside your repository.<br>Hold REC, speak, press Send, and watch it typed across.','sys');
  if(!ST.has_key) log('keys','No AssemblyAI key yet. Tap the gold gear and import your keys file, voice starts working immediately.','sys');
  if(!ST.repo_ok) log('repo','No repository checkout yet. Tap the gear and press <b>Create or clone repository</b>, it makes the folder and pulls it down for you.','sys');
}
$('#save').onclick=async()=>{
  const b={repo_path:$('#cRepo').value,repo_slug:$('#cSlug').value,branch:$('#cBr').value,claude_cmd:$('#cCmd').value};
  await fetch('/api/config',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(b)});
  log('settings','saved','sys'); boot();
};
$('#restart').onclick=async()=>{ await fetch('/api/restart',{method:'POST'}); log('engine','agent restarted','sys'); };
$('#pushnow').onclick=async()=>{ const r=await(await fetch('/api/push',{method:'POST'})).json();
  log('git',r.ok?'pushed':'nothing to push or push failed','sys'); };

/* ---------------- splitter ---------------- */
let dragging=false;
$('#drag').addEventListener('mousedown',()=>{dragging=true;document.body.style.cursor='col-resize'});
window.addEventListener('mouseup',()=>{dragging=false;document.body.style.cursor=''});
window.addEventListener('mousemove',e=>{ if(!dragging)return;
  const pct=Math.min(72,Math.max(24,e.clientX/window.innerWidth*100));
  $('#left').style.width=pct+'%'; fit.fit(); sendSize(); });
window.addEventListener('resize',()=>{fit.fit();sendSize()});
speechSynthesis.getVoices();
boot();
</script>
</body></html>

BF_HTML_EOF
ok "interface written"

chmod +x "$APP/bf_server.py"
cat > "$BIN/brainfreedom" <<'RUNEOF'
#!/usr/bin/env bash
exec "$HOME/brain_freedom/venv/bin/python" "$HOME/brain_freedom/bf_server.py" "$@"
RUNEOF
chmod +x "$BIN/brainfreedom"; ok "command installed: brainfreedom"
case ":$PATH:" in *":$BIN:"*) : ;; *)
  for rc in "$HOME/.zshrc" "$HOME/.bash_profile"; do
    [ -f "$rc" ] && ! grep -q '.local/bin' "$rc" && echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc" || true
  done
  warn "added ~/.local/bin to PATH, open a new terminal tab" ;;
esac
command -v claude >/dev/null && ok "claude code found" || warn "claude code missing:  npm install -g @anthropic-ai/claude-code"
if [ ! -f "$CFG/config.json" ]; then
  printf '%s\n' '{"assemblyai_key":"","github_token":"","repo_path":"'"$HOME"'/brain_freedom/BRAIN_BRAKE","repo_slug":"markoboskoauroville/BRAIN_BRAKE","branch":"main","claude_cmd":"claude","voice_lang":"en"}' > "$CFG/config.json"
  chmod 600 "$CFG/config.json"; ok "defaults written, no keys asked, they live behind the gold gear"
else ok "existing settings kept"; fi
echo; say "${G}ready${R}"; say "${D}press ${W}[S]${D} to start, or type ${W}brainfreedom${D} any time${R}"; echo
}

uninstall_all(){
logo
say "${W}uninstall${R}"
pkill -f bf_server.py 2>/dev/null || true
rm -f "$BIN/brainfreedom" 2>/dev/null || true; ok "command removed"
rm -rf "$APP/venv" "$APP/bf_server.py" "$APP/bf.html" "$APP/port" 2>/dev/null || true; ok "app removed"
echo
printf "  ${G}[K]${R}  also delete your keys and settings\n"
printf "  ${G}[any]${R} keep them\n\n  "
read -rsn1 a
case "$a" in k|K) rm -rf "$CFG"; ok "keys removed";; *) ok "keys kept";; esac
say "${D}your repository and every frame inside $APP are untouched${R}"; echo
}

start_it(){
  if [ -x "$APP/bf_server.py" ]; then exec "$BIN/brainfreedom"; fi
  warn "not installed yet, press [I] first"; sleep 1.4
}

while true; do
  menu
  read -rsn1 key
  echo; echo
  case "$key" in
    i|I) install_all; printf "  ${D}press any key${R}"; read -rsn1 _; ;;
    s|S) start_it ;;
    u|U) uninstall_all; printf "  ${D}press any key${R}"; read -rsn1 _; ;;
    q|Q|$'\033') logo; say "${D}closed${R}"; echo; exit 0 ;;
    *) ;;
  esac
done
