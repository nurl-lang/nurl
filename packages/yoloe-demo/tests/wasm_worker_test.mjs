// tests/wasm_worker_test.mjs — drive web/worker.js (the real browser
// worker, run in a node worker thread via wasm_worker_wrap.mjs) exactly
// as the page does: init with model+tpe over a SharedArrayBuffer, hand
// one frame, check detections + that the masked out-frame carries the
// dog's green mask. Env:
//   YOLOE_WASM        web/yoloe_detect.wasm (built by build_wasm.sh)
//   YOLOE_PROMPT_MODEL, YOLOE_TPE   the promptable export + seed tpe
// Exits 0 on PASS / skips (0) when artifacts are missing.
import { Worker } from 'node:worker_threads';
import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const PKG = join(HERE, '..');
const HOME = process.env.HOME;
const WASM = process.env.YOLOE_WASM || join(PKG, 'web/yoloe_detect.wasm');
const MODEL = process.env.YOLOE_PROMPT_MODEL || join(HOME, 'yoloe-export/yoloe-promptable-k32.onnx');
const TPE = process.env.YOLOE_TPE || join(HOME, 'yoloe-export/tpe10.f32');
const DEMO_PNG = join(PKG, '../yoloe/docs/demo.png');

if (!existsSync(WASM) || !existsSync(MODEL) || !existsSync(TPE)) {
  console.log('SKIP: wasm module / model / tpe not found — build with tools/ + build_wasm.sh');
  process.exit(0);
}

const W = 640, H = 480, FRAME = W * H * 3;
const SAB_IN = 4096, SAB_OUT = SAB_IN + FRAME;

// letterbox the demo image into 640x480 RGB via a tiny python (Pillow)
const RGB_TMP = join(HERE, '.wasm_test_frame.rgb');
execFileSync('python3', ['-c', `
from PIL import Image
im = Image.open('${DEMO_PNG}').convert('RGB').resize((${W},${H}))
open('${RGB_TMP}','wb').write(im.tobytes())
`]);

const [wasm, model, tpe, rgb] = await Promise.all([
  readFile(WASM), readFile(MODEL), readFile(TPE), readFile(RGB_TMP),
]);

const sab = new SharedArrayBuffer(SAB_OUT + FRAME);
const ctl = new Int32Array(sab, 0, 1024);
const bytes = new Uint8Array(sab);

const w = new Worker(new URL('./wasm_worker_wrap.mjs', import.meta.url));
const t0 = Date.now();
let state = 'init';

w.on('message', (m) => {
  if (m.type === 'log') { console.log('[wasm]', m.line); return; }
  if (m.type === 'status') { console.log(`[main] status ${m.code} (${m.extra}) +${Date.now()-t0}ms`); }
  if (m.type === 'status' && m.code === 2) {
    // engine ready → hand over one frame
    bytes.set(rgb, SAB_IN);
    ctl[1] = 0; ctl[2] = 250; ctl[3] = 1; ctl[4] = 0x3ff;
    // wait for the worker to reach idle before notifying
    const arm = () => {
      Atomics.store(ctl, 0, 1);
      Atomics.notify(ctl, 0);
    };
    setTimeout(arm, 300);
    state = 'frame-sent';
  }
  if (m.type === 'result') {
    console.log(`[main] result: n=${m.n} inference=${m.ms}ms`);
    for (let k = 0; k < m.n; k++) {
      const [cls, score, x, y, wd, h] = m.dets.slice(k*6, k*6+6);
      console.log(`  cls=${cls} score=${score.toFixed(3)} box=[${x},${y},${wd},${h}]`);
    }
    // masked out-frame sanity: some green pixels from the dog mask
    const out = bytes.subarray(SAB_OUT, SAB_OUT + FRAME);
    let greenish = 0;
    for (let i = 0; i < FRAME; i += 3) if (out[i+1] > out[i] + 30 && out[i+1] > out[i+2] + 30) greenish++;
    console.log(`[main] masked-frame greenish px: ${greenish}`);
    // quit: next host_frame gets cmd 9
    ctl[1] = 9;
    Atomics.store(ctl, 0, 1);
    Atomics.notify(ctl, 0);
  }
  if (m.type === 'result') { globalThis.__got = m; }
  if (m.type === 'exit') {
    console.log(`[main] module exit rc=${m.code}, total ${(Date.now()-t0)/1000}s`);
    w.terminate();
    const g = globalThis.__got;
    let dogSeen = false;
    for (let k = 0; k < g.n; k++) if (Math.round(g.dets[k*6]) === 1 && g.dets[k*6+1] > 0.5) dogSeen = true;
    const out = bytes.subarray(SAB_OUT, SAB_OUT + FRAME);
    let green = 0; for (let i = 0; i < FRAME; i += 3) if (out[i+1] > out[i]+30 && out[i+1] > out[i+2]+30) green++;
    const ok = g.n >= 2 && dogSeen && green > 5000;
    console.log(ok ? 'PASS wasm worker: dog detected + mask composited' : 'FAIL wasm worker');
    process.exit(ok ? 0 : 1);
  }
  if (m.type === 'error') { console.error('[main] ERROR', m.message); process.exit(1); }
});
w.postMessage({ type: 'init', sab, wasm: wasm.buffer, model: model.buffer, tpe: tpe.buffer });
