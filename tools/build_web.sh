#!/usr/bin/env bash
# Export the web build and adapt it for artifact hosting, which caps files at 15MB
# and only serves known file types: split the engine into .wasm parts, rename the
# game data to .wasm, and add a fetch shim that maps the original names back.
set -euo pipefail
GODOT=${GODOT:-$HOME/tools/godot}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="${OUT:-$ROOT/../build/web}"
rm -rf "$OUT" && mkdir -p "$OUT"
"$GODOT" --headless --path "$ROOT" --export-release Web "$OUT/index.html"
cd "$OUT"
split -b 12m -d -a 1 index.wasm engine && rm index.wasm
for f in engine?; do mv "$f" "$f.wasm"; done
mv index.pck game-data.wasm
python3 - <<'PY'
import glob
parts = sorted(glob.glob("engine?.wasm"))
shim = """<script>
// Artifact hosting caps file size and only serves known file types, so the engine is split
// into .wasm parts and the game data is renamed; requests are mapped back here.
(function () {
  const parts = %s;
  const realFetch = window.fetch.bind(window);
  window.fetch = async function (url, opts) {
    if (typeof url === "string" && url.endsWith("index.wasm")) {
      const bufs = await Promise.all(parts.map(p => realFetch(p).then(r => r.arrayBuffer())));
      const blob = new Blob(bufs, { type: "application/wasm" });
      return new Response(blob, { headers: { "Content-Type": "application/wasm", "Content-Length": String(blob.size) } });
    }
    if (typeof url === "string" && url.endsWith("index.pck")) {
      return realFetch("game-data.wasm", opts);
    }
    return realFetch(url, opts);
  };
})();
</script>
""" % parts
s = open("index.html").read()
s = s.replace('<script src="index.js"></script>', shim + '<script src="index.js"></script>', 1)
open("index.html", "w").write(s)
PY
ls "$OUT"
