// objdet_demo_test.mjs — drive nurlapi/static/objdet_detect.wasm the way
// objdetdemo.html does (main thread, host.asyncImport for host_frame),
// against Deno's headless WebGPU. 3 frames of the yoloe dog image.
// Needs the tiny-yolov2 model:  OBJDET_MODEL=~/tinyyolov2-8.onnx
//   deno run --unstable-webgpu --allow-read --allow-env --allow-run objdet_demo_test.mjs
import { makeWebGPUHost } from "../static/webgpu.js";

const N = 416, NCHW = 3 * N * N;
const DIR = new URL(".", import.meta.url).pathname;
const MODEL = Deno.env.get("OBJDET_MODEL") || Deno.env.get("HOME") + "/tinyyolov2-8.onnx";
let model;
try { model = await Deno.readFile(MODEL); }
catch { console.log("SKIP: model not found (" + MODEL + ") — set OBJDET_MODEL"); Deno.exit(0); }
const wasm = (await Deno.readFile(DIR + "../static/objdet_detect.wasm")).buffer;

// dog image → 416×416 CHW 0-255 via PIL
const rgb = new Uint8Array((new Deno.Command("python3", { args: ["-c", `
from PIL import Image
im=Image.open('${DIR}../../packages/yoloe/docs/demo.png').convert('RGB')
s=min(416/im.width,416/im.height); im=im.resize((round(im.width*s),round(im.height*s)))
bg=Image.new('RGB',(416,416)); bg.paste(im,((416-im.width)//2,(416-im.height)//2)); im=bg
import sys; sys.stdout.buffer.write(im.tobytes())`], stdout: "piped", stderr: "piped" }).outputSync()).stdout);
if (rgb.length !== N * N * 3) { console.log("image load failed", rgb.length); Deno.exit(1); }

const host = await makeWebGPUHost();
if (!host.ok) { console.log("SKIP: no WebGPU adapter"); Deno.exit(0); }
console.log("adapter:", host.describe(), "fallback:", host.isFallback);

let memory = null, running = true, frames = 0, t0 = 0;
const times = [], results = [];
const env = {
  ...host.imports,
  host_blob_size: (k) => BigInt(Number(k) === 0 ? model.length : 0),
  host_blob_read: (k, dst) => { if (Number(k) === 0) new Uint8Array(memory.buffer).set(model, Number(dst)); return 0n; },
  host_frame: host.asyncImport(async (nchwP, ctlP) => {
    if (frames >= 3) return 9n;
    await new Promise(r => setTimeout(r, 0));
    new Int32Array(memory.buffer, Number(ctlP), 4)[0] = 250; // conf 25%
    const dst = new Float32Array(memory.buffer, Number(nchwP), NCHW);
    const plane = N * N;
    for (let px = 0; px < plane; px++) {
      dst[px] = rgb[px * 3]; dst[plane + px] = rgb[px * 3 + 1]; dst[2 * plane + px] = rgb[px * 3 + 2];
    }
    t0 = performance.now();
    return 0n;
  }),
  host_result: (ptr, nd) => {
    const ms = Math.round(performance.now() - t0);
    const n = Number(nd), d = new Float32Array(memory.buffer, Number(ptr), n * 6);
    const dets = [];
    for (let k = 0; k < n; k++) dets.push({ cls: Math.round(d[k*6]), score: +d[k*6+1].toFixed(3) });
    times.push(ms); results.push(dets); frames++;
  },
  host_status: () => {},
};
const module = await WebAssembly.compile(wasm);
const td = new TextDecoder();
const wasi = new Proxy({
  fd_write: (fd, iovs, iovsLen, nwritten) => {
    const v = new DataView(memory.buffer); let tot = 0, out = "";
    for (let i = 0; i < iovsLen; i++) { const p = v.getUint32(iovs+i*8,true), l = v.getUint32(iovs+i*8+4,true); out += td.decode(new Uint8Array(memory.buffer, p, l)); tot += l; }
    if (out.trim()) console.log("[wasm]", out.trim());
    v.setUint32(nwritten, tot, true); return 0;
  },
  proc_exit: (c) => { const e = new Error("exit"); e.code = Number(c); throw e; },
  random_get: (p, l) => { crypto.getRandomValues(new Uint8Array(memory.buffer, p, l)); return 0; },
  clock_time_get: (id, prec, out) => { new DataView(memory.buffer).setBigUint64(out, BigInt(Math.round(performance.now()*1e6)), true); return 0; },
  fd_prestat_get: () => 8, fd_prestat_dir_name: () => 8,
  fd_fdstat_get: (fd, buf) => { new Uint8Array(memory.buffer).fill(0, buf, buf + 24); return 0; },
  fd_fdstat_set_flags: () => 0, fd_close: () => 0, fd_read: () => 52, fd_seek: () => 52,
  environ_sizes_get: (a, b) => { const v = new DataView(memory.buffer); v.setUint32(a,0,true); v.setUint32(b,0,true); return 0; },
  environ_get: () => 0,
  args_sizes_get: (a, b) => { const v = new DataView(memory.buffer); v.setUint32(a,0,true); v.setUint32(b,0,true); return 0; },
  args_get: () => 0,
}, { get: (t, k) => t[k] ?? (() => 52) });
for (const imp of WebAssembly.Module.imports(module)) {
  if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => { throw new Error("stub " + imp.name); };
}
const instance = await WebAssembly.instantiate(module, { wasi_snapshot_preview1: wasi, env });
memory = instance.exports.memory; host.bind(instance);
try { await host.runWithAsyncify(() => instance.exports._start()); }
catch (e) { if (!(typeof e.code === "number")) throw e; console.log("proc_exit code:", e.code); }
const VOC = ["aeroplane","bicycle","bird","boat","bottle","bus","car","cat","chair","cow","diningtable","dog","horse","motorbike","person","pottedplant","sheep","sofa","train","tvmonitor"];
const dogs = results.map(r => r.some(d => VOC[d.cls] === "dog" && d.score > 0.25));
console.log("frames ms:", times.join(","), "dets:", JSON.stringify(results[results.length-1]));
console.log(dogs.every(Boolean) && frames === 3 ? "PASS (dog on all frames)" : "FAIL");
Deno.exit(dogs.every(Boolean) && frames === 3 ? 0 : 1);
