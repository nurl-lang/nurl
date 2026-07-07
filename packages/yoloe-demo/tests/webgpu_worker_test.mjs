// Drive the REAL packages/yoloe-demo/web/worker.js as a Deno module
// Worker (same Web Worker API + WebGPU as a browser), one frame, both
// backends. Proves the shipped worker code, not a reimplementation.
const engine = Deno.args[0] || "webgpu";
const W=640,H=480,FRAME=W*H*3, SAB_IN=4096, SAB_OUT=SAB_IN+FRAME;
const PKG = new URL("..", import.meta.url).pathname;
const HOME = Deno.env.get("HOME");
const MODEL = Deno.env.get("YOLOE_PROMPT_MODEL") || HOME + "/yoloe-export/yoloe-promptable-k32.onnx";
const TPE = Deno.env.get("YOLOE_TPE") || HOME + "/yoloe-export/tpe10.f32";
const wasm = (await Deno.readFile(PKG + "web/yoloe_detect.wasm")).buffer;
const model = (await Deno.readFile(MODEL)).buffer;
const tpe = (await Deno.readFile(TPE)).buffer;
const rgb = new Uint8Array((new Deno.Command("python3",{args:["-c",`
from PIL import Image
im=Image.open('${PKG}../yoloe/docs/demo.png').convert('RGB').resize((640,480))
import sys; sys.stdout.buffer.write(im.tobytes())`],stdout:"piped",stderr:"piped"}).outputSync()).stdout);
if (rgb.length !== FRAME) { console.log(engine + ": image load failed (" + rgb.length + " bytes)"); Deno.exit(1); }

const sab = new SharedArrayBuffer(SAB_OUT + FRAME);
const ctl = new Int32Array(sab, 0, 1024); const bytes = new Uint8Array(sab);
const w = new Worker(new URL("../web/worker.js", import.meta.url), { type: "module" });
let done=false, result=null;
w.onmessage = (e) => {
  const m = e.data;
  if (m.type === "log") { /* console.error("[wasm]", m.line); */ return; }
  if (m.type === "status" && m.code === 2) {
    bytes.set(rgb, SAB_IN); ctl[1]=0; ctl[2]=250; ctl[3]=1; ctl[4]=0x3ff;
    setTimeout(() => { Atomics.store(ctl,0,1); Atomics.notify(ctl,0); }, 200);
  }
  if (m.type === "result") { result=m; ctl[1]=9; Atomics.store(ctl,0,1); Atomics.notify(ctl,0); }
  if (m.type === "exit") {
    let dog=false; for(let k=0;k<result.n;k++) if(Math.round(result.dets[k*6])===1 && result.dets[k*6+1]>0.5) dog=true;
    console.log(`${engine}: ${result.n} dets, ${result.ms}ms — ${dog?"PASS (dog)":"FAIL"}`);
    done=true; Deno.exit(dog?0:1);
  }
  if (m.type === "error") { console.log(`${engine}: ERROR ${m.message}`); Deno.exit(1); }
};
w.postMessage({ type:"init", engine, sab, wasm, model, tpe }, [wasm, model, tpe]);
setTimeout(()=>{ if(!done){ console.log(`${engine}: TIMEOUT`); Deno.exit(1); } }, 60000);
