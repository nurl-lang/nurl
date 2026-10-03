// webgpu.js — the WebGPU host for the gpu package's backend 3.
//
// Implements the wgpu_* imports a NURL wasm module (built with the
// WebGPU backend selected) calls, against navigator.gpu. Works in both
// Deno (headless verification) and a browser worker. The one async op —
// gpu_download → wgpu_download (GPUBuffer.mapAsync) — is bridged with
// Asyncify: the wasm module is post-processed with `wasm-opt --asyncify
// --pass-arg=asyncify-imports@env.wgpu_download`, and runWithAsyncify()
// below drives the unwind/await/rewind dance so the synchronous NURL
// call returns the data in wasm memory.
//
//   const host = await makeWebGPUHost();
//   const { instance } = await WebAssembly.instantiate(module, {
//     wasi_snapshot_preview1: wasi, env: { ...host.imports, ...otherEnv },
//   });
//   host.bind(instance);                 // after memory is available
//   await host.runWithAsyncify(() => instance.exports._start());
//
// kernels_wgsl.js supplies the kernel set: each kernel's WGSL body and
// the C parameter list it is launched with, from which the bindings, the
// uniform block and the argument decoding are generated (marshal).

import { K, buildWGSL, bindLayout, marshal, uniformLayout, dispatchInvocations } from "./kernels_wgsl.js";

export async function makeWebGPUHost() {
  // high-performance matters on multi-GPU machines: the default adapter
  // can be the weakest device (observed: Deno/wgpu handing out a GTX 970
  // while an RTX 4090 sat idle in the same box)
  const adapter = navigator.gpu && await navigator.gpu.requestAdapter({ powerPreference: "high-performance" });
  const device = adapter && await adapter.requestDevice();
  const ok = !!device;
  // A WGSL that fails to compile, or a bind group that does not match its
  // pipeline, is reported asynchronously and otherwise silently drops the
  // work — say so (labels carry the kernel's name).
  if (ok) device.addEventListener("uncapturederror", (e) => console.error("[gpu/webgpu] " + ((e.error && e.error.message) || e)));

  let memory = null, exp = null;
  const mem = () => new Uint8Array(memory.buffer);
  const memF = () => new Float32Array(memory.buffer);
  const memI = () => new Int32Array(memory.buffer);

  // ── resources ──
  const buffers = new Map();      // id → GPUBuffer
  let nextBuf = 1;
  const pipelines = [];           // [null, {pipe, name}, ...] (1-based)
  const pipeByName = new Map();   // name → id

  const ST = ok ? (GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_SRC | GPUBufferUsage.COPY_DST) : 0;
  const UN = ok ? (GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST) : 0;
  // A shared placeholder for null (id 0) buffer arguments. CUDA lets a
  // kernel take a null pointer for an unused param (e.g. conv bias when
  // hasB=0); WebGPU requires every bind-group entry to be a real buffer,
  // so bind this 4-byte buffer — the kernel's guard never reads it.
  let dummyBuf = null;
  const nullBuf = () => (dummyBuf ||= device.createBuffer({ size: 4, usage: ST }));

  // ── batched submission ──
  // One queue.submit per kernel launch is the dominant cost in a browser
  // (each submit is an IPC round-trip to the GPU process — a ~270-node
  // net paid it ~270× per frame). Instead launches accumulate dispatches
  // in ONE command encoder / compute pass, and flush() submits only when
  // something must observe the results (download, or an upload that
  // would otherwise be reordered before the encoded work — queue
  // operations execute in queue order, so a writeBuffer issued while an
  // encoder is still pending would land BEFORE those dispatches).
  let enc = null, pass = null;
  const deadBufs = [];            // wgpu_free'd while referenced by the pending encoder
  function getPass() {
    if (!enc) enc = device.createCommandEncoder();
    if (!pass) pass = enc.beginComputePass();
    return pass;
  }
  function endPass() { if (pass) { pass.end(); pass = null; } }
  function flush() {
    if (!enc) return;
    endPass();
    device.queue.submit([enc.finish()]);
    enc = null;
    for (const b of deadBufs) b.destroy();
    deadBufs.length = 0;
  }
  // A model forward launches the same nodes with the same buffers and
  // scalars every frame — cache the (bind group + uniform buffer) per
  // (pipeline, buffer ids, scalar bytes), so steady-state frames create
  // no GPU objects and write no uniforms at all.
  const bgCache = new Map();      // key → { bg, uni, ids }
  function dropCachedFor(bufId) {
    for (const [k, e] of bgCache) {
      if (e.ids.includes(bufId)) {
        if (e.uni) { if (enc) deadBufs.push(e.uni); else e.uni.destroy(); }
        bgCache.delete(k);
      }
    }
  }

  // ── asyncify state ──
  let stackBase = 0, stackSize = 0, stackInited = false;
  const asy = { pending: null, rewinding: false, result: 0n };

  function initStack() {
    if (stackInited) return;
    stackBase = exp.__nurl_asyncify_stack_ptr();
    stackSize = exp.__nurl_asyncify_stack_size();
    // [current, end] header at stackBase; data region follows.
    memI()[(stackBase >> 2) + 0] = stackBase + 8;
    memI()[(stackBase >> 2) + 1] = stackBase + stackSize;
    stackInited = true;
  }

  const imports = {
    wgpu_pipeline: (namePtr) => {
      if (!ok) return 0n;
      const name = cstr(namePtr);
      if (!K[name]) return 0n;
      let id = pipeByName.get(name);
      if (id) return BigInt(id);
      let pipe;
      try {
        const mod = device.createShaderModule({ label: name, code: buildWGSL(name) });
        // the bind-group layout is the kernel's parameter list, not what
        // the body happens to reference ("auto" drops an unused binding,
        // and the launch's bind group would then fail to match)
        const bgl = device.createBindGroupLayout({ label: name, entries: bindLayout(name).map((e) => ({
          binding: e.binding, visibility: GPUShaderStage.COMPUTE, buffer: { type: e.type } })) });
        pipe = device.createComputePipeline({ label: name,
          layout: device.createPipelineLayout({ bindGroupLayouts: [bgl] }),
          compute: { module: mod, entryPoint: "main" } });
      } catch (e) {
        console.error(`[gpu/webgpu] ${name}: ${e.message || e}`);
        return 0n;
      }
      pipelines.push({ pipe, name, hasUniform: uniformLayout(name).length > 0 });
      id = pipelines.length; // 1-based
      pipeByName.set(name, id);
      return BigInt(id);
    },
    wgpu_alloc: (bytes) => {
      if (!ok) return 0n;
      const b = device.createBuffer({ size: Math.max(4, Number(bytes)), usage: ST });
      const id = nextBuf++;
      buffers.set(id, b);
      return BigInt(id);
    },
    wgpu_free: (id) => {
      const b = buffers.get(Number(id)); if (!b) return;
      buffers.delete(Number(id));
      dropCachedFor(Number(id));
      // The pending encoder may still reference it in a bind group;
      // destroying now would fail validation at submit. Defer to flush().
      if (enc) deadBufs.push(b); else b.destroy();
    },
    wgpu_upload: (id, hostPtr, bytes) => {
      const b = buffers.get(Number(id)); if (!b) return -1n;
      // writeBuffer executes in queue order — flush pending dispatches so
      // they read the buffer's OLD contents, not this write.
      flush();
      const n = Number(bytes);
      device.queue.writeBuffer(b, 0, mem().slice(Number(hostPtr), Number(hostPtr) + n));
      return 0n;
    },
    wgpu_dtod: (dst, src, bytes) => {
      const d = buffers.get(Number(dst)), sb = buffers.get(Number(src)); if (!d || !sb) return -1n;
      // Encode into the pending batch (copies can't live inside a compute
      // pass, so end it; the next launch reopens one in the same encoder).
      endPass();
      if (!enc) enc = device.createCommandEncoder();
      enc.copyBufferToBuffer(sb, 0, d, 0, Number(bytes));
      return 0n;
    },
    wgpu_launch: (pipeId, total, argsPtr, nargs) => {
      const entry = pipelines[Number(pipeId) - 1]; if (!entry) return -1n;
      const name = entry.name;
      // args: nargs i64 cells at argsPtr — buffer ids or scalar bits, in
      // the kernel's parameter order (its `sig`)
      const dv = new DataView(memory.buffer, Number(argsPtr), Number(nargs) * 8);
      const cells = [];
      for (let i = 0; i < Number(nargs); i++) cells.push(dv.getBigInt64(i * 8, true));
      const m = marshal(name, cells);
      if (m.error) { console.error("[gpu/webgpu] " + m.error); return -3n; }
      const key = pipeId + "|" + m.ids.join(",") + "|" + new Uint32Array(m.uniform).join(",");
      let ce = bgCache.get(key);
      if (!ce) {
        const entries = [];
        for (let i = 0; i < m.ids.length; i++) {
          const b = m.ids[i] === 0 ? nullBuf() : buffers.get(m.ids[i]);
          if (!b) return -2n;
          entries.push({ binding: i, resource: { buffer: b } });
        }
        let uni = null;
        if (entry.hasUniform) {
          uni = device.createBuffer({ size: m.uniform.byteLength, usage: UN });
          device.queue.writeBuffer(uni, 0, m.uniform);
          entries.push({ binding: m.ids.length, resource: { buffer: uni } });
        }
        const bg = entries.length ? device.createBindGroup({ label: name, layout: entry.pipe.getBindGroupLayout(0), entries }) : null;
        ce = { bg, uni, ids: m.ids };
        bgCache.set(key, ce);
      }
      const groups = Math.ceil(dispatchInvocations(name, m.scalars, Number(total)) / 64);
      if (groups <= 0) return 0n;
      const p = getPass();
      p.setPipeline(entry.pipe);
      if (ce.bg) p.setBindGroup(0, ce.bg);
      const gx = Math.min(groups, 65535), gy = Math.ceil(groups / 65535);
      p.dispatchWorkgroups(gx, gy);
      return 0n;
    },
    // async readback → asyncify unwind/rewind
    wgpu_download: (hostPtr, id, bytes) => {
      if (asy.rewinding) { asy.rewinding = false; exp.asyncify_stop_rewind(); return asy.result; }
      initStack();
      const b = buffers.get(Number(id)); if (!b) return -1n;
      const n = Number(bytes), hp = Number(hostPtr);
      const rb = device.createBuffer({ size: n, usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ });
      // Ride the pending batch: the readback copy is ordered after every
      // encoded dispatch, and the whole frame goes up in ONE submit.
      endPass();
      if (!enc) enc = device.createCommandEncoder();
      enc.copyBufferToBuffer(b, 0, rb, 0, n);
      flush();
      asy.result = 0n;
      asy.pending = rb.mapAsync(GPUMapMode.READ).then(() => {
        mem().set(new Uint8Array(rb.getMappedRange().slice(0)), hp);
        rb.destroy();
      });
      exp.asyncify_start_unwind(stackBase);
      return 0n;
    },
  };

  function cstr(ptr) {
    const m = mem(); let e = Number(ptr);
    while (m[e] !== 0) e++;
    return new TextDecoder().decode(m.subarray(Number(ptr), e));
  }

  const info = adapter ? (adapter.info || {}) : {};
  return {
    ok,
    adapterInfo: info,
    // A software adapter (Chrome's SwiftShader, Mesa's lavapipe) runs the
    // shaders on the CPU — 20-50× slower than a real GPU. Surface it so a
    // demo can warn instead of silently reading "running on your GPU".
    isFallback: !!(adapter && (adapter.isFallbackAdapter ||
      /swiftshader|llvmpipe|lavapipe|software|cpu/i.test(
        (info.vendor || "") + " " + (info.architecture || "") + " " + (info.device || "") + " " + (info.description || "")))),
    describe() {
      if (!ok) return "no WebGPU";
      const s = [info.vendor, info.architecture, info.description].filter(Boolean).join(" · ");
      return s || "GPU adapter";
    },
    imports,
    bind(instance) { memory = instance.exports.memory; exp = instance.exports; },
    // Read device buffer `id` back without Asyncify (for a JS caller that
    // can await — tests drive the imports directly with this).
    async readBuffer(id, bytes) {
      const b = buffers.get(Number(id)); if (!b) throw new Error("no buffer " + id);
      const rb = device.createBuffer({ size: bytes, usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ });
      endPass();
      if (!enc) enc = device.createCommandEncoder();
      enc.copyBufferToBuffer(b, 0, rb, 0, bytes);
      flush();
      await rb.mapAsync(GPUMapMode.READ);
      const out = rb.getMappedRange().slice(0);
      rb.destroy();
      return out;
    },
    // Wrap a host import so a synchronous NURL call suspends the module
    // (Asyncify unwind), awaits `fn`'s Promise, then rewinds returning its
    // result. Use for a blocking import that must go async without a
    // worker — e.g. host_frame awaiting the next camera frame on the main
    // thread. `fn` must resolve to a BigInt (the value the NURL call
    // returns). Build the module with this import in --asyncify-imports.
    asyncImport(fn) {
      return (...args) => {
        if (asy.rewinding) { asy.rewinding = false; exp.asyncify_stop_rewind(); return asy.result; }
        initStack();
        asy.pending = Promise.resolve(fn(...args)).then((r) => { asy.result = (typeof r === "bigint") ? r : BigInt(r | 0); });
        exp.asyncify_start_unwind(stackBase);
        return 0n;
      };
    },
    async runWithAsyncify(entry) {
      entry();
      while (asy.pending) {
        const p = asy.pending; asy.pending = null;
        await p;
        exp.asyncify_stop_unwind();
        asy.rewinding = true;
        exp.asyncify_start_rewind(stackBase);
        entry();
      }
    },
  };
}
