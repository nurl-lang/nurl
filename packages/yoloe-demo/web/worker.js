// worker.js — runs yoloe_detect.wasm (the pure-NURL onnx runtime compiled
// to wasm32-wasi, static kernels linked in) off the UI thread.
//
// Protocol with the main thread (one SharedArrayBuffer):
//   i32[0]  futex cell: 0 = idle, 1 = work ready (frame or prompt)
//   i32[1]  cmd for the module: 0 = frame, 2 = add prompt
//   i32[2]  conf ‰            i32[3]  masks 0/1
//   i32[4]  enabled-class bitmask
//   i32[5]  add-prompt slot index
//   f32[16..527]              add-prompt embedding (512 floats)
//   bytes[4096 ..]            frame in  (640*480*3 RGB)
//   bytes[4096+921600 ..]     frame out (masked RGB, written before result msg)
//
// postMessage out: {type:'status'|'result'|'error', ...}. The module's
// host_frame import BLOCKS on Atomics.wait — legal here, never on main.

import { makeWebGPUHost } from "./webgpu.js";

const W = 640, H = 480, FRAME = W * H * 3;
const CTL_I32 = 1024;            // 4096 bytes of control space
const IN_OFF = 4096, OUT_OFF = IN_OFF + FRAME;

let memory = null;
let sab = null, ctl = null, ctlF = null, sabBytes = null;
let blobs = {};                  // 0: model, 1: tpe
const mem = () => new Uint8Array(memory.buffer);

function wasiShim() {
  // The module uses a handful of WASI calls: stdout/stderr writes,
  // clocks, random, args/env, exit. Everything else returns ENOSYS (52)
  // or success-with-zeroes — enough for this compute-only module.
  const td = new TextDecoder();
  let lineBuf = '';
  const view = () => new DataView(memory.buffer);
  return {
    fd_write: (fd, iovs, iovsLen, nwritten) => {
      const v = view();
      let total = 0, out = '';
      for (let i = 0; i < iovsLen; i++) {
        const ptr = v.getUint32(iovs + i * 8, true);
        const len = v.getUint32(iovs + i * 8 + 4, true);
        out += td.decode(new Uint8Array(memory.buffer, ptr, len));
        total += len;
      }
      lineBuf += out;
      let nl;
      while ((nl = lineBuf.indexOf('\n')) >= 0) {
        postMessage({ type: 'log', fd, line: lineBuf.slice(0, nl) });
        lineBuf = lineBuf.slice(nl + 1);
      }
      v.setUint32(nwritten, total, true);
      return 0;
    },
    fd_read: () => 52,
    fd_seek: () => 52,
    fd_close: () => 0,
    fd_fdstat_get: (fd, buf) => { mem().fill(0, buf, buf + 24); return 0; },
    fd_fdstat_set_flags: () => 0,
    fd_prestat_get: () => 8 /* EBADF: no preopens */,
    fd_prestat_dir_name: () => 8,
    path_open: () => 52,
    path_filestat_get: () => 52,
    fd_filestat_get: () => 52,
    fd_readdir: () => 52,
    clock_time_get: (id, prec, out) => {
      const ns = BigInt(Math.round(performance.now() * 1e6));
      new DataView(memory.buffer).setBigUint64(out, ns, true);
      return 0;
    },
    clock_res_get: (id, out) => {
      new DataView(memory.buffer).setBigUint64(out, 1000n, true);
      return 0;
    },
    random_get: (ptr, len) => {
      const b = new Uint8Array(memory.buffer, ptr, len);
      // crypto.getRandomValues caps at 64 KiB per call
      for (let o = 0; o < len; o += 65536) {
        crypto.getRandomValues(b.subarray(o, Math.min(o + 65536, len)));
      }
      return 0;
    },
    args_sizes_get: (argc, argvBufSize) => {
      const v = view();
      v.setUint32(argc, 1, true);
      v.setUint32(argvBufSize, 6, true);
      return 0;
    },
    args_get: (argv, argvBuf) => {
      const v = view();
      v.setUint32(argv, argvBuf, true);
      mem().set(new TextEncoder().encode('yoloe\0'), argvBuf);
      return 0;
    },
    environ_sizes_get: (cnt, sz) => {
      const v = view();
      v.setUint32(cnt, 0, true);
      v.setUint32(sz, 0, true);
      return 0;
    },
    environ_get: () => 0,
    poll_oneoff: () => 52,
    sched_yield: () => 0,
    proc_exit: (code) => { throw { wasiExit: Number(code) }; },
  };
}

let gpuHost = null;      // WebGPU host (backend 3), created on init if requested
let useWebGPU = false;

const env = {
  host_use_webgpu: () => (useWebGPU && gpuHost && gpuHost.ok) ? 1n : 0n,
  host_blob_size: (kind) => BigInt(blobs[Number(kind)]?.length ?? 0),
  host_blob_read: (kind, dst) => {
    const b = blobs[Number(kind)];
    if (!b) return -1n;
    mem().set(b, Number(dst));
    return 0n;
  },
  host_frame: (rgbPtr, ctlPtr) => {
    // idle until the main thread posts work
    Atomics.store(ctl, 0, 0);
    postMessage({ type: 'idle' });
    Atomics.wait(ctl, 0, 0);
    const cmd = ctl[1];
    const wctl = new Int32Array(memory.buffer, Number(ctlPtr), 544);
    wctl[0] = ctl[2];   // conf ‰
    wctl[1] = ctl[3];   // masks
    wctl[2] = ctl[4];   // bitmask
    wctl[4] = ctl[5];   // prompt slot
    if (cmd === 2) {
      const src = new Float32Array(sab, 64, 512);   // f32[16..527]
      new Float32Array(memory.buffer, Number(ctlPtr) + 64, 512).set(src);
    } else if (cmd === 0) {
      mem().set(sabBytes.subarray(IN_OFF, IN_OFF + FRAME), Number(rgbPtr));
      env._rgbPtr = Number(rgbPtr);
    }
    return BigInt(cmd);
  },
  host_result: (detsPtr, nd, ms) => {
    const n = Number(nd);
    const dets = Array.from(new Float32Array(memory.buffer, Number(detsPtr), n * 6));
    sabBytes.set(mem().subarray(env._rgbPtr, env._rgbPtr + FRAME), OUT_OFF);
    postMessage({ type: 'result', n, dets, ms: Number(ms) });
  },
  host_status: (code, extra) => {
    postMessage({ type: 'status', code: Number(code), extra: Number(extra) });
  },
};

onmessage = async (e) => {
  const m = e.data;
  if (m.type !== 'init') return;
  try {
    sab = m.sab;
    ctl = new Int32Array(sab, 0, CTL_I32);
    sabBytes = new Uint8Array(sab);
    blobs[0] = new Uint8Array(m.model);
    blobs[1] = new Uint8Array(m.tpe);
    useWebGPU = m.engine === 'webgpu';
    gpuHost = await makeWebGPUHost();
    if (useWebGPU && !gpuHost.ok) throw new Error('WebGPU unavailable (no adapter)');
    Object.assign(env, gpuHost.imports);   // wgpu_* imports (stubbed when !ok)
    const module = await WebAssembly.compile(m.wasm);
    const wasi = wasiShim();
    for (const imp of WebAssembly.Module.imports(module)) {
      // dead code paths (cuda/nvrtc/dlopen/system, unused fs syscalls…) —
      // stub anything unknown: env stubs trap loudly if ever called,
      // wasi stubs return ENOSYS (52).
      if (imp.module === 'env' && !(imp.name in env)) {
        env[imp.name] = () => { throw new Error(`stub import called: ${imp.name}`); };
      }
      if (imp.module === 'wasi_snapshot_preview1' && !(imp.name in wasi)) {
        wasi[imp.name] = () => 52;
      }
    }
    const instance = await WebAssembly.instantiate(module, {
      wasi_snapshot_preview1: wasi,
      env,
    });
    memory = instance.exports.memory;
    gpuHost.bind(instance);
    postMessage({ type: 'ready', gpu: gpuHost.describe(), fallback: gpuHost.isFallback });
    try {
      // runWithAsyncify drives the WebGPU async readback (unwind/await/
      // rewind); for the static-CPU path nothing unwinds and it is just
      // one _start() call.
      await gpuHost.runWithAsyncify(() => instance.exports._start());
      postMessage({ type: 'exit', code: 0 });
    } catch (ex) {
      if (ex && typeof ex.wasiExit === 'number') {
        postMessage({ type: 'exit', code: ex.wasiExit });
      } else {
        throw ex;
      }
    }
  } catch (ex) {
    postMessage({ type: 'error', message: String(ex && ex.message || ex) });
  }
};
