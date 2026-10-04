#!/usr/bin/env python3
# ---------------------------------------------------------------------------
#  omega-webui  -  tiny on-device control panel for Omega.
#
#  Runs as root via a LaunchDaemon, bound to 127.0.0.1 ONLY (reachable just
#  from Safari on the device itself). Gives buttons to Apply the cleanup, see
#  Status, tail the Log and run Debug diagnostics - all by calling the
#  omega-ondevice worker. Pure Python 3 standard library, no dependencies.
# ---------------------------------------------------------------------------
import html
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = "127.0.0.1"
PORT = 8472
WORKER = "/var/jb/usr/local/bin/omega-ondevice"
LOG = "/var/mobile/omega-ondevice.log"

PAGE = """<!doctype html><html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Omega Control</title>
<style>
 :root{color-scheme:dark}
 *{box-sizing:border-box}
 body{margin:0;font:16px/1.5 -apple-system,system-ui,sans-serif;background:#0b0d10;color:#e6e9ef}
 header{padding:20px 16px;background:linear-gradient(135deg,#1b2430,#0b0d10);border-bottom:1px solid #222}
 h1{margin:0;font-size:20px} .sub{color:#8a94a6;font-size:13px;margin-top:4px}
 main{padding:16px;max-width:760px;margin:0 auto}
 .grid{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-bottom:16px}
 button{appearance:none;border:0;border-radius:12px;padding:16px;font-size:15px;font-weight:600;color:#fff;cursor:pointer}
 .apply{background:#c0392b}.status{background:#2d7d46}.log{background:#2e5aac}.debug{background:#6b4fa0}
 button:active{transform:scale(.98)}
 pre{background:#05070a;border:1px solid #1d2430;border-radius:12px;padding:14px;white-space:pre-wrap;
     word-break:break-word;min-height:220px;max-height:60vh;overflow:auto;font:13px/1.45 ui-monospace,Menlo,monospace}
 .bar{display:flex;align-items:center;gap:10px;margin:0 0 10px}
 .dot{width:9px;height:9px;border-radius:50%;background:#2d7d46}
 .muted{color:#8a94a6;font-size:12px}
 label{font-size:13px;color:#8a94a6;display:flex;align-items:center;gap:6px;margin-bottom:10px}
</style></head><body>
<header><h1>Omega Control</h1>
<div class="sub">On-device revocation neutraliser &middot; localhost only</div></header>
<main>
 <div class="grid">
  <button class="apply"  onclick="act('apply','POST',true)">Appliquer (clean)</button>
  <button class="status" onclick="act('status')">Vérifier l'état</button>
  <button class="log"    onclick="act('log')">Voir le log</button>
  <button class="debug"  onclick="act('debug')">Debug</button>
 </div>
 <label><input type="checkbox" id="auto"> rafraîchir le log toutes les 3 s</label>
 <div class="bar"><span class="dot" id="dot"></span><span class="muted" id="st">prêt</span></div>
 <pre id="out">Choisis une action ci-dessus.

Rappel : ceci enlève le blocage LOCAL (apps OK hors-ligne). En ligne, bloque
ocsp/ppq/crl/valid.apple.com via ton DNS (NextDNS / VPS) sinon ça re-bloque.</pre>
</main>
<script>
let timer=null;
async function act(ep, method='GET', confirmFirst=false){
 if(confirmFirst && !confirm('Appliquer le nettoyage et redémarrer les démons ?')) return;
 const dot=document.getElementById('dot'), st=document.getElementById('st'), out=document.getElementById('out');
 dot.style.background='#d8a200'; st.textContent=ep+'…';
 try{
  const r=await fetch('/api/'+ep,{method});
  out.textContent=await r.text();
  dot.style.background= r.ok ? '#2d7d46' : '#c0392b'; st.textContent=ep+' — '+(r.ok?'ok':'erreur');
 }catch(e){ out.textContent=String(e); dot.style.background='#c0392b'; st.textContent='échec'; }
}
document.getElementById('auto').addEventListener('change',e=>{
 clearInterval(timer);
 if(e.target.checked){ act('log'); timer=setInterval(()=>act('log'),3000); }
});
</script></body></html>"""


def run_worker(arg, timeout=120):
    try:
        p = subprocess.run([WORKER, arg], capture_output=True, text=True, timeout=timeout)
        return (p.stdout + p.stderr) or f"(no output, exit {p.returncode})"
    except Exception as e:  # noqa: BLE001
        return f"error running {WORKER} {arg}: {e}"


def tail_log(n=200):
    try:
        with open(LOG, "r", errors="replace") as f:
            return "".join(f.readlines()[-n:]) or "(log vide)"
    except FileNotFoundError:
        return "(pas encore de log)"
    except Exception as e:  # noqa: BLE001
        return f"error: {e}"


class H(BaseHTTPRequestHandler):
    def _send(self, body, ctype="text/plain; charset=utf-8", code=200):
        data = body.encode() if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *a):  # silence console noise
        pass

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            return self._send(PAGE, "text/html; charset=utf-8")
        if self.path == "/api/status":
            return self._send(run_worker("status"))
        if self.path == "/api/debug":
            return self._send(run_worker("diag"))
        if self.path == "/api/log":
            return self._send(tail_log())
        return self._send("not found", code=404)

    def do_POST(self):
        if self.path == "/api/apply":
            return self._send(run_worker("apply"))
        return self._send("not found", code=404)


if __name__ == "__main__":
    ThreadingHTTPServer((HOST, PORT), H).serve_forever()
