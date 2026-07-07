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
// kernels_wgsl.js supplies the WGSL + arg signatures.

import { K, buildWGSL, scalarLayout } from "./kernels_wgsl.js";

export async function makeWebGPUHost() {
  const adapter = navigator.gpu && await navigator.gpu.requestAdapter();
  const device = adapter && await adapter.requestDevice();
  const ok = !!device;

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

  // ── asyncify state ──
  let stackBase = 0, stackSize = 0, stackInited = false;
  const asy = { pendingWrite: null, rewinding: false };

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
      const mod = device.createShaderModule({ code: buildWGSL(name) });
      const pipe = device.createComputePipeline({ layout: "auto", compute: { module: mod, entryPoint: "main" } });
      pipelines.push({ pipe, name });
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
    wgpu_free: (id) => { const b = buffers.get(Number(id)); if (b) { b.destroy(); buffers.delete(Number(id)); } },
    wgpu_upload: (id, hostPtr, bytes) => {
      const b = buffers.get(Number(id)); if (!b) return -1n;
      const n = Number(bytes);
      device.queue.writeBuffer(b, 0, mem().slice(Number(hostPtr), Number(hostPtr) + n));
      return 0n;
    },
    wgpu_dtod: (dst, src, bytes) => {
      const d = buffers.get(Number(dst)), sb = buffers.get(Number(src)); if (!d || !sb) return -1n;
      const enc = device.createCommandEncoder();
      enc.copyBufferToBuffer(sb, 0, d, 0, Number(bytes));
      device.queue.submit([enc.finish()]);
      return 0n;
    },
    wgpu_launch: (pipeId, total, argsPtr, nargs) => {
      const entry = pipelines[Number(pipeId) - 1]; if (!entry) return -1n;
      const name = entry.name;
      const params = K[name].params;
      // args: nargs i64 cells at argsPtr — buffer ids or scalar bits, in param order.
      const argsBase = Number(argsPtr) >> 3; // i64 index
      const cellsLo = new Int32Array(memory.buffer, Number(argsPtr), Number(nargs) * 2);
      const storageEntries = [];
      const scalars = scalarLayout(name);
      const ub = new ArrayBuffer(Math.max(16, Math.ceil(scalars.length * 4 / 16) * 16));
      const ubI = new Int32Array(ub), ubF = new Float32Array(ub);
      let bufBinding = 0, scalarIdx = 0;
      for (let i = 0; i < params.length; i++) {
        const [pn, t] = params[i];
        const lo = cellsLo[i * 2]; // low 32 bits of the i64 cell
        if (t === "b" || t === "w" || t === "q" || t === "Q") {
          const b = lo === 0 ? nullBuf() : buffers.get(lo);
          if (!b) return -2n;
          storageEntries.push({ binding: bufBinding++, resource: { buffer: b } });
        } else if (t === "f") {
          ubF[scalarIdx++] = new Float32Array(new Int32Array([lo]).buffer)[0];
        } else {
          ubI[scalarIdx++] = lo;
        }
      }
      const uni = device.createBuffer({ size: ub.byteLength, usage: UN });
      device.queue.writeBuffer(uni, 0, ub);
      storageEntries.push({ binding: bufBinding, resource: { buffer: uni } });
      const bg = device.createBindGroup({ layout: entry.pipe.getBindGroupLayout(0), entries: storageEntries });
      const enc = device.createCommandEncoder();
      const pass = enc.beginComputePass();
      pass.setPipeline(entry.pipe); pass.setBindGroup(0, bg);
      const groups = Math.ceil(Number(total) / 64);
      const gx = Math.min(groups, 65535), gy = Math.ceil(groups / 65535);
      pass.dispatchWorkgroups(gx, gy); pass.end();
      device.queue.submit([enc.finish()]);
      return 0n;
    },
    // async readback → asyncify unwind/rewind
    wgpu_download: (hostPtr, id, bytes) => {
      if (asy.rewinding) { asy.rewinding = false; exp.asyncify_stop_rewind(); return 0n; }
      initStack();
      const b = buffers.get(Number(id)); if (!b) return -1n;
      const n = Number(bytes), hp = Number(hostPtr);
      const rb = device.createBuffer({ size: n, usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ });
      const enc = device.createCommandEncoder();
      enc.copyBufferToBuffer(b, 0, rb, 0, n);
      device.queue.submit([enc.finish()]);
      asy.pendingWrite = rb.mapAsync(GPUMapMode.READ).then(() => {
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

  return {
    ok,
    adapterInfo: adapter ? (adapter.info || {}) : {},
    imports,
    bind(instance) { memory = instance.exports.memory; exp = instance.exports; },
    async runWithAsyncify(entry) {
      entry();
      while (asy.pendingWrite) {
        const p = asy.pendingWrite; asy.pendingWrite = null;
        await p;
        exp.asyncify_stop_unwind();
        asy.rewinding = true;
        exp.asyncify_start_rewind(stackBase);
        entry();
      }
    },
  };
}
