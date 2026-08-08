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
VERSION  = "v6 (a)"

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
    try:
        okr, msg, path = ensure_repo()
        print("  " + (G if okr else D) + ("repository " + msg + "  " + path if okr else msg) + R)
    except Exception:
        pass
    try:
        okr, msg, path = ensure_repo()
        print("  " + (G if okr else D) + ("repository " + msg if okr else msg) + R)
    except Exception:
        pass
    b = open_in_browser(url)
    print("  " + D + "opening " + (b or "your browser") + R + "\n")
    threading.Thread(target=hotkeys, args=(PORT,url), daemon=True).start()
    from werkzeug.serving import make_server
    srv = make_server("127.0.0.1", PORT, app, threaded=True)
    srv.serve_forever()
