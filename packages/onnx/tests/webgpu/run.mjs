// run.mjs — host tests/webgpu/run.nu (an ONNX forward on the gpu
// package's WebGPU backend, built to wasm32-wasi by tests/webgpu_test.sh)
// and compare its output with a reference.
//
// Environment-neutral: export default(args, log) → exit code (0 match,
// 1 mismatch / failure, 2 no WebGPU adapter). `args` (URLs relative to
// the page): { wasm, model, input, shape: [dims], expect, tol }. `expect`
// is raw f32; the run matches when max|out − expect| <= tol × range(expect).
// Runner: deps/gpu/tests/webgpu_chrome.mjs (headless Chrome).

import { makeWebGPUHost } from "../../deps/gpu/web/webgpu.js";

const bytes = async (url) => new Uint8Array(await (await fetch(url)).arrayBuffer());

export default async function run(args, log = console.log) {
  const host = await makeWebGPUHost();
  if (!host.ok) { log("no WebGPU adapter"); return 2; }
  log(`adapter: ${host.describe()}${host.isFallback ? " (software)" : ""}`);
  const shape = new BigInt64Array(args.shape.map(BigInt));
  const blobs = [await bytes(args.model), await bytes(args.input), new Uint8Array(shape.buffer)];
  const expect = new Float32Array((await bytes(args.expect)).buffer);
  let memory = null, out = null;
  const td = new TextDecoder();
  let line = "";
  const env = {
    ...host.imports,
    host_blob_size: (k) => BigInt(blobs[Number(k)] ? blobs[Number(k)].length : 0),
    host_blob_read: (k, dst) => { new Uint8Array(memory.buffer).set(blobs[Number(k)], Number(dst)); return 0n; },
    host_result: (p, n) => { out = new Float32Array(memory.buffer.slice(Number(p), Number(p) + Number(n) * 4)); },
  };
  const view = () => new DataView(memory.buffer);
  const wasi = {
    fd_write: (fd, iovs, n, nw) => {
      let tot = 0;
      for (let i = 0; i < n; i++) {
        const p = view().getUint32(iovs + i * 8, true), l = view().getUint32(iovs + i * 8 + 4, true);
        line += td.decode(new Uint8Array(memory.buffer, p, l)); tot += l;
      }
      let nl; while ((nl = line.indexOf("\n")) >= 0) { log("[wasm] " + line.slice(0, nl)); line = line.slice(nl + 1); }
      view().setUint32(nw, tot, true); return 0;
    },
    proc_exit: (c) => { throw { wasiExit: Number(c) }; },
    random_get: (p, l) => { crypto.getRandomValues(new Uint8Array(memory.buffer, p, l)); return 0; },
    clock_time_get: (id, prec, o) => { view().setBigUint64(o, BigInt(Math.round(performance.now() * 1e6)), true); return 0; },
    fd_fdstat_get: (fd, b) => { new Uint8Array(memory.buffer).fill(0, b, b + 24); return 0; },
    fd_prestat_get: () => 8, fd_prestat_dir_name: () => 8, fd_close: () => 0, fd_fdstat_set_flags: () => 0,
    environ_sizes_get: (a, b) => { view().setUint32(a, 0, true); view().setUint32(b, 0, true); return 0; },
    environ_get: () => 0,
    args_sizes_get: (a, b) => { view().setUint32(a, 0, true); view().setUint32(b, 0, true); return 0; },
    args_get: () => 0,
  };
  const module = await WebAssembly.compile(await bytes(args.wasm));
  for (const imp of WebAssembly.Module.imports(module)) {
    if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => { throw new Error("stub import called: " + imp.name); };
    if (imp.module === "wasi_snapshot_preview1" && !(imp.name in wasi)) wasi[imp.name] = () => 52;
  }
  const instance = await WebAssembly.instantiate(module, { wasi_snapshot_preview1: wasi, env });
  memory = instance.exports.memory;
  host.bind(instance);
  const t0 = performance.now();
  let code = 0;
  try { await host.runWithAsyncify(() => instance.exports._start()); }
  catch (e) { if (e && typeof e.wasiExit === "number") code = e.wasiExit; else throw e; }
  const ms = performance.now() - t0;
  if (code !== 0) { log(`module exited ${code}`); return code === 2 ? 2 : 1; }
  if (!out) { log("no result"); return 1; }
  let lo = Infinity, hi = -Infinity, maxd = 0;
  for (const v of expect) { lo = Math.min(lo, v); hi = Math.max(hi, v); }
  for (let i = 0; i < expect.length; i++) maxd = Math.max(maxd, Math.abs(out[i] - expect[i]) || (Number.isNaN(out[i]) ? Infinity : 0));
  const range = Math.max(hi - lo, 1e-30);
  const ok = out.length === expect.length && maxd <= (args.tol ?? 1e-5) * range;
  log(`output ${out.length} values (expect ${expect.length}), max |diff| ${maxd.toExponential(2)} = ${(maxd / range).toExponential(2)} of range, ${ms.toFixed(0)} ms`);
  log(ok ? "MATCH" : "MISMATCH");
  return ok ? 0 : 1;
}
