#!/usr/bin/env bash
# =============================================================================
#  BRAIN FREEDOM  v10 (a)  ·  Mantra Productions
#  One file, one keypress. No switches, no flags, nothing to remember.
#  Run it:   bash 10sh_brain_freedom_v10_macos.sh
# =============================================================================
case "${COLORTERM:-}" in
  truecolor|24bit)
    G=$'\033[38;2;224;132;46m'; C=$'\033[38;2;116;199;232m'; Y=$'\033[38;2;242;193;105m'
    D=$'\033[38;2;138;133;120m'; W=$'\033[38;2;233;227;212m' ;;
  *)
    G=$'\033[38;5;208m'; C=$'\033[38;5;117m'; Y=$'\033[38;5;215m'
    D=$'\033[38;5;245m'; W=$'\033[38;5;230m' ;;
esac
R=$'\033[0m'
APP="$HOME/brain_freedom"; CFG="$HOME/.brain_freedom"; BIN="$HOME/.local/bin"
say(){ printf "  %s\n" "$1"; }
ok(){  printf "  ${G}▍${R} %s\n" "$1"; }
warn(){ printf "  ${Y}▍${R} %s\n" "$1"; }

logo(){
clear 2>/dev/null || true
echo
printf "  ${G}BRAIN FREEDOM${R}\n"
printf "  ${D}left brain speaks | right brain works${R}\n"
echo
printf "${G}   ____  ____      _    ___ _   _   _____ ____  _____ _____ ____   ___  __  __${R}\n"
printf "${G}  | __ )|  _ \\    / \\  |_ _| \\ | | |  ___|  _ \\| ____| ____|  _ \\ / _ \\|  \\/  |${R}\n"
printf "${G}  |  _ \\| |_) |  / _ \\  | ||  \\| | | |_  | |_) |  _| |  _| | | | | | | | |\\/| |${R}\n"
printf "${G}  | |_) |  _ <  / ___ \\ | || |\\  | |  _| |  _ <| |___| |___| |_| | |_| | |  | |${R}\n"
printf "${G}  |____/|_| \\_\\/_/   \\_\\___|_| \\_| |_|   |_| \\_\\_____|_____|____/ \\___/|_|  |_|${R}\n"

printf "      ${D}left brain speaks | right brain works | Brain Freedom${R}\n"
echo
printf "  ${D}──────────────────────────────────────────────────────────────────────────${R}\n"
echo
}

menu(){
  logo
  if [ -x "$APP/bf_server.py" ]; then printf "  ${D}installed  ${R}${W}%s${R}\n\n" "$APP"; fi
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
"$APP/venv/bin/pip" install -q flask flask-sock simple-websocket requests pillow edge-tts
ok "flask · websockets · pillow · edge-tts"

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
VERSION  = "v10 (a)"

for d in (CFG_DIR, INBOX):
    d.mkdir(parents=True, exist_ok=True)

# ---------------------------------------------------------------- config
DEFAULTS = {
    "browser": "",
    "assemblyai_key": "",
    "github_token": "",
    "repo_path": str(HOME / "BRAIN_BRAKE"),
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
    # migration: the working folder moved to the home folder in v6
    rp = d.get("repo_path") or ""
    if rp.endswith("brain_freedom/BRAIN_BRAKE") and not os.path.isdir(os.path.join(rp, ".git")):
        d["repo_path"] = str(HOME / "BRAIN_BRAKE")
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
            wd = cfg_load().get("repo_path") or ""
            if not os.path.isdir(wd): wd = str(HOME)
            try: os.chdir(wd)
            except Exception: pass
            shell = os.environ.get("SHELL") or ""
            if not os.path.exists(shell):
                for cand in ("/bin/zsh", "/bin/bash", "/bin/sh"):
                    if os.path.exists(cand):
                        shell = cand; break
            try:
                # login shell, so the agent inherits the PATH the user actually has
                # cd is repeated inside the shell so the agent reports the right folder
                os.execvp(shell, [shell, "-lc", "cd %s 2>/dev/null; exec %s" % (json.dumps(wd), cmd)])
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
REPO_READY = threading.Event()

@sock.route("/ws/term")
def ws_term(ws):
    TERM.clients.append(ws)
    if TERM.pid is None and not REPO_READY.is_set():
        try:
            ws.send("\r\n  \033[38;5;245mpreparing the working folder, this happens once\033[0m\r\n")
        except Exception:
            pass
        REPO_READY.wait(timeout=300)
        c = cfg_load()
        try:
            ws.send("  \033[38;5;208mworking in %s\033[0m\r\n\r\n" % c.get("repo_path"))
        except Exception:
            pass
    TERM.start()
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
        "repo_ready": REPO_READY.is_set(),
        "agent_cwd": (os.readlink("/proc/%d/cwd" % TERM.pid)
                      if (TERM.pid and os.path.exists("/proc/%d/cwd" % TERM.pid)) else ""),
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
    TERM.kill(); time.sleep(.4)
    REPO_READY.wait(timeout=120)
    TERM.start()
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
    note_error("/api/transcribe", "; ".join(tried), "voice")
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
    path = c.get("repo_path") or str(HOME / "BRAIN_BRAKE")
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



# ---------------------------------------------------------------- error log
ERRORS = []
def note_error(where, detail, kind="server"):
    ERRORS.append({"t": time.strftime("%H:%M:%S"), "date": time.strftime("%Y-%m-%d"),
                   "where": where, "kind": kind, "detail": str(detail)[:4000]})
    del ERRORS[:-60]

@app.errorhandler(Exception)
def any_error(e):
    import traceback
    note_error(request.path if request else "?", traceback.format_exc(), "server")
    return jsonify(ok=False, error="%s: %s" % (type(e).__name__, str(e)[:200])), 500

@app.get("/api/errors")
def errors_get():
    return jsonify(errors=list(reversed(ERRORS)))

@app.post("/api/errors")
def errors_post():
    o = request.json or {}
    note_error(o.get("where", "browser"), o.get("detail", ""), "browser")
    return jsonify(ok=True)

@app.post("/api/errors/clear")
def errors_clear():
    ERRORS.clear()
    return jsonify(ok=True)

# ---------------------------------------------------------------- speech, edge tts
TTS_DIR = APP / "tts"
TTS_DIR.mkdir(parents=True, exist_ok=True)
VOICES = {"sonia": "en-GB-SoniaNeural", "ryan": "en-GB-RyanNeural",
          "aria": "en-US-AriaNeural", "guy": "en-US-GuyNeural"}

def _communicate(edge_tts, text, voice):
    """edge-tts 7.x defaults to SentenceBoundary, which gives no word events.
    Ask for WordBoundary explicitly, fall back for older versions."""
    try:
        return edge_tts.Communicate(text, voice, boundary="WordBoundary")
    except TypeError:
        return edge_tts.Communicate(text, voice)

@app.post("/api/tts")
def tts():
    import asyncio, hashlib
    try:
        import edge_tts
    except Exception:
        return jsonify(ok=False, error="edge-tts not installed, run the installer again")
    o = request.json or {}
    text = (o.get("text") or "").strip()
    if not text: return jsonify(ok=False, error="nothing to read")
    voice = VOICES.get(o.get("voice", "sonia"), VOICES["sonia"])
    rate = int(o.get("rate", 0))
    rate_s = ("+%d%%" % rate) if rate >= 0 else ("%d%%" % rate)
    uid = hashlib.sha1((text + voice + rate_s).encode()).hexdigest()[:16]
    mp3 = TTS_DIR / (uid + ".mp3")
    js  = TTS_DIR / (uid + ".json")
    if mp3.exists() and js.exists():
        return jsonify(ok=True, id=uid, bounds=json.loads(js.read_text()), cached=True)

    async def go():
        bounds = []
        try:
            com = edge_tts.Communicate(text, voice, rate=rate_s, boundary="WordBoundary")
        except TypeError:
            com = edge_tts.Communicate(text, voice, rate=rate_s)
        with open(str(mp3) + ".part", "wb") as f:
            async for ch in com.stream():
                if ch["type"] == "audio":
                    f.write(ch["data"])
                elif ch["type"] == "WordBoundary":
                    bounds.append({"t": ch["offset"] / 1e7, "d": ch["duration"] / 1e7, "w": ch["text"]})
        return bounds
    loop = asyncio.new_event_loop()
    try:
        bounds = loop.run_until_complete(go())
    except Exception as e:
        try: os.remove(str(mp3) + ".part")
        except Exception: pass
        note_error("/api/tts", e, "speech")
        return jsonify(ok=False, error="speech failed: %s" % str(e)[:140])
    finally:
        loop.close()
    try:
        if not os.path.getsize(str(mp3) + ".part"):
            return jsonify(ok=False, error="no audio came back")
    except Exception:
        return jsonify(ok=False, error="no audio came back")
    os.replace(str(mp3) + ".part", str(mp3))
    js.write_text(json.dumps(bounds))
    # keep the cache small
    files = sorted(TTS_DIR.glob("*.mp3"), key=lambda p: p.stat().st_mtime)
    for old in files[:-60]:
        try:
            old.unlink(); Path(str(old)[:-4] + ".json").unlink(missing_ok=True)
        except Exception: pass
    return jsonify(ok=True, id=uid, bounds=bounds, cached=False)

@app.get("/api/tts/<uid>.mp3")
def tts_audio(uid):
    p = TTS_DIR / (uid + ".mp3")
    if not p.exists(): return ("no", 404)
    return send_file(p, mimetype="audio/mpeg")

@app.get("/api/online")
def online():
    ok = False
    try:
        s = socket.create_connection(("1.1.1.1", 443), 1.5); s.close(); ok = True
    except Exception:
        try:
            s = socket.create_connection(("8.8.8.8", 53), 1.5); s.close(); ok = True
        except Exception: ok = False
    try:
        import edge_tts; tts_ok = True
    except Exception:
        tts_ok = False
    return jsonify(online=ok, term=TERM.pid is not None, tts=tts_ok)

# ---------------------------------------------------------------- banner
_TRUE = os.environ.get("COLORTERM", "").lower() in ("truecolor", "24bit")
def _c(rgb, idx):
    """Terminal.app on macOS has no 24 bit colour, so fall back to the 256 palette."""
    return ("\033[38;2;%d;%d;%dm" % rgb) if _TRUE else ("\033[38;5;%dm" % idx)
G  = _c((224, 132, 46), 208)    # orange, FREEDOM
C2 = _c((116, 199, 232), 117)   # light blue, BRAIN
D  = _c((140, 135, 120), 245)   # dim
W  = _c((231, 226, 214), 230)   # paper
R  = "\033[0m"
GR = _c((111, 174, 99), 71)

def banner(port, url, compact=False, lan=""):
    tty_ok = sys.stdout.isatty()
    def c(x, col): return (col+x+R) if tty_ok else x
    ART = [
        ' ____  ____      _    ___ _   _   _____ ____  _____ _____ ____   ___  __  __',
        '| __ )|  _ \\    / \\  |_ _| \\ | | |  ___|  _ \\| ____| ____|  _ \\ / _ \\|  \\/  |',
        '|  _ \\| |_) |  / _ \\  | ||  \\| | | |_  | |_) |  _| |  _| | | | | | | | |\\/| |',
        '| |_) |  _ <  / ___ \\ | || |\\  | |  _| |  _ <| |___| |___| |_| | |_| | |  | |',
        '|____/|_| \\_\\/_/   \\_\\___|_| \\_| |_|   |_| \\_\\_____|_____|____/ \\___/|_|  |_|',
    ]
    RULE = "\u2500" * 74

    def kv(k, v):
        print("  " + c(k.ljust(9), D) + c(str(v), W))

    print()
    print("  " + c("BRAIN FREEDOM", G))
    print("  " + c("left brain speaks | right brain works", D))
    print()
    print("  " + c("\u25ba", GR) + c(" on this Mac   ", D) + c(url, W))
    if lan:
        print("  " + c("\u25ba", GR) + c(" on Wi-Fi      ", D) + c("http://%s:%d" % (lan, port), W))
    print()
    print("  " + c("Ctrl+C to stop", D))
    print()
    if not compact:
        for l in ART: print("  " + c(l, G))
        print("      " + c("left brain speaks | right brain works | Brain Freedom", D))
        print()
    c2 = cfg_load()
    print("  " + c(RULE, D))
    kv("version", VERSION)
    kv("address", url)
    kv("port", "%d  (base %d)" % (port, BASE_PORT))
    kv("repo", c2.get("repo_path"))
    kv("branch", c2.get("branch"))
    kv("browser", pick_browser() or "none found")
    kv("voice", ("AssemblyAI, %d keys" % len(key_list("assemblyai"))) if key_list("assemblyai") else "no key yet, open the gear")
    print("  " + c(RULE, D))
    print()
    print("  " + c("q quit", G) + c("     o open the page", G) + c("     b background", G))
    print()

def lan_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("1.1.1.1", 80)); ip = s.getsockname()[0]; s.close()
        return ip if not ip.startswith("127.") else ""
    except Exception:
        return ""

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
    banner(PORT, url, compact=False, lan=lan_ip())
    def prepare_repo():
        try:
            okr, msg, path = ensure_repo()
            print("  " + (G if okr else D) + ("repository " + msg + "  " + path if okr else msg) + R)
        except Exception as e:
            note_error("startup", e, "server")
        finally:
            REPO_READY.set()
    threading.Thread(target=prepare_repo, daemon=True).start()
    def open_when_ready():
        import urllib.request
        for _ in range(60):
            try:
                urllib.request.urlopen(url + "/api/state", timeout=1).read(1)
                break
            except Exception:
                time.sleep(0.25)
        b = open_in_browser(url)
        print("  " + D + "opened in " + (b or "your default browser") + R)
        print("  " + D + "if nothing appeared, paste this into Firefox:" + R + "  " + W + url + R + "\n")
    threading.Thread(target=open_when_ready, daemon=True).start()
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
 --ink:#08090c;--panel:#0e1014;--panel2:#14171c;--line:#23272f;--edge:#2e2a20;
 --paper:#e9e3d4;--dim:#8a8578;--muted:#a08c62;--gold:#e0a340;--gold2:#f2c169;
 --red:#c9453c;--green:#6fae63;--blue:#4a7fb5;
 --mono:'SF Mono',ui-monospace,Menlo,Consolas,monospace;
 --fsL:14px;--fsT:13px;
}
*{box-sizing:border-box}
html,body{height:100%;margin:0;background:var(--ink);color:var(--paper);font-family:var(--mono);
 font-size:13px;overflow:hidden;-webkit-font-smoothing:antialiased}
button{font-family:var(--mono);cursor:pointer;color:var(--paper)}
.pill{background:var(--panel2);border:1px solid var(--line);border-radius:999px;padding:9px 18px;
 font-size:11px;letter-spacing:.14em;text-transform:uppercase;transition:.14s;color:var(--paper)}
.pill:hover{border-color:var(--edge);color:var(--gold2)}
.pill.on{background:var(--gold);border-color:var(--gold);color:#0a0a0a;font-weight:600}
.pill.sm{padding:6px 12px;font-size:10px}
#app{display:flex;height:100vh;width:100vw}
#left{width:46%;min-width:340px;display:flex;flex-direction:column;border-right:1px solid var(--line)}
#drag{width:5px;cursor:col-resize;background:var(--line);flex:0 0 5px}#drag:hover{background:var(--gold)}
header{display:flex;align-items:center;gap:9px;padding:12px 14px;border-bottom:1px solid var(--line)}
.logo{color:var(--muted);font-size:12px;letter-spacing:.24em;text-transform:uppercase}
.k,.sub{color:var(--dim);font-size:10px;letter-spacing:.16em;text-transform:uppercase}
.slug{color:var(--muted);font-size:10px;letter-spacing:.14em;text-transform:uppercase}
.spacer{flex:1}
.led{width:7px;height:7px;border-radius:50%;background:#3a3f46;box-shadow:none;transition:.3s}
.led.on{background:var(--green);box-shadow:0 0 7px rgba(111,174,99,.8)}
#gear{background:none;border:0;color:var(--muted);font-size:17px;padding:0 2px;line-height:1}
#gear:hover{color:var(--gold2)}
nav{display:flex;gap:8px;padding:12px 14px 0}
main{flex:1;overflow-y:auto;padding:14px}
section{display:none}section.a{display:block}
.msg{margin:0 0 14px;line-height:1.65;font-size:var(--fsL);position:relative;padding-right:22px}
.msg .who{color:var(--gold);font-size:9px;letter-spacing:.2em;text-transform:uppercase;display:block;margin-bottom:3px}
.msg.sys{color:var(--dim)}.msg.sys b{color:var(--gold2);font-weight:400}
.spk{position:absolute;top:0;right:0;background:none;border:0;color:#4a4d55;font-size:13px;padding:2px;line-height:1}
.spk:hover{color:var(--gold)}
.spk.on{color:var(--gold)}
.w.hl{background:var(--gold);color:#0a0a0a;border-radius:2px}
footer{border-top:1px solid var(--line);padding:12px 14px}
#boxwrap{position:relative}
#box{width:100%;background:var(--panel);border:1px solid var(--edge);border-radius:16px;color:var(--paper);
 padding:14px 34px 14px 14px;font-size:var(--fsL);font-family:var(--mono);resize:none;min-height:88px;line-height:1.55}
#box:focus{outline:0;border-color:var(--gold)}
#boxread{position:absolute;top:10px;right:10px;background:none;border:0;color:#4a4d55;font-size:13px}
#boxread:hover{color:var(--gold)}
#boxecho{display:none;background:var(--panel);border:1px solid var(--edge);border-radius:16px;padding:14px;
 font-size:var(--fsL);line-height:1.55;min-height:88px}
.tools{display:flex;align-items:center;gap:8px;margin-top:10px}
.icon{width:52px;height:52px;border-radius:50%;border:1px solid;font-size:11px;letter-spacing:.08em;
 font-weight:700;display:flex;align-items:center;justify-content:center;background:none}
#mic{background:#1c0f0e;border-color:#5a2b27;color:#b8695f}
#mic.rec{background:#3a1512;border-color:var(--red);color:#ff8f86}
#read{background:#0d151e;border-color:#2b3f56;color:#6f92b5;width:auto;height:auto;border-radius:999px;
 padding:10px 16px;font-size:10px;letter-spacing:.16em;text-transform:uppercase}
.fs{display:flex;align-items:center;gap:5px}
.fs button{width:26px;height:26px;border-radius:50%;background:none;border:1px solid var(--line);
 color:var(--dim);font-size:13px;line-height:1;display:flex;align-items:center;justify-content:center}
.fs button:hover{border-color:var(--gold);color:var(--gold)}
.fs span{color:var(--dim);font-size:9px;min-width:20px;text-align:center}
/* vu meter */
.vu{flex:1;height:26px;display:flex;align-items:center;gap:2px;background:var(--panel);
 border:1px solid var(--edge);border-radius:6px;padding:0 7px;overflow:hidden}
.vu i{flex:1;height:11px;background:#1a1d22;border-radius:1px;transition:background .05s}
.vu i.on{background:var(--green)}
.vu i.mid.on{background:var(--gold)}
.vu i.hot.on{background:var(--red)}
.vu i.peak{background:var(--paper)}
.meter{color:var(--dim);font-size:10px;letter-spacing:.06em;min-width:172px;text-align:right}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:10px}
.card{border:1px solid var(--edge);border-radius:14px;overflow:hidden;background:var(--panel)}
.card img{width:100%;display:block}
.card .cap{padding:8px 10px;display:flex;gap:8px;align-items:center;font-size:10px;color:var(--dim)}
.card .cap b{color:var(--paper);font-weight:400;flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.drop{border:1px dashed var(--edge);border-radius:16px;padding:24px;text-align:center;color:var(--dim);
 font-size:11px;letter-spacing:.06em;margin-bottom:12px}
.drop.hot{border-color:var(--gold);color:var(--gold)}
input[type=text]{width:100%;background:var(--ink);border:1px solid var(--edge);border-radius:12px;
 color:var(--paper);padding:11px 13px;font-family:var(--mono);font-size:12px;margin:5px 0 12px}
input:focus{outline:0;border-color:var(--gold)}
.row{display:flex;gap:8px;flex-wrap:wrap}
.bar{height:5px;background:var(--panel2);border-radius:3px;overflow:hidden;margin:5px 0 12px}
.bar i{display:block;height:100%;background:var(--gold)}
.v{font-size:26px;color:var(--gold2)}
.two{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-bottom:16px}
.two>div{border:1px solid var(--edge);border-radius:16px;padding:14px;background:var(--panel)}
#modal{position:fixed;inset:0;background:rgba(4,5,7,.88);display:none;align-items:center;justify-content:center;z-index:80;padding:24px}
#modal.on{display:flex}
.sheet{width:min(780px,96vw);max-height:88vh;overflow-y:auto;background:var(--panel);border:1px solid var(--edge);
 border-radius:22px;padding:22px}
.sheet h2{margin:22px 0 6px;font-size:11px;letter-spacing:.22em;text-transform:uppercase;color:var(--gold)}
.sheet h2:first-child{margin-top:0}
.keyrow{display:flex;align-items:center;gap:8px;padding:9px 12px;border:1px solid var(--line);border-radius:12px;
 margin-bottom:7px;background:var(--ink)}
.keyrow .m{flex:1;font-size:11px}
.st{font-size:9px;letter-spacing:.14em;text-transform:uppercase;padding:3px 9px;border-radius:999px;
 border:1px solid var(--line);color:var(--dim)}
.st.ok{color:var(--green);border-color:#2c3a2c}.st.failed{color:var(--red);border-color:#3a2626}
.prov{margin:16px 0 8px;display:flex;align-items:center;gap:10px}
.prov b{color:var(--gold2);font-weight:400;font-size:11px;letter-spacing:.18em;text-transform:uppercase}
.note{color:var(--dim);font-size:11px;line-height:1.8;letter-spacing:.03em;text-transform:none}
.errcard{border:1px solid var(--line);border-radius:12px;background:var(--ink);padding:12px 14px;margin-bottom:10px}
.errcard .top{display:flex;align-items:center;gap:10px;margin-bottom:8px}
.errcard .tag{font-size:9px;letter-spacing:.14em;text-transform:uppercase;padding:3px 9px;border-radius:999px;
 border:1px solid var(--line);color:var(--dim)}
.errcard .tag.server{color:var(--red);border-color:#3a2626}
.errcard .tag.browser{color:var(--blue);border-color:#26313a}
.errcard .tag.voice,.errcard .tag.speech{color:var(--gold);border-color:#3a3426}
.errcard pre{margin:0;white-space:pre-wrap;word-break:break-word;font-size:11px;line-height:1.6;
 color:var(--paper);max-height:220px;overflow:auto}
#right{flex:1;display:flex;flex-direction:column;background:#06070a;min-width:0}
#rhead{display:flex;align-items:center;gap:9px;padding:10px 16px;border-bottom:1px solid var(--line)}
#term{flex:1;padding:14px 30px 14px 18px;min-height:0}
</style></head>
<body>
<div id="app">
 <div id="left">
  <header>
    <span class="logo">Brain Freedom</span><span class="k" id="ver"></span>
    <span class="spacer"></span>
    <span class="led" id="ledL"></span><span class="slug" id="repo"></span>
    <button id="gear" title="Settings and keys">&#9881;</button>
  </header>
  <nav>
    <button class="pill on" data-t="chat">Command</button>
    <button class="pill" data-t="gal">Frames</button>
    <button class="pill" data-t="use">Usage</button>
  </nav>
  <main>
    <section id="chat" class="a"></section>
    <section id="gal">
      <div class="drop" id="drop">Drop a render here, or click.<br>
        <span class="k">named · optimised · committed · pushed · link copied</span></div>
      <div class="k">Name</div><input type="text" id="iname" placeholder="HERO_V3_1">
      <div class="k">Folder</div><input type="text" id="ifolder" value="assets/HERO_V3">
      <div class="grid" id="grid"></div>
    </section>
    <section id="use">
      <div class="two">
        <div><div class="k">Today</div><div class="v" id="uToday">0</div></div>
        <div><div class="k">7 day average</div><div class="v" id="uAvg">0</div></div>
      </div>
      <div class="k" style="margin-bottom:8px">Last 14 days</div>
      <div id="uDays"></div>
      <p class="note" id="uNote"></p>
    </section>
  </main>
  <footer>
    <div id="boxwrap">
      <textarea id="box" placeholder="Speak, or type. This is typed across to the agent one character at a time."></textarea>
      <div id="boxecho"></div>
      <button id="boxread" title="Read this aloud">&#9834;</button>
    </div>
    <div class="tools">
      <button class="icon" id="mic">REC</button>
      <button class="icon" id="read">Read</button>
      <div class="fs" title="Text size, left side">
        <button id="lminus">&minus;</button><span id="lsize">14</span><button id="lplus">+</button>
      </div>
      <div class="vu" id="vu"></div>
      <span class="meter" id="meter">ready</span>
      <button class="pill on" id="send">Send</button>
    </div>
  </footer>
 </div>
 <div id="drag"></div>
 <div id="right">
   <div id="rhead">
     <span class="logo" style="color:var(--dim)">Engine</span>
     <span class="led" id="ledR"></span>
     <span class="k" id="cwd">claude code · live pty</span><span class="spacer"></span>
     <div class="fs" title="Text size, terminal">
       <button id="tminus">&minus;</button><span id="tsize">13</span><button id="tplus">+</button>
     </div>
     <button class="pill sm" id="esc">esc</button>
     <button class="pill sm" id="ctrlc">ctrl c</button>
     <button class="pill sm" id="clr">clear</button>
   </div>
   <div id="term"></div>
 </div>
</div>

<div id="modal"><div class="sheet">
  <div class="row" id="stabs" style="margin-bottom:16px">
    <button class="pill on" data-s="sKeys">Keys</button>
    <button class="pill" data-s="sVoice">Voice</button>
    <button class="pill" data-s="sBrow">Browser</button>
    <button class="pill" data-s="sRepo">Repository</button>
    <button class="pill" data-s="sErr">Error log</button>
    <span class="spacer"></span><button class="pill" id="close">Close</button>
  </div>

  <div class="spane" id="sKeys">
  <h2>Keys</h2>
  <p class="note">Point at any file. Notes, exports, a mess, it does not matter. Every key inside is found,
  sorted by provider and queued. Transcription walks the queue until one answers, so a dead key costs a
  second rather than a session. Shape only sorts a key, it never rejects one.</p>
  <div class="row" style="margin:12px 0 10px">
    <button class="pill on" id="kimport">Import from file</button>
    <button class="pill" id="kpaste">Paste text</button>
    <button class="pill" id="krefresh">Refresh</button>
  </div>
  <div id="klist"></div>
  </div>

  <div class="spane" id="sVoice" style="display:none">
  <h2>Voice</h2>
  <p class="note">Reading aloud uses edge-tts, which returns the timing of every word, so the highlight
  follows the speech exactly rather than guessing.</p>
  <div class="row" id="voices"></div>
  </div>

  <div class="spane" id="sBrow" style="display:none">
  <h2>Browser</h2>
  <p class="note">Brain Freedom opens itself in the browser you pick here, ignoring the macOS default.
  Firefox first when present, because its recorder produces Opus.</p>
  <div class="row" id="brow"></div>
  </div>

  <div class="spane" id="sRepo" style="display:none">
  <h2>Repository</h2>
  <p class="note">The working folder is created for you at your home folder. Nothing to set up.</p>
  <div class="k">Path</div><input type="text" id="cRepo">
  <div class="k">Slug</div><input type="text" id="cSlug">
  <div class="k">Branch</div><input type="text" id="cBr">
  <div class="row" style="margin-top:4px">
    <button class="pill on" id="save">Save</button>
    <button class="pill" id="clone">Create or clone repository</button>
    <button class="pill" id="restart">Restart agent</button>
    <button class="pill" id="pushnow">Push now</button>
  </div>
  </div>

  <div class="spane" id="sErr" style="display:none">
  <h2>Error log</h2>
  <p class="note">Everything that went wrong since the app started, newest first. Each one has a copy button,
  so you can send it to me without retyping anything.</p>
  <div class="row" style="margin:10px 0 12px">
    <button class="pill on" id="errRefresh">Refresh</button>
    <button class="pill" id="errClear">Clear</button>
    <button class="pill" id="errCopyAll">Copy all</button>
  </div>
  <div id="errlist"></div>
  </div>
</div></div>

<script src="https://cdn.jsdelivr.net/npm/@xterm/xterm@5.5.0/lib/xterm.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/@xterm/addon-fit@0.10.0/lib/addon-fit.min.js"></script>
<script>
const $=s=>document.querySelector(s), $$=s=>[...document.querySelectorAll(s)];
let ST={}, VOICE=localStorage.getItem('voice')||'sonia';

/* ---------- terminal ---------- */
const term=new Terminal({fontFamily:"'SF Mono',Menlo,monospace",fontSize:13,lineHeight:1.25,cursorBlink:true,
  allowProposedApi:true,scrollback:8000,macOptionIsMeta:true,
  theme:{background:'#06070a',foreground:'#e9e3d4',cursor:'#e0a340',selectionBackground:'#2a2417',
   black:'#06070a',red:'#c9453c',green:'#6fae63',yellow:'#e0a340',blue:'#7fa8d0',magenta:'#b39ddb',
   cyan:'#7fc8c0',white:'#e9e3d4',brightBlack:'#5a5c63',brightYellow:'#f2c169'}});
const fit=new FitAddon.FitAddon(); term.loadAddon(fit); term.open($('#term')); fit.fit();
let ws;
function connect(){
  ws=new WebSocket((location.protocol==='https:'?'wss':'ws')+'://'+location.host+'/ws/term');
  ws.onopen=()=>{size()};
  ws.onmessage=e=>term.write(e.data);
  ws.onclose=()=>{setTimeout(connect,1500)};
}
function size(){ if(ws&&ws.readyState===1) ws.send(JSON.stringify({t:'resize',cols:term.cols,rows:term.rows})); }
term.onData(d=>{ if(ws&&ws.readyState===1) ws.send(JSON.stringify({t:'in',d})); });
new ResizeObserver(()=>{fit.fit();size()}).observe($('#term')); connect();
const K=d=>fetch('/api/key',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({d})});
$('#esc').onclick=()=>K('\x1b'); $('#ctrlc').onclick=()=>K('\x03'); $('#clr').onclick=()=>term.clear();

/* ---------- tabs ---------- */
$$('nav .pill').forEach(b=>b.onclick=()=>{
  $$('nav .pill').forEach(x=>x.classList.remove('on')); b.classList.add('on');
  $$('main section').forEach(s=>s.classList.remove('a')); $('#'+b.dataset.t).classList.add('a');
  if(b.dataset.t==='gal') gallery(); if(b.dataset.t==='use') usage();
});

/* ---------- messages, each one readable in place ---------- */
function log(who,html,cls){
  const d=document.createElement('div'); d.className='msg '+(cls||'');
  d.innerHTML='<span class="who">'+who+'</span><span class="body">'+html+'</span>';
  const b=document.createElement('button'); b.className='spk'; b.innerHTML='&#9834;';
  b.title='Read this aloud'; b.onclick=()=>speak(d.querySelector('.body'),b);
  d.appendChild(b); $('#chat').appendChild(d); d.scrollIntoView({block:'end'}); return d;
}

/* ---------- speech, inline highlight ---------- */
let audio=null, raf=null, cur=null, curBtn=null;
function stopSpeech(){
  if(audio){audio.pause();audio=null}
  if(raf){cancelAnimationFrame(raf);raf=null}
  if(cur){ cur.innerHTML=cur.dataset.plain!==undefined?cur.dataset.plain:cur.innerHTML; cur=null; }
  if(curBtn){curBtn.classList.remove('on');curBtn=null}
}
async function speak(el,btn){
  if(cur===el){ stopSpeech(); return; }
  stopSpeech();
  const text=el.innerText.trim(); if(!text) return;
  btn.classList.add('on'); curBtn=btn;
  el.dataset.plain=el.innerHTML;
  const parts=text.split(/(\s+)/);
  el.innerHTML=parts.map(p=>p.trim()?'<span class="w">'+p.replace(/</g,'&lt;')+'</span>':p).join('');
  const spans=[...el.querySelectorAll('.w')];
  cur=el;
  let r;
  try{ r=await(await fetch('/api/tts',{method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({text,voice:VOICE,rate:0})})).json(); }
  catch(e){ stopSpeech(); return; }
  if(!r.ok){ stopSpeech(); log('voice',r.error,'sys'); return; }
  audio=new Audio('/api/tts/'+r.id+'.mp3');
  const bounds=r.bounds||[];
  audio.play().catch(()=>{});
  const tick=()=>{
    if(!audio){return}
    const t=audio.currentTime; let i=-1;
    for(let n=0;n<bounds.length;n++){ if(bounds[n].t<=t) i=n; else break; }
    spans.forEach(s=>s.classList.remove('hl'));
    if(i>=0&&spans[i]){ spans[i].classList.add('hl');
      const rc=spans[i].getBoundingClientRect(), pc=$('main').getBoundingClientRect();
      if(rc.top<pc.top+30||rc.bottom>pc.bottom-30) spans[i].scrollIntoView({block:'center',behavior:'smooth'}); }
    raf=requestAnimationFrame(tick);
  };
  raf=requestAnimationFrame(tick);
  audio.onended=()=>stopSpeech();
}
$('#read').onclick=()=>{
  const last=[...$$('#chat .msg .body')].pop();
  if(!last) return;
  speak(last, last.parentElement.querySelector('.spk'));
};
$('#boxread').onclick=()=>{
  const t=$('#box').value.trim(); if(!t) return;
  const e=$('#boxecho');
  if(e.style.display==='block'){ stopSpeech(); e.style.display='none'; $('#box').style.display='block'; return; }
  $('#box').style.display='none'; e.style.display='block'; e.textContent=t;
  speak(e,$('#boxread'));
  const restore=()=>{ e.style.display='none'; $('#box').style.display='block'; };
  const iv=setInterval(()=>{ if(!audio){clearInterval(iv);restore();} },400);
};

/* ---------- send ---------- */
async function send(){
  const t=$('#box').value.trim(); if(!t)return;
  log('you',t.replace(/</g,'&lt;')); $('#box').value='';
  const r=await(await fetch('/api/say',{method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify({text:t,cps:120})})).json();
  log('engine','typing '+r.chars+' characters across','sys');
}
$('#send').onclick=send;
$('#box').addEventListener('keydown',e=>{if(e.key==='Enter'&&(e.metaKey||e.ctrlKey))send()});

/* ---------- voice in, with a real vu meter ---------- */
const SEG=22, segs=[];
for(let i=0;i<SEG;i++){const s=document.createElement('i');
  if(i>SEG*0.82) s.className='hot'; else if(i>SEG*0.62) s.className='mid';
  $('#vu').appendChild(s); segs.push(s);}
let rec,chunks=[],t0,tick,analyser,actx,peak=0,peakAt=0;
function vu(level){
  const lit=Math.round(level*SEG);
  segs.forEach((s,i)=>{ s.classList.toggle('on', i<lit); s.classList.remove('peak'); });
  const now=performance.now();
  if(lit>peak||now-peakAt>700){ peak=lit; peakAt=now; }
  if(peak>0&&peak<=SEG&&segs[peak-1]&&lit<peak) segs[peak-1].classList.add('peak');
}
function vuClear(){ segs.forEach(s=>{s.classList.remove('on');s.classList.remove('peak')}); peak=0; }
$('#mic').onclick=async()=>{
  if(rec&&rec.state==='recording'){rec.stop();return}
  let stream;
  try{stream=await navigator.mediaDevices.getUserMedia({audio:{channelCount:1,noiseSuppression:true,echoCancellation:true}})}
  catch(e){log('mic','Firefox blocked the microphone. Allow it from the address bar.','sys');return}
  actx=new AudioContext();const src=actx.createMediaStreamSource(stream);
  analyser=actx.createAnalyser();analyser.fftSize=1024;analyser.smoothingTimeConstant=.35;src.connect(analyser);
  const mime=MediaRecorder.isTypeSupported('audio/ogg;codecs=opus')?'audio/ogg;codecs=opus':'audio/webm;codecs=opus';
  rec=new MediaRecorder(stream,{mimeType:mime,audioBitsPerSecond:24000});chunks=[];t0=Date.now();
  rec.ondataavailable=e=>{if(e.data.size)chunks.push(e.data)};
  rec.onstop=async()=>{
    clearInterval(tick);stream.getTracks().forEach(t=>t.stop());try{actx.close()}catch(e){}
    $('#mic').classList.remove('rec');$('#mic').textContent='REC';vuClear();
    const blob=new Blob(chunks,{type:mime}),kb=(blob.size/1024).toFixed(0);
    $('#meter').textContent='uploading '+kb+' KB';
    const fd=new FormData();fd.append('audio',blob,'v.'+(mime.includes('ogg')?'ogg':'webm'));
    const up=Date.now();
    try{
      const r=await(await fetch('/api/transcribe',{method:'POST',body:fd})).json();
      if(!r.ok){$('#meter').textContent='failed';
        log('voice',r.error+((r.tried&&r.tried.length)?'<br>'+r.tried.join('<br>'):''),'sys');return}
      const rate=(blob.size/1024/((Date.now()-up)/1000)).toFixed(0);
      $('#meter').textContent=kb+' KB · '+rate+' KB/s · '+r.seconds+'s · key '+r.key_index;
      if(r.key_index>1) log('voice','key 1 rejected, fell through to key '+r.key_index,'sys');
      $('#box').value=($('#box').value?$('#box').value+' ':'')+r.text;$('#box').focus();
    }catch(e){$('#meter').textContent='network error'}
  };
  rec.start(250);$('#mic').classList.add('rec');$('#mic').textContent='STOP';
  const buf=new Float32Array(analyser.fftSize);
  tick=setInterval(()=>{
    analyser.getFloatTimeDomainData(buf);
    let sum=0; for(let i=0;i<buf.length;i++) sum+=buf[i]*buf[i];
    const rms=Math.sqrt(sum/buf.length);
    const db=20*Math.log10(rms||1e-8);
    const level=Math.max(0,Math.min(1,(db+55)/50));
    vu(level);
    const s=((Date.now()-t0)/1000).toFixed(1),est=(chunks.reduce((a,c)=>a+c.size,0)/1024).toFixed(0);
    $('#meter').textContent='recording · '+s+'s · '+est+' KB';},60);
};

/* ---------- text size ---------- */
let FSL=parseInt(localStorage.getItem('fsL')||'14'), FST=parseInt(localStorage.getItem('fsT')||'13');
function setFS(which,val){
  if(which==='L'){FSL=Math.max(11,Math.min(30,val));
    document.documentElement.style.setProperty('--fsL',FSL+'px');$('#lsize').textContent=FSL;localStorage.setItem('fsL',FSL);}
  else{FST=Math.max(9,Math.min(28,val));term.options.fontSize=FST;$('#tsize').textContent=FST;
    localStorage.setItem('fsT',FST);setTimeout(()=>{fit.fit();size()},30);}
}
$('#lplus').onclick=()=>setFS('L',FSL+1);$('#lminus').onclick=()=>setFS('L',FSL-1);
$('#tplus').onclick=()=>setFS('T',FST+1);$('#tminus').onclick=()=>setFS('T',FST-1);
setFS('L',FSL);setFS('T',FST);

/* ---------- frames ---------- */
async function gallery(){
  const r=await(await fetch('/api/gallery')).json();
  $('#grid').innerHTML=r.items.map(i=>`<div class="card"><img loading="lazy" src="${i.url}">
    <div class="cap"><b>${i.name}</b><button class="pill sm" onclick="copyRaw('${i.rel}')">link</button></div></div>`).join('')
    ||'<span class="k">nothing yet</span>';
}
function copyRaw(rel){const u='https://raw.githubusercontent.com/'+ST.repo_slug+'/'+ST.branch+'/'+rel.replace('_web.jpg','.png');
  navigator.clipboard.writeText(u);log('link',u,'sys')}
const drop=$('#drop');
drop.onclick=()=>{const i=document.createElement('input');i.type='file';i.onchange=e=>up(e.target.files[0]);i.click()};
['dragover','dragenter'].forEach(e=>drop.addEventListener(e,v=>{v.preventDefault();drop.classList.add('hot')}));
['dragleave','drop'].forEach(e=>drop.addEventListener(e,v=>{v.preventDefault();drop.classList.remove('hot')}));
drop.addEventListener('drop',v=>{if(v.dataTransfer.files[0])up(v.dataTransfer.files[0])});
async function up(f){
  const name=$('#iname').value.trim();if(!name){log('frames','give it a name first','sys');return}
  const fd=new FormData();fd.append('file',f);fd.append('name',name);fd.append('folder',$('#ifolder').value.trim());
  log('frames','uploading '+(f.size/1048576).toFixed(1)+' MB','sys');
  const r=await(await fetch('/api/image',{method:'POST',body:fd})).json();
  if(!r.ok){log('frames',r.error,'sys');return}
  navigator.clipboard.writeText(r.raw);log('frames','<b>'+name+'</b> pushed, link copied<br>'+r.raw,'sys');gallery();
}

/* ---------- usage ---------- */
async function usage(){
  const r=await(await fetch('/api/usage')).json();
  $('#uToday').textContent=((r.today.in+r.today.out)/1000).toFixed(0)+'k';
  $('#uAvg').textContent=(r.avg7/1000).toFixed(0)+'k';
  const max=Math.max(1,...r.days.map(d=>d.in+d.out));
  $('#uDays').innerHTML=r.days.map(d=>`<div class="k">${d.d} · ${((d.in+d.out)/1000).toFixed(0)}k</div>
    <div class="bar"><i style="width:${((d.in+d.out)/max*100).toFixed(0)}%"></i></div>`).join('');
  const t=r.today.in+r.today.out;
  $('#uNote').textContent=(r.avg7?(t>r.avg7*1.6?'Well above your usual pace today. A rest would be sensible.':
    t>r.avg7?'A little above your usual pace.':'Comfortably within your usual pace.'):'')+' '+r.note;
}

/* ---------- keys, voices, browser ---------- */
async function keys(){
  const r=await(await fetch('/api/keys')).json();
  let h='';
  for(const p in r.providers){
    const list=r.keys[p]||[]; if(!list.length&&p==='other')continue;
    h+='<div class="prov"><b>'+r.providers[p].label+'</b><span class="k">'+list.length+' key(s)</span></div>';
    h+=list.length?list.map(e=>'<div class="keyrow"><span class="m">'+e.mask+'</span>'+
      '<span class="st '+e.state+'">'+e.state+'</span>'+
      '<button class="pill sm" onclick="kact(\''+p+'\','+e.i+',\'first\')">first</button>'+
      (p==='assemblyai'?'<button class="pill sm" onclick="kact(\''+p+'\','+e.i+',\'test\')">test</button>':'')+
      '<button class="pill sm" onclick="kact(\''+p+'\','+e.i+',\'delete\')">&times;</button></div>').join('')
      :'<span class="k">none</span>';
  }
  $('#klist').innerHTML=h;
}
async function kact(p,i,act){await fetch('/api/keys/act',{method:'POST',headers:{'Content-Type':'application/json'},
  body:JSON.stringify({provider:p,i:i,act:act})});keys();}
$('#kimport').onclick=()=>{const inp=document.createElement('input');inp.type='file';
  inp.onchange=async e=>{const fd=new FormData();fd.append('file',e.target.files[0]);
   const r=await(await fetch('/api/keys/import',{method:'POST',body:fd})).json();
   log('keys','found '+r.found+', added '+r.added,'sys');keys();boot();};inp.click();};
$('#kpaste').onclick=async()=>{const t=prompt('Paste anything that contains keys');if(!t)return;
  const r=await(await fetch('/api/keys/import',{method:'POST',headers:{'Content-Type':'application/json'},
   body:JSON.stringify({text:t})})).json();log('keys','found '+r.found+', added '+r.added,'sys');keys();boot();};
$('#krefresh').onclick=keys;
function voices(){
  const list=[['sonia','Sonia, en GB'],['ryan','Ryan, en GB'],['aria','Aria, en US'],['guy','Guy, en US']];
  $('#voices').innerHTML=list.map(v=>'<button class="pill'+(v[0]===VOICE?' on':'')+
    '" onclick="pickVoice(\''+v[0]+'\')">'+v[1]+'</button>').join('');
}
function pickVoice(v){VOICE=v;localStorage.setItem('voice',v);voices();}
async function browsers(){
  const r=await(await fetch('/api/browsers')).json();
  $('#brow').innerHTML=(r.found.length?r.found:['none found']).map(b=>
    '<button class="pill'+((b===r.chosen||(!r.chosen&&b===r.preferred))?' on':'')+
    '" onclick="pickBrowser(\''+b.replace(/'/g,'')+'\')">'+b+'</button>').join('');
}
async function pickBrowser(b){
  await fetch('/api/config',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({browser:b})});
  log('browser',b+' from now on','sys');browsers();
}
$('#gear').onclick=()=>{$('#modal').classList.add('on');keys();voices();browsers();};
$('#close').onclick=()=>$('#modal').classList.remove('on');
$('#modal').addEventListener('click',e=>{if(e.target.id==='modal')$('#modal').classList.remove('on')});
$('#save').onclick=async()=>{
  await fetch('/api/config',{method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify({repo_path:$('#cRepo').value,repo_slug:$('#cSlug').value,branch:$('#cBr').value})});
  log('settings','saved','sys');boot();};
$('#clone').onclick=async()=>{const r=await(await fetch('/api/repo',{method:'POST'})).json();
  log('repo',(r.ok?('repository '+r.msg+' at '+r.path):r.msg),'sys');boot();};
$('#restart').onclick=async()=>{await fetch('/api/restart',{method:'POST'});log('engine','agent restarted','sys')};
$('#pushnow').onclick=async()=>{const r=await(await fetch('/api/push',{method:'POST'})).json();
  log('git',r.ok?'pushed':('push did not run: '+(r.out||'')),'sys')};

/* ---------- leds ---------- */
async function health(){
  try{
    const r=await(await fetch('/api/online')).json();
    const good=r.online&&r.term;
    $('#ledL').classList.toggle('on',r.online);
    $('#ledR').classList.toggle('on',good);
  }catch(e){$('#ledL').classList.remove('on');$('#ledR').classList.remove('on')}
}
setInterval(health,5000);


/* ---------- settings tabs ---------- */
$$('#stabs .pill').forEach(b=>{ if(!b.dataset.s) return;
  b.onclick=()=>{ $$('#stabs .pill').forEach(x=>x.classList.remove('on')); b.classList.add('on');
    $$('.spane').forEach(p=>p.style.display='none'); $('#'+b.dataset.s).style.display='block';
    if(b.dataset.s==='sErr') errs(); };
});

/* ---------- error log ---------- */
function errText(e){ return '['+e.date+' '+e.t+'] '+e.kind+' · '+e.where+'\n'+e.detail; }
let ERRS=[];
async function errs(){
  const r=await(await fetch('/api/errors')).json(); ERRS=r.errors||[];
  $('#errlist').innerHTML = ERRS.length ? ERRS.map((e,i)=>
    '<div class="errcard"><div class="top"><span class="tag '+e.kind+'">'+e.kind+'</span>'+
    '<span class="k">'+e.t+'</span><span class="k" style="flex:1;text-transform:none">'+
    (e.where||'').replace(/</g,'&lt;')+'</span>'+
    '<button class="pill sm" onclick="errCopy('+i+')">copy</button></div>'+
    '<pre>'+(e.detail||'').replace(/</g,'&lt;')+'</pre></div>').join('')
    : '<span class="k">nothing has gone wrong yet</span>';
}
function errCopy(i){ navigator.clipboard.writeText(errText(ERRS[i])); }
$('#errRefresh').onclick=errs;
$('#errClear').onclick=async()=>{await fetch('/api/errors/clear',{method:'POST'});errs()};
$('#errCopyAll').onclick=()=>navigator.clipboard.writeText(ERRS.map(errText).join('\n\n'));
function report(where,detail){
  try{ fetch('/api/errors',{method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify({where:where,detail:String(detail).slice(0,3000)})}); }catch(e){}
}
window.addEventListener('error',e=>report(e.filename+':'+e.lineno, e.message+'\n'+(e.error&&e.error.stack||'')));
window.addEventListener('unhandledrejection',e=>report('promise', e.reason&&(e.reason.stack||e.reason.message)||e.reason));

/* ---------- boot ---------- */
async function boot(){
  ST=await(await fetch('/api/state')).json();
  $('#ver').textContent=ST.version;$('#repo').textContent=ST.repo_slug+' · '+ST.branch;
  const short=(ST.repo_path||'').replace(/^\/Users\/[^/]+/,'~').replace(/^\/home\/[^/]+/,'~');
  $('#cwd').textContent='claude code · '+short;
  $('#cRepo').value=ST.repo_path;$('#cSlug').value=ST.repo_slug;$('#cBr').value=ST.branch;
  health();
  if(!$('#chat').children.length){
    log('brain freedom','Left brain, one thing at a time. Right brain, the whole forest, a real terminal running the agent inside your repository.<br>Hold REC, speak, press Send, and watch it typed across. The small note beside any message reads it aloud and follows the words.','sys');
    if(!ST.has_key) log('keys','No AssemblyAI key yet. Tap the gear and import your keys file.','sys');
  }
}
let dg=false;
$('#drag').addEventListener('mousedown',()=>{dg=true;document.body.style.cursor='col-resize'});
window.addEventListener('mouseup',()=>{dg=false;document.body.style.cursor=''});
window.addEventListener('mousemove',e=>{if(!dg)return;
  $('#left').style.width=Math.min(74,Math.max(26,e.clientX/window.innerWidth*100))+'%';fit.fit();size()});
window.addEventListener('resize',()=>{fit.fit();size()});
boot();
</script></body></html>

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
  printf '%s\n' '{"assemblyai_key":"","github_token":"","repo_path":"'"$HOME"'/BRAIN_BRAKE","repo_slug":"markoboskoauroville/BRAIN_BRAKE","branch":"main","claude_cmd":"claude","voice_lang":"en"}' > "$CFG/config.json"
  chmod 600 "$CFG/config.json"; ok "defaults written, no keys asked, they live behind the gold gear"
else ok "existing settings kept"; fi
echo
printf "  ${G}ready${R}\n\n"
printf "  ${D}to start it, press${R} ${W}[S]${R} ${D}now, or type this anywhere in Terminal:${R}\n\n"
printf "      ${C}brainfreedom${R}\n\n"
printf "  ${D}it opens by itself in the browser you chose. If it does not,${R}\n"
printf "  ${D}paste the address it prints into Firefox.${R}\n"
echo
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
