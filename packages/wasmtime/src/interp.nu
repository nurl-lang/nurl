// packages/wasmtime/src/interp.nu — a small WebAssembly interpreter (pure NURL).
//
// Executes wasm: i32/i64/f32/f64 const, locals, globals, the integer and float
// arithmetic/comparison/bitwise ops, all int↔float conversions, structured
// control flow (block / loop / if / else / br / br_if / return), drop / select,
// direct and indirect calls, and linear memory load/store. Each value occupies
// one 64-bit cell; i32 wraps + sign-extends to 32 bits, and floats are held as
// their IEEE-754 bit pattern (reinterpreted via std/floatbits for arithmetic).
// Imports (the WASI surface) are the remaining milestone — so this runs
// self-contained compute modules today.
//
// Control flow uses an explicit control stack. Entering a block/if computes its
// matching `end` by a one-pass immediate-skipping scan; `br` to a loop re-enters
// at the loop start, to a block jumps past its `end`.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`
$ `module.nu`

// round-to-nearest-even (wasm f*.nearest) — libm rint honours the default mode.
& `m` @ rint f x → f

// OS entropy (runtime helper; getrandom/urandom under the hood).
& `c` @ nurl_rand_fill *u buf i n → i

// The one lock behind the 0xfe atomics (see __atom_init). Declared here
// rather than taken from std/thread.nu because the handles live in file
// globals, and a NURL global holds a pointer as an integer.
& `c` @ pthread_mutex_init *u m *u attr → i32

& `c` @ pthread_mutex_lock *u m → i32

& `c` @ pthread_mutex_unlock *u m → i32

& `c` @ pthread_cond_init *u c *u attr → i32

& `c` @ pthread_cond_wait *u c *u m → i32

& `c` @ pthread_cond_broadcast *u c → i32

// unlink(2): path_unlink_file must NOT remove directories (remove(3) would).
& `c` @ unlink s path → i32

// ── raw sockets, for the "nurl_net" host-import bridge ────────────
// The listen/accept/read/write/close/err_kind/peer_addr/set_timeout half
// of this ABI is preamble-declared by the compiler; the rest lives in
// stdlib FFI declares, so name it here the same way std/dns.nu and
// ext/http_pure.nu do.
& `c` @ nurl_tcp_connect s host i port → i

& `c` @ nurl_tcp_timeout_ms i handle → i

& `c` @ nurl_tcp_get_fd i handle → i

& `c` @ nurl_tcp_set_nonblock i handle i on → v

& `c` @ nurl_tcp_ref i handle → v

& `c` @ nurl_tcp_unref i handle → v

& `c` @ nurl_tcp_local_addr i handle → s

& `c` @ nurl_udp_bind s host i port → i

& `c` @ nurl_udp_connect i handle s host i port → i

& `c` @ nurl_udp_send i handle s buf i n → i

& `c` @ nurl_udp_recv i handle s buf i n → i

& `c` @ nurl_udp_send_to i handle s buf i n s host i port → i

& `c` @ nurl_udp_recv_from i handle s buf i n → i

& `c` @ nurl_udp_close i handle → v

& `c` @ nurl_udp_err_kind i handle → i

& `c` @ nurl_udp_peer_addr i handle → s

& `c` @ nurl_udp_local_addr i handle → s

& `c` @ nurl_udp_set_timeout i handle i ms → v

& `c` @ nurl_udp_set_nonblock i handle i on → v

& `c` @ nurl_udp_family i handle → i

& `c` @ nurl_udp_get_fd i handle → i

& `c` @ nurl_udp_set_broadcast i handle i on → i

& `c` @ nurl_udp_join_group i handle s group s iface → i

& `c` @ nurl_udp_leave_group i handle s group s iface → i

& `c` @ nurl_udp_set_multicast_ttl i handle i ttl → i

& `c` @ nurl_udp_set_multicast_loop i handle i on → i

& `c` @ nurl_dns_resolve s host → s

& `c` @ nurl_dns_resolve_port s host i port → s

& `c` @ nurl_dns_reverse s ip → s

// ── CUDA driver + NVRTC (the GPU host-import bridge) ──────────────
// A wasm module built from a GPU-using NURL package (packages/gpu →
// onnx → objdet) imports these under module "env"; wasmtime resolves them
// to the real libcuda/libnvrtc here, marshalling guest linear memory ↔
// host. nurl.sh auto-links libcuda/libnvrtc when these symbols appear, and
// links stub objects on a GPU-less host (so wasmtime always builds; the
// guest then just sees nonzero CUresult codes). Handle types match the
// portable i64 model in packages/gpu/src/cuda.nu.
& `cuda` @ cuInit i32 flags → i32

& `cuda` @ cuDeviceGetCount *u count → i32

& `cuda` @ cuDeviceGet *u device i32 ordinal → i32

& `cuda` @ cuDeviceGetName *u name i32 len i32 dev → i32

& `cuda` @ cuCtxCreate *u pctx i32 flags i32 dev → i32

& `cuda` @ cuCtxDestroy i ctx → i32

& `cuda` @ cuCtxSynchronize → i32

& `cuda` @ cuModuleLoadData *u module *u image → i32

& `cuda` @ cuModuleUnload i module → i32

& `cuda` @ cuModuleGetFunction *u hfunc i hmod s name → i32

& `cuda` @ cuMemAlloc *u dptr i bytesize → i32

& `cuda` @ cuMemFree i dptr → i32

& `cuda` @ cuMemcpyHtoD i dst *u src i n → i32

& `cuda` @ cuMemcpyDtoH *u dst i src i n → i32

& `cuda` @ cuLaunchKernel i f i32 gx i32 gy i32 gz i32 bx i32 by i32 bz i32 sh i stream *u params i extra → i32

& `nvrtc` @ nvrtcCreateProgram *u prog s src s name i32 nh *u headers *u incs → i32

& `nvrtc` @ nvrtcCompileProgram i prog i32 nopt *u opts → i32

& `nvrtc` @ nvrtcGetPTXSize i prog *u sz → i32

& `nvrtc` @ nvrtcGetPTX i prog *u ptx → i32

& `nvrtc` @ nvrtcGetProgramLogSize i prog *u sz → i32

& `nvrtc` @ nvrtcGetProgramLog i prog *u log → i32

& `nvrtc` @ nvrtcDestroyProgram *u prog → i32

// ── value + control stacks ───────────────────────────────────────

: Arg { ( Vec u ) bytes }

: Ctrl { i is_loop i start_pc i end_pc i height i arity }

// A WASI file descriptor. kind: 0 closed, 1 stdio, 2 preopened dir, 3 file,
// 4 opened (non-preopen) directory. For a file, `data` holds the contents,
// `pos` the read/write offset, `host` the on-disk path (for open/flush), and
// `name` (a dir) the guest-visible preopen name reported by fd_prestat_*.
// `append` = O_APPEND: every write lands at the end regardless of pos.
: WFd { i kind ( Vec u ) data i pos ( Vec u ) host ( Vec u ) name b writable b dirty b append }

: Interp {
    s mod  // *Module
    ( Vec i ) vs  // value stack
    ( Vec u ) mem  // linear memory (bytes)
    i mem_pages  // current size in 64 KiB pages
    // Bytes the guest may address = mem_pages * 64 KiB. Usually the whole
    // buffer, but a SHARED memory reserves its declared maximum up front —
    // growth must never move the buffer, because another thread is reading
    // it through the same pointer — so there the buffer is larger than
    // what the guest may touch, and every bounds check reads this instead
    // of the Vec's length.
    i mem_bytes
    ( Vec i ) globals  // mutable global values
    ( Vec i ) table  // runtime funcref table (mutable via table.set/grow/…)
    ( Vec i ) data_dropped  // 1 per data segment once dropped / active
    ( Vec i ) elem_dropped  // 1 per element segment once dropped / active
    ( Vec s ) argv  // *Arg — WASI program arguments (argv[0] = program)
    ( Vec s ) envp  // *Arg — WASI environment entries ("NAME=VALUE")
    ( Vec s ) fds  // *WFd — file-descriptor table (0/1/2 stdio, 3 preopen, …)
    // Why execution stopped, as one word so the driver's hot loop tests one
    // load instead of two byte fields: bit 0 = trapped, bit 1 = exited (via
    // proc_exit). `interp_trapped` / `interp_exited` are the readers; nothing
    // outside `__trap` and `__wasi_proc_exit` sets it.
    i halt
    i exit_code
    ( Vec u ) trapmsg
    i pending_call  // callee set by call/call_indirect for the driver (-1 none)
    i max_depth  // frame-stack depth limit (trap when exceeded)
    i fuel  // remaining budget in predecoded records (-1 = unlimited)
    b gpu_ok  // env/CUDA host imports enabled (opt-in; default off)
    b net_ok  // nurl_net host imports (real sockets) enabled (opt-in; default off)
    // Shared memory changes what a narrow store is allowed to touch: see
    // __mem_store. Cached here because every store reads it.
    b shared_mem
    // Guest socket handle → host handle. The guest never sees a host
    // pointer: it gets an index into this table, so a forged handle can
    // only miss, never become a host address the runtime dereferences.
    // Slot 0 is reserved — the stdlib reads handle 0 as "failed".
    ( Vec i ) nethandles
    ( Vec i ) netkinds  // 1 = TCP, 2 = UDP (which close the runtime owes it)
    b cap  // capture stdout/stderr into capout/caperr instead of the host streams
    ( Vec u ) capout  // captured module stdout (raw bytes, NULs preserved)
    ( Vec u ) caperr  // captured module stderr
    ( Vec s ) pfuncs  // *PFunc per defined function, predecoded lazily (#s 0 until first call)
    // Threads (wasi-threads). A spawned thread runs its OWN Interp — own
    // value stack, frames, globals and therefore its own `__stack_pointer`,
    // exactly as the proposal's "one instance per thread" says — over the
    // SHARED linear memory, table and module. `owner` points at the
    // instantiating Interp (0 in it), and the host-side tables that must
    // stay common (file descriptors, socket handles, captured output) are
    // reached through it; `__host` is that hop.
    s owner  // *Interp of the instantiating thread, 0 when this IS it
    i next_tid  // owner only: thread ids handed to wasi.thread-spawn
    ( Vec s ) thread_holders  // owner only: *TStart, keeping spawn closures alive
    ( Vec i ) thread_kids  // owner only: live child *Interp, for memory.grow
    ( Vec i ) thread_joins  // owner only: host Thread handles, joined before free
    i tstart_fidx  // cached export index of `wasi_thread_start` (-2 = not looked up)
    i sp_global  // cached global index of `__stack_pointer` (-2 = not looked up)
}

// One spawned thread's closure, heap-held so it outlives the host call
// that created it (thread_spawn borrows the closure and its captures).
: TStart { ( @ v ) f }

// One activation record on the explicit call stack: the function, its locals,
// its control stack, and the instruction cursor [pos, end) — pos/end are
// *record indices* into the function's predecoded instruction array, not byte
// positions; `pins` borrows the *PFunc owned by it.pfuncs.
: Frame { i fidx ( Vec i ) regs i pos i end i code_start s pins i ret_dst }

// A predecoded function body in REGISTER FORM. wasm validation guarantees a
// static stack height at every instruction, so the value at stack position h
// lives in slot (nlocals + h) of one flat per-frame array — locals first,
// stack after — and predecode resolves every operand to an absolute slot
// index. There is no value-stack traffic and no runtime control stack left:
// `local.get`/`set`/`tee` become register moves, `block`/`loop`/`end` emit
// nothing at all, and branches are direct jumps that carry (dst, src, n)
// result-move triples computed statically. Layout: 6 x i64 per record —
//   [0] micro-op   a dense internal opcode, NOT the wasm byte — see `__iop`
//   [1..4] A B C D operands: slot indices, jump targets (record indices),
//                  immediates, packed move triples. A load's D is its index
//                  slot — the address add folded into the access, or the
//                  pool's zero slot when there was none (`__fuse_addr`).
//   [5] BYTE       the instruction's byte offset in the module image, for
//                  trap backtraces — the one thing byte positions are
//                  still good for
// `aux` holds br_table rows, 4 words per label: target, dst, src, n.
// The 0xfc family is the one group still bridged through the old value
// stack: the record copies its operands from slots onto it.vs, runs the
// existing executor arm, and copies the result back — correctness
// identical, speed unchanged for them, and no duplicated semantics. Floats
// and the int/float conversions are register form like everything else.
// `nparams` / `nresults` are the callee's arity, copied out of the type
// section once at predecode time. Every call and every return needs them,
// and re-deriving them per call means walking funcs → typeidx → types and
// two `vec_len`s inside `module_func_type` — pure repeat work on a value
// that is fixed for the life of the module.
: PFunc { ( Vec i ) code ( Vec i ) aux i count i nlocals i nslots i nparams i nresults i code_start i sbase ( Vec i ) kv ( Vec s ) pool }

@ __page → i { ^ 65536 }

@ interp_new * Module m → *Interp {
    : *Interp it # *Interp ( nurl_alloc Z Interp )
    = . it mod # s m
    = . it pfuncs ( vec_new [s] )
    = . it vs ( vec_new [i] )
    // Linear memory is ONE zero-filled block of the declared minimum.
    // `vec_zeroed` hands the whole size to calloc, so the pages arrive
    // from the kernel already zero and stay untouched until the guest
    // writes them. The push-a-zero-per-byte loop this replaces ran
    // 16.8 million bounds-checked pushes for the 257-page minimum a
    // wasi command module declares — 78 % of the wall clock of a run
    // whose guest printed one line and exited.
    // A shared memory is allocated at its declared maximum immediately: the
    // threads proposal lets several threads hold the same buffer, so a
    // reallocating grow would pull it out from under them.
    : i __mpages ? == . m has_mem 1 . m mem_min 0
    : i __mreserve ? & == . m has_mem 1 != . m mem_shared 0 . m mem_max __mpages
    = . it mem ( vec_zeroed [u] * __mreserve ( __page ) )
    = . it mem_pages __mpages
    = . it mem_bytes * __mpages ( __page )
    = . it globals ( vec_new [i] )
    = . it argv ( vec_new [s] )
    = . it envp ( vec_new [s] )
    = . it fds ( vec_new [s] )
    // fds 0/1/2 = stdin/stdout/stderr (kind 1); higher slots filled by preopen.
    : ~ i sfd 0
    ~ < sfd 3 { ( vec_push [s] . it fds # s ( __mkfd 1 ) ) = sfd + sfd 1 }
    = . it halt 0
    = . it exit_code 0
    = . it trapmsg ( vec_new [u] )
    = . it pending_call -1
    = . it max_depth 65536
    = . it fuel -1
    = . it gpu_ok F
    = . it net_ok F
    = . it shared_mem ? & == . m has_mem 1 != . m mem_shared 0 T F
    = . it nethandles ( vec_new [i] )
    = . it netkinds ( vec_new [i] )
    ( vec_push [i] . it nethandles 0 )
    ( vec_push [i] . it netkinds 0 )
    = . it cap F
    = . it capout ( vec_new [u] )
    = . it caperr ( vec_new [u] )
    = . it owner # s 0
    = . it next_tid 1
    = . it thread_holders ( vec_new [s] )
    = . it thread_kids ( vec_new [i] )
    = . it thread_joins ( vec_new [i] )
    = . it tstart_fidx -2
    = . it sp_global -2
    // copy global initial values
    : i ng ( vec_len [i] . m global_init )
    : ~ i gi 0
    ~ < gi ng { ( vec_push [i] . it globals ?? ( vec_get [i] . m global_init gi ) { T x → x F → 0 } ) = gi + gi 1 }
    // runtime table = the decoded initial image (mutable from here on)
    = . it table ( vec_new [i] )
    : i tn ( vec_len [i] . m table )
    : ~ i ti 0
    ~ < ti tn { ( vec_push [i] . it table ?? ( vec_get [i] . m table ti ) { T x → x F → -1 } ) = ti + ti 1 }
    // segment drop state: active segments count as dropped once instantiated
    = . it data_dropped ( vec_new [i] )
    = . it elem_dropped ( vec_new [i] )
    : i ndd ( vec_len [s] . m datas )
    : ~ i dd 0
    ~ < dd ndd {
        : s dpp ?? ( vec_get [s] . m datas dd ) { T x → x F → # s 0 }
        : ~ i drp 1
        ? != # i dpp 0 { : *DataSeg dsg # *DataSeg dpp ? == . dsg passive 1 { = drp 0 } {} } {}
        ( vec_push [i] . it data_dropped drp )
        = dd + dd 1
    }
    : i ned ( vec_len [s] . m elems )
    : ~ i ee 0
    ~ < ee ned {
        : s epp ?? ( vec_get [s] . m elems ee ) { T x → x F → # s 0 }
        : ~ i drp 1
        ? != # i epp 0 { : *ElemSeg esg # *ElemSeg epp ? == . esg passive 1 { = drp 0 } {} } {}
        ( vec_push [i] . it elem_dropped drp )
        = ee + ee 1
    }
    ? == . m has_mem 1 {
        // Copy active data segments into memory: one memcpy per segment.
        // Per byte this used to cost a bounds check, an Option unwrap and
        // a bounds-checked store, and a module carries as much data as it
        // has initialised globals — nurlc.wasm ships 110 KB of it.
        //
        // A segment that does not fit is an instantiation error, as the
        // spec says and as the reference runtime reports it. The loop
        // this replaces silently dropped the overhanging bytes, and for a
        // negative offset it wrote the segment's tail at the wrong
        // address instead of rejecting the module.
        : i cap . it mem_bytes
        : i nd ( vec_len [s] . m datas )
        : ~ i di 0
        ~ < di nd {
            : s dp ?? ( vec_get [s] . m datas di ) { T x → x F → # s 0 }
            ? & != # i dp 0 == . # *DataSeg dp passive 0 {  // passive: memory.init only
                : *DataSeg ds # *DataSeg dp
                : i dn ( vec_len [u] . ds bytes )
                : i off . ds offset
                // `off > cap - dn` rather than `off + dn > cap`: the offset
                // is a number the module chose, and the sum can wrap.
                ? | < off 0 > off - cap dn {
                    ( __trap it `data segment does not fit in linear memory` )
                } {
                    ? > dn 0 {
                        : s dst # s + # i ( vec_data [u] . it mem ) off
                        ( nurl_memcpy dst # s ( vec_data [u] . ds bytes ) dn )
                    } {}
                }
            } {}
            = di + di 1
        }
    } {}
    ^ it
}

// Allocate a fresh file-descriptor record of the given kind.
@ __mkfd i kind → s {
    : *WFd f # *WFd ( nurl_alloc Z WFd )
    = . f kind kind
    = . f data ( vec_new [u] )
    = . f pos 0
    = . f host ( vec_new [u] )
    = . f name ( vec_new [u] )
    = . f writable F
    = . f dirty F
    = . f append F
    ^ # s f
}

@ __freefd s pp → v {
    ? == # i pp 0 { ^ v } {}
    : *WFd f # *WFd pp
    ( vec_free [u] . f data ) ( vec_free [u] . f host ) ( vec_free [u] . f name )
    ( nurl_free # s f )
}

@ interp_free * Interp it → v {
    // A spawned thread owns only what interp_thread_new made for it: the
    // memory, table, argv/envp and every host table belong to the Interp
    // that instantiated, and are freed exactly once, there.
    ? != # i . it owner 0 {
        ( __thread_unregister it )
        ( vec_free [i] . it vs )
        ( vec_free [i] . it thread_kids )
        ( vec_free [i] . it thread_joins )
        ( vec_free [i] . it globals )
        ( vec_free [i] . it nethandles )
        ( vec_free [i] . it netkinds )
        ( vec_free [s] . it fds )
        ( vec_free [s] . it thread_holders )
        ( vec_free [u] . it trapmsg )
        ( vec_free [u] . it capout )
        ( vec_free [u] . it caperr )
        : i tpn ( vec_len [s] . it pfuncs )
        : ~ i tpi 0
        ~ < tpi tpn { ?? ( vec_get [s] . it pfuncs tpi ) { T pp → ( __pf_free pp ) F → {} } = tpi + tpi 1 }
        ( vec_free [s] . it pfuncs )
        ( nurl_free # s it )
        ^ v
    } {}
    // Wait for the threads before dropping what they run on. The guest's
    // own join only proves the thread's BODY finished; the host thread is
    // still inside the interpreter for a moment after that, and it reads
    // this Interp's memory and table.
    : i tjn ( vec_len [i] . it thread_joins )
    : ~ i tji 0
    ~ < tji tjn {
        : i raw ?? ( vec_get [i] . it thread_joins tji ) { T x → x F → 0 }
        ? != raw 0 { ( thread_join @ Thread { # s raw } ) } {}
        = tji + tji 1
    }
    ( vec_free [i] . it thread_joins )
    ( interp_net_close_all it )
    ( vec_free [i] . it nethandles )
    ( vec_free [i] . it netkinds )
    : i thn ( vec_len [s] . it thread_holders )
    : ~ i thi 0
    ~ < thi thn { ?? ( vec_get [s] . it thread_holders thi ) { T pp → ? != # i pp 0 { ( nurl_free pp ) } {} F → {} } = thi + thi 1 }
    ( vec_free [s] . it thread_holders )
    ( vec_free [i] . it thread_kids )
    ( vec_free [i] . it vs )
    ( vec_free [u] . it mem )
    ( vec_free [i] . it globals )
    ( vec_free [i] . it table )
    ( vec_free [i] . it data_dropped )
    ( vec_free [i] . it elem_dropped )
    : i an ( vec_len [s] . it argv )
    : ~ i ai 0
    ~ < ai an { ?? ( vec_get [s] . it argv ai ) { T pp → ? != # i pp 0 { : *Arg a # *Arg pp ( vec_free [u] . a bytes ) ( nurl_free # s a ) } {} F → {} } = ai + ai 1 }
    ( vec_free [s] . it argv )
    : i en ( vec_len [s] . it envp )
    : ~ i ei 0
    ~ < ei en { ?? ( vec_get [s] . it envp ei ) { T pp → ? != # i pp 0 { : *Arg a # *Arg pp ( vec_free [u] . a bytes ) ( nurl_free # s a ) } {} F → {} } = ei + ei 1 }
    ( vec_free [s] . it envp )
    : i fn ( vec_len [s] . it fds )
    : ~ i fi 0
    ~ < fi fn { ?? ( vec_get [s] . it fds fi ) { T pp → ( __freefd pp ) F → {} } = fi + fi 1 }
    ( vec_free [s] . it fds )
    ( vec_free [u] . it trapmsg )
    ( vec_free [u] . it capout )
    ( vec_free [u] . it caperr )
    : i pn ( vec_len [s] . it pfuncs )
    : ~ i pi 0
    ~ < pi pn { ?? ( vec_get [s] . it pfuncs pi ) { T pp → ( __pf_free pp ) F → {} } = pi + pi 1 }
    ( vec_free [s] . it pfuncs )
    ( nurl_free # s it )
}

// Capture the module's stdout/stderr into buffers instead of writing
// them to the host's own streams. This is the embedder's switch: a
// host program that runs a module as a function call wants the
// module's output back as a VALUE, not interleaved into its own
// console. Enable before exec_func; read the buffers after it.
@ interp_capture * Interp it → v { = . it cap T }

// The captured bytes — BORROWED views into the Interp (valid until
// interp_free; do not free). Raw bytes, exactly as the module wrote
// them: a NUL neither truncates nor terminates.
@ interp_stdout_bytes * Interp it → ( Vec u ) { ^ . it capout }

@ interp_stderr_bytes * Interp it → ( Vec u ) { ^ . it caperr }

// Did the guest trap? Did it call proc_exit? The two halves of `halt`.
// Both can be set: a trap while unwinding an exiting module leaves the
// trap visible, which is what an embedder wants to report.
@ interp_trapped * Interp it → b { ^ != 0 & . it halt 1 }

@ interp_exited * Interp it → b { ^ != 0 & . it halt 2 }

// Append a program argument (copied from a NUL-terminated host string).
@ interp_push_arg * Interp it s str → v {
    : *Arg a # *Arg ( nurl_alloc Z Arg )
    = . a bytes ( bytes_from_str str )
    ( vec_push [s] . it argv # s a )
}

// Append an environment entry ("NAME=VALUE", copied).
@ interp_push_env * Interp it s str → v {
    : *Arg a # *Arg ( nurl_alloc Z Arg )
    = . a bytes ( bytes_from_str str )
    ( vec_push [s] . it envp # s a )
}

// Enable the module "env" GPU/CUDA host-import bridge. Off by default: those
// imports hand the guest raw host pointers into linear memory and forward them
// to libcuda, so they are only safe for trusted compute — the embedder must
// opt in explicitly (the CLI does so with --allow-gpu).
@ interp_allow_gpu * Interp it → v { = . it gpu_ok T }

// Enable the module "nurl_net" socket bridge — the guest's TCP/UDP/DNS
// calls become this process's. Off by default for the same reason the
// GPU bridge is: it is the guest reaching the network through us (the
// CLI opts in with --allow-net).
@ interp_allow_net * Interp it → v { = . it net_ok T }

// Grant the module one preopened host directory, visible to it as `guest_name`
// (the path it resolves opens against). Installed as fd 3.
@ interp_set_preopen * Interp it s host_path s guest_name → v {
    : *WFd f # *WFd ( __mkfd 2 )
    ( vec_free [u] . f host ) = . f host ( bytes_from_str host_path )
    ( vec_free [u] . f name ) = . f name ( bytes_from_str guest_name )
    ( vec_push [s] . ( __host it ) fds # s f )
}

// Run the module's start-section function, if any — the final instantiation
// step, before any export is invoked.
// The Interp that owns the shared host state — this one, or the thread
// that instantiated it. File descriptors, socket handles and captured
// output are per-INSTANCE in wasm terms but per-PROCESS in the guest's:
// a file opened by one thread has to be the same fd in another.
@ __host * Interp it → *Interp {
    ? == # i . it owner 0 { ^ it } {}
    ^ # *Interp . it owner
}

// A fresh Interp for a spawned thread: its own stacks and globals over
// the owner's memory, table and module. The shared Vecs are copied by
// HANDLE — safe because a threaded module's memory is allocated at its
// maximum up front and never moves — and `interp_free` on a thread
// releases only what the thread itself owns.
@ interp_thread_new * Interp parent → *Interp {
    : *Interp ho ( __host parent )
    : *Module m # *Module . ho mod
    : *Interp it # *Interp ( nurl_alloc Z Interp )
    = . it mod . ho mod
    = . it vs ( vec_new [i] )
    = . it mem . ho mem
    = . it mem_pages . ho mem_pages
    = . it mem_bytes . ho mem_bytes
    = . it table . ho table
    = . it data_dropped . ho data_dropped
    = . it elem_dropped . ho elem_dropped
    = . it argv . ho argv
    = . it envp . ho envp
    = . it fds ( vec_new [s] )  // unused in a thread: __host redirects
    = . it halt 0
    = . it exit_code 0
    = . it trapmsg ( vec_new [u] )
    = . it pending_call -1
    = . it max_depth . ho max_depth
    = . it fuel -1
    = . it gpu_ok . ho gpu_ok
    = . it net_ok . ho net_ok
    = . it shared_mem . ho shared_mem
    = . it nethandles ( vec_new [i] )
    = . it netkinds ( vec_new [i] )
    = . it cap . ho cap
    = . it capout ( vec_new [u] )
    = . it caperr ( vec_new [u] )
    = . it owner # s ho
    = . it next_tid 0
    = . it thread_holders ( vec_new [s] )
    = . it thread_kids ( vec_new [i] )
    = . it thread_joins ( vec_new [i] )
    = . it tstart_fidx -2
    = . it sp_global -2
    // Mutable globals are per-instance, which is precisely what gives the
    // thread its own __stack_pointer. They start from the module's
    // initialisers, as a fresh instantiation would.
    = . it globals ( vec_new [i] )
    : i ng ( vec_len [i] . m global_init )
    : ~ i gi 0
    ~ < gi ng { ( vec_push [i] . it globals ?? ( vec_get [i] . m global_init gi ) { T x → x F → 0 } ) = gi + gi 1 }
    // Predecoded bodies are per-Interp (the cache is filled lazily and
    // mutated in place), so a thread decodes what it actually runs.
    = . it pfuncs ( vec_new [s] )
    : i nf ( vec_len [s] . m funcs )
    : ~ i fi 0
    ~ < fi nf { ( vec_push [s] . it pfuncs # s 0 ) = fi + fi 1 }
    // How much memory is addressable is per-Interp (the bounds check is on
    // the hot path and must stay one field read), so a growing thread has
    // to publish the new bound to its siblings. Joining the group and
    // growing both happen under the atomics lock, so a thread can never
    // start life with a bound that was already raised.
    ( __atom_lock )
    = . it mem_pages . ho mem_pages
    = . it mem_bytes . ho mem_bytes
    ( vec_push [i] . ho thread_kids # i it )
    ( __atom_unlock )
    ^ it
}

// Publish a new memory size to every Interp in the group. Called with the
// atomics lock held.
@ __mem_publish * Interp ho i pages i bytes → v {
    = . ho mem_pages pages
    = . ho mem_bytes bytes
    : i n ( vec_len [i] . ho thread_kids )
    : ~ i k 0
    ~ < k n {
        : i kp ?? ( vec_get [i] . ho thread_kids k ) { T x → x F → 0 }
        ? != kp 0 {
            : *Interp kid # *Interp # s kp
            = . kid mem_pages pages
            = . kid mem_bytes bytes
        } {}
        = k + k 1
    }
}

// Leave the group (the thread is done with its Interp).
@ __thread_unregister * Interp it → v {
    ? == # i . it owner 0 { ^ v } {}
    : *Interp ho ( __host it )
    ( __atom_lock )
    : i n ( vec_len [i] . ho thread_kids )
    : ~ i k 0
    ~ < k n {
        ? == ?? ( vec_get [i] . ho thread_kids k ) { T x → x F → 0 } # i it { ( vec_set [i] . ho thread_kids k 0 ) } {}
        = k + k 1
    }
    ( __atom_unlock )
}

@ interp_run_start * Interp it → v {
    : *Module m # *Module . it mod
    ? >= . m start_func 0 { ( exec_func it . m start_func ) } {}
}

@ __push * Interp it i v → v { ( vec_push [i] . it vs v ) }

@ __pop * Interp it → i {
    : i n ( vec_len [i] . it vs )
    ? <= n 0 { ( __trap it `value stack underflow` ) ^ 0 } {}
    : i v ?? ( vec_get [i] . it vs - n 1 ) { T x → x F → 0 }
    ( vec_pop [i] . it vs )
    ^ v
}

@ __vsh * Interp it → i { ^ ( vec_len [i] . it vs ) }

// Truncate the value stack back to height h.
@ __vtrunc * Interp it i h → v {
    ~ > ( vec_len [i] . it vs ) h { ( vec_pop [i] . it vs ) }
}

// Sign-extend the low 32 bits (i32 value semantics in a 64-bit cell).
@ __w32 i v → i { : i lo & v 4294967295 ^ ? != 0 & lo 2147483648 | lo -4294967296 lo }

// Read n little-endian bytes from the cursor into an i (zero-extended).
@ __read_le * Wc c i n → i {
    : ~ i bits 0
    : ~ i k 0
    ~ < k n { = bits | bits << ( wc_u8 c ) * 8 k = k + k 1 }
    ^ bits
}

// ── immediate skipping (for matching `end`) ──────────────────────
// Advance `c` past the immediates of the instruction whose opcode is `op`.

@ __skip_imm * Wc c i op → v {
    // block / loop / if : block type = signed LEB (s33: void / valtype / type index)
    ? | == op 2 | == op 3 == op 4 { ( wc_sleb c ) ^ v } {}
    // br / br_if / call / local.* / global.* / table.get/set / ref.func : one uleb
    ? | == op 12 | == op 13 | == op 16 | == op 32 | == op 33 | == op 34 | == op 35 | == op 36 | == op 37 | == op 38 == op 210 { ( wc_uleb c ) ^ v } {}
    // call_indirect : two ulebs
    ? == op 17 { ( wc_uleb c ) ( wc_uleb c ) ^ v } {}
    // select t : valtype vec ; ref.null : heap type byte
    ? == op 28 { : i tc ( wc_uleb c ) ( wc_skip c tc ) ^ v } {}
    ? == op 208 { ( wc_u8 c ) ^ v } {}
    // br_table : vec of ulebs + default
    ? == op 14 { : i n ( wc_uleb c ) : ~ i k 0 ~ <= k n { ( wc_uleb c ) = k + k 1 } ^ v } {}
    // i32.const / i64.const : one sleb
    ? | == op 65 == op 66 { ( wc_sleb c ) ^ v } {}
    // f32.const : 4 bytes ; f64.const : 8 bytes
    ? == op 67 { ( wc_skip c 4 ) ^ v } {}
    ? == op 68 { ( wc_skip c 8 ) ^ v } {}
    // memory load/store (0x28..0x3e) : align + offset ulebs
    ? & >= op 40 <= op 62 { ( wc_uleb c ) ( wc_uleb c ) ^ v } {}
    // memory.size / memory.grow : 1 reserved byte
    ? | == op 63 == op 64 { ( wc_u8 c ) ^ v } {}
    // 0xfc prefix (bulk memory / table ops / saturating trunc)
    ? == op 252 {
        : i sub ( wc_uleb c )
        ? == sub 8 { ( wc_uleb c ) ( wc_u8 c ) } {  // memory.init: dataidx + memidx
            ? == sub 9 { ( wc_uleb c ) } {  // data.drop
                ? == sub 10 { ( wc_u8 c ) ( wc_u8 c ) } {  // memory.copy: 2 memidx
                    ? == sub 11 { ( wc_u8 c ) } {  // memory.fill: 1 memidx
                        ? == sub 12 { ( wc_uleb c ) ( wc_uleb c ) } {  // table.init: elemidx + tableidx
                            ? == sub 13 { ( wc_uleb c ) } {  // elem.drop
                                ? == sub 14 { ( wc_uleb c ) ( wc_uleb c ) } {  // table.copy: 2 tableidx
                                    ? | == sub 15 | == sub 16 == sub 17 { ( wc_uleb c ) } {} } } } } } } }  // table.grow/size/fill
        ^ v
    } {}
    // 0xfd prefix (SIMD / v128). These are unsupported at execution, but their
    // immediates must still be skipped correctly here so block/`end`/`else`
    // scanning is not thrown off by a 0x0b/0x05 byte living inside them.
    ? == op 253 {
        : i sub ( wc_uleb c )
        ? | == sub 12 == sub 13 { ( wc_skip c 16 ) } {  // v128.const / i8x16.shuffle
            ? & >= sub 84 <= sub 91 { ( wc_uleb c ) ( wc_uleb c ) ( wc_u8 c ) } {  // load/store lane: memarg + lane
                ? | & >= sub 0 <= sub 11 | == sub 92 == sub 93 { ( wc_uleb c ) ( wc_uleb c ) } {  // memory ops: memarg
                    ? & >= sub 21 <= sub 34 { ( wc_u8 c ) } {} } } }  // extract/replace lane: 1 byte
        ^ v
    } {}
    // 0xfe prefix (threads / atomics). atomic.fence carries a single reserved
    // byte; every other atomic op carries a memarg (two ulebs).
    ? == op 254 {
        : i sub ( wc_uleb c )
        ? == sub 3 { ( wc_u8 c ) } { ( wc_uleb c ) ( wc_uleb c ) }
        ^ v
    } {}
    // sign-extension ops (0xc0..0xc4): no immediates (fall through)
    // everything else: no immediates
}

// Block types are a signed LEB (s33): -64 (0x40) = void, other negatives are a
// single valtype, non-negative = an index into the type section (multi-value).

// Parameter count of a block type.
@ __bt_params * Module m i bt → i {
    ? < bt 0 { ^ 0 } {}
    : s tp ?? ( vec_get [s] . m types bt ) { T x → x F → # s 0 }
    ? == # i tp 0 { ^ 0 } {}
    : *FuncType ft # *FuncType tp
    ^ ( vec_len [i] . ft params )
}

// Result count of a block type.
@ __bt_results * Module m i bt → i {
    ? == bt -64 { ^ 0 } {}
    ? < bt 0 { ^ 1 } {}
    : s tp ?? ( vec_get [s] . m types bt ) { T x → x F → # s 0 }
    ? == # i tp 0 { ^ 0 } {}
    : *FuncType ft # *FuncType tp
    ^ ( vec_len [i] . ft results )
}

// ── arithmetic helpers ───────────────────────────────────────────

// Set the trap flag with a message (the uniform way every trap is raised).
@ __trap * Interp it s msg → v {
    = . it halt | . it halt 1
    ( vec_free [u] . it trapmsg )
    = . it trapmsg ( bytes_from_str msg )
}

// wasm div/rem semantics: divide-by-zero traps; signed div overflow
// (minv / −1, where minv = INT32_MIN or INT64_MIN) traps; signed rem by −1 is
// defined as 0 (also dodging the host SIGFPE on INT_MIN % −1).
@ __div_s * Interp it i a i b i minv → i {
    ? == b 0 { ( __trap it `integer divide by zero` ) ^ 0 } {}
    ? & == a minv == b -1 { ( __trap it `integer overflow` ) ^ 0 } {}
    ^ / a b
}

@ __rem_s * Interp it i a i b → i {
    ? == b 0 { ( __trap it `integer divide by zero` ) ^ 0 } {}
    ? == b -1 { ^ 0 } {}
    ^ % a b
}

// Unsigned variants over already-nonnegative operands (u32 zero-extended).
@ __div_u * Interp it i a i b → i {
    ? == b 0 { ( __trap it `integer divide by zero` ) ^ 0 } {}
    ^ / a b
}

@ __rem_u * Interp it i a i b → i {
    ? == b 0 { ( __trap it `integer divide by zero` ) ^ 0 } {}
    ^ % a b
}

// ── unsigned helpers (NURL's `/ % >> < …` are signed; wasm needs unsigned) ──

// Low 32 bits as a non-negative i64.
@ __u32 i x → i { ^ & x 4294967295 }

// Logical (zero-filling) right shift of a full 64-bit value by n (0..63).
@ __lshr64 i a i n → i { ^ ? == n 0 a & >> a n - << 1 - 64 n 1 }

// Unsigned 64-bit less-than (flip sign bits → signed order matches unsigned).
@ __ultb i a i b → b { ^ < ^^ a << 1 63 ^^ b << 1 63 }

// Unsigned 64-bit division / remainder by bitwise long division.
@ __udiv64 i a i b → i {
    ? == b 0 { ^ 0 } {}
    : ~ i q 0
    : ~ i r 0
    : ~ i k 63
    ~ >= k 0 { = r | << r 1 & ( __lshr64 a k ) 1 ? ! ( __ultb r b ) { = r - r b = q | q << 1 k } {} = k - k 1 }
    ^ q
}

@ __urem64 i a i b → i {
    ? == b 0 { ^ 0 } {}
    : ~ i r 0
    : ~ i k 63
    ~ >= k 0 { = r | << r 1 & ( __lshr64 a k ) 1 ? ! ( __ultb r b ) { = r - r b } {} = k - k 1 }
    ^ r
}

// Rotates (n masked to the type width by the caller).
@ __rotl32 i a i n → i { : i s & n 31 ^ ? == s 0 ( __w32 a ) ( __w32 | << ( __u32 a ) s >> ( __u32 a ) - 32 s ) }

@ __rotr32 i a i n → i { ^ ( __rotl32 a - 32 & n 31 ) }

@ __rotl64 i a i n → i { : i s & n 63 ^ ? == s 0 a | << a s ( __lshr64 a - 64 s ) }

@ __rotr64 i a i n → i { ^ ( __rotl64 a - 64 & n 63 ) }

// Count leading / trailing zeros and population count.
@ __clz32 i x → i { : i v ( __u32 x ) ? == v 0 { ^ 32 } {} : ~ i n 0 : ~ i k 31 ~ & >= k 0 == 0 & >> v k 1 { = n + n 1 = k - k 1 } ^ n }

@ __ctz32 i x → i { : i v ( __u32 x ) ? == v 0 { ^ 32 } {} : ~ i n 0 : ~ i k 0 ~ & < k 32 == 0 & >> v k 1 { = n + n 1 = k + k 1 } ^ n }

@ __popc32 i x → i { : i v ( __u32 x ) : ~ i n 0 : ~ i k 0 ~ < k 32 { = n + n & >> v k 1 = k + k 1 } ^ n }

@ __clz64 i x → i { ? == x 0 { ^ 64 } {} : ~ i n 0 : ~ i k 63 ~ & >= k 0 == 0 & ( __lshr64 x k ) 1 { = n + n 1 = k - k 1 } ^ n }

@ __ctz64 i x → i { ? == x 0 { ^ 64 } {} : ~ i n 0 : ~ i k 0 ~ & < k 64 == 0 & ( __lshr64 x k ) 1 { = n + n 1 = k + k 1 } ^ n }

@ __popc64 i x → i { : ~ i n 0 : ~ i k 0 ~ < k 64 { = n + n & ( __lshr64 x k ) 1 = k + k 1 } ^ n }

// ── float↔int conversion helpers ─────────────────────────────────
// NaN tests on the IEEE-754 bit patterns. (NURL's float `!=` lowers to
// `fcmp one` — ordered — so the x≠x trick cannot see NaN; inspect bits.)
@ __f64_nan i bits → b { ^ > & bits 9223372036854775807 9218868437227405312 }

@ __f32_nan i bits → b { ^ > & bits 2147483647 2139095040 }

// 2^63 and 2^64 as f64 (too big for a float literal's integer part).
@ __f_2p63 → f { ^ ( bits_to_f64 4890909195324358656 ) }

@ __f_2p64 → f { ^ ( bits_to_f64 4895412794951729152 ) }

// Trapping float→int truncation core (wasm's two distinct traps): NaN →
// `invalid conversion to integer`; trunc(x) outside [lo, hi) → `integer
// overflow`. Returns the integral value as f64.
@ __trunc_ck * Interp it b isnan f x f lo f hi → f {
    ? isnan { ( __trap it `invalid conversion to integer` ) ^ 0.0 } {}
    : f t ( trunc x )
    ? ! & >= t lo < t hi { ( __trap it `integer overflow` ) ^ 0.0 } {}
    ^ t
}

// Saturating counterpart (0xfc 0..7): NaN → 0, below lo → imin, at/above hi →
// imax, else the truncated value. (Targets whose values fit an i64 cell.)
@ __trunc_sat b isnan f x f lo f hi i imin i imax → i {
    ? isnan { ^ 0 } {}
    : f t ( trunc x )
    ? < t lo { ^ imin } {}
    ? >= t hi { ^ imax } {}
    ^ # i t
}

// An integral f64 in [0, 2^64) → its u64 bit pattern in the i64 cell (values
// ≥ 2^63 wrap into the negative half; NURL integer add wraps).
@ __f_to_u64 f t → i {
    ? >= t ( __f_2p63 ) { ^ + # i - t ( __f_2p63 ) -9223372036854775808 } {}
    ^ # i t
}

// Saturating trunc to u64 (needs __f_to_u64 for the in-range conversion).
@ __trunc_sat_u64 b isnan f x → i {
    ? isnan { ^ 0 } {}
    : f t ( trunc x )
    ? < t 0.0 { ^ 0 } {}
    ? >= t ( __f_2p64 ) { ^ -1 } {}
    ^ ( __f_to_u64 t )
}

// ── linear memory ────────────────────────────────────────────────
// The byte-crossing paths of a load and a store: an access whose n bytes
// straddle two 8-byte words. Every naturally-aligned access — which is what
// a wasm compiler emits — takes the single-word path in the two callers and
// never comes here, so these stay out of line. Inlined, they put a loop
// neither ever enters inside all twenty-odd access arms of the driver, and
// the driver is instruction-cache bound: hoisting them out was 1.9 % of the
// whole corpus with the instruction count unchanged to the digit.
@ __mem_load_split s base i ea i n → i {
    : ~ i v 0
    : ~ i k 0
    ~ < k n {
        : i off + ea k
        : i w ( nurl_peek base >> off 3 )
        = v | v << & ( __lshr64 w * & off 7 8 ) 255 * 8 k
        = k + k 1
    }
    ^ v
}

@ __mem_store_split s base i ea i n i val → v {
    : ~ i k 0
    ~ < k n {
        : i off + ea k
        : i wi >> off 3
        : i sh * & off 7 8
        : i w ( nurl_peek base wi )
        : i cleared & w ^^ << 255 sh -1
        ( nurl_poke base wi | cleared << & ( __lshr64 val * 8 k ) 255 sh )
        = k + k 1
    }
}

// Read n bytes little-endian from mem[ea]; sign-extend when `signed` and n<8.
// One bounds check up front, then raw word access on the linear-memory
// buffer. The old body did a bounds-checked vec_get + Option unwrap PER
// BYTE — an i64.load was eight of each. Aligned 8- and 4-byte accesses are
// a single machine load; a straddling one goes out of line.
// The base pointer is re-fetched from the Vec every call (one dereference)
// so memory.grow can never leave a stale pointer behind.
//
// `ea` is the sum of an operand slot masked to u32 and a memarg offset the
// predecoder masked to u32, so it cannot wrap negative past the check.
//
// `inline` (grammar v2.7): every driver arm calls this with `n` and
// `signed` as literals, so an inlined copy folds to a bounds check, one
// load and a shift — but LLVM scores the callee's whole body, sees the
// sign-extension it will never reach from that site, and declines. Forcing
// it was 9.5 % off the benchmark corpus, 24 % off nbody and matmul, 19 %
// off sieve.
inline @ __mem_load * Interp it i ea i n i signed → i {
    ? | < ea 0 > + ea n . it mem_bytes {
        ( __trap_oob it `memory load out of bounds` ea n )
        ^ 0
    } {}
    // The memory Vec is always a whole number of 64 KiB pages, so any
    // in-bounds byte's containing 8-byte word is in-bounds too — word reads
    // below can never run past the buffer.
    : s base # s ( vec_data [u] . it mem )
    : i lo & ea 7
    : ~ i v 0
    ? <= + lo n 8 {
        // the access sits inside one word — every naturally-aligned load
        // (i64 at 8, i32 at 0/4, halves and bytes anywhere) lands here
        : i w ( nurl_peek base >> ea 3 )
        : i mask ? == n 8 -1 - << 1 * 8 n 1
        = v & ( __lshr64 w * lo 8 ) mask
    } { = v ( __mem_load_split base ea n ) }
    ? & == signed 1 < n 8 {
        : i bits * 8 n
        ? != 0 & v << 1 - bits 1 { = v - v << 1 bits } {}
    } {}
    ^ v
}

// Store the low n bytes one byte at a time. On a SHARED memory this is
// the only correct way to write fewer than eight bytes: the fast path
// below reads the containing 64-bit word, patches its own bytes and
// writes the word back, and two threads writing NEIGHBOURING bytes of one
// word then lose one of the two updates. wasm says those bytes are
// independent locations, and guests rely on it — two malloc headers, two
// struct fields, a length beside a flag. The symptom is a heap that grows
// a wrong size field and hands out a wild pointer somewhere else.
@ __mem_store_bytes * Interp it i ea i n i val → v {
    : ~ i k 0
    ~ < k n {
        ( vec_set [u] . it mem + ea k # u & ( __lshr64 val * 8 k ) 255 )
        = k + k 1
    }
}

// Write the low n bytes of val little-endian to mem[ea].
inline @ __mem_store * Interp it i ea i n i val → v {
    ? | < ea 0 > + ea n . it mem_bytes {
        ( __trap_oob it `memory store out of bounds` ea n )
        ^ v
    } {}
    // A shared memory takes the byte-wise path for anything narrower than
    // the word it would otherwise rewrite.
    ? & . it shared_mem < n 8 { ( __mem_store_bytes it ea n val ) ^ v } {}
    : s base # s ( vec_data [u] . it mem )
    : i lo & ea 7
    ? <= + lo n 8 {
        // within one word: read-modify-write it once
        : i wi >> ea 3
        : i mask ? == n 8 -1 - << 1 * 8 n 1
        : i sh * lo 8
        : i w ( nurl_peek base wi )
        : i cleared & w ^^ << mask sh -1
        ( nurl_poke base wi | cleared << & val mask sh )
        ^ v
    } {}
    ? . it shared_mem { ( __mem_store_bytes it ea n val ) ^ v } {}
    ( __mem_store_split base ea n val )
}

// Grow linear memory by `delta` pages. Returns the old page count, or −1 when
// the declared maximum (or the wasm32 hard limit of 65536 pages) would be
// exceeded — the value memory.grow pushes.
@ __mem_grow * Interp it i delta → i {
    : *Module m # *Module . it mod
    : ~ i limit 65536
    ? & > . m mem_max 0 < . m mem_max limit { = limit . m mem_max } {}
    // A shared memory already owns its maximum: growing is only raising
    // the addressable bound, never a realloc — another thread may be
    // holding the buffer's base pointer right now. The WHOLE operation
    // has to be atomic, current size included: two threads that each read
    // the old size before either published would both grow from the same
    // base, one growth would be lost, and both guests would take the same
    // pages for their own — one heap on top of another, and addresses
    // past a bound that never moved. (memory.grow returns the OLD size,
    // which is exactly what the guest allocator uses as its new arena.)
    ? != . m mem_shared 0 {
        ( __atom_lock )
        : *Interp ho ( __host it )
        : i old . ho mem_pages
        ? == delta 0 { ( __atom_unlock ) ^ old } {}
        ? | < delta 0 > + old delta limit { ( __atom_unlock ) ^ -1 } {}
        ( __mem_publish ho + old delta * + old delta ( __page ) )
        ( __atom_unlock )
        ^ old
    } {}
    : i old . it mem_pages
    ? == delta 0 { ^ old } {}
    ? | < delta 0 > + old delta limit { ^ -1 } {}
    // One resize, zero-filling the new tail in a single memset, instead of
    // a push per byte: growing by a single page was 65 536 pushes.
    : b _ok ( vec_resize_zeroed [u] . it mem * + old delta ( __page ) )
    = . it mem_pages + old delta
    = . it mem_bytes * . it mem_pages ( __page )
    ^ old
}

// ── the executor ─────────────────────────────────────────────────
// Execute function `fidx`. Arguments are already on the value stack; on return
// the function's results are left on top. Recurses for `call`.

// Dispatch an imported function to the WASI host layer (no frame needed).
@ __call_import * Interp it * Module m i fidx → v {
    : s wp ?? ( vec_get [s] . m imports fidx ) { T x → x F → # s 0 }
    ? != # i wp 0 { : *WImport w # *WImport wp ( __wasi_dispatch it . w module . w field ) } { ( __trap it `bad import index` ) }
}

// Build a frame for defined function `fidx`. `ret_dst` is the caller slot
// the results are copied back to (-1 = outermost frame: arguments arrive on
// it.vs and results leave on it.vs — the embedder protocol). Register form:
// one flat array, locals first, stack slots after; the driver copies call
// arguments straight from the caller's slots, so only the outermost frame
// touches the value stack.
@ __frame_new * Interp it * Module m i fidx i ret_dst → s {
    : s pins ( __pfunc_for it m fidx )
    ? == # i pins 0 { ( __trap it `bad function index` ) ^ # s 0 } {}
    : *PFunc pfc # *PFunc pins
    // Reuse a frame from this function's pool when one is free: a call then
    // costs zeroing the declared locals instead of allocating and zero-
    // filling the whole slot array. Parameters are overwritten by the
    // caller and stack slots are written before they are read (register
    // form guarantees it), so only [nparams, nlocals) needs clearing —
    // wasm requires declared locals to read as zero.
    : i pooln ( vec_len [s] . pfc pool )
    ? > pooln 0 {
        : s rf ?? ( vec_get [s] . pfc pool - pooln 1 ) { T x → x F → # s 0 }
        ( vec_pop [s] . pfc pool )
        ? != # i rf 0 {
            : *Frame rfr # *Frame rf
            : *i rb ( vec_data [i] . rfr regs )
            : ~ i zk . pfc nparams
            ~ < zk . pfc nlocals { = . rb zk 0 = zk + zk 1 }
            = . rfr pos 0
            = . rfr ret_dst ret_dst
            ? < ret_dst 0 {
                : ~ i pk0 . pfc nparams
                ~ > pk0 0 { = pk0 - pk0 1 = . rb pk0 ( __pop it ) }
            } {}
            ^ rf
        } {}
    } {}
    // One zeroed block for the whole slot array. The slot count is
    // locals + constant pool + max stack height and the decoder lets it
    // reach 2^20, so a push per slot is both slower on every cold call
    // and the shape a hostile module would aim at.
    : ( Vec i ) regs ( vec_zeroed [i] . pfc nslots )
    // The constant pool, once per frame rather than once per execution of
    // the `i32.const` that used to build it. Recycled frames keep it: no
    // record writes above the locals except into the operand stack.
    : i knum ( vec_len [i] . pfc kv )
    ? > knum 0 {
        : *i kb ( vec_data [i] regs )
        : i kbase . pfc nlocals
        : ~ i kk 0
        ~ < kk knum { = . kb + kbase kk ?? ( vec_get [i] . pfc kv kk ) { T x → x F → 0 } = kk + kk 1 }
    } {}
    ? < ret_dst 0 {
        // outermost: pop the arguments off the value stack, last first
        : ~ i pk . pfc nparams
        ~ > pk 0 { = pk - pk 1 ( vec_set [i] regs pk ( __pop it ) ) }
    } {}
    : *Frame fr # *Frame ( nurl_alloc Z Frame )
    = . fr fidx fidx
    = . fr regs regs
    = . fr pos 0
    = . fr end * . pfc count 6
    = . fr code_start . pfc code_start
    = . fr pins pins
    = . fr ret_dst ret_dst
    ^ # s fr
}

@ __frame_free s pp → v {
    ? == # i pp 0 { ^ v } {}
    : *Frame fr # *Frame pp
    ( vec_free [i] . fr regs )
    ( nurl_free # s fr )
}

// Return a frame to its function's pool instead of freeing it. The pool is
// unbounded by design: its high-water mark is the deepest simultaneous
// recursion into that one function, which max_depth already caps.
@ __frame_recycle s pp → v {
    ? == # i pp 0 { ^ v } {}
    : *Frame fr # *Frame pp
    : *PFunc pf # *PFunc . fr pins
    ( vec_push [s] . pf pool pp )
}

@ __pf_free s pp → v {
    ? == # i pp 0 { ^ v } {}
    : *PFunc pf # *PFunc pp
    : i pn ( vec_len [s] . pf pool )
    : ~ i pk 0
    ~ < pk pn {
        ?? ( vec_get [s] . pf pool pk ) { T fp → ? != # i fp 0 {
                : *Frame fr # *Frame fp
                ( vec_free [i] . fr regs )
                ( nurl_free fp )
            } {} F → {} }
        = pk + pk 1
    }
    ( vec_free [s] . pf pool )
    ( vec_free [i] . pf code )
    ( vec_free [i] . pf aux )
    ( vec_free [i] . pf kv )
    ( nurl_free # s pf )
}

// ── the register-form micro-ops (record slot [0]) ────────────────
// The record's opcode is NOT the wasm byte: `__iop` renumbers the whole
// space into one dense run ordered by measured frequency, and these are the
// forms that changed shape in register form taking their place in it. The
// numbers are therefore not stable — they are whatever `__iop`'s table
// says — and nothing outside this file may depend on them.
@ __R_MOV → i { ^ 47 }  // A=dst B=src
@ __R_CONST → i { ^ 51 }  // A=dst B=imm (f32/f64 consts carry raw bits)
@ __R_GG → i { ^ 52 }  // global.get: A=dst B=gidx
@ __R_GS → i { ^ 53 }  // global.set: A=gidx B=src
@ __R_SEL → i { ^ 46 }  // A=dst B=srcT C=srcF D=cond
@ __R_MEMSZ → i { ^ 162 }  // A=dst
@ __R_MEMGROW → i { ^ 163 }  // A=dst B=src
@ __R_TABGET → i { ^ 164 }  // A=dst B=idxslot
@ __R_TABSET → i { ^ 165 }  // A=idxslot B=valslot
@ __R_ISNULL → i { ^ 166 }  // A=dst B=src
@ __R_BR → i { ^ 49 }  // A=target
@ __R_BRM → i { ^ 167 }  // A=target B=dst C=src D=n
@ __R_BRIF → i { ^ 54 }  // A=target B=cond
@ __R_BRIFM → i { ^ 168 }  // A=target B=cond C=dst<<20|src D=n
@ __R_BRTBL → i { ^ 169 }  // A=aux base B=idxslot C=n labels (default row last)
@ __R_RET → i { ^ 55 }  // A=src base B=n results
@ __R_CALL → i { ^ 50 }  // A=fidx B=argbase (args in, results out)
@ __R_CALLIND → i { ^ 170 }  // A=typeidx B=argbase C=idxslot
@ __R_UNREACH → i { ^ 172 }

@ __R_TRAPUN → i { ^ 173 }  // unsupported opcode (0xfd/unknown)

@ __R_ATOM → i { ^ 174 }  // vs bridge: A=sub B=memarg offset C=srcbase D=pops<<1|push
@ __R_FCB → i { ^ 171 }  // vs bridge: A=sub B=idx-imm C=srcbase D=pops<<1|push
@ __R_IFZ → i { ^ 48 }  // A=target B=cond — jump when cond == 0
@ __R_BRIFC → i { ^ 45 }  // A=target B=lhs C=rhs D=compare op — jump when it holds

// A `br_if` that also moves block results packs its destination and source
// slot indices into one word, so a slot index has to fit in 20 bits. A
// function needing more than a million slots is not one a compiler emits —
// a ten-byte function CAN declare a million locals, though, so this is an
// architectural limit like the memory and table minimums the decoder
// already enforces, not an assumption.
@ __slot_cap → i { ^ 1048576 }

// wasm opcode → internal micro-op.
//
// The driver dispatches on a dense space ordered by measured frequency, not
// on the wasm byte. The reason is how the arm chain lowers: the optimiser
// folds a run of equality tests on the same value into a switch in batches
// of 64, in source order, and each batch becomes its own jump table behind
// the previous one's range check. On the wasm byte the used space is
// 0x28..0x53, 0x45..0xc4 and the register forms above it — sparse, in an
// order nothing chose — and the chain came out as three chained tables, so
// the arms in the third paid twelve dispatch instructions where the first
// paid five. Renumbered, the 56 opcodes that are 99 % of a compiled
// module's execution land in the first batch and everything else in the
// second: 15 % of the corpus, with no arm's body changed.
//
// The order inside the hot run is measured, not guessed — bench/wasmbench's
// corpus, counted per opcode. Two constraints on top of it: the twenty
// integer compares stay contiguous, because `__fuse_branch` range-tests
// them, and `__R_*` (below) take their numbers from here like everything
// else.
//
// Called once per instruction at predecode time, never at run time.
@ __iop i op → i {
    ? == op 40 { ^ 20 } {}  // i32.load
    ? == op 41 { ^ 18 } {}  // i64.load
    ? == op 42 { ^ 24 } {}  // f32.load
    ? == op 43 { ^ 19 } {}  // f64.load
    ? == op 44 { ^ 76 } {}  // i32.load8_s
    ? == op 45 { ^ 21 } {}  // i32.load8_u
    ? == op 46 { ^ 77 } {}  // i32.load16_s
    ? == op 47 { ^ 23 } {}  // i32.load16_u
    ? == op 48 { ^ 78 } {}  // i64.load8_s
    ? == op 49 { ^ 25 } {}  // i64.load8_u
    ? == op 50 { ^ 79 } {}  // i64.load16_s
    ? == op 51 { ^ 26 } {}  // i64.load16_u
    ? == op 52 { ^ 80 } {}  // i64.load32_s
    ? == op 53 { ^ 22 } {}  // i64.load32_u
    ? == op 54 { ^ 30 } {}  // i32.store
    ? == op 55 { ^ 27 } {}  // i64.store
    ? == op 56 { ^ 31 } {}  // f32.store
    ? == op 57 { ^ 28 } {}  // f64.store
    ? == op 58 { ^ 29 } {}  // i32.store8
    ? == op 59 { ^ 33 } {}  // i32.store16
    ? == op 60 { ^ 34 } {}  // i64.store8
    ? == op 61 { ^ 35 } {}  // i64.store16
    ? == op 62 { ^ 32 } {}  // i64.store32
    ? == op 69 { ^ 43 } {}  // i32.eqz
    ? == op 70 { ^ 56 } {}  // i32.eq
    ? == op 71 { ^ 57 } {}  // i32.ne
    ? == op 72 { ^ 58 } {}  // i32.lt_s
    ? == op 73 { ^ 59 } {}  // i32.lt_u
    ? == op 74 { ^ 60 } {}  // i32.gt_s
    ? == op 75 { ^ 61 } {}  // i32.gt_u
    ? == op 76 { ^ 62 } {}  // i32.le_s
    ? == op 77 { ^ 63 } {}  // i32.le_u
    ? == op 78 { ^ 64 } {}  // i32.ge_s
    ? == op 79 { ^ 65 } {}  // i32.ge_u
    ? == op 80 { ^ 44 } {}  // i64.eqz
    ? == op 81 { ^ 66 } {}  // i64.eq
    ? == op 82 { ^ 67 } {}  // i64.ne
    ? == op 83 { ^ 68 } {}  // i64.lt_s
    ? == op 84 { ^ 69 } {}  // i64.lt_u
    ? == op 85 { ^ 70 } {}  // i64.gt_s
    ? == op 86 { ^ 71 } {}  // i64.gt_u
    ? == op 87 { ^ 72 } {}  // i64.le_s
    ? == op 88 { ^ 73 } {}  // i64.le_u
    ? == op 89 { ^ 74 } {}  // i64.ge_s
    ? == op 90 { ^ 75 } {}  // i64.ge_u
    ? == op 91 { ^ 81 } {}  // f32.eq
    ? == op 92 { ^ 82 } {}  // f32.ne
    ? == op 93 { ^ 83 } {}  // f32.lt
    ? == op 94 { ^ 84 } {}  // f32.gt
    ? == op 95 { ^ 85 } {}  // f32.le
    ? == op 96 { ^ 86 } {}  // f32.ge
    ? == op 97 { ^ 87 } {}  // f64.eq
    ? == op 98 { ^ 88 } {}  // f64.ne
    ? == op 99 { ^ 89 } {}  // f64.lt
    ? == op 100 { ^ 90 } {}  // f64.gt
    ? == op 101 { ^ 91 } {}  // f64.le
    ? == op 102 { ^ 92 } {}  // f64.ge
    ? == op 103 { ^ 93 } {}  // i32.clz
    ? == op 104 { ^ 94 } {}  // i32.ctz
    ? == op 105 { ^ 95 } {}  // i32.popcnt
    ? == op 106 { ^ 9 } {}  // i32.add
    ? == op 107 { ^ 13 } {}  // i32.sub
    ? == op 108 { ^ 17 } {}  // i32.mul
    ? == op 109 { ^ 96 } {}  // i32.div_s
    ? == op 110 { ^ 97 } {}  // i32.div_u
    ? == op 111 { ^ 98 } {}  // i32.rem_s
    ? == op 112 { ^ 99 } {}  // i32.rem_u
    ? == op 113 { ^ 11 } {}  // i32.and
    ? == op 114 { ^ 14 } {}  // i32.or
    ? == op 115 { ^ 15 } {}  // i32.xor
    ? == op 116 { ^ 10 } {}  // i32.shl
    ? == op 117 { ^ 16 } {}  // i32.shr_s
    ? == op 118 { ^ 12 } {}  // i32.shr_u
    ? == op 119 { ^ 100 } {}  // i32.rotl
    ? == op 120 { ^ 101 } {}  // i32.rotr
    ? == op 121 { ^ 102 } {}  // i64.clz
    ? == op 122 { ^ 103 } {}  // i64.ctz
    ? == op 123 { ^ 104 } {}  // i64.popcnt
    ? == op 124 { ^ 0 } {}  // i64.add
    ? == op 125 { ^ 5 } {}  // i64.sub
    ? == op 126 { ^ 1 } {}  // i64.mul
    ? == op 127 { ^ 105 } {}  // i64.div_s
    ? == op 128 { ^ 106 } {}  // i64.div_u
    ? == op 129 { ^ 107 } {}  // i64.rem_s
    ? == op 130 { ^ 108 } {}  // i64.rem_u
    ? == op 131 { ^ 2 } {}  // i64.and
    ? == op 132 { ^ 7 } {}  // i64.or
    ? == op 133 { ^ 4 } {}  // i64.xor
    ? == op 134 { ^ 8 } {}  // i64.shl
    ? == op 135 { ^ 6 } {}  // i64.shr_s
    ? == op 136 { ^ 3 } {}  // i64.shr_u
    ? == op 137 { ^ 109 } {}  // i64.rotl
    ? == op 138 { ^ 110 } {}  // i64.rotr
    ? == op 139 { ^ 111 } {}  // f32.abs
    ? == op 140 { ^ 112 } {}  // f32.neg
    ? == op 141 { ^ 113 } {}  // f32.ceil
    ? == op 142 { ^ 114 } {}  // f32.floor
    ? == op 143 { ^ 115 } {}  // f32.trunc
    ? == op 144 { ^ 116 } {}  // f32.nearest
    ? == op 145 { ^ 117 } {}  // f32.sqrt
    ? == op 146 { ^ 118 } {}  // f32.add
    ? == op 147 { ^ 119 } {}  // f32.sub
    ? == op 148 { ^ 120 } {}  // f32.mul
    ? == op 149 { ^ 121 } {}  // f32.div
    ? == op 150 { ^ 122 } {}  // f32.min
    ? == op 151 { ^ 123 } {}  // f32.max
    ? == op 152 { ^ 124 } {}  // f32.copysign
    ? == op 153 { ^ 125 } {}  // f64.abs
    ? == op 154 { ^ 126 } {}  // f64.neg
    ? == op 155 { ^ 127 } {}  // f64.ceil
    ? == op 156 { ^ 128 } {}  // f64.floor
    ? == op 157 { ^ 129 } {}  // f64.trunc
    ? == op 158 { ^ 130 } {}  // f64.nearest
    ? == op 159 { ^ 131 } {}  // f64.sqrt
    ? == op 160 { ^ 40 } {}  // f64.add
    ? == op 161 { ^ 41 } {}  // f64.sub
    ? == op 162 { ^ 39 } {}  // f64.mul
    ? == op 163 { ^ 42 } {}  // f64.div
    ? == op 164 { ^ 132 } {}  // f64.min
    ? == op 165 { ^ 133 } {}  // f64.max
    ? == op 166 { ^ 134 } {}  // f64.copysign
    ? == op 167 { ^ 36 } {}  // i32.wrap_i64
    ? == op 168 { ^ 135 } {}  // i32.trunc_f32_s
    ? == op 169 { ^ 136 } {}  // i32.trunc_f32_u
    ? == op 170 { ^ 137 } {}  // i32.trunc_f64_s
    ? == op 171 { ^ 138 } {}  // i32.trunc_f64_u
    ? == op 172 { ^ 38 } {}  // i64.extend_i32_s
    ? == op 173 { ^ 37 } {}  // i64.extend_i32_u
    ? == op 174 { ^ 139 } {}  // i64.trunc_f32_s
    ? == op 175 { ^ 140 } {}  // i64.trunc_f32_u
    ? == op 176 { ^ 141 } {}  // i64.trunc_f64_s
    ? == op 177 { ^ 142 } {}  // i64.trunc_f64_u
    ? == op 178 { ^ 143 } {}  // f32.convert_i32_s
    ? == op 179 { ^ 144 } {}  // f32.convert_i32_u
    ? == op 180 { ^ 145 } {}  // f32.convert_i64_s
    ? == op 181 { ^ 146 } {}  // f32.convert_i64_u
    ? == op 182 { ^ 147 } {}  // f32.demote_f64
    ? == op 183 { ^ 148 } {}  // f64.convert_i32_s
    ? == op 184 { ^ 149 } {}  // f64.convert_i32_u
    ? == op 185 { ^ 150 } {}  // f64.convert_i64_s
    ? == op 186 { ^ 151 } {}  // f64.convert_i64_u
    ? == op 187 { ^ 152 } {}  // f64.promote_f32
    ? == op 188 { ^ 153 } {}  // i32.reinterpret_f32
    ? == op 189 { ^ 154 } {}  // i64.reinterpret_f64
    ? == op 190 { ^ 155 } {}  // f32.reinterpret_i32
    ? == op 191 { ^ 156 } {}  // f64.reinterpret_i64
    ? == op 192 { ^ 157 } {}  // i32.extend8_s
    ? == op 193 { ^ 158 } {}  // i32.extend16_s
    ? == op 194 { ^ 159 } {}  // i64.extend8_s
    ? == op 195 { ^ 160 } {}  // i64.extend16_s
    ? == op 196 { ^ 161 } {}  // i64.extend32_s
    ^ 173  // anything else never reaches the driver as itself
}

// Emit one 6-slot record; returns its index.
@ __pf_emit ( Vec i ) code i op i a i b i cc i dd i byte → i {
    : i idx / ( vec_len [i] code ) 6
    ( vec_push [i] code op ) ( vec_push [i] code a ) ( vec_push [i] code b )
    ( vec_push [i] code cc ) ( vec_push [i] code dd ) ( vec_push [i] code byte )
    ^ idx
}

// One open block/loop/if during predecode. `patches` holds forward-branch
// sites that must learn "the record index just past this frame's end":
// value site*2 → record A-field, site*2+1 → aux word `site`.
: PBlk { i kind i base i params i results i live_entry i t0 i else_br ( Vec i ) patches }

@ __pblk_new i kind i base i params i results i live i t0 → s {
    : *PBlk k # *PBlk ( nurl_alloc Z PBlk )
    = . k kind kind = . k base base = . k params params = . k results results
    = . k live_entry live = . k t0 t0 = . k else_br -1
    = . k patches ( vec_new [i] )
    ^ # s k
}

@ __pblk_free s pp → v {
    ? == # i pp 0 { ^ v } {}
    : *PBlk k # *PBlk pp
    ( vec_free [i] . k patches )
    ( nurl_free # s k )
}

// npops of the vs-bridged float/conversion family: compares and the binary
// arithmetic groups take two operands, everything else one.
@ __float_pops i op → i {
    ? & >= op 91 <= op 102 { ^ 2 } {}
    ? & >= op 146 <= op 152 { ^ 2 } {}
    ? & >= op 160 <= op 166 { ^ 2 } {}
    ^ 1
}

// `cmp; br_if L` is two records where one will do: the compare writes a 0/1
// into a slot the very next record reads and then throws away. When the
// compare is the record just emitted and the branch needs no result move,
// the compare is rewritten IN PLACE into a branch that does its own test,
// and no branch record is emitted at all.
//
// `i32.eqz x; br_if L` needs no new opcode: it is exactly `br_if_zero x`,
// the record `if` already uses.
//
// The safety argument is `__fold_set`'s: `lastp` is only non-negative when
// the previous instruction was straight-line, and no control opcode is, so
// no label can sit between the compare and the branch — which is the only
// way a path could reach the branch without the compare.
@ __fuse_branch * PFunc pf i lastp i cond i tgt i byte → b {
    ? < lastp 0 { ^ F } {}
    ? != ( vec_len [i] . pf code ) * + lastp 1 6 { ^ F } {}
    : i base * lastp 6
    : i lop ?? ( vec_get [i] . pf code base ) { T x → x F → 0 }
    ? != ?? ( vec_get [i] . pf code + base 1 ) { T x → x F → -1 } cond { ^ F } {}
    : i lb ?? ( vec_get [i] . pf code + base 2 ) { T x → x F → 0 }
    : i lc ?? ( vec_get [i] . pf code + base 3 ) { T x → x F → 0 }
    ? | == lop 43 == lop 44 {  // eqz → branch when the operand itself is zero
        ( vec_set [i] . pf code base ( __R_IFZ ) )
        ( vec_set [i] . pf code + base 1 tgt )
        ( vec_set [i] . pf code + base 2 lb )
        ( vec_set [i] . pf code + base 5 byte )
        ^ T
    } {}
    ? & >= lop 56 <= lop 75 {  // the integer compares
        ( vec_set [i] . pf code base ( __R_BRIFC ) )
        ( vec_set [i] . pf code + base 1 tgt )
        ( vec_set [i] . pf code + base 2 lb )
        ( vec_set [i] . pf code + base 3 lc )
        ( vec_set [i] . pf code + base 4 lop )
        ( vec_set [i] . pf code + base 5 byte )
        ^ T
    } {}
    ^ F
}

// Emit a branch to label depth `k` (top of `open` = depth 0). `cond` is the
// condition slot for br_if (-1 = unconditional). `h` is the height AFTER any
// condition pop. Fills patch sites for forward targets. Returns nothing; the
// caller handles liveness.
@ __emit_branch * PFunc pf ( Vec s ) open i k i cond i sb i h i byte i lastp → v {
    : i n ( vec_len [s] open )
    ? >= k n { ( __pf_emit . pf code ( __R_TRAPUN ) 0 0 0 0 byte ) ^ v } {}
    : s bp ?? ( vec_get [s] open - - n 1 k ) { T x → x F → # s 0 }
    ? == # i bp 0 { ( __pf_emit . pf code ( __R_TRAPUN ) 0 0 0 0 byte ) ^ v } {}
    : *PBlk blk # *PBlk bp
    : i arity ? == . blk kind 1 . blk params . blk results
    : i dst + sb . blk base
    : i src + sb - h arity
    // `t0` is a record index (it doubles as a patch site for `if`); a stored
    // jump target is the same thing scaled to the driver's word cursor.
    : i tgt ? == . blk kind 1 * . blk t0 6 -1
    : ~ i rec 0
    ? | == arity 0 == dst src {
        ? < cond 0 { = rec ( __pf_emit . pf code ( __R_BR ) tgt 0 0 0 byte ) } {
            ? ( __fuse_branch pf lastp cond tgt byte ) { = rec lastp }
            { = rec ( __pf_emit . pf code ( __R_BRIF ) tgt cond 0 0 byte ) }
        }
    } {
        ? < cond 0 { = rec ( __pf_emit . pf code ( __R_BRM ) tgt dst src arity byte ) }
        { = rec ( __pf_emit . pf code ( __R_BRIFM ) tgt cond | << dst 20 src arity byte ) }
    }
    ? != . blk kind 1 { ( vec_push [i] . blk patches * rec 2 ) } {}
}

// ── operand forwarding (the height → slot map) ───────────────────
// `local.get` used to emit a MOV copying the local into the stack slot for
// its height. On the benchmark corpus that one record was 45 % of every
// instruction the interpreter executed, and it buys nothing: operands are
// absolute slot indices, so a consumer can read the local's own slot.
//
// `vm` maps a stack height to the slot that actually holds that value, with
// `-1` meaning "canonical" (`L + height`). `local.get` records the alias and
// emits nothing; every operand read goes through `__vg`, so the consumer
// addresses the local directly. Destinations stay canonical — a record only
// ever writes `L + height` or a local — which is what keeps the map from
// having to track aliases of aliases.
//
// An alias holds only while the slot it names still holds that value, so it
// is materialised again ("flushed") wherever the layout has to be the
// canonical one: before any control transfer, because branch targets move
// results between canonical slots; before a call or a value-stack bridge,
// because both need their operands contiguous; and, in `__vkill`, before a
// `local.set` overwrites a local that a live stack entry is aliasing.
//
// Invariant: while `live` is 0 the map is all-canonical — every transition
// to dead code goes through a flush, and no alias is recorded when dead.
@ __vg ( Vec i ) vm i sb i k → i {
    : i sl ?? ( vec_get [i] vm k ) { T x → x F → -1 }
    ^ ? < sl 0 + sb k sl
}

// ── the per-function constant pool ───────────────────────────────
// After operand forwarding, `i32.const` was the biggest single record class
// left. It is the same redundancy one level down: the value is fixed for the
// life of the module, so copying it into a stack slot at run time is work the
// predecoder can do once. A pre-scan of the body interns the distinct
// constants; the frame reserves a slot for each, right after the locals, and
// `i32.const K` becomes an alias to that slot — a `local.get` of a read-only
// local, handled by the map that already exists. Nothing writes those slots
// after the frame is built, so a recycled frame keeps them.
//
// Reserving them between the locals and the operand stack is what keeps this
// free: both bases are known before the pass, so every slot index is final
// when it is emitted. A pool after the stack would need `maxh`, which is not
// known until the pass ends.
//
// The pool is capped: interning is a linear scan, and a frame carries one
// word per entry. Past the cap a constant falls back to the CONST record the
// predecoder always emitted, so the behaviour degrades rather than breaking.
@ __kcap → i { ^ 128 }

@ __kfind ( Vec i ) kv i cv → i {
    : i n ( vec_len [i] kv )
    : ~ i k 0
    ~ < k n {
        : i x ?? ( vec_get [i] kv k ) { T x → x F → 0 }
        ? == x cv { ^ k } {}
        = k + k 1
    }
    ^ -1
}

@ __kintern ( Vec i ) kv i cv → v {
    ? >= ( __kfind kv cv ) 0 { ^ v } {}
    ? >= ( vec_len [i] kv ) ( __kcap ) { ^ v } {}
    ( vec_push [i] kv cv )
}

// One structural walk of the body collecting the distinct constants. Every
// other opcode is stepped over by `__skip_imm`, the same routine the decoder
// already trusts for immediate layout, so this cannot desynchronise.
@ __const_pool * Module m * WFunc f ( Vec i ) kv → v {
    // Pool entry 0 is the address-fusion zero. Every load record carries a
    // second address operand (see `__fuse_addr`); an access with nothing
    // folded into it names this slot, so the arm adds a slot that is always
    // zero instead of testing whether it has an index at all.
    ( __kintern kv 0 )
    : *Wc c ( wc_new . m code )
    = . c pos . f code_start
    = . c len . f code_end
    ~ < . c pos . f code_end {
        : i p0 . c pos
        : i op ( wc_u8 c )
        ? == op 65 { : i cv ( wc_sleb c ) ( __kintern kv ( __w32 cv ) ) } {
            ? == op 66 { : i cv ( wc_sleb c ) ( __kintern kv cv ) } {
                ? == op 67 { : i cv ( __read_le c 4 ) ( __kintern kv cv ) } {
                    ? == op 68 { : i cv ( __read_le c 8 ) ( __kintern kv cv ) } {
                        ( __skip_imm c op ) } } } }
        // A hostile immediate can decode to a length that moves the cursor
        // backwards; this scan only reads, so it just has to end. Forcing it
        // forward makes termination a property of the loop rather than of
        // every immediate encoding it walks past.
        ? <= . c pos p0 { = . c pos + p0 1 } {}
    }
    ( wc_free c )
}

// Bind height `h` to the constant `cv`: the pool slot when the pre-scan
// interned it, otherwise the CONST record into the canonical slot.
@ __kbind * PFunc pf ( Vec i ) vm ( Vec i ) kv i L i sb i h i cv i live i byte → v {
    : i idx ( __kfind kv cv )
    ? >= idx 0 { ( __vset vm h + L idx ) } {
        ? != 0 live { ( __pf_emit . pf code ( __R_CONST ) + sb h cv 0 0 byte ) } {}
        ( __vset vm h -1 )
    }
}

@ __vset ( Vec i ) vm i k i slot → v {
    ~ <= ( vec_len [i] vm ) k { ( vec_push [i] vm -1 ) }
    ( vec_set [i] vm k slot )
}

// Materialise every alias below `h` into its canonical slot, then reset the
// whole map. `h` = 0 makes it a pure reset; `live` = 0 means nothing was
// aliased in the first place, so the reset alone is the whole job.
@ __vflush * PFunc pf ( Vec i ) vm i sb i h i live i byte → v {
    : i n ( vec_len [i] vm )
    : ~ i k 0
    ~ < k n {
        : i sl ?? ( vec_get [i] vm k ) { T x → x F → -1 }
        ? >= sl 0 {
            ? & < k h != 0 live { ( __pf_emit . pf code ( __R_MOV ) + sb k sl 0 0 byte ) } {}
            ( vec_set [i] vm k -1 )
        } {}
        = k + k 1
    }
}

// ── folding `local.set` into its producer ────────────────────────
// After operand forwarding and the constant pool, `MOV` was the biggest
// record class left — 31 % of everything the benchmark corpus dispatched,
// and 46 % of nbody's. Most of them are `local.set` / `local.tee`: the
// producing instruction writes the stack slot for its height and the very
// next record copies that slot into a local. The slot is dead the instant
// the copy is made, so the producer can be told to write the local instead
// and the copy deleted.
//
// The fold is legal only when nothing can observe the slot it stops writing
// and nothing can reach the copy without the producer:
//   * the producer must be the record just emitted, by the instruction just
//     decoded, and that instruction must be straight-line — a label can sit
//     only where a control opcode put it, and no control opcode is
//     straight-line, so `lastp` is -1 across every merge point;
//   * the value must be the fresh canonical one, not an alias: a
//     `local.get`/const source is a genuine copy;
//   * no live stack entry may alias `li`, because `__vkill` would have to
//     materialise it *from the old* `li` — and that read would be emitted
//     after the retargeted write.

// True while `op`'s record is a straight-line value producer: its only
// effect is the write to slot A, and no label can land between it and the
// next instruction.
@ __straightline i op → b {
    ? & >= op 40 <= op 53 { ^ T } {}  // loads
    ? | == op 27 == op 28 { ^ T } {}  // select (typed select folds to the same record)
    ? | == op 35 == op 37 { ^ T } {}  // global.get / table.get
    ? | == op 63 == op 64 { ^ T } {}  // memory.size / memory.grow
    ? | == op 69 == op 80 { ^ T } {}  // eqz
    ? & >= op 70 <= op 79 { ^ T } {}  // i32 compares
    ? & >= op 81 <= op 138 { ^ T } {}  // i64 compares, float compares, int arithmetic + unary
    ? & >= op 139 <= op 196 { ^ T } {}  // float arithmetic, conversions, sign extensions
    ? == op 209 { ^ T } {}  // ref.is_null
    ^ F
}

// Does any live stack entry below `lim` alias local `li`?
@ __valias ( Vec i ) vm i lim i li → b {
    : i n ( vec_len [i] vm )
    : i m ? < lim n lim n
    : ~ i k 0
    ~ < k m {
        ? == ?? ( vec_get [i] vm k ) { T x → x F → -1 } li { ^ T } {}
        = k + k 1
    }
    ^ F
}

// Retarget the last record's destination to local `li`, or report that the
// move has to be a real MOV after all. `hm1` is the height of the value.
@ __fold_set * PFunc pf ( Vec i ) vm i lastp i sb i hm1 i li → b {
    ? < lastp 0 { ^ F } {}
    ? >= ?? ( vec_get [i] vm hm1 ) { T x → x F → -1 } 0 { ^ F } {}
    : i dstat + * lastp 6 1
    ? != ?? ( vec_get [i] . pf code dstat ) { T x → x F → -1 } + sb hm1 { ^ F } {}
    ? ( __valias vm hm1 li ) { ^ F } {}
    ( vec_set [i] . pf code dstat li )
    ^ T
}

// A write to local `li` invalidates every live stack entry aliasing it:
// those are copied to their canonical slots first, while `li` still holds
// the old value.
@ __vkill * PFunc pf ( Vec i ) vm i sb i h i li i live i byte → v {
    : i n ( vec_len [i] vm )
    : i lim ? < h n h n
    : ~ i k 0
    ~ < k lim {
        : i sl ?? ( vec_get [i] vm k ) { T x → x F → -1 }
        ? == sl li {
            ? != 0 live { ( __pf_emit . pf code ( __R_MOV ) + sb k li 0 0 byte ) } {}
            ( vec_set [i] vm k -1 )
        } {}
        = k + k 1
    }
}

// ── the predecoder ───────────────────────────────────────────────
// One linear pass with an abstract stack height `h`: every reachable
// instruction knows exactly where its operands live, so records carry
// absolute slot indices. Code made unreachable by br/return/unreachable is
// parsed structurally (blocks still nest, immediates still skipped — record
// alignment survives hostile bytes exactly as before) but emits nothing;
// heights resume at the statically-known values at `else` and `end`.
// `i32.add b i; <load> off` is two records where one will do: the add
// computes an address the load immediately consumes and nothing else can
// see. The add is deleted and its two operands become the load's base and
// index — an `i64.load` off a computed address stops being two dispatches.
//
// The safety argument is `__fuse_branch`'s, plus one more clause: the add
// must write a STACK slot. `__fold_set` may already have retargeted it at a
// local, and a local outlives the access.
//
// Returns `base << 21 | index` (slots are capped at 2^20), or -1 when there
// is nothing to fold. On success the add record is gone, so the load takes
// its index and every earlier record index still means what it did.
@ __fuse_addr * PFunc pf i lastp i addr i sb → i {
    ? < lastp 0 { ^ -1 } {}
    ? != ( vec_len [i] . pf code ) * + lastp 1 6 { ^ -1 } {}
    : i base * lastp 6
    ? != ?? ( vec_get [i] . pf code base ) { T x → x F → -1 } ( __iop 106 ) { ^ -1 } {}
    : i dst ?? ( vec_get [i] . pf code + base 1 ) { T x → x F → -1 }
    ? | != dst addr < dst sb { ^ -1 } {}
    : i s1 ?? ( vec_get [i] . pf code + base 2 ) { T x → x F → 0 }
    : i s2 ?? ( vec_get [i] . pf code + base 3 ) { T x → x F → 0 }
    : b _ok ( vec_set_len [i] . pf code base )
    ^ | << s1 21 s2
}

@ __predecode * Module m * WFunc f → s {
    : *PFunc pf # *PFunc ( nurl_alloc Z PFunc )
    = . pf code ( vec_new [i] )
    = . pf aux ( vec_new [i] )
    : s ftp ?? ( vec_get [s] . m types . f typeidx ) { T x → x F → # s 0 }
    : ~ i nparams 0
    : ~ i nresults 0
    ? != # i ftp 0 {
        : *FuncType ftt # *FuncType ftp
        = nparams ( vec_len [i] . ftt params )
        = nresults ( vec_len [i] . ftt results )
    } {}
    : i L + nparams ( vec_len [i] . f locals )
    = . pf nlocals L
    // Locals occupy [0, L); the constant pool [L, L + |kv|); the operand
    // stack everything above. Both boundaries are fixed before the pass, so
    // every slot a record carries is final the moment it is emitted.
    : ( Vec i ) kv ( vec_new [i] )
    ( __const_pool m f kv )
    : i SB + L ( vec_len [i] kv )
    = . pf sbase SB
    = . pf kv kv
    : ( Vec s ) open ( vec_new [s] )
    // the function body behaves as one enclosing block returning the results
    ( vec_push [s] open ( __pblk_new 0 0 0 nresults 1 -1 ) )
    : *Wc c ( wc_new . m code )
    = . c pos . f code_start
    = . c len . f code_end
    : ~ i h 0
    : ~ i maxh 0
    : ~ i live 1
    // index of the record a `local.set` may fold into, or -1 (see __fold_set)
    : ~ i lastp -1
    : ( Vec i ) vm ( vec_new [i] )
    ~ & < . c pos . f code_end > ( vec_len [s] open ) 0 {
        : i byte . c pos
        : i op ( wc_u8 c )
        ? | == op 2 == op 3 {  // block / loop
            ( __vflush pf vm SB h live byte )
            : i bt ( wc_sleb c )
            : i p ( __bt_params m bt )
            : i r ( __bt_results m bt )
            : i t0 ? == op 3 / ( vec_len [i] . pf code ) 6 -1
            ( vec_push [s] open ( __pblk_new ? == op 3 1 0 - h p p r live t0 ) )
        } {
            ? == op 4 {  // if: pop cond, IFZ to else/end (patched)
                : i bt ( wc_sleb c )
                : i p ( __bt_params m bt )
                : i r ( __bt_results m bt )
                ? != 0 live {
                    = h - h 1
                    : i cnd ( __vg vm SB h )
                    ( __vflush pf vm SB h live byte )
                    : i rec ( __pf_emit . pf code ( __R_IFZ ) -1 cnd 0 0 byte )
                    : s kp ( __pblk_new 2 - h p p r 1 rec )
                    ( vec_push [s] open kp )
                } { ( vec_push [s] open ( __pblk_new 2 h p r 0 -1 ) ) }
            } {
                ? == op 5 {  // else
                    ( __vflush pf vm SB h live byte )
                    : i n ( vec_len [s] open )
                    : s bp ?? ( vec_get [s] open - n 1 ) { T x → x F → # s 0 }
                    ? != # i bp 0 {
                        : *PBlk blk # *PBlk bp
                        ? != 0 . blk live_entry {
                            // end of a live then-arm jumps past the else arm
                            ? != 0 live { = . blk else_br ( __pf_emit . pf code ( __R_BR ) -1 0 0 0 byte ) } {}
                            // the cond==0 edge lands here
                            ? >= . blk t0 0 { ( vec_set [i] . pf code + * . blk t0 6 1 ( vec_len [i] . pf code ) ) = . blk t0 -1 } {}
                            = h + . blk base . blk params
                            = live 1
                        } {}
                    } {}
                } {
                    ? == op 11 {  // end: close the frame, patch all forward targets here
                        ( __vflush pf vm SB h live byte )
                        : i n ( vec_len [s] open )
                        : s bp ?? ( vec_get [s] open - n 1 ) { T x → x F → # s 0 }
                        ( vec_pop [s] open )
                        ? != # i bp 0 {
                            : *PBlk blk # *PBlk bp
                            // the word offset just past this frame — what a jump to
                            // the end of the construct has to land on
                            : i here ( vec_len [i] . pf code )
                            : ~ i out live
                            // no-else if: the cond==0 edge lands past the construct
                            ? & == . blk kind 2 >= . blk t0 0 {
                                ( vec_set [i] . pf code + * . blk t0 6 1 here )
                                ? != 0 . blk live_entry { = out 1 } {}
                            } {}
                            ? >= . blk else_br 0 { ( vec_set [i] . pf code + * . blk else_br 6 1 here ) = out 1 } {}
                            : i np ( vec_len [i] . blk patches )
                            ? > np 0 { = out 1 } {}
                            : ~ i pk 0
                            ~ < pk np {
                                : i site ?? ( vec_get [i] . blk patches pk ) { T x → x F → 0 }
                                ? == 0 & site 1 { ( vec_set [i] . pf code + * / site 2 6 1 here ) }
                                { ( vec_set [i] . pf aux / site 2 here ) }
                                = pk + pk 1
                            }
                            ? != 0 out { = h + . blk base . blk results = live 1 } { = live 0 }
                            ( __pblk_free bp )
                        } {}
                    } {
                        ? == op 12 {  // br
                            : i k ( wc_uleb c )
                            ? != 0 live { ( __vflush pf vm SB h live byte ) ( __emit_branch pf open k -1 SB h byte -1 ) = live 0 } {}
                        } {
                            ? == op 13 {  // br_if: pop cond, branch on it, fall through otherwise
                                : i k ( wc_uleb c )
                                ? != 0 live {
                                    = h - h 1
                                    : i cnd ( __vg vm SB h )
                                    ( __vflush pf vm SB h live byte )
                                    ( __emit_branch pf open k cnd SB h byte lastp )
                                } {}
                            } {
                                ? == op 14 {  // br_table
                                    : i nl ( wc_uleb c )
                                    ? == 0 live { : ~ i sk 0 ~ <= sk nl { ( wc_uleb c ) = sk + sk 1 } } {
                                        = h - h 1
                                        : i idxs ( __vg vm SB h )
                                        ( __vflush pf vm SB h live byte )
                                        : i astart ( vec_len [i] . pf aux )
                                        : i non ( vec_len [s] open )
                                        : ~ i lk 0
                                        ~ <= lk nl {
                                            : i dep ( wc_uleb c )
                                            ? >= dep non { ( vec_push [i] . pf aux -1 ) ( vec_push [i] . pf aux 0 ) ( vec_push [i] . pf aux 0 ) ( vec_push [i] . pf aux 0 ) } {
                                                : s bp2 ?? ( vec_get [s] open - - non 1 dep ) { T x → x F → # s 0 }
                                                : *PBlk b2 # *PBlk bp2
                                                : i ar ? == . b2 kind 1 . b2 params . b2 results
                                                : i tg ? == . b2 kind 1 * . b2 t0 6 -1
                                                : i auxpos ( vec_len [i] . pf aux )
                                                ( vec_push [i] . pf aux tg )
                                                ( vec_push [i] . pf aux + SB . b2 base )
                                                ( vec_push [i] . pf aux + SB - h ar )
                                                ( vec_push [i] . pf aux ar )
                                                ? != . b2 kind 1 { ( vec_push [i] . b2 patches + * auxpos 2 1 ) } {}
                                            }
                                            = lk + lk 1
                                        }
                                        ( __pf_emit . pf code ( __R_BRTBL ) astart idxs nl 0 byte )
                                        = live 0
                                    }
                                } {
                                    ? == op 15 {  // return
                                        ? != 0 live {
                                            ( __vflush pf vm SB h live byte )
                                            ( __pf_emit . pf code ( __R_RET ) + SB - h nresults nresults 0 0 byte )
                                            = live 0
                                        } {}
                                    } {
                                        ? == op 16 {  // call
                                            : i fi ( wc_uleb c )
                                            ? != 0 live {
                                                ( __vflush pf vm SB h live byte )
                                                : s ct ( module_func_type m fi )
                                                : ~ i cp 0
                                                : ~ i cr 0
                                                ? != # i ct 0 { : *FuncType ctt # *FuncType ct = cp ( vec_len [i] . ctt params ) = cr ( vec_len [i] . ctt results ) } {}
                                                ( __pf_emit . pf code ( __R_CALL ) fi + SB - h cp 0 0 byte )
                                                = h + - h cp cr
                                                ? > h maxh { = maxh h } {}
                                            } {}
                                        } {
                                            ? == op 17 {  // call_indirect
                                                : i ti ( wc_uleb c ) ( wc_uleb c )
                                                ? != 0 live {
                                                    = h - h 1
                                                    : i idxs ( __vg vm SB h )
                                                    ( __vflush pf vm SB h live byte )
                                                    : s ct ?? ( vec_get [s] . m types ti ) { T x → x F → # s 0 }
                                                    : ~ i cp 0
                                                    : ~ i cr 0
                                                    ? != # i ct 0 { : *FuncType ctt # *FuncType ct = cp ( vec_len [i] . ctt params ) = cr ( vec_len [i] . ctt results ) } {}
                                                    ( __pf_emit . pf code ( __R_CALLIND ) ti + SB - h cp idxs 0 byte )
                                                    = h + - h cp cr
                                                    ? > h maxh { = maxh h } {}
                                                } {}
                                            } {
                                                ? == op 0 { ? != 0 live { ( __vflush pf vm SB 0 live byte ) ( __pf_emit . pf code ( __R_UNREACH ) 0 0 0 0 byte ) = live 0 } {} } {
                                                    ? == op 1 {} {  // nop
                                                        ? == op 26 { ? != 0 live { = h - h 1 } {} } {  // drop
                                                            ? | == op 27 == op 28 {  // select (typed select folds to the same record)
                                                                ? == op 28 { : i tc ( wc_uleb c ) ( wc_skip c tc ) } {}
                                                                ? != 0 live {
                                                                    ( __pf_emit . pf code ( __R_SEL ) + SB - h 3 ( __vg vm SB - h 3 ) ( __vg vm SB - h 2 ) ( __vg vm SB - h 1 ) byte ) ( __vset vm - h 3 -1 )
                                                                    = h - h 2
                                                                } {}
                                                            } {
                                                                ? == op 32 { : i li ( wc_uleb c ) ? != 0 live { ( __vset vm h li ) = h + h 1 ? > h maxh { = maxh h } {} } {} } {
                                                                    ? == op 33 { : i li ( wc_uleb c ) ? != 0 live { ? ( __fold_set pf vm lastp SB - h 1 li ) {} { : i sv ( __vg vm SB - h 1 ) ( __vkill pf vm SB - h 1 li live byte ) ( __pf_emit . pf code ( __R_MOV ) li sv 0 0 byte ) } = h - h 1 } {} } {
                                                                        ? == op 34 { : i li ( wc_uleb c ) ? != 0 live { ? ( __fold_set pf vm lastp SB - h 1 li ) {} { : i sv ( __vg vm SB - h 1 ) ( __vkill pf vm SB - h 1 li live byte ) ( __pf_emit . pf code ( __R_MOV ) li sv 0 0 byte ) } ( __vset vm - h 1 li ) } {} } {
                                                                            ? == op 35 { : i gi ( wc_uleb c ) ? != 0 live { ( __pf_emit . pf code ( __R_GG ) + SB h gi 0 0 byte ) ( __vset vm h -1 ) = h + h 1 ? > h maxh { = maxh h } {} } {} } {
                                                                                ? == op 36 { : i gi ( wc_uleb c ) ? != 0 live { ( __pf_emit . pf code ( __R_GS ) gi ( __vg vm SB - h 1 ) 0 0 byte ) = h - h 1 } {} } {
                                                                                    ? == op 37 { ( wc_uleb c ) ? != 0 live { ( __pf_emit . pf code ( __R_TABGET ) + SB - h 1 ( __vg vm SB - h 1 ) 0 0 byte ) ( __vset vm - h 1 -1 ) } {} } {
                                                                                        ? == op 38 { ( wc_uleb c ) ? != 0 live { ( __pf_emit . pf code ( __R_TABSET ) ( __vg vm SB - h 2 ) ( __vg vm SB - h 1 ) 0 0 byte ) = h - h 2 } {} } {
                                                                                            ? == op 65 { : i cv ( wc_sleb c ) ? != 0 live { ( __kbind pf vm kv L SB h ( __w32 cv ) live byte ) = h + h 1 ? > h maxh { = maxh h } {} } {} } {
                                                                                                ? == op 66 { : i cv ( wc_sleb c ) ? != 0 live { ( __kbind pf vm kv L SB h cv live byte ) = h + h 1 ? > h maxh { = maxh h } {} } {} } {
                                                                                                    ? == op 67 { : i cv ( __read_le c 4 ) ? != 0 live { ( __kbind pf vm kv L SB h cv live byte ) = h + h 1 ? > h maxh { = maxh h } {} } {} } {
                                                                                                        ? == op 68 { : i cv ( __read_le c 8 ) ? != 0 live { ( __kbind pf vm kv L SB h cv live byte ) = h + h 1 ? > h maxh { = maxh h } {} } {} } {
                                                                                                            ? & >= op 40 <= op 53 {  // loads: A=dst B=base C=off D=index
                                                                                                                ( wc_uleb c )
                                                                                                                : i off & ( wc_uleb c ) 4294967295
                                                                                                                ? != 0 live {
                                                                                                                    : i adr ( __vg vm SB - h 1 )
                                                                                                                    : i fz ( __fuse_addr pf lastp adr SB )
                                                                                                                    ( __pf_emit . pf code ( __iop op ) + SB - h 1 ? < fz 0 adr >> fz 21 off ? < fz 0 L & fz 2097151 byte )
                                                                                                                    ( __vset vm - h 1 -1 )
                                                                                                                } {}
                                                                                                            } {
                                                                                                                ? & >= op 54 <= op 62 {  // stores: A=addr B=val C=off
                                                                                                                    ( wc_uleb c )
                                                                                                                    : i off & ( wc_uleb c ) 4294967295
                                                                                                                    ? != 0 live { ( __pf_emit . pf code ( __iop op ) ( __vg vm SB - h 2 ) ( __vg vm SB - h 1 ) off 0 byte ) = h - h 2 } {}
                                                                                                                } {
                                                                                                                    ? == op 63 { ( wc_u8 c ) ? != 0 live { ( __pf_emit . pf code ( __R_MEMSZ ) + SB h 0 0 0 byte ) ( __vset vm h -1 ) = h + h 1 ? > h maxh { = maxh h } {} } {} } {
                                                                                                                        ? == op 64 { ( wc_u8 c ) ? != 0 live { ( __pf_emit . pf code ( __R_MEMGROW ) + SB - h 1 ( __vg vm SB - h 1 ) 0 0 byte ) ( __vset vm - h 1 -1 ) } {} } {
                                                                                                                            ? | == op 69 | == op 80 | & >= op 103 <= op 105 | & >= op 121 <= op 123 & >= op 192 <= op 196 {
                                                                                                                                // integer unary: in place at the top slot
                                                                                                                                ? != 0 live { ( __pf_emit . pf code ( __iop op ) + SB - h 1 ( __vg vm SB - h 1 ) 0 0 byte ) ( __vset vm - h 1 -1 ) } {}
                                                                                                                            } {
                                                                                                                                ? | & >= op 70 <= op 79 | & >= op 81 <= op 90 | & >= op 106 <= op 120 & >= op 124 <= op 138 {
                                                                                                                                    // integer binary: dst = h-2, operands h-2 / h-1
                                                                                                                                    ? != 0 live { ( __pf_emit . pf code ( __iop op ) + SB - h 2 ( __vg vm SB - h 2 ) ( __vg vm SB - h 1 ) 0 byte ) ( __vset vm - h 2 -1 ) = h - h 1 } {}
                                                                                                                                } {
                                                                                                                                    ? | & >= op 91 <= op 102 & >= op 139 <= op 191 {
                                                                                                                                        // float arithmetic / compares and the int↔float conversions:
                                                                                                                                        // the same register shape as the integer unary and binary arms
                                                                                                                                        // above, dst = the slot of the first operand.
                                                                                                                                        ? != 0 live {
                                                                                                                                            : i np ( __float_pops op )
                                                                                                                                            ( __pf_emit . pf code ( __iop op ) + SB - h np ( __vg vm SB - h np ) ? == np 2 ( __vg vm SB - h 1 ) 0 0 byte )
                                                                                                                                            ( __vset vm - h np -1 )
                                                                                                                                            = h + - h np 1
                                                                                                                                        } {}
                                                                                                                                    } {
                                                                                                                                        ? == op 208 { ( wc_u8 c ) ? != 0 live { ( __kbind pf vm kv L SB h -1 live byte ) = h + h 1 ? > h maxh { = maxh h } {} } {} } {
                                                                                                                                            ? == op 209 { ? != 0 live { ( __pf_emit . pf code ( __R_ISNULL ) + SB - h 1 ( __vg vm SB - h 1 ) 0 0 byte ) ( __vset vm - h 1 -1 ) } {} } {
                                                                                                                                                ? == op 210 { : i rfi ( wc_uleb c ) ? != 0 live { ( __kbind pf vm kv L SB h rfi live byte ) = h + h 1 ? > h maxh { = maxh h } {} } {} } {
                                                                                                                                                    ? == op 252 {  // 0xfc family: vs bridge, pops/pushes per sub
                                                                                                                                                        : i sub ( wc_uleb c )
                                                                                                                                                        : ~ i bop 0
                                                                                                                                                        ? == sub 8 { = bop ( wc_uleb c ) ( wc_u8 c ) } {
                                                                                                                                                            ? == sub 9 { = bop ( wc_uleb c ) } {
                                                                                                                                                                ? == sub 10 { ( wc_u8 c ) ( wc_u8 c ) } {
                                                                                                                                                                    ? == sub 11 { ( wc_u8 c ) } {
                                                                                                                                                                        ? == sub 12 { = bop ( wc_uleb c ) ( wc_uleb c ) } {
                                                                                                                                                                            ? == sub 13 { = bop ( wc_uleb c ) } {
                                                                                                                                                                                ? == sub 14 { ( wc_uleb c ) ( wc_uleb c ) } {
                                                                                                                                                                                    ? | | == sub 15 == sub 16 == sub 17 { ( wc_uleb c ) } {} } } } } } } }
                                                                                                                                                        ? != 0 live {
                                                                                                                                                            : ~ i pops 0
                                                                                                                                                            : ~ i push 0
                                                                                                                                                            ? <= sub 7 { = pops 1 = push 1 } {
                                                                                                                                                                ? | == sub 8 | == sub 10 | == sub 11 | == sub 12 | == sub 14 == sub 17 { = pops 3 } {
                                                                                                                                                                    ? == sub 15 { = pops 2 = push 1 } {
                                                                                                                                                                        ? == sub 16 { = push 1 } {} } } }
                                                                                                                                                            ( __vflush pf vm SB h live byte )
                                                                                                                                                            ( __pf_emit . pf code ( __R_FCB ) sub bop + SB - h pops | << pops 1 push byte )
                                                                                                                                                            = h + - h pops push
                                                                                                                                                            ? > h maxh { = maxh h } {}
                                                                                                                                                        } {}
                                                                                                                                                    } {
                                                                                                                                                        ? == op 254 {  // 0xfe family (atomics): vs bridge, like 0xfc
                                                                                                                                                            : i asub ( wc_uleb c )
                                                                                                                                                            : ~ i aoff 0
                                                                                                                                                            ? == asub 3 { ( wc_u8 c ) } { ( wc_uleb c ) = aoff ( wc_uleb c ) }
                                                                                                                                                            ? != 0 live {
                                                                                                                                                                : i shape ( __atom_shape asub )
                                                                                                                                                                : i pops >> shape 1
                                                                                                                                                                : i push & shape 1
                                                                                                                                                                ( __vflush pf vm SB h live byte )
                                                                                                                                                                ( __pf_emit . pf code ( __R_ATOM ) asub aoff + SB - h pops | << pops 1 push byte )
                                                                                                                                                                = h + - h pops push
                                                                                                                                                                ? > h maxh { = maxh h } {}
                                                                                                                                                            } {}
                                                                                                                                                        } {
                                                                                                                                                            // unsupported (0xfd and anything unknown): keep alignment,
                                                                                                                                                            // trap if ever executed
                                                                                                                                                            ? == op 253 { ( __skip_imm c op ) } {}
                                                                                                                                                            ? != 0 live { ( __vflush pf vm SB 0 live byte ) ( __pf_emit . pf code ( __R_TRAPUN ) 0 0 0 0 byte ) } {}
                                                                                                                                                        }
                                                                                                                                                    } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } }
        // Arm the fold for the next instruction. Every arm above that is
        // straight-line emitted exactly one record when live, and it is the
        // last one; everything else — control flow, calls, the bridges, the
        // instructions that emit nothing — leaves -1, so no fold can reach
        // across a label or a record that is not a pure producer.
        = lastp ? & != 0 live ( __straightline op ) - / ( vec_len [i] . pf code ) 6 1 -1
    }
    : i on ( vec_len [s] open )
    : ~ i ok 0
    ~ < ok on { ?? ( vec_get [s] open ok ) { T pp → ( __pblk_free pp ) F → {} } = ok + ok 1 }
    ( vec_free [s] open )
    ( vec_free [i] vm )
    ( wc_free c )
    // Past the slot cap the packed operand fields would wrap, so the body is
    // replaced by a single trap: the module still loads and still decodes,
    // and says so cleanly if the function is ever called. The frame is
    // rebuilt to the shape that trap needs and nothing more — room for the
    // arguments the caller copies in, no declared locals to zero and no
    // constant pool to fill, so nothing writes past it.
    ? >= + SB + maxh 4 ( __slot_cap ) {
        ( vec_free [i] . pf code )
        ( vec_free [i] . pf kv )
        = . pf code ( vec_new [i] )
        = . pf kv ( vec_new [i] )
        ( __pf_emit . pf code ( __R_TRAPUN ) 0 0 0 0 . f code_start )
        = . pf count 1
        = . pf nlocals nparams
        = . pf sbase nparams
        = . pf nslots + nparams 4
        = . pf nparams nparams
        = . pf nresults nresults
        = . pf code_start . f code_start
        = . pf pool ( vec_new [s] )
        ^ # s pf
    } {}
    = . pf count / ( vec_len [i] . pf code ) 6
    = . pf nslots + SB + maxh 4
    = . pf nparams nparams
    = . pf nresults nresults
    = . pf code_start . f code_start
    = . pf pool ( vec_new [s] )
    ^ # s pf
}
// Get-or-build the PFunc for defined function `fidx`.
@ __pfunc_for * Interp it * Module m i fidx → s {
    : i di - fidx . m num_import_funcs
    // Bound first: `di` comes from a call record, i.e. straight out of the
    // module, so a hostile index must not be allowed to grow the cache.
    ? | < di 0 >= di ( vec_len [s] . m funcs ) { ^ # s 0 } {}
    ~ <= ( vec_len [s] . it pfuncs ) di { ( vec_push [s] . it pfuncs # s 0 ) }
    : s have ?? ( vec_get [s] . it pfuncs di ) { T x → x F → # s 0 }
    ? != # i have 0 { ^ have } {}
    : s fp ?? ( vec_get [s] . m funcs di ) { T x → x F → # s 0 }
    ? == # i fp 0 { ^ # s 0 } {}
    : *WFunc f # *WFunc fp
    : s built ( __predecode m f )
    ( vec_set [s] . it pfuncs di built )
    ^ built
}

// On trap: append a wasm backtrace (innermost first) to the trap message,
// naming frames from the module's name section when present.
@ __trap_backtrace * Interp it * Module m ( Vec s ) frames → v {
    : ( Vec u ) msg . it trapmsg
    : i n ( vec_len [s] frames )
    : ~ i k - n 1
    : ~ i shown 0
    ~ & >= k 0 < shown 16 {
        : s pp ?? ( vec_get [s] frames k ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *Frame fr # *Frame pp
            ( __msg_push_str msg `\n  at ` )
            : ( Vec u ) nm ( module_func_name m . fr fidx )
            ? > ( vec_len [u] nm ) 0 { ( __msg_push_vec msg nm ) } { ( __msg_push_str msg `<unknown>` ) }
            ( vec_free [u] nm )
            ( __msg_push_str msg ` (func ` )
            ( __msg_push_int msg . fr fidx )
            ( __msg_push_str msg `, +` )
            // fr.pos is a word offset into `code` (6 words per record); the
            // record's BYTE slot maps it back to the module image so the
            // offset stays meaningful against a wasm-objdump of the file.
            // pos can sit one past the last record (fell off the end) —
            // clamp before reading.
            : *PFunc bpf # *PFunc . fr pins
            : ~ i bpos . fr pos
            ? >= bpos * . bpf count 6 { = bpos - * . bpf count 6 6 } {}
            : ~ i boff 0
            ? >= bpos 0 { = boff - ?? ( vec_get [i] . bpf code + bpos 5 ) { T x → x F → . fr code_start } . fr code_start } {}
            ( __msg_push_int msg boff )
            ( __msg_push_str msg `)` )
        } {}
        = shown + shown 1
        = k - k 1
    }
    ? >= k 0 { ( __msg_push_str msg `\n  …` ) } {}
    = . it trapmsg msg
}

@ __msg_push_str ( Vec u ) msg s str → v {
    : i n ( nurl_str_len str )
    : ~ i k 0
    ~ < k n { ( vec_push [u] msg # u ( nurl_str_get str k ) ) = k + k 1 }
}

@ __msg_push_vec ( Vec u ) msg ( Vec u ) src → v {
    : i n ( vec_len [u] src )
    : ~ i k 0
    ~ < k n { ( vec_push [u] msg ?? ( vec_get [u] src k ) { T x → x F → # u 0 } ) = k + k 1 }
}

@ __msg_push_int ( Vec u ) msg i x → v {
    ? < x 0 { ( vec_push [u] msg # u 45 ) ( __msg_push_int msg - 0 x ) ^ v } {}
    ? >= x 10 { ( __msg_push_int msg / x 10 ) } {}
    ( vec_push [u] msg # u + 48 % x 10 )
}

// Execute function `fidx` to completion on an EXPLICIT frame stack — guest
// recursion depth is bounded by max_depth, not by the host's native stack.
// Arguments are already on the value stack; results are left on top.
//
// Two loops, not one. The outer loop owns the frame stack: it loads the top
// frame's bases into registers and, when the inner loop comes back, either
// returns from that frame or picks up the one a call just pushed. The inner
// loop owns the records of a single frame and its condition is one compare —
// everything that has to leave a frame (a call, a return, a trap, exhausted
// fuel) parks the cursor at `pend` and falls out of it. That is what the old
// single loop paid for on *every record*: a `vec_len` on the frame stack, a
// `reload` test, and two byte loads for the trap and exit flags, none of
// which can change between two records of the same basic block.
@ exec_func * Interp it i fidx → v {
    ? != 0 . it halt { ^ v } {}
    : *Module m # *Module . it mod
    // Imported functions occupy the low indices → dispatch to the host (WASI).
    ? < fidx . m num_import_funcs { ( __call_import it m fidx ) ^ v } {}
    : ( Vec s ) frames ( vec_new [s] )
    : s fr0 ( __frame_new it m fidx -1 )
    ? != # i fr0 0 { ( vec_push [s] frames fr0 ) } {}
    // Register-form driver. `pc` is a WORD offset into the frame's record
    // array (6 words per record), so fetching a record is four loads off one
    // index and stepping is one add — branch targets are stored pre-scaled by
    // the predecoder. `rbase` is the raw base of the top frame's flat register
    // array (locals first, stack slots after). Every hot op is three raw word
    // accesses: read operands, write the result. There is no runtime control
    // stack — branches carry their targets and their statically-computed
    // result moves in the record.
    : ~ s tp # s 0
    : ~ * i pbase # *i 0
    : ~ * i rbase # *i 0
    : ~ i pc 0
    : ~ i pend 0
    // Fuel is a plain countdown here, never the sentinel: `-1` (unlimited)
    // becomes a budget nothing can outlive, so the per-instruction cost is
    // `dec` + `js` instead of a load, a zero-test, a conditional decrement
    // and a store. Decrement-then-test still executes exactly `fuel`
    // instructions before trapping, and the sentinel is restored on the
    // way out so the field keeps its public meaning.
    : i fuel0 . it fuel
    : ~ i fuel ? < fuel0 0 4611686018427387904 fuel0
    // 1 once a call has moved the frame stack: the inner loop then ended at
    // a call, not at the end of the body, so there is nothing to return.
    : ~ i tail 0
    ~ & > ( vec_len [s] frames ) 0 == 0 . it halt {
        = tp ?? ( vec_get [s] frames - ( vec_len [s] frames ) 1 ) { T x → x F → # s 0 }
        : *Frame fr # *Frame tp
        : *PFunc npf # *PFunc . fr pins
        = pbase ( vec_data [i] . npf code )
        = rbase ( vec_data [i] . fr regs )
        = pc . fr pos
        = pend . fr end
        = tail 0
        ~ < pc pend {
            : i r0 pc
            = fuel - fuel 1
            ? < fuel 0 { ( __trap it `fuel exhausted` ) = . fr pos r0 = pc pend } {
                : i op . pbase r0
                : i ra . pbase + r0 1
                : i rb . pbase + r0 2
                : i rc . pbase + r0 3
                = pc + pc 6
                // ── the dispatch ──
                // One chain of equality tests on the internal micro-op. The
                // opcodes are numbered so the hot 56 are 0..55: the first 64
                // arms fold into one jump table, and the rest into a second
                // behind it (see `__iop`).
                ? == op 0 { = . rbase ra + . rbase rb . rbase rc } {  // i64.add
                    ? == op 1 { = . rbase ra * . rbase rb . rbase rc } {  // i64.mul
                        ? == op 2 { = . rbase ra & . rbase rb . rbase rc } {  // i64.and
                            ? == op 3 { = . rbase ra ( __lshr64 . rbase rb & . rbase rc 63 ) } {  // i64.shr_u
                                ? == op 4 { = . rbase ra ^^ . rbase rb . rbase rc } {  // i64.xor
                                    ? == op 5 { = . rbase ra - . rbase rb . rbase rc } {  // i64.sub
                                        ? == op 6 { = . rbase ra >> . rbase rb & . rbase rc 63 } {  // i64.shr_s
                                            ? == op 7 { = . rbase ra | . rbase rb . rbase rc } {  // i64.or
                                                ? == op 8 { = . rbase ra << . rbase rb & . rbase rc 63 } {  // i64.shl
                                                    ? == op 9 { = . rbase ra ( __w32 + . rbase rb . rbase rc ) } {  // i32.add
                                                        ? == op 10 { = . rbase ra ( __w32 << . rbase rb & . rbase rc 31 ) } {  // i32.shl
                                                            ? == op 11 { = . rbase ra ( __w32 & . rbase rb . rbase rc ) } {  // i32.and
                                                                ? == op 12 { = . rbase ra ( __w32 >> ( __u32 . rbase rb ) & . rbase rc 31 ) } {  // i32.shr_u
                                                                    ? == op 13 { = . rbase ra ( __w32 - . rbase rb . rbase rc ) } {  // i32.sub
                                                                        ? == op 14 { = . rbase ra ( __w32 | . rbase rb . rbase rc ) } {  // i32.or
                                                                            ? == op 15 { = . rbase ra ( __w32 ^^ . rbase rb . rbase rc ) } {  // i32.xor
                                                                                ? == op 16 { = . rbase ra ( __w32 >> ( __w32 . rbase rb ) & . rbase rc 31 ) } {  // i32.shr_s
                                                                                    ? == op 17 { = . rbase ra ( __w32 * . rbase rb . rbase rc ) } {  // i32.mul
                                                                                        ? == op 18 { = . rbase ra ( __mem_load it + & + . rbase rb . rbase . pbase + r0 4 4294967295 rc 8 0 ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // i64.load
                                                                                            ? == op 19 { = . rbase ra ( __mem_load it + & + . rbase rb . rbase . pbase + r0 4 4294967295 rc 8 0 ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // f64.load
                                                                                                ? == op 20 { = . rbase ra ( __w32 ( __mem_load it + & + . rbase rb . rbase . pbase + r0 4 4294967295 rc 4 0 ) ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // i32.load
                                                                                                    ? == op 21 { = . rbase ra ( __mem_load it + & + . rbase rb . rbase . pbase + r0 4 4294967295 rc 1 0 ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // i32.load8_u
                                                                                                        ? == op 22 { = . rbase ra ( __mem_load it + & + . rbase rb . rbase . pbase + r0 4 4294967295 rc 4 0 ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // i64.load32_u
                                                                                                            ? == op 23 { = . rbase ra ( __mem_load it + & + . rbase rb . rbase . pbase + r0 4 4294967295 rc 2 0 ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // i32.load16_u
                                                                                                                ? == op 24 { = . rbase ra ( __mem_load it + & + . rbase rb . rbase . pbase + r0 4 4294967295 rc 4 0 ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // f32.load
                                                                                                                    ? == op 25 { = . rbase ra ( __mem_load it + & + . rbase rb . rbase . pbase + r0 4 4294967295 rc 1 0 ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // i64.load8_u
                                                                                                                        ? == op 26 { = . rbase ra ( __mem_load it + & + . rbase rb . rbase . pbase + r0 4 4294967295 rc 2 0 ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // i64.load16_u
                                                                                                                            ? == op 27 { ( __mem_store it + & . rbase ra 4294967295 rc 8 . rbase rb ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // i64.store
                                                                                                                                ? == op 28 { ( __mem_store it + & . rbase ra 4294967295 rc 8 . rbase rb ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // f64.store
                                                                                                                                    ? == op 29 { ( __mem_store it + & . rbase ra 4294967295 rc 1 . rbase rb ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // i32.store8
                                                                                                                                        ? == op 30 { ( __mem_store it + & . rbase ra 4294967295 rc 4 . rbase rb ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // i32.store
                                                                                                                                            ? == op 31 { ( __mem_store it + & . rbase ra 4294967295 rc 4 . rbase rb ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // f32.store
                                                                                                                                                ? == op 32 { ( __mem_store it + & . rbase ra 4294967295 rc 4 . rbase rb ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // i64.store32
                                                                                                                                                    ? == op 33 { ( __mem_store it + & . rbase ra 4294967295 rc 2 . rbase rb ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // i32.store16
                                                                                                                                                        ? == op 34 { ( __mem_store it + & . rbase ra 4294967295 rc 1 . rbase rb ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // i64.store8
                                                                                                                                                            ? == op 35 { ( __mem_store it + & . rbase ra 4294967295 rc 2 . rbase rb ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // i64.store16
                                                                                                                                                                ? == op 36 { = . rbase ra ( __w32 . rbase rb ) } {  // i32.wrap_i64
                                                                                                                                                                    ? == op 37 { = . rbase ra & . rbase rb 4294967295 } {  // i64.extend_i32_u
                                                                                                                                                                        ? == op 38 { = . rbase ra ( __w32 . rbase rb ) } {  // i64.extend_i32_s
                                                                                                                                                                            ? == op 39 { = . rbase ra ( f64_to_bits * ( bits_to_f64 . rbase rb ) ( bits_to_f64 . rbase rc ) ) } {  // f64.mul
                                                                                                                                                                                ? == op 40 { = . rbase ra ( f64_to_bits + ( bits_to_f64 . rbase rb ) ( bits_to_f64 . rbase rc ) ) } {  // f64.add
                                                                                                                                                                                    ? == op 41 { = . rbase ra ( f64_to_bits - ( bits_to_f64 . rbase rb ) ( bits_to_f64 . rbase rc ) ) } {  // f64.sub
                                                                                                                                                                                        ? == op 42 { = . rbase ra ( f64_to_bits / ( bits_to_f64 . rbase rb ) ( bits_to_f64 . rbase rc ) ) } {  // f64.div
                                                                                                                                                                                            ? == op 43 { = . rbase ra ? == . rbase rb 0 1 0 } {  // i32.eqz
                                                                                                                                                                                                ? == op 44 { = . rbase ra ? == . rbase rb 0 1 0 } {  // i64.eqz
                                                                                                                                                                                                    ? == op 45 { ? != 0 ( __rcmp . pbase + r0 4 . rbase rb . rbase rc ) { = pc ra } {} } {  // __R_BRIFC
                                                                                                                                                                                                        ? == op 46 {  // __R_SEL
                                                                                                                                                                                                            : i cond . rbase . pbase + r0 4
                                                                                                                                                                                                            = . rbase ra ? != cond 0 . rbase rb . rbase rc
                                                                                                                                                                                                        } {
                                                                                                                                                                                                            ? == op 47 { = . rbase ra . rbase rb } {  // __R_MOV
                                                                                                                                                                                                                ? == op 48 { ? == . rbase rb 0 { = pc ra } {} } {  // __R_IFZ
                                                                                                                                                                                                                    ? == op 49 { = pc ra } {  // __R_BR
                                                                                                                                                                                                                        ? == op 50 {  // __R_CALL
                                                                                                                                                                                                                            = . fr pos pc
                                                                                                                                                                                                                            ( __rdo_call it m frames ra rb rbase )
                                                                                                                                                                                                                            = tail 1
                                                                                                                                                                                                                            = pc pend
                                                                                                                                                                                                                            ? != 0 . it halt { = . fr pos r0 } {}
                                                                                                                                                                                                                        } {
                                                                                                                                                                                                                            ? == op 51 { = . rbase ra rb } {  // __R_CONST
                                                                                                                                                                                                                                ? == op 52 { = . rbase ra ?? ( vec_get [i] . it globals rb ) { T x → x F → 0 } } {  // __R_GG
                                                                                                                                                                                                                                    ? == op 53 { ( vec_set [i] . it globals ra . rbase rb ) } {  // __R_GS
                                                                                                                                                                                                                                        ? == op 54 { ? != . rbase rb 0 { = pc ra } {} } {  // __R_BRIF
                                                                                                                                                                                                                                            ? == op 55 {  // __R_RET
                                                                                                                                                                                                                                                : *PFunc rpf # *PFunc . fr pins
                                                                                                                                                                                                                                                : i lloc . rpf sbase
                                                                                                                                                                                                                                                : ~ i rk 0
                                                                                                                                                                                                                                                ~ < rk rb { = . rbase + lloc rk . rbase + ra rk = rk + rk 1 }
                                                                                                                                                                                                                                                = pc pend
                                                                                                                                                                                                                                            } {
                                                                                                                                                                                                                                                ? == op 56 { = . rbase ra ? == ( __w32 . rbase rb ) ( __w32 . rbase rc ) 1 0 } {  // i32.eq
                                                                                                                                                                                                                                                    ? == op 57 { = . rbase ra ? != ( __w32 . rbase rb ) ( __w32 . rbase rc ) 1 0 } {  // i32.ne
                                                                                                                                                                                                                                                        ? == op 58 { = . rbase ra ? < ( __w32 . rbase rb ) ( __w32 . rbase rc ) 1 0 } {  // i32.lt_s
                                                                                                                                                                                                                                                            ? == op 59 { = . rbase ra ? < ( __u32 . rbase rb ) ( __u32 . rbase rc ) 1 0 } {  // i32.lt_u
                                                                                                                                                                                                                                                                ? == op 60 { = . rbase ra ? > ( __w32 . rbase rb ) ( __w32 . rbase rc ) 1 0 } {  // i32.gt_s
                                                                                                                                                                                                                                                                    ? == op 61 { = . rbase ra ? > ( __u32 . rbase rb ) ( __u32 . rbase rc ) 1 0 } {  // i32.gt_u
                                                                                                                                                                                                                                                                        ? == op 62 { = . rbase ra ? <= ( __w32 . rbase rb ) ( __w32 . rbase rc ) 1 0 } {  // i32.le_s
                                                                                                                                                                                                                                                                            ? == op 63 { = . rbase ra ? <= ( __u32 . rbase rb ) ( __u32 . rbase rc ) 1 0 } {  // i32.le_u
                                                                                                                                                                                                                                                                                ? == op 64 { = . rbase ra ? >= ( __w32 . rbase rb ) ( __w32 . rbase rc ) 1 0 } {  // i32.ge_s
                                                                                                                                                                                                                                                                                    ? == op 65 { = . rbase ra ? >= ( __u32 . rbase rb ) ( __u32 . rbase rc ) 1 0 } {  // i32.ge_u
                                                                                                                                                                                                                                                                                        ? == op 66 { = . rbase ra ? == . rbase rb . rbase rc 1 0 } {  // i64.eq
                                                                                                                                                                                                                                                                                            ? == op 67 { = . rbase ra ? != . rbase rb . rbase rc 1 0 } {  // i64.ne
                                                                                                                                                                                                                                                                                                ? == op 68 { = . rbase ra ? < . rbase rb . rbase rc 1 0 } {  // i64.lt_s
                                                                                                                                                                                                                                                                                                    ? == op 69 { = . rbase ra ? ( __ultb . rbase rb . rbase rc ) 1 0 } {  // i64.lt_u
                                                                                                                                                                                                                                                                                                        ? == op 70 { = . rbase ra ? > . rbase rb . rbase rc 1 0 } {  // i64.gt_s
                                                                                                                                                                                                                                                                                                            ? == op 71 { = . rbase ra ? ( __ultb . rbase rc . rbase rb ) 1 0 } {  // i64.gt_u
                                                                                                                                                                                                                                                                                                                ? == op 72 { = . rbase ra ? <= . rbase rb . rbase rc 1 0 } {  // i64.le_s
                                                                                                                                                                                                                                                                                                                    ? == op 73 { = . rbase ra ? ! ( __ultb . rbase rc . rbase rb ) 1 0 } {  // i64.le_u
                                                                                                                                                                                                                                                                                                                        ? == op 74 { = . rbase ra ? >= . rbase rb . rbase rc 1 0 } {  // i64.ge_s
                                                                                                                                                                                                                                                                                                                            ? == op 75 { = . rbase ra ? ! ( __ultb . rbase rb . rbase rc ) 1 0 } {  // i64.ge_u
                                                                                                                                                                                                                                                                                                                                ? == op 76 { = . rbase ra ( __w32 ( __mem_load it + & + . rbase rb . rbase . pbase + r0 4 4294967295 rc 1 1 ) ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // i32.load8_s
                                                                                                                                                                                                                                                                                                                                    ? == op 77 { = . rbase ra ( __w32 ( __mem_load it + & + . rbase rb . rbase . pbase + r0 4 4294967295 rc 2 1 ) ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // i32.load16_s
                                                                                                                                                                                                                                                                                                                                        ? == op 78 { = . rbase ra ( __mem_load it + & + . rbase rb . rbase . pbase + r0 4 4294967295 rc 1 1 ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // i64.load8_s
                                                                                                                                                                                                                                                                                                                                            ? == op 79 { = . rbase ra ( __mem_load it + & + . rbase rb . rbase . pbase + r0 4 4294967295 rc 2 1 ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // i64.load16_s
                                                                                                                                                                                                                                                                                                                                                ? == op 80 { = . rbase ra ( __mem_load it + & + . rbase rb . rbase . pbase + r0 4 4294967295 rc 4 1 ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // i64.load32_s
                                                                                                                                                                                                                                                                                                                                                    ? == op 81 { = . rbase ra ( __f32_cmp 91 . rbase rb . rbase rc ) } {  // f32.eq
                                                                                                                                                                                                                                                                                                                                                        ? == op 82 { = . rbase ra ( __f32_cmp 92 . rbase rb . rbase rc ) } {  // f32.ne
                                                                                                                                                                                                                                                                                                                                                            ? == op 83 { = . rbase ra ( __f32_cmp 93 . rbase rb . rbase rc ) } {  // f32.lt
                                                                                                                                                                                                                                                                                                                                                                ? == op 84 { = . rbase ra ( __f32_cmp 94 . rbase rb . rbase rc ) } {  // f32.gt
                                                                                                                                                                                                                                                                                                                                                                    ? == op 85 { = . rbase ra ( __f32_cmp 95 . rbase rb . rbase rc ) } {  // f32.le
                                                                                                                                                                                                                                                                                                                                                                        ? == op 86 { = . rbase ra ( __f32_cmp 96 . rbase rb . rbase rc ) } {  // f32.ge
                                                                                                                                                                                                                                                                                                                                                                            ? == op 87 { = . rbase ra ( __f64_cmp 97 . rbase rb . rbase rc ) } {  // f64.eq
                                                                                                                                                                                                                                                                                                                                                                                ? == op 88 { = . rbase ra ( __f64_cmp 98 . rbase rb . rbase rc ) } {  // f64.ne
                                                                                                                                                                                                                                                                                                                                                                                    ? == op 89 { = . rbase ra ( __f64_cmp 99 . rbase rb . rbase rc ) } {  // f64.lt
                                                                                                                                                                                                                                                                                                                                                                                        ? == op 90 { = . rbase ra ( __f64_cmp 100 . rbase rb . rbase rc ) } {  // f64.gt
                                                                                                                                                                                                                                                                                                                                                                                            ? == op 91 { = . rbase ra ( __f64_cmp 101 . rbase rb . rbase rc ) } {  // f64.le
                                                                                                                                                                                                                                                                                                                                                                                                ? == op 92 { = . rbase ra ( __f64_cmp 102 . rbase rb . rbase rc ) } {  // f64.ge
                                                                                                                                                                                                                                                                                                                                                                                                    ? == op 93 { = . rbase ra ( __runary 103 . rbase rb ) } {  // i32.clz
                                                                                                                                                                                                                                                                                                                                                                                                        ? == op 94 { = . rbase ra ( __runary 104 . rbase rb ) } {  // i32.ctz
                                                                                                                                                                                                                                                                                                                                                                                                            ? == op 95 { = . rbase ra ( __runary 105 . rbase rb ) } {  // i32.popcnt
                                                                                                                                                                                                                                                                                                                                                                                                                ? == op 96 { = . rbase ra ( __rdiv it 109 . rbase rb . rbase rc ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // i32.div_s
                                                                                                                                                                                                                                                                                                                                                                                                                    ? == op 97 { = . rbase ra ( __rdiv it 110 . rbase rb . rbase rc ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // i32.div_u
                                                                                                                                                                                                                                                                                                                                                                                                                        ? == op 98 { = . rbase ra ( __rdiv it 111 . rbase rb . rbase rc ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // i32.rem_s
                                                                                                                                                                                                                                                                                                                                                                                                                            ? == op 99 { = . rbase ra ( __rdiv it 112 . rbase rb . rbase rc ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // i32.rem_u
                                                                                                                                                                                                                                                                                                                                                                                                                                ? == op 100 { = . rbase ra ( __rotl32 . rbase rb . rbase rc ) } {  // i32.rotl
                                                                                                                                                                                                                                                                                                                                                                                                                                    ? == op 101 { = . rbase ra ( __rotr32 . rbase rb . rbase rc ) } {  // i32.rotr
                                                                                                                                                                                                                                                                                                                                                                                                                                        ? == op 102 { = . rbase ra ( __runary 121 . rbase rb ) } {  // i64.clz
                                                                                                                                                                                                                                                                                                                                                                                                                                            ? == op 103 { = . rbase ra ( __runary 122 . rbase rb ) } {  // i64.ctz
                                                                                                                                                                                                                                                                                                                                                                                                                                                ? == op 104 { = . rbase ra ( __runary 123 . rbase rb ) } {  // i64.popcnt
                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? == op 105 { = . rbase ra ( __rdiv it 127 . rbase rb . rbase rc ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // i64.div_s
                                                                                                                                                                                                                                                                                                                                                                                                                                                        ? == op 106 { = . rbase ra ( __rdiv it 128 . rbase rb . rbase rc ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // i64.div_u
                                                                                                                                                                                                                                                                                                                                                                                                                                                            ? == op 107 { = . rbase ra ( __rdiv it 129 . rbase rb . rbase rc ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // i64.rem_s
                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? == op 108 { = . rbase ra ( __rdiv it 130 . rbase rb . rbase rc ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // i64.rem_u
                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? == op 109 { = . rbase ra ( __rotl64 . rbase rb . rbase rc ) } {  // i64.rotl
                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ? == op 110 { = . rbase ra ( __rotr64 . rbase rb . rbase rc ) } {  // i64.rotr
                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ? == op 111 { = . rbase ra ( __f32_unary 139 . rbase rb ) } {  // f32.abs
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? == op 112 { = . rbase ra ( __f32_unary 140 . rbase rb ) } {  // f32.neg
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? == op 113 { = . rbase ra ( __f32_unary 141 . rbase rb ) } {  // f32.ceil
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ? == op 114 { = . rbase ra ( __f32_unary 142 . rbase rb ) } {  // f32.floor
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ? == op 115 { = . rbase ra ( __f32_unary 143 . rbase rb ) } {  // f32.trunc
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? == op 116 { = . rbase ra ( __f32_unary 144 . rbase rb ) } {  // f32.nearest
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? == op 117 { = . rbase ra ( __f32_unary 145 . rbase rb ) } {  // f32.sqrt
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ? == op 118 { = . rbase ra ( __f32_binary 146 . rbase rb . rbase rc ) } {  // f32.add
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ? == op 119 { = . rbase ra ( __f32_binary 147 . rbase rb . rbase rc ) } {  // f32.sub
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? == op 120 { = . rbase ra ( __f32_binary 148 . rbase rb . rbase rc ) } {  // f32.mul
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? == op 121 { = . rbase ra ( __f32_binary 149 . rbase rb . rbase rc ) } {  // f32.div
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ? == op 122 { = . rbase ra ( __f32_binary 150 . rbase rb . rbase rc ) } {  // f32.min
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ? == op 123 { = . rbase ra ( __f32_binary 151 . rbase rb . rbase rc ) } {  // f32.max
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? == op 124 { = . rbase ra ( __f32_binary 152 . rbase rb . rbase rc ) } {  // f32.copysign
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? == op 125 { = . rbase ra & . rbase rb 9223372036854775807 } {  // f64.abs
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ? == op 126 { = . rbase ra ^^ . rbase rb -9223372036854775808 } {  // f64.neg
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ? == op 127 { = . rbase ra ( __f64_unary 155 . rbase rb ) } {  // f64.ceil
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? == op 128 { = . rbase ra ( __f64_unary 156 . rbase rb ) } {  // f64.floor
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? == op 129 { = . rbase ra ( __f64_unary 157 . rbase rb ) } {  // f64.trunc
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ? == op 130 { = . rbase ra ( __f64_unary 158 . rbase rb ) } {  // f64.nearest
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ? == op 131 { = . rbase ra ( f64_to_bits ( sqrt ( bits_to_f64 . rbase rb ) ) ) } {  // f64.sqrt
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? == op 132 { = . rbase ra ( __f64_binary 164 . rbase rb . rbase rc ) } {  // f64.min
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? == op 133 { = . rbase ra ( __f64_binary 165 . rbase rb . rbase rc ) } {  // f64.max
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ? == op 134 { = . rbase ra ( __f64_binary 166 . rbase rb . rbase rc ) } {  // f64.copysign
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ? == op 135 { = . rbase ra ( __convert it 168 . rbase rb ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // i32.trunc_f32_s
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? == op 136 { = . rbase ra ( __convert it 169 . rbase rb ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // i32.trunc_f32_u
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? == op 137 { = . rbase ra ( __convert it 170 . rbase rb ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // i32.trunc_f64_s
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ? == op 138 { = . rbase ra ( __convert it 171 . rbase rb ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // i32.trunc_f64_u
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ? == op 139 { = . rbase ra ( __convert it 174 . rbase rb ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // i64.trunc_f32_s
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? == op 140 { = . rbase ra ( __convert it 175 . rbase rb ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // i64.trunc_f32_u
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? == op 141 { = . rbase ra ( __convert it 176 . rbase rb ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // i64.trunc_f64_s
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ? == op 142 { = . rbase ra ( __convert it 177 . rbase rb ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // i64.trunc_f64_u
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ? == op 143 { = . rbase ra ( __convert it 178 . rbase rb ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // f32.convert_i32_s
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? == op 144 { = . rbase ra ( __convert it 179 . rbase rb ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // f32.convert_i32_u
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? == op 145 { = . rbase ra ( __convert it 180 . rbase rb ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // f32.convert_i64_s
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ? == op 146 { = . rbase ra ( __convert it 181 . rbase rb ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // f32.convert_i64_u
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ? == op 147 { = . rbase ra ( __convert it 182 . rbase rb ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // f32.demote_f64
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? == op 148 { = . rbase ra ( __convert it 183 . rbase rb ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // f64.convert_i32_s
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? == op 149 { = . rbase ra ( __convert it 184 . rbase rb ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // f64.convert_i32_u
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ? == op 150 { = . rbase ra ( __convert it 185 . rbase rb ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // f64.convert_i64_s
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ? == op 151 { = . rbase ra ( __convert it 186 . rbase rb ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // f64.convert_i64_u
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? == op 152 { = . rbase ra ( __convert it 187 . rbase rb ) ? != 0 . it halt { = . fr pos r0 = pc pend } {} } {  // f64.promote_f32
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? == op 153 { = . rbase ra . rbase rb } {  // i32.reinterpret_f32
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ? == op 154 { = . rbase ra . rbase rb } {  // i64.reinterpret_f64
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ? == op 155 { = . rbase ra . rbase rb } {  // f32.reinterpret_i32
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? == op 156 { = . rbase ra . rbase rb } {  // f64.reinterpret_i64
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? == op 157 { = . rbase ra ( __runary 192 . rbase rb ) } {  // i32.extend8_s
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ? == op 158 { = . rbase ra ( __runary 193 . rbase rb ) } {  // i32.extend16_s
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ? == op 159 { = . rbase ra ( __runary 194 . rbase rb ) } {  // i64.extend8_s
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? == op 160 { = . rbase ra ( __runary 195 . rbase rb ) } {  // i64.extend16_s
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? == op 161 { = . rbase ra ( __runary 196 . rbase rb ) } {  // i64.extend32_s
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ? == op 162 { = . rbase ra . it mem_pages } {  // __R_MEMSZ
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ? == op 163 { = . rbase ra ( __mem_grow it ( __u32 . rbase rb ) ) } {  // __R_MEMGROW
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? == op 164 {  // __R_TABGET
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    : i ei ( __u32 . rbase rb )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? >= ei ( vec_len [i] . it table ) { ( __trap it `out of bounds table access` ) = . fr pos r0 = pc pend } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        = . rbase ra ?? ( vec_get [i] . it table ei ) { T x → x F → -1 } }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? == op 165 {  // __R_TABSET
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        : i ei ( __u32 . rbase ra )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ? >= ei ( vec_len [i] . it table ) { ( __trap it `out of bounds table access` ) = . fr pos r0 = pc pend } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ( vec_set [i] . it table ei . rbase rb ) }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ? == op 166 { = . rbase ra ? == . rbase rb -1 1 0 } {  // __R_ISNULL
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ? == op 167 {  // __R_BRM
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                : i dd . pbase + r0 4
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                : ~ i mk 0
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ~ < mk dd { = . rbase + rb mk . rbase + rc mk = mk + mk 1 }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                = pc ra
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? == op 168 {  // __R_BRIFM
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? != . rbase rb 0 {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        : i dd . pbase + r0 4
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        : i mdst >> rc 20
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        : i msrc & rc 1048575
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        : ~ i mk 0
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ~ < mk dd { = . rbase + mdst mk . rbase + msrc mk = mk + mk 1 }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        = pc ra
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    } {}
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? == op 169 {  // __R_BRTBL
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        : *PFunc tpf # *PFunc . fr pins
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        : *i abase ( vec_data [i] . tpf aux )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        : i ui ( __u32 . rbase rb )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        : i pick ? < ui rc ui rc
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        : i rowb + ra * pick 4
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        : i tgt . abase rowb
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        : i mdst . abase + rowb 1
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        : i msrc . abase + rowb 2
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        : i mn . abase + rowb 3
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        : ~ i mk 0
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ~ < mk mn { = . rbase + mdst mk . rbase + msrc mk = mk + mk 1 }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        = pc tgt
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ? == op 170 {  // __R_CALLIND
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            : i ei & . rbase rc 4294967295
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ? | < ei 0 >= ei ( vec_len [i] . it table ) { ( __trap it `call_indirect: index out of range` ) = . fr pos r0 = pc pend } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                : i cfi ?? ( vec_get [i] . it table ei ) { T x → x F → -1 }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? < cfi 0 { ( __trap it `call_indirect: null table element` ) = . fr pos r0 = pc pend } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    : s want ?? ( vec_get [s] . m types ra ) { T x → x F → # s 0 }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    : s have ( module_func_type m cfi )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? | == # i want 0 == # i have 0 { ( __trap it `call_indirect: bad type index` ) = . fr pos r0 = pc pend } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ? ! ( functype_eq # *FuncType want # *FuncType have ) { ( __trap it `call_indirect: signature mismatch` ) = . fr pos r0 = pc pend } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            = . fr pos pc
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ( __rdo_call it m frames cfi rb rbase )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            = tail 1
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            = pc pend
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ? != 0 . it halt { = . fr pos r0 } {}
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ? == op 171 {  // __R_FCB
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                : i dd . pbase + r0 4
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                : i pops >> dd 1
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                : ~ i bk 0
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ~ < bk pops { ( __push it . rbase + rc bk ) = bk + bk 1 }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ( __exec_fc it ra rb )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? & != 0 & dd 1 ! ( interp_trapped it ) { = . rbase rc ( __pop it ) } {}
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? != 0 . it halt { = . fr pos r0 = pc pend } {}
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? == op 174 {  // __R_ATOM
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    : i dd . pbase + r0 4
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    : i pops >> dd 1
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    : ~ i bk 0
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ~ < bk pops { ( __push it . rbase + rc bk ) = bk + bk 1 }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ( __exec_atomic it ra rb )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? & != 0 & dd 1 ! ( interp_trapped it ) { = . rbase rc ( __pop it ) } {}
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? != 0 . it halt { = . fr pos r0 = pc pend } {}
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? == op 172 { ( __trap it `unreachable` ) = . fr pos r0 = pc pend } {  // __R_UNREACH
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ? == op 173 { ( __trap it `unsupported opcode` ) = . fr pos r0 = pc pend } {  // __R_TRAPUN
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ( __trap it `unsupported opcode` ) = . fr pos r0 = pc pend
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                    } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } }
                                                                                                                                                                                                                                                                                                                                    } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } }
                                                                                                                                                                                                    } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } }
                                                                    } } } } } } } } } } } } } }
            }
        }
        ? & == tail 0 == 0 . it halt {
            // fell off the end → return: results sit at slots lloc.. by
            // construction (the body ends at height = result count)
            // `sbase` / `nresults` are read from the frame being left rather
            // than carried in the driver: two loads on a frame transition
            // instead of two registers held across every record.
            : *PFunc dpf # *PFunc . fr pins
            : i lloc . dpf sbase
            : i nres . dpf nresults
            : i rdst . fr ret_dst
            ( vec_pop [s] frames )
            ? < rdst 0 {
                // outermost frame: results leave on the value stack
                : ~ i rk 0
                ~ < rk nres { ( __push it . rbase + lloc rk ) = rk + rk 1 }
            } {
                : s cp2 ?? ( vec_get [s] frames - ( vec_len [s] frames ) 1 ) { T x → x F → # s 0 }
                ? != # i cp2 0 {
                    : *Frame cfr # *Frame cp2
                    : *i crb ( vec_data [i] . cfr regs )
                    : ~ i rk 0
                    ~ < rk nres { = . crb + rdst rk . rbase + lloc rk = rk + rk 1 }
                } {}
            }
            ( __frame_recycle tp )
        } {}
    }
    ? ( interp_trapped it ) { ( __trap_backtrace it m frames ) } {}
    : i fn ( vec_len [s] frames )
    : ~ i fi 0
    ~ < fi fn { ?? ( vec_get [s] frames fi ) { T pp → ( __frame_free pp ) F → {} } = fi + fi 1 }
    ( vec_free [s] frames )
    = . it fuel ? < fuel0 0 -1 ? < fuel 0 0 fuel
}

// Perform a call from the register driver: `argbase` is the caller slot of
// the first argument (and the destination of the results). Imports bridge
// through the value stack; defined functions get a fresh frame with the
// arguments copied straight into their first locals.
@ __rdo_call * Interp it * Module m ( Vec s ) frames i callee i argbase * i caller_rbase → v {
    ? < callee . m num_import_funcs {
        : s wt ( module_func_type m callee )
        : ~ i np 0
        : ~ i nr 0
        ? != # i wt 0 { : *FuncType wft # *FuncType wt = np ( vec_len [i] . wft params ) = nr ( vec_len [i] . wft results ) } {}
        : ~ i ak 0
        ~ < ak np { ( __push it . caller_rbase + argbase ak ) = ak + ak 1 }
        ( __call_import it m callee )
        ? ! ( interp_trapped it ) {
            : ~ i rk nr
            ~ > rk 0 { = rk - rk 1 = . caller_rbase + argbase rk ( __pop it ) }
        } {}
        ^ v
    } {}
    ? >= ( vec_len [s] frames ) . it max_depth { ( __trap it `call stack exhausted` ) ^ v } {}
    : s nf ( __frame_new it m callee argbase )
    ? == # i nf 0 { ^ v } {}
    : *Frame nfr # *Frame nf
    : *i nrb ( vec_data [i] . nfr regs )
    : *PFunc npf # *PFunc . nfr pins
    : i np . npf nparams
    : ~ i ak 0
    ~ < ak np { = . nrb ak . caller_rbase + argbase ak = ak + ak 1 }
    ( vec_push [s] frames nf )
}

// The integer arithmetic that traps: i32 div/rem (0x6d..0x70) and i64
// div/rem (0x7f..0x82). The twenty-two that cannot trap are written out in
// the driver arm itself — they need neither `it` nor the halt test after
// them, and keeping the interpreter pointer dead across them leaves a
// register for the frame's slot base. `op` here is the wasm opcode: each
// arm passes its own literal, so the arm keeps only the one branch it
// needs.
@ __rdiv * Interp it i op i a i b → i {
    ? == op 127 { ^ ( __div_s it a b -9223372036854775808 ) } {}
    ? == op 128 { ? == b 0 { ( __trap it `integer divide by zero` ) ^ 0 } {} ^ ( __udiv64 a b ) } {}  // i64.div_u
    ? == op 129 { ^ ( __rem_s it a b ) } {}
    ? == op 130 { ? == b 0 { ( __trap it `integer divide by zero` ) ^ 0 } {} ^ ( __urem64 a b ) } {}  // i64.rem_u
    ? == op 109 { ^ ( __w32 ( __div_s it ( __w32 a ) ( __w32 b ) -2147483648 ) ) } {}
    ? == op 110 { ^ ( __w32 ( __div_u it ( __u32 a ) ( __u32 b ) ) ) } {}  // i32.div_u
    ? == op 111 { ^ ( __w32 ( __rem_s it ( __w32 a ) ( __w32 b ) ) ) } {}
    ^ ( __w32 ( __rem_u it ( __u32 a ) ( __u32 b ) ) )  // 112 i32.rem_u
}

@ __rcmp i op i a i b → i {  // the internal compare codes, i32 then i64 → 0/1
    ? == op 56 { ^ ? == ( __w32 a ) ( __w32 b ) 1 0 } {}
    ? == op 57 { ^ ? != ( __w32 a ) ( __w32 b ) 1 0 } {}
    ? == op 58 { ^ ? < ( __w32 a ) ( __w32 b ) 1 0 } {}
    ? == op 59 { ^ ? < ( __u32 a ) ( __u32 b ) 1 0 } {}  // lt_u
    ? == op 60 { ^ ? > ( __w32 a ) ( __w32 b ) 1 0 } {}
    ? == op 61 { ^ ? > ( __u32 a ) ( __u32 b ) 1 0 } {}  // gt_u
    ? == op 62 { ^ ? <= ( __w32 a ) ( __w32 b ) 1 0 } {}
    ? == op 63 { ^ ? <= ( __u32 a ) ( __u32 b ) 1 0 } {}  // le_u
    ? == op 64 { ^ ? >= ( __w32 a ) ( __w32 b ) 1 0 } {}
    ? == op 65 { ^ ? >= ( __u32 a ) ( __u32 b ) 1 0 } {}  // ge_u
    ? == op 66 { ^ ? == a b 1 0 } {}
    ? == op 67 { ^ ? != a b 1 0 } {}
    ? == op 68 { ^ ? < a b 1 0 } {}
    ? == op 69 { ^ ? ( __ultb a b ) 1 0 } {}  // lt_u
    ? == op 70 { ^ ? > a b 1 0 } {}
    ? == op 71 { ^ ? ( __ultb b a ) 1 0 } {}  // gt_u
    ? == op 72 { ^ ? <= a b 1 0 } {}
    ? == op 73 { ^ ? ! ( __ultb b a ) 1 0 } {}  // le_u
    ? == op 74 { ^ ? >= a b 1 0 } {}
    ^ ? ! ( __ultb a b ) 1 0  // 90 ge_u
}

@ __runary i op i x → i {  // clz/ctz/popcnt + sign extensions
    ? == op 103 { ^ ( __clz32 x ) } {}
    ? == op 104 { ^ ( __ctz32 x ) } {}
    ? == op 105 { ^ ( __popc32 x ) } {}
    ? == op 121 { ^ ( __clz64 x ) } {}
    ? == op 122 { ^ ( __ctz64 x ) } {}
    ? == op 123 { ^ ( __popc64 x ) } {}
    ? == op 192 { ^ ( __w32 ( __sext x 8 ) ) } {}  // i32.extend8_s
    ? == op 193 { ^ ( __w32 ( __sext x 16 ) ) } {}  // i32.extend16_s
    ? == op 194 { ^ ( __sext x 8 ) } {}  // i64.extend8_s
    ? == op 195 { ^ ( __sext x 16 ) } {}  // i64.extend16_s
    ^ ( __sext x 32 )  // 196 i64.extend32_s
}

// ── floats (values held as their IEEE-754 bit pattern in the i64 cell) ──
// abs/neg/copysign are done on the bits (NaN-sign correct); the rest reinterpret
// via std/floatbits, compute with libm / native float arithmetic, and re-encode.
//
// Value form, exactly like the integer core: operands in, result bits out.
// These used to be stack form, reached through a record that copied the
// operands from slots onto `it.vs` and the result back — two `vec_push`, a
// `vec_pop` and a second dispatch level per float instruction, plus the
// operand flush the bridge forced on every `local.get` feeding it. On the
// benchmark corpus that bridge was 5 % of all records dispatched and the
// flush it forced was most of another 30 %; nbody spent 45 % of its records
// moving values into place for it.

@ __f64_unary i op i ab → i {
    ? == op 153 { ^ & ab 9223372036854775807 } {}  // f64.abs (clear sign)
    ? == op 154 { ^ ^^ ab -9223372036854775808 } {}  // f64.neg (flip sign)
    : f x ( bits_to_f64 ab )
    ? == op 155 { ^ ( f64_to_bits ( ceil x ) ) } {}  // f64.ceil
    ? == op 156 { ^ ( f64_to_bits ( floor x ) ) } {}  // f64.floor
    ? == op 157 { ^ ( f64_to_bits ( trunc x ) ) } {}  // f64.trunc
    ? == op 158 { ^ ( f64_to_bits ( rint x ) ) } {}  // f64.nearest
    ^ ( f64_to_bits ( sqrt x ) )  // 159 f64.sqrt
}

@ __f64_binary i op i ab i bb → i {
    ? == op 166 { ^ | & ab 9223372036854775807 & bb -9223372036854775808 } {}  // copysign
    : f a ( bits_to_f64 ab )
    : f b ( bits_to_f64 bb )
    ? == op 160 { ^ ( f64_to_bits + a b ) } {}
    ? == op 161 { ^ ( f64_to_bits - a b ) } {}
    ? == op 162 { ^ ( f64_to_bits * a b ) } {}
    ? == op 163 { ^ ( f64_to_bits / a b ) } {}
    // min/max, wasm semantics: any NaN → canonical NaN; min(±0,∓0) = −0 (sign
    // OR on the bits), max(±0,∓0) = +0 (sign AND).
    ? | ( __f64_nan ab ) ( __f64_nan bb ) { ^ 9221120237041090560 } {}
    ? & == & ab 9223372036854775807 0 == & bb 9223372036854775807 0 {
        ^ ? == op 164 | ab bb & ab bb } {}
    ? == op 164 { ^ ( f64_to_bits ? < a b a b ) } {}  // min
    ^ ( f64_to_bits ? > a b a b )  // 165 max
}

@ __f64_cmp i op i ab i bb → i {
    // unordered: NaN makes `ne` true and every other comparison false
    ? | ( __f64_nan ab ) ( __f64_nan bb ) { ^ ? == op 98 1 0 } {}
    : f a ( bits_to_f64 ab )
    : f b ( bits_to_f64 bb )
    ? == op 97 { ^ ? == a b 1 0 } {}
    ? == op 98 { ^ ? != a b 1 0 } {}
    ? == op 99 { ^ ? < a b 1 0 } {}
    ? == op 100 { ^ ? > a b 1 0 } {}
    ? == op 101 { ^ ? <= a b 1 0 } {}
    ^ ? >= a b 1 0  // 102
}

@ __f32_unary i op i ab → i {
    ? == op 139 { ^ & ab 2147483647 } {}  // f32.abs
    ? == op 140 { ^ & ^^ ab 2147483648 4294967295 } {}  // f32.neg
    : f x # f ( bits_to_f32 ab )
    ? == op 141 { ^ ( f32_to_bits # f32 ( ceil x ) ) } {}
    ? == op 142 { ^ ( f32_to_bits # f32 ( floor x ) ) } {}
    ? == op 143 { ^ ( f32_to_bits # f32 ( trunc x ) ) } {}
    ? == op 144 { ^ ( f32_to_bits # f32 ( rint x ) ) } {}
    ^ ( f32_to_bits # f32 ( sqrt x ) )  // 145
}

@ __f32_binary i op i ab i bb → i {
    ? == op 152 { ^ & | & ab 2147483647 & bb 2147483648 4294967295 } {}  // copysign
    : f32 a ( bits_to_f32 ab )
    : f32 b ( bits_to_f32 bb )
    ? == op 146 { ^ ( f32_to_bits + a b ) } {}
    ? == op 147 { ^ ( f32_to_bits - a b ) } {}
    ? == op 148 { ^ ( f32_to_bits * a b ) } {}
    ? == op 149 { ^ ( f32_to_bits / a b ) } {}
    // min/max, wasm semantics (see the f64 twin)
    ? | ( __f32_nan ab ) ( __f32_nan bb ) { ^ 2143289344 } {}
    ? & == & ab 2147483647 0 == & bb 2147483647 0 {
        ^ ? == op 150 | ab bb & ab bb } {}
    ? == op 150 { ^ ( f32_to_bits ? < a b a b ) } {}
    ^ ( f32_to_bits ? > a b a b )  // 151
}

@ __f32_cmp i op i ab i bb → i {
    // unordered: NaN makes `ne` true and every other comparison false
    ? | ( __f32_nan ab ) ( __f32_nan bb ) { ^ ? == op 92 1 0 } {}
    : f32 b ( bits_to_f32 bb )
    : f32 a ( bits_to_f32 ab )
    ? == op 91 { ^ ? == a b 1 0 } {}
    ? == op 92 { ^ ? != a b 1 0 } {}
    ? == op 93 { ^ ? < a b 1 0 } {}
    ? == op 94 { ^ ? > a b 1 0 } {}
    ? == op 95 { ^ ? <= a b 1 0 } {}
    ^ ? >= a b 1 0  // 96
}

// The int↔float conversions (0xa7..0xbf). Reinterpret (0xbc..0xbf) is the
// identity because a value already lives as its bit pattern; the trapping
// truncations report through `it` and their result is then dead.
@ __convert * Interp it i op i ab → i {
    ? == op 167 { ^ ( __w32 ab ) } {}  // i32.wrap_i64
    ? == op 172 { ^ ( __w32 ab ) } {}  // i64.extend_i32_s
    ? == op 173 { ^ & ab 4294967295 } {}  // i64.extend_i32_u
    ? & >= op 188 <= op 191 { ^ ab } {}  // *.reinterpret_* : no-op
    // trapping float→int truncation (NaN / out-of-range → trap, per spec)
    ? == op 168 {  // i32.trunc_f32_s
        ^ ( __w32 # i ( __trunc_ck it ( __f32_nan ab ) # f ( bits_to_f32 ab ) -2147483648.0 2147483648.0 ) ) } {}
    ? == op 169 {  // i32.trunc_f32_u  (trunc(-0.9) = -0.0 ≥ 0.0 → valid 0)
        ^ ( __w32 # i ( __trunc_ck it ( __f32_nan ab ) # f ( bits_to_f32 ab ) 0.0 4294967296.0 ) ) } {}
    ? == op 170 {  // i32.trunc_f64_s
        ^ ( __w32 # i ( __trunc_ck it ( __f64_nan ab ) ( bits_to_f64 ab ) -2147483648.0 2147483648.0 ) ) } {}
    ? == op 171 {  // i32.trunc_f64_u
        ^ ( __w32 # i ( __trunc_ck it ( __f64_nan ab ) ( bits_to_f64 ab ) 0.0 4294967296.0 ) ) } {}
    ? == op 174 {  // i64.trunc_f32_s
        ^ # i ( __trunc_ck it ( __f32_nan ab ) # f ( bits_to_f32 ab ) - 0.0 ( __f_2p63 ) ( __f_2p63 ) ) } {}
    ? == op 175 {  // i64.trunc_f32_u
        ^ ( __f_to_u64 ( __trunc_ck it ( __f32_nan ab ) # f ( bits_to_f32 ab ) 0.0 ( __f_2p64 ) ) ) } {}
    ? == op 176 {  // i64.trunc_f64_s
        ^ # i ( __trunc_ck it ( __f64_nan ab ) ( bits_to_f64 ab ) - 0.0 ( __f_2p63 ) ( __f_2p63 ) ) } {}
    ? == op 177 {  // i64.trunc_f64_u
        ^ ( __f_to_u64 ( __trunc_ck it ( __f64_nan ab ) ( bits_to_f64 ab ) 0.0 ( __f_2p64 ) ) ) } {}
    ? == op 178 { ^ ( f32_to_bits # f32 ( __w32 ab ) ) } {}  // f32.convert_i32_s
    ? == op 179 { ^ ( f32_to_bits # f32 & ab 4294967295 ) } {}  // f32.convert_i32_u
    ? == op 180 { ^ ( f32_to_bits # f32 ab ) } {}  // f32.convert_i64_s
    ? == op 181 {  // f32.convert_i64_u — u64 ≥ 2^63 via halve-with-sticky-bit + double
        ? >= ab 0 { ^ ( f32_to_bits # f32 ab ) } {}
        : f32 t # f32 | ( __lshr64 ab 1 ) & ab 1
        ^ ( f32_to_bits + t t ) } {}
    ? == op 182 { ^ ( f32_to_bits # f32 ( bits_to_f64 ab ) ) } {}  // f32.demote_f64
    ? == op 183 { ^ ( f64_to_bits # f ( __w32 ab ) ) } {}  // f64.convert_i32_s
    ? == op 184 { ^ ( f64_to_bits # f & ab 4294967295 ) } {}  // f64.convert_i32_u
    ? == op 185 { ^ ( f64_to_bits # f ab ) } {}  // f64.convert_i64_s
    ? == op 186 {  // f64.convert_i64_u — u64 ≥ 2^63 via halve-with-sticky-bit + double
        ? >= ab 0 { ^ ( f64_to_bits # f ab ) } {}
        : f t # f | ( __lshr64 ab 1 ) & ab 1
        ^ ( f64_to_bits + t t ) } {}
    ? == op 187 { ^ ( f64_to_bits # f # f ( bits_to_f32 ab ) ) } {}  // f64.promote_f32
    ( __trap it `unsupported float opcode` )
    ^ 0
}

// Float arithmetic, unary and compares (0x5b..0x66, 0x8b..0xa6): the half of
// the float set that needs neither the interpreter (none of it traps) nor a
// single floating-point constant. That is what makes it safe to inline into
// the driver — `__convert`, which carries 2^63, 2^64 and the truncation
// bounds, stays a call precisely so those constants keep out of the hot
// loop's register allocation. `b` is unused by the unary forms.

// ── WASI host functions (wasi_snapshot_preview1) ─────────────────
// Each takes its args from the value stack (last arg on top) and pushes the
// i32 errno result. Pointer args index linear memory.

@ __feq ( Vec u ) field s name → b {
    : i n ( vec_len [u] field )
    ? != n ( nurl_str_len name ) { ^ F } {}
    : ~ b eq T : ~ i k 0
    ~ & eq < k n {
        ? != ?? ( vec_get [u] field k ) { T x → # i x F → -1 } ( nurl_str_get name k ) { = eq F } {}
        = k + k 1
    }
    ^ eq
}

@ __m_get_u32 * Interp it i a → i { ^ & ( __mem_load it a 4 0 ) 4294967295 }

@ __m_put_u32 * Interp it i a i val → v { ( __mem_store it a 4 val ) }

// Overwrite/extend a file fd's buffer at byte offset `at` (gap zero-filled —
// the file-semantics core shared by fd_write and fd_pwrite).
@ __fd_put_at * WFd f i at ( Vec u ) buf → v {
    = . f dirty T
    : i bn ( vec_len [u] buf )
    ~ < ( vec_len [u] . f data ) + at bn { ( vec_push [u] . f data # u 0 ) }
    : ~ i bi 0
    ~ < bi bn { ( vec_set [u] . f data + at bi ?? ( vec_get [u] buf bi ) { T x → x F → # u 0 } ) = bi + bi 1 }
}

// Write `len` bytes of memory at `ptr` to fd: 1 stdout, 2 stderr, else a file
// descriptor's buffer at its current position (flushed to disk on close/sync).
@ __wasi_write_bytes * Interp it i fd i ptr i len → v {
    ? <= len 0 { ^ v } {}
    // A write cannot cover more bytes than linear memory holds; a larger length
    // is a hostile iovec — trap rather than pre-allocate gigabytes for it.
    ? > len . it mem_bytes { ( __trap it `fd_write length exceeds memory` ) ^ v } {}
    : ( Vec u ) buf ( vec_with_cap [u] len )
    : ~ i k 0
    ~ < k len { ( vec_push [u] buf # u & ( __mem_load it + ptr k 1 0 ) 255 ) = k + k 1 }
    ? | == fd 1 == fd 2 {
        ? . it cap {
            // An embedder asked for the output as a value: raw bytes,
            // appended, NULs preserved — bytes_to_str would truncate at
            // the first NUL a binary-printing module emits.
            : *Interp hoc ( __host it )
            : ( Vec u ) dst ? == fd 2 . hoc caperr . hoc capout
            : ~ i c 0
            ~ < c len { ( vec_push [u] dst # u ?? ( vec_get [u] buf c ) { T x → # i x F → 0 } ) = c + c 1 }
        } {
            : String s ( bytes_to_str buf )
            ? == fd 2 { ( nurl_eprint ( string_data s ) ) } { ( nurl_print ( string_data s ) ) }
            ( string_free s )
        }
    } {
        : s fp ( __fd_at it fd )
        ? != # i fp 0 {
            : *WFd f # *WFd fp
            : i at ? . f append ( vec_len [u] . f data ) . f pos
            ( __fd_put_at f at buf )
            = . f pos + at len
        } {}
    }
    ( vec_free [u] buf )
}

@ __wasi_proc_exit * Interp it → v {
    = . it exit_code ( __pop it )
    = . it halt | . it halt 2
    ( interp_flush it )
}

@ __wasi_fd_write * Interp it → v {
    : i nwritten ( __pop it )
    : i iovs_len ( __pop it )
    : i iovs ( __pop it )
    : i fd ( __pop it )
    // The iovec array cannot hold more entries than linear memory has bytes;
    // clamp so a bogus iovs_len can neither loop unboundedly nor over-read. The
    // trap guard stops the loop the moment an iovec header is out of bounds.
    : i maxio . it mem_bytes
    : ~ i total 0
    : ~ i i 0
    ~ & & ! ( interp_trapped it ) < i iovs_len <= i maxio {
        : i bufp ( __m_get_u32 it + iovs * i 8 )
        : i buflen ( __m_get_u32 it + + iovs * i 8 4 )
        ( __wasi_write_bytes it fd bufp buflen )
        = total + total buflen
        = i + i 1
    }
    ( __m_put_u32 it nwritten total )
    // A write is a write: push it out of the host's buffer now. A guest
    // that never exits — a server, which is most of the point of having
    // sockets — otherwise produces no output at all, because the host's
    // stdio buffer is only drained when the process ends.
    ? == fd 1 { ( nurl_flush_stdout ) } {}
    ? == fd 2 { ( nurl_flush_stderr ) } {}
    ( __push it 0 )
}

// Fetch the fd record for descriptor `fd`, or #s 0 if out of range / closed.
@ __fd_at * Interp it i fd → s {
    : *Interp ho ( __host it )
    ? | < fd 0 >= fd ( vec_len [s] . ho fds ) { ^ # s 0 } {}
    ^ ?? ( vec_get [s] . ho fds fd ) { T x → x F → # s 0 }
}

// Read `len` bytes of linear memory at `ptr` into a fresh byte vector.
@ __mem_slice * Interp it i ptr i len → ( Vec u ) {
    // Clamp to memory size: a slice can never be longer than linear memory, so
    // a bogus guest length cannot force a multi-gigabyte allocation. Bytes past
    // the end still trap in __mem_load, so this only bounds the up-front cap.
    : ~ i n len
    ? < n 0 { = n 0 } {}
    ? > n . it mem_bytes { = n . it mem_bytes } {}
    : ( Vec u ) b ( vec_with_cap [u] ? > n 0 n 1 )
    : ~ i k 0
    ~ < k n { ( vec_push [u] b # u & ( __mem_load it + ptr k 1 0 ) 255 ) = k + k 1 }
    ^ b
}

// IoErr → WASI errno (2 EACCES, 20 EEXIST, 29 EIO, 44 ENOENT).
@ __ioerr_errno IoErr e → i {
    ^ ?? e {
        NotFound → 44
        PermissionDenied → 2
        AlreadyExists → 20
        _ → 29
    }
}

// Is `path` a directory on the host? (opendir succeeds ⇔ directory.)
@ __is_dir s path → b {
    : !( Vec String ) IoErr r ( dir_list path )
    ^ ?? r {
        T names → {
            : i n ( vec_len [String] names )
            : ~ i k 0
            ~ < k n { ?? ( vec_get [String] names k ) { T nm → ( string_free nm ) F → {} } = k + k 1 }
            ( vec_free [String] names )
            ^ T
        }
        F e → F
    }
}

// Join a dir fd's host path + "/" + `len` guest bytes at `ptr` into an owned
// String; #s 0 (as String data) is never returned — the caller checked the fd.
@ __join_path * Interp it * WFd d i ptr i len → String {
    : ( Vec u ) full ( vec_new [u] )
    : i hn ( vec_len [u] . d host )
    : ~ i k 0
    ~ < k hn { ( vec_push [u] full ?? ( vec_get [u] . d host k ) { T x → x F → # u 0 } ) = k + k 1 }
    ? & > hn 0 != ?? ( vec_get [u] . d host - hn 1 ) { T x → # i x F → 0 } 47 { ( vec_push [u] full # u 47 ) } {}
    : ( Vec u ) rel ( __mem_slice it ptr len )
    : i rn ( vec_len [u] rel )
    : ~ i j 0
    ~ < j rn { ( vec_push [u] full ?? ( vec_get [u] rel j ) { T x → x F → # u 0 } ) = j + j 1 }
    ( vec_free [u] rel )
    : String hs ( bytes_to_str full )
    ( vec_free [u] full )
    ^ hs
}

// The dir fd record for `fd`, or #s 0 unless it is a directory (preopen or
// opened) — the base every path_* call resolves against.
@ __dirfd_at * Interp it i fd → s {
    : s dp ( __fd_at it fd )
    ? == # i dp 0 { ^ # s 0 } {}
    : *WFd d # *WFd dp
    ? | == . d kind 2 == . d kind 4 { ^ dp } {}
    ^ # s 0
}

// path_open(dirfd, dirflags, path_ptr, path_len, oflags, rights_base,
//   rights_inheriting, fdflags, opened_fd_ptr) → errno.
// oflags: 1 CREAT, 2 DIRECTORY, 4 EXCL, 8 TRUNC. fdflags: 1 APPEND.
// rights bit 6 (fd_write) makes the fd writable. Files are slurped into a
// buffer; writes are flushed on close/sync/exit.
@ __wasi_path_open * Interp it → v {
    : i ofd_p ( __pop it )
    : i fdflags ( __pop it )
    ( __pop it )  // fs_rights_inheriting (i64 cell)
    : i rights ( __pop it )  // fs_rights_base (i64 cell)
    : i oflags ( __pop it )
    : i path_len ( __pop it )
    : i path_p ( __pop it )
    ( __pop it )  // dirflags
    : i dirfd ( __pop it )
    : s dp ( __dirfd_at it dirfd )
    ? == # i dp 0 { ( __push it 8 ) ^ v } {}  // EBADF
    : *WFd d # *WFd dp
    : String hs ( __join_path it d path_p path_len )
    : i creat & oflags 1
    : i wantdir & oflags 2
    : i excl & oflags 4
    : i trunc & oflags 8
    : i want_write | | != & rights 64 0 != creat 0 != trunc 0
    : ~ i rc 0
    ? != wantdir 0 {
        // open a directory: it must exist and be a directory
        ? ( __is_dir ( string_data hs ) ) {
            : *WFd nf # *WFd ( __mkfd 4 )
            ( vec_free [u] . nf host ) = . nf host ( bytes_from_str ( string_data hs ) )
            : *Interp ho1 ( __host it )
            ( __m_put_u32 it ofd_p ( vec_len [s] . ho1 fds ) )
            ( vec_push [s] . ho1 fds # s nf )
        } { = rc ? != 0 ( nurl_file_exists ( string_data hs ) ) 54 44 }  // ENOTDIR / ENOENT
        ( string_free hs )
        ( __push it rc )
        ^ v
    } {}
    : i exists ( nurl_file_exists ( string_data hs ) )
    ? & & != creat 0 != excl 0 != exists 0 { ( string_free hs ) ( __push it 20 ) ^ v } {}  // EEXIST
    ? & != exists 0 ( __is_dir ( string_data hs ) ) {
        // an existing directory opened without O_DIRECTORY: readable as a dir fd
        : *WFd nf # *WFd ( __mkfd 4 )
        ( vec_free [u] . nf host ) = . nf host ( bytes_from_str ( string_data hs ) )
        : *Interp ho2 ( __host it )
        ( __m_put_u32 it ofd_p ( vec_len [s] . ho2 fds ) )
        ( vec_push [s] . ho2 fds # s nf )
        ( string_free hs )
        ( __push it 0 )
        ^ v
    } {}
    ? & == exists 0 == creat 0 { ( string_free hs ) ( __push it 44 ) ^ v } {}  // ENOENT
    : *WFd nf # *WFd ( __mkfd 3 )
    ( vec_free [u] . nf host ) = . nf host ( bytes_from_str ( string_data hs ) )
    ? & != exists 0 == trunc 0 {
        // keep existing contents (read, or write without truncation)
        : !( Vec u ) IoErr fr ( read_file_bytes ( string_data hs ) )
        ?? fr {
            T bytes → { ( vec_free [u] . nf data ) = . nf data bytes }
            F e → { = rc ( __ioerr_errno e ) }
        }
    } {}
    ? != rc 0 { ( __freefd # s nf ) ( string_free hs ) ( __push it rc ) ^ v } {}
    = . nf writable ? != want_write 0 T F
    = . nf append ? != & fdflags 1 0 T F
    // O_CREAT on a new name: create it on the host NOW, not at flush time.
    // The open is where the guest's libc learns whether the file can exist
    // at all — deferring it meant a write into a directory that does not
    // exist answered "ok" all the way through fd_close.
    ? & != creat 0 == exists 0 {
        : ( Vec u ) empty ( vec_new [u] )
        : !v IoErr cr ( write_file_bytes ( string_data hs ) empty )
        ( vec_free [u] empty )
        ?? cr { T x → {} F e → { = rc ( __ioerr_errno e ) } }
        ? != rc 0 { ( __freefd # s nf ) ( string_free hs ) ( __push it rc ) ^ v } {}
    } {}
    : *Interp ho3 ( __host it )
    ( __m_put_u32 it ofd_p ( vec_len [s] . ho3 fds ) )
    ( vec_push [s] . ho3 fds # s nf )
    ( string_free hs )
    ( __push it 0 )
}

// fd_pread / fd_pwrite: positioned I/O that leaves the fd offset untouched.
@ __wasi_fd_pread * Interp it → v {
    : i nread_p ( __pop it )
    : i offset ( __pop it )
    : i iovs_len ( __pop it )
    : i iovs ( __pop it )
    : i fd ( __pop it )
    : s fp ( __fd_at it fd )
    ? == # i fp 0 { ( __push it 8 ) ^ v } {}
    : *WFd f # *WFd fp
    ? != . f kind 3 { ( __m_put_u32 it nread_p 0 ) ( __push it 0 ) ^ v } {}
    : i dn ( vec_len [u] . f data )
    : i maxio . it mem_bytes
    : ~ i at offset
    : ~ i total 0
    : ~ i iv 0
    ~ & & ! ( interp_trapped it ) < iv iovs_len <= iv maxio {
        : i bufp ( __m_get_u32 it + iovs * iv 8 )
        : i buflen ( __m_get_u32 it + + iovs * iv 8 4 )
        : ~ i c 0
        ~ & < c buflen < at dn {
            ( __mem_store it + bufp c 1 ?? ( vec_get [u] . f data at ) { T x → # i x F → 0 } )
            = at + at 1
            = c + c 1
        }
        = total + total c
        = iv + iv 1
    }
    ( __m_put_u32 it nread_p total )
    ( __push it 0 )
}

@ __wasi_fd_pwrite * Interp it → v {
    : i nwritten_p ( __pop it )
    : i offset ( __pop it )
    : i iovs_len ( __pop it )
    : i iovs ( __pop it )
    : i fd ( __pop it )
    : s fp ( __fd_at it fd )
    ? == # i fp 0 { ( __push it 8 ) ^ v } {}
    : *WFd f # *WFd fp
    ? ! . f writable { ( __push it 8 ) ^ v } {}
    : i maxio . it mem_bytes
    : ~ i at offset
    : ~ i total 0
    : ~ i iv 0
    ~ & & ! ( interp_trapped it ) < iv iovs_len <= iv maxio {
        : i bufp ( __m_get_u32 it + iovs * iv 8 )
        : i buflen ( __m_get_u32 it + + iovs * iv 8 4 )
        : ( Vec u ) chunk ( __mem_slice it bufp buflen )
        ( __fd_put_at f at chunk )
        ( vec_free [u] chunk )
        = at + at buflen
        = total + total buflen
        = iv + iv 1
    }
    ( __m_put_u32 it nwritten_p total )
    ( __push it 0 )
}

// path_create_directory / path_remove_directory / path_unlink_file /
// path_rename / path_filestat_get — the host-directory mutations, resolved
// against a dir fd exactly like path_open.
@ __wasi_path_create_directory * Interp it → v {
    : i path_len ( __pop it )
    : i path_p ( __pop it )
    : i dirfd ( __pop it )
    : s dp ( __dirfd_at it dirfd )
    ? == # i dp 0 { ( __push it 8 ) ^ v } {}
    : String hs ( __join_path it # *WFd dp path_p path_len )
    : !v IoErr r ( dir_create ( string_data hs ) )
    ( string_free hs )
    ( __push it ?? r { T x → 0 F e → ( __ioerr_errno e ) } )
}

@ __wasi_path_remove_directory * Interp it → v {
    : i path_len ( __pop it )
    : i path_p ( __pop it )
    : i dirfd ( __pop it )
    : s dp ( __dirfd_at it dirfd )
    ? == # i dp 0 { ( __push it 8 ) ^ v } {}
    : String hs ( __join_path it # *WFd dp path_p path_len )
    : i rc ( nurl_dir_remove ( string_data hs ) )
    ( string_free hs )
    ( __push it ? == rc 0 0 ( __ioerr_errno ( _io_err_of_kind ( errno_kind ) ) ) )
}

@ __wasi_path_unlink_file * Interp it → v {
    : i path_len ( __pop it )
    : i path_p ( __pop it )
    : i dirfd ( __pop it )
    : s dp ( __dirfd_at it dirfd )
    ? == # i dp 0 { ( __push it 8 ) ^ v } {}
    : String hs ( __join_path it # *WFd dp path_p path_len )
    : i32 rc ( unlink ( string_data hs ) )
    ( string_free hs )
    ( __push it ? == # i rc 0 0 ( __ioerr_errno ( _io_err_of_kind ( errno_kind ) ) ) )
}

@ __wasi_path_rename * Interp it → v {
    : i new_len ( __pop it )
    : i new_p ( __pop it )
    : i new_dirfd ( __pop it )
    : i old_len ( __pop it )
    : i old_p ( __pop it )
    : i old_dirfd ( __pop it )
    : s odp ( __dirfd_at it old_dirfd )
    : s ndp ( __dirfd_at it new_dirfd )
    ? | == # i odp 0 == # i ndp 0 { ( __push it 8 ) ^ v } {}
    : String os ( __join_path it # *WFd odp old_p old_len )
    : String ns ( __join_path it # *WFd ndp new_p new_len )
    : !v IoErr r ( fs_rename ( string_data os ) ( string_data ns ) )
    ( string_free os ) ( string_free ns )
    ( __push it ?? r { T x → 0 F e → ( __ioerr_errno e ) } )
}

// path_filestat_get(dirfd, flags, path_ptr, path_len, st_p): 64-byte filestat —
// filetype at +16, size at +32 (the fields programs actually read).
@ __wasi_path_filestat_get * Interp it → v {
    : i st_p ( __pop it )
    : i path_len ( __pop it )
    : i path_p ( __pop it )
    ( __pop it )  // lookup flags
    : i dirfd ( __pop it )
    : s dp ( __dirfd_at it dirfd )
    ? == # i dp 0 { ( __push it 8 ) ^ v } {}
    : String hs ( __join_path it # *WFd dp path_p path_len )
    : ~ i rc 0
    : ~ i k 0
    ~ < k 64 { ( __mem_store it + st_p k 1 0 ) = k + k 1 }
    ? ( __is_dir ( string_data hs ) ) {
        ( __mem_store it + st_p 16 1 3 )  // directory
    } {
        : !i IoErr szr ( file_size ( string_data hs ) )
        ?? szr {
            T sz → {
                ( __mem_store it + st_p 16 1 4 )  // regular file
                ( __mem_store it + st_p 32 8 sz )
            }
            F e → { = rc ( __ioerr_errno e ) }
        }
    }
    ( string_free hs )
    ( __push it rc )
}

// fd_readdir(fd, buf, buf_len, cookie, bufused_p): WASI dirent stream. Each
// entry = 24-byte header (d_next u64, d_ino u64, d_namlen u32, d_type u8+pad)
// + name. A partially-written final entry with bufused == buf_len tells libc
// to enlarge and retry, per the ABI.
@ __wasi_fd_readdir * Interp it → v {
    : i bufused_p ( __pop it )
    : i cookie ( __pop it )
    : i buf_len ( __pop it )
    : i buf ( __pop it )
    : i fd ( __pop it )
    : s fp ( __fd_at it fd )
    ? == # i fp 0 { ( __push it 8 ) ^ v } {}
    : *WFd f # *WFd fp
    ? ! | == . f kind 2 == . f kind 4 { ( __push it 54 ) ^ v } {}  // ENOTDIR
    : String hostdir ( bytes_to_str . f host )
    : !( Vec String ) IoErr lr ( dir_list ( string_data hostdir ) )
    : ~ i rc 0
    : ~ i used 0
    ?? lr {
        F e → { = rc ( __ioerr_errno e ) }
        T names → {
            : i n ( vec_len [String] names )
            : ~ i idx cookie
            : ~ b full F
            ~ & ! full < idx n {
                : String nm ?? ( vec_get [String] names idx ) { T x → x F → # String 0 }
                : i nlen ( nurl_str_len ( string_data nm ) )
                // d_type: probe the joined path (3 dir / 4 regular)
                : String sub ( __join_path2 hostdir ( string_data nm ) )
                : i dtype ? ( __is_dir ( string_data sub ) ) 3 4
                ( string_free sub )
                // serialize header + name, truncating at buf_len
                : ( Vec u ) ent ( vec_with_cap [u] + 24 nlen )
                ( __ent_put64 ent + idx 1 )  // d_next
                ( __ent_put64 ent + idx 1 )  // d_ino (nonzero, stable per entry)
                ( __ent_put32 ent nlen )
                ( vec_push [u] ent # u dtype )
                ( vec_push [u] ent # u 0 ) ( vec_push [u] ent # u 0 ) ( vec_push [u] ent # u 0 )
                : ~ i c 0
                ~ < c nlen { ( vec_push [u] ent # u ( nurl_str_get ( string_data nm ) c ) ) = c + c 1 }
                : i en ( vec_len [u] ent )
                : ~ i w 0
                ~ & < w en < used buf_len {
                    ( __mem_store it + buf used 1 ?? ( vec_get [u] ent w ) { T x → # i x F → 0 } )
                    = used + used 1
                    = w + w 1
                }
                ( vec_free [u] ent )
                ? < w en { = full T } {}  // buffer exhausted mid-entry
                = idx + idx 1
            }
            : ~ i fi 0
            ~ < fi n { ?? ( vec_get [String] names fi ) { T nm → ( string_free nm ) F → {} } = fi + fi 1 }
            ( vec_free [String] names )
        }
    }
    ( string_free hostdir )
    ( __m_put_u32 it bufused_p used )
    ( __push it rc )
}

// Little-endian u64/u32 pushes for dirent serialization.
@ __ent_put64 ( Vec u ) v i x → v {
    : ~ i k 0
    ~ < k 8 { ( vec_push [u] v # u & ( __lshr64 x * 8 k ) 255 ) = k + k 1 }
}

@ __ent_put32 ( Vec u ) v i x → v {
    : ~ i k 0
    ~ < k 4 { ( vec_push [u] v # u & >> x * 8 k 255 ) = k + k 1 }
}

// hostdir + "/" + name as an owned String (host-side join for readdir probes).
@ __join_path2 String dir s name → String {
    : ( Vec u ) full ( bytes_from_str ( string_data dir ) )
    : i hn ( vec_len [u] full )
    ? & > hn 0 != ?? ( vec_get [u] full - hn 1 ) { T x → # i x F → 0 } 47 { ( vec_push [u] full # u 47 ) } {}
    : i nl ( nurl_str_len name )
    : ~ i k 0
    ~ < k nl { ( vec_push [u] full # u ( nurl_str_get name k ) ) = k + k 1 }
    : String out ( bytes_to_str full )
    ( vec_free [u] full )
    ^ out
}

@ __wasi_fd_read * Interp it → v {
    : i nread_p ( __pop it )
    : i iovs_len ( __pop it )
    : i iovs ( __pop it )
    : i fd ( __pop it )
    : s fp ( __fd_at it fd )
    ? == # i fp 0 { ( __m_put_u32 it nread_p 0 ) ( __push it 0 ) ^ v } {}
    : *WFd f # *WFd fp
    ? != . f kind 3 { ( __m_put_u32 it nread_p 0 ) ( __push it 0 ) ^ v } {}  // stdin/dir → EOF
    : i dn ( vec_len [u] . f data )
    : i maxio . it mem_bytes
    : ~ i total 0
    : ~ i iv 0
    ~ & & ! ( interp_trapped it ) < iv iovs_len <= iv maxio {
        : i bufp ( __m_get_u32 it + iovs * iv 8 )
        : i buflen ( __m_get_u32 it + + iovs * iv 8 4 )
        : ~ i c 0
        ~ & < c buflen < . f pos dn {
            ( __mem_store it + bufp c 1 ?? ( vec_get [u] . f data . f pos ) { T x → # i x F → 0 } )
            = . f pos + . f pos 1
            = c + c 1
        }
        = total + total c
        = iv + iv 1
    }
    ( __m_put_u32 it nread_p total )
    ( __push it 0 )
}

@ __wasi_fd_seek * Interp it → v {
    : i noff_p ( __pop it )
    : i whence ( __pop it )
    : i offset ( __pop it )
    : i fd ( __pop it )
    : s fp ( __fd_at it fd )
    ? == # i fp 0 { ( __mem_store it noff_p 8 0 ) ( __push it 0 ) ^ v } {}
    : *WFd f # *WFd fp
    : i dn ( vec_len [u] . f data )
    : i base ? == whence 0 0 ? == whence 1 . f pos dn  // SET / CUR / END
    : i np + base offset
    = . f pos ? < np 0 0 np
    ( __mem_store it noff_p 8 . f pos )
    ( __push it 0 )
}

@ __wasi_args_sizes_get * Interp it → v {
    : i bufsz_p ( __pop it )
    : i argc_p ( __pop it )
    : i argc ( vec_len [s] . it argv )
    : ~ i bufsz 0
    : ~ i k 0
    ~ < k argc {
        : *Arg a # *Arg ?? ( vec_get [s] . it argv k ) { T x → x F → # s 0 }
        = bufsz + bufsz + ( vec_len [u] . a bytes ) 1
        = k + k 1
    }
    ( __m_put_u32 it argc_p argc )
    ( __m_put_u32 it bufsz_p bufsz )
    ( __push it 0 )
}

@ __wasi_args_get * Interp it → v {
    : i buf_p ( __pop it )
    : i argv_p ( __pop it )
    : i argc ( vec_len [s] . it argv )
    : ~ i cur buf_p
    : ~ i k 0
    ~ < k argc {
        : *Arg a # *Arg ?? ( vec_get [s] . it argv k ) { T x → x F → # s 0 }
        ( __m_put_u32 it + argv_p * k 4 cur )
        : i blen ( vec_len [u] . a bytes )
        : ~ i j 0
        ~ < j blen { ( __mem_store it + cur j 1 ?? ( vec_get [u] . a bytes j ) { T x → # i x F → 0 } ) = j + j 1 }
        ( __mem_store it + cur blen 1 0 )  // NUL terminator
        = cur + cur + blen 1
        = k + k 1
    }
    ( __push it 0 )
}

@ __wasi_fd_prestat_get * Interp it → v {
    : i buf ( __pop it )
    : i fd ( __pop it )
    : s fp ( __fd_at it fd )
    ? == # i fp 0 { ( __push it 8 ) ^ v } {}  // EBADF: ends libc's preopen scan
    : *WFd f # *WFd fp
    ? != . f kind 2 { ( __push it 8 ) ^ v } {}
    ( __mem_store it buf 1 0 )  // pr_type = dir
    ( __m_put_u32 it + buf 4 ( vec_len [u] . f name ) )  // pr_name_len
    ( __push it 0 )
}

@ __wasi_fd_prestat_dir_name * Interp it → v {
    : i plen ( __pop it )
    : i pptr ( __pop it )
    : i fd ( __pop it )
    : s fp ( __fd_at it fd )
    ? == # i fp 0 { ( __push it 8 ) ^ v } {}
    : *WFd f # *WFd fp
    : i nn ( vec_len [u] . f name )
    : i n ? < plen nn plen nn
    : ~ i k 0
    ~ < k n { ( __mem_store it + pptr k 1 ?? ( vec_get [u] . f name k ) { T x → # i x F → 0 } ) = k + k 1 }
    ( __push it 0 )
}

// filetype byte for a fd kind: stdio→char device(2), dir (preopened 2 or
// opened 4)→directory(3), file→regular(4).
@ __filetype_of i kind → i { ^ ? | == kind 2 == kind 4 3 ? == kind 3 4 2 }

@ __wasi_fd_fdstat_get * Interp it → v {
    : i stat_p ( __pop it )
    : i fd ( __pop it )
    : s fp ( __fd_at it fd )
    : ~ i k 0
    ~ < k 24 { ( __mem_store it + stat_p k 1 0 ) = k + k 1 }
    : ~ i kind 1
    ? != # i fp 0 { : *WFd f # *WFd fp = kind . f kind } {}
    ( __mem_store it stat_p 1 ( __filetype_of kind ) )
    // grant all rights so libc never refuses an operation
    ( __mem_store it + stat_p 8 8 -1 )
    ( __mem_store it + stat_p 16 8 -1 )
    ( __push it 0 )
}

@ __wasi_fd_filestat_get * Interp it → v {
    : i st_p ( __pop it )
    : i fd ( __pop it )
    : s fp ( __fd_at it fd )
    : ~ i k 0
    ~ < k 64 { ( __mem_store it + st_p k 1 0 ) = k + k 1 }
    ? != # i fp 0 {
        : *WFd f # *WFd fp
        ( __mem_store it + st_p 16 1 ( __filetype_of . f kind ) )  // filetype
        ( __mem_store it + st_p 32 8 ( vec_len [u] . f data ) )  // file size
    } {}
    ( __push it 0 )
}

// Flush a dirty written file to disk (fd_close / fd_sync / proc_exit / normal
// program exit all funnel through here).
// Write the buffer back to the host file. Returns an errno (0 = ok) —
// a flush is the moment every buffered write of this fd actually reaches
// the disk, so its failure is the ONLY chance the guest has to learn that
// the write did not happen. Swallowing it made `write_file` report
// success for a file the host never created.
@ __fd_flush * WFd f → i {
    ? & . f writable . f dirty {
        : String hs ( bytes_to_str . f host )
        : !v IoErr wr ( write_file_bytes ( string_data hs ) . f data )
        : ~ i rc 0
        ?? wr { T x → { = . f dirty F } F e → { = rc ( __ioerr_errno e ) } }
        ( string_free hs )
        ^ rc
    } {}
    ^ 0
}

// Flush every open dirty file — called on proc_exit and when _start returns,
// so buffered writes are never lost to a missing fd_close.
@ interp_flush * Interp it → v {
    : *Interp ho ( __host it )
    : i n ( vec_len [s] . ho fds )
    : ~ i k 3
    ~ < k n { ?? ( vec_get [s] . ho fds k ) { T pp → ? != # i pp 0 { ( __fd_flush # *WFd pp ) } {} F → {} } = k + k 1 }
}

@ __wasi_fd_close * Interp it → v {
    : i fd ( __pop it )
    : s fp ( __fd_at it fd )
    : ~ i rc 0
    ? != # i fp 0 {
        : *WFd f # *WFd fp
        = rc ( __fd_flush f )
        ? >= fd 3 { ( __freefd fp ) ( vec_set [s] . ( __host it ) fds fd # s 0 ) } {}  // keep stdio
    } {}
    ( __push it rc )
}

@ __wasi_fd_sync * Interp it → v {
    : i fd ( __pop it )
    : s fp ( __fd_at it fd )
    ? == # i fp 0 { ( __push it 8 ) ^ v } {}  // EBADF
    ( __push it ( __fd_flush # *WFd fp ) )
}

// fd_tell(fd, off_p): current offset as u64.
@ __wasi_fd_tell * Interp it → v {
    : i off_p ( __pop it )
    : i fd ( __pop it )
    : s fp ( __fd_at it fd )
    ? == # i fp 0 { ( __push it 8 ) ^ v } {}
    : *WFd f # *WFd fp
    ( __mem_store it off_p 8 . f pos )
    ( __push it 0 )
}

// environ_sizes_get / environ_get: the entries pushed via interp_push_env
// (the host environment is NOT inherited — capability-style, like --env).
@ __wasi_environ_sizes_get * Interp it → v {
    : i bufsz_p ( __pop it )
    : i cnt_p ( __pop it )
    : i n ( vec_len [s] . it envp )
    : ~ i bufsz 0
    : ~ i k 0
    ~ < k n {
        : *Arg a # *Arg ?? ( vec_get [s] . it envp k ) { T x → x F → # s 0 }
        = bufsz + bufsz + ( vec_len [u] . a bytes ) 1
        = k + k 1
    }
    ( __m_put_u32 it cnt_p n )
    ( __m_put_u32 it bufsz_p bufsz )
    ( __push it 0 )
}

@ __wasi_environ_get * Interp it → v {
    : i buf_p ( __pop it )
    : i envv_p ( __pop it )
    : i n ( vec_len [s] . it envp )
    : ~ i cur buf_p
    : ~ i k 0
    ~ < k n {
        : *Arg a # *Arg ?? ( vec_get [s] . it envp k ) { T x → x F → # s 0 }
        ( __m_put_u32 it + envv_p * k 4 cur )
        : i blen ( vec_len [u] . a bytes )
        : ~ i j 0
        ~ < j blen { ( __mem_store it + cur j 1 ?? ( vec_get [u] . a bytes j ) { T x → # i x F → 0 } ) = j + j 1 }
        ( __mem_store it + cur blen 1 0 )  // NUL terminator
        = cur + cur + blen 1
        = k + k 1
    }
    ( __push it 0 )
}

// clock_time_get(id, precision, time_ptr): realtime (0) from the wall clock,
// everything else from the monotonic clock. Nanoseconds.
@ __wasi_clock_time_get * Interp it → v {
    : i t_p ( __pop it )
    ( __pop it )  // precision (i64)
    : i id ( __pop it )
    : i ns ? == id 0 * ( now_ms ) 1000000 ( monotonic_ns )
    ( __mem_store it t_p 8 ns )
    ( __push it 0 )
}

// poll_oneoff(in, out, nsubs, nevents_p) → errno.
//
// The one WASI call a server cannot do without: libc's sleep, nanosleep
// and every timeout is a clock subscription here. Regular files and the
// stdio streams are always ready — which is what poll(2) says about a
// regular file too — so an fd subscription answers immediately and only
// a pure clock wait actually sleeps.
//
// Subscription is 48 bytes: userdata(0) tag(8), then for a clock
// clock_id(16) timeout(24) precision(32) flags(40) — flag bit 0 means
// the timeout is ABSOLUTE — and for an fd subscription fd(16).
// Event is 32 bytes: userdata(0) error(8) type(10) nbytes(16) flags(24).
@ __wasi_poll_oneoff * Interp it → v {
    : i nev_p ( __pop it )
    : i nsubs ( __pop it )
    : i out ( __pop it )
    : i in ( __pop it )
    ? | < nsubs 0 > * nsubs 48 . it mem_bytes { ( __m_put_u32 it nev_p 0 ) ( __push it 28 ) ^ v } {}  // EINVAL
    : ~ i nev 0
    : ~ i sleep_ns -1  // shortest clock wait seen, -1 = none
    : ~ i k 0
    ~ & < k nsubs ! ( interp_trapped it ) {
        : i sub + in * k 48
        : i userdata ( __mem_load it sub 8 0 )
        : i tag ( __mem_load it + sub 8 1 0 )
        ? == tag 0 {
            : i clock_id ( __m_get_u32 it + sub 16 )
            : i timeout ( __mem_load it + sub 24 8 0 )
            : i flags ( __mem_load it + sub 40 2 0 )
            : ~ i rel timeout
            ? != 0 & flags 1 {
                : i now ? == clock_id 0 * ( now_ms ) 1000000 ( monotonic_ns )
                = rel - timeout now
            } {}
            ? < rel 0 { = rel 0 } {}
            ? | == sleep_ns -1 < rel sleep_ns { = sleep_ns rel } {}
        } {
            // fd_read (1) / fd_write (2): ready now, or EBADF for a
            // descriptor the guest never opened.
            : i fd ( __m_get_u32 it + sub 16 )
            : s fp ( __fd_at it fd )
            : i ev + out * nev 32
            ( __mem_store it ev 8 userdata )
            ( __mem_store it + ev 8 2 ? == # i fp 0 8 0 )
            ( __mem_store it + ev 10 1 tag )
            ( __mem_store it + ev 16 8 0 )
            ( __mem_store it + ev 24 2 0 )
            = nev + nev 1
        }
        = k + k 1
    }
    // Only a wait with nothing else to report actually sleeps.
    ? & == nev 0 >= sleep_ns 0 {
        ? > sleep_ns 0 { ( sleep_ms / + sleep_ns 999999 1000000 ) } {}
        // Report every clock subscription as fired: they all shared the
        // one wait, and the shortest of them has certainly elapsed.
        : ~ i j 0
        ~ < j nsubs {
            : i sub + in * j 48
            ? == ( __mem_load it + sub 8 1 0 ) 0 {
                : i ev + out * nev 32
                ( __mem_store it ev 8 ( __mem_load it sub 8 0 ) )
                ( __mem_store it + ev 8 2 0 )
                ( __mem_store it + ev 10 1 0 )
                ( __mem_store it + ev 16 8 0 )
                ( __mem_store it + ev 24 2 0 )
                = nev + nev 1
            } {}
            = j + j 1
        }
    } {}
    ( __m_put_u32 it nev_p nev )
    ( __push it 0 )
}

// random_get(buf, len): real OS entropy via the runtime CSPRNG.
@ __wasi_random_get * Interp it → v {
    : i len ( __pop it )
    : i buf ( __pop it )
    // The destination buffer lives in linear memory, so a length larger than
    // memory is bogus — trap instead of allocating it.
    ? > len . it mem_bytes { ( __trap it `random_get length exceeds memory` ) ( __push it 0 ) ^ v } {}
    ? > len 0 {
        : ( Vec u ) tmp ( vec_with_cap [u] len )
        : ~ i z 0
        ~ < z len { ( vec_push [u] tmp # u 0 ) = z + z 1 }
        ( nurl_rand_fill # *u ( vec_data [u] tmp ) len )
        : ~ i k 0
        ~ < k len { ( __mem_store it + buf k 1 ?? ( vec_get [u] tmp k ) { T x → # i x F → 0 } ) = k + k 1 }
        ( vec_free [u] tmp )
    } {}
    ( __push it 0 )
}

// An out-of-bounds access says WHICH address and against what bound: with
// threads those two numbers separate "the guest computed a wild pointer"
// from "this thread's view of the memory size is behind the others".
@ __trap_oob * Interp it s what i ea i n → v {
    = . it halt | . it halt 1
    ( vec_free [u] . it trapmsg )
    : String m ( string_from what )
    ( string_push_str m ` (addr ` )
    ( string_push_int m ea )
    ( string_push_str m `+` )
    ( string_push_int m n )
    ( string_push_str m `, limit ` )
    ( string_push_int m . it mem_bytes )
    ( string_push_str m `, pages ` )
    ( string_push_int m . it mem_pages )
    ( string_push_char m 41 )
    = . it trapmsg ( bytes_from_str ( string_data m ) )
    ( string_free m )
}

// Trap with a message that carries a dynamic name (import module/field).
@ __trap_named * Interp it s prefix ( Vec u ) name → v {
    = . it halt | . it halt 1
    ( vec_free [u] . it trapmsg )
    : ( Vec u ) msg ( bytes_from_str prefix )
    : i n ( vec_len [u] name )
    : ~ i k 0
    ~ < k n { ( vec_push [u] msg ?? ( vec_get [u] name k ) { T x → x F → # u 0 } ) = k + k 1 }
    = . it trapmsg msg
}

// ── GPU host bridge (CUDA driver + NVRTC) ─────────────────────────
// Guest imports (module "env") are hand-bridged to the real libcuda /
// libnvrtc. Marshalling rule, matching packages/gpu/src/cuda.nu's ABI:
//   • a `*u` parameter is a GUEST linear-memory OFFSET → host address is
//     (host base of guest memory) + offset; NULL(0) stays NULL. libcuda
//     reads/writes guest memory in place — data copies are zero-copy.
//   • an `i` handle (CUcontext/CUmodule/CUfunction/nvrtcProgram) or a
//     CUdeviceptr is a raw 64-bit value → passed straight through.
// NOTE: raw host handles/device pointers are visible to the guest, exactly
// as in native NURL. Safe for trusted compute (our own kernels); an
// untrusted-guest deployment would add an id↔pointer handle table here.

// Host base address of the guest linear memory (recomputed per call — a
// memory.grow between host calls may relocate the backing).
@ __gpu_base * Interp it → i { ^ # i ( vec_data [u] . it mem ) }

// Guest offset → host pointer (NULL stays NULL).
@ __gpu_ptr * Interp it i off → *u {
    : i o & off 4294967295
    ? == o 0 { ^ # *u 0 } {}
    ^ # *u + ( __gpu_base it ) o
}

@ __cu_init * Interp it → v {
    : i flags ( __pop it )
    ( __push it # i ( cuInit # i32 flags ) )
}

@ __cu_device_get_count * Interp it → v {
    : i count ( __pop it )
    ( __push it # i ( cuDeviceGetCount ( __gpu_ptr it count ) ) )
}

@ __cu_device_get * Interp it → v {
    : i ordinal ( __pop it )
    : i device ( __pop it )
    ( __push it # i ( cuDeviceGet ( __gpu_ptr it device ) # i32 ordinal ) )
}

@ __cu_device_get_name * Interp it → v {
    : i dev ( __pop it )
    : i len ( __pop it )
    : i name ( __pop it )
    ( __push it # i ( cuDeviceGetName ( __gpu_ptr it name ) # i32 len # i32 dev ) )
}

@ __cu_ctx_create * Interp it → v {
    : i dev ( __pop it )
    : i flags ( __pop it )
    : i pctx ( __pop it )
    ( __push it # i ( cuCtxCreate ( __gpu_ptr it pctx ) # i32 flags # i32 dev ) )
}

@ __cu_ctx_destroy * Interp it → v {
    : i ctx ( __pop it )
    ( __push it # i ( cuCtxDestroy ctx ) )
}

@ __cu_ctx_sync * Interp it → v { ( __push it # i ( cuCtxSynchronize ) ) }

@ __cu_module_load * Interp it → v {
    : i image ( __pop it )
    : i module ( __pop it )
    ( __push it # i ( cuModuleLoadData ( __gpu_ptr it module ) ( __gpu_ptr it image ) ) )
}

@ __cu_module_unload * Interp it → v {
    : i module ( __pop it )
    ( __push it # i ( cuModuleUnload module ) )
}

@ __cu_module_get_function * Interp it → v {
    : i name ( __pop it )
    : i hmod ( __pop it )
    : i hfunc ( __pop it )
    ( __push it # i ( cuModuleGetFunction ( __gpu_ptr it hfunc ) hmod # s ( __gpu_ptr it name ) ) )
}

@ __cu_mem_alloc * Interp it → v {
    : i bytesize ( __pop it )
    : i dptr ( __pop it )
    ( __push it # i ( cuMemAlloc ( __gpu_ptr it dptr ) bytesize ) )
}

@ __cu_mem_free * Interp it → v {
    : i dptr ( __pop it )
    ( __push it # i ( cuMemFree dptr ) )
}

@ __cu_memcpy_htod * Interp it → v {
    : i n ( __pop it )
    : i src ( __pop it )
    : i dst ( __pop it )
    ( __push it # i ( cuMemcpyHtoD dst ( __gpu_ptr it src ) n ) )
}

@ __cu_memcpy_dtoh * Interp it → v {
    : i n ( __pop it )
    : i src ( __pop it )
    : i dst ( __pop it )
    ( __push it # i ( cuMemcpyDtoH ( __gpu_ptr it dst ) src n ) )
}
// cuLaunchKernel's `params` is a guest void** — an array of guest pointers,
// each addressing an 8-byte argument cell in guest memory. CUDA needs a
// HOST void** whose entries are host addresses. Since the arg cells live in
// guest memory, translate each entry to (base + entry). The kernel's own
// parameter count bounds how many entries CUDA reads; the guest builds the
// array contiguously and each entry points at base_args + i*8, so the region
// is contiguous — reconstruct a host copy the same length as the guest array
// implies. We don't know the exact count here, so we translate a bounded run
// (up to __GPU_MAX_ARGS) of entries; CUDA reads only the real count and
// ignores the rest, and each translated entry is a valid host address.
@ __GPU_MAX_ARGS → i { ^ 64 }

@ __cu_launch_kernel * Interp it → v {
    : i extra ( __pop it )
    : i params ( __pop it )
    : i stream ( __pop it )
    : i sh ( __pop it )
    : i bz ( __pop it )
    : i by ( __pop it )
    : i bx ( __pop it )
    : i gz ( __pop it )
    : i gy ( __pop it )
    : i gx ( __pop it )
    : i f ( __pop it )
    : i base ( __gpu_base it )
    : i poff & params 4294967295
    // Build a host void** by translating each guest entry (guest ptr → host
    // ptr) into a fresh host buffer. Entry i lives at guest offset poff+i*8.
    : *u hostp ( nurl_alloc * ( __GPU_MAX_ARGS ) 8 )
    : i memlen . it mem_bytes
    : ~ i k 0
    ~ & < k ( __GPU_MAX_ARGS ) <= + + poff * k 8 8 memlen {
        : i ent & ( __mem_load it + poff * k 8 8 0 ) 4294967295
        ( nurl_poke hostp k ? == ent 0 0 + base ent )
        = k + k 1
    }
    : i rc # i ( cuLaunchKernel f # i32 gx # i32 gy # i32 gz # i32 bx # i32 by # i32 bz # i32 sh stream hostp extra )
    ( nurl_free # s hostp )
    ( __push it rc )
}

@ __cu_get_error_name * Interp it → v {
    // Writes a HOST const char* into the guest out-slot — unusable as a guest
    // offset. Write NULL so cuda_error_name falls back to a static string;
    // diagnostics only, never on the compute path.
    : i pstr ( __pop it )
    : i err ( __pop it )
    ( __mem_store it & pstr 4294967295 8 0 )
    ( __push it 0 )
}

@ __nvrtc_create * Interp it → v {
    : i incs ( __pop it )
    : i headers ( __pop it )
    : i nh ( __pop it )
    : i name ( __pop it )
    : i src ( __pop it )
    : i prog ( __pop it )
    ( __push it # i ( nvrtcCreateProgram ( __gpu_ptr it prog ) # s ( __gpu_ptr it src ) # s ( __gpu_ptr it name ) # i32 nh ( __gpu_ptr it headers ) ( __gpu_ptr it incs ) ) )
}
// nvrtcCompileProgram's `opts` is a guest char** — like cuLaunchKernel's
// params, each ENTRY is itself a guest pointer libnvrtc would dereference, so
// a host copy of the array is built with every entry translated (guest offset
// → host address). nopt bounds the array exactly; entries past guest memory
// (a hostile/broken module) become NULL rather than wild host pointers.
@ __nvrtc_compile * Interp it → v {
    : i opts ( __pop it )
    : i nopt ( __pop it )
    : i prog ( __pop it )
    : i n & nopt 4294967295
    : i poff & opts 4294967295
    ? | <= n 0 == poff 0 {
        ( __push it # i ( nvrtcCompileProgram prog # i32 nopt # *u 0 ) )
        ^ v
    } {}
    ? > n 256 { ( __trap it `nvrtcCompileProgram: too many options` ) ^ v } {}
    : i base ( __gpu_base it )
    : *u hostp ( nurl_alloc * n 8 )
    : i memlen . it mem_bytes
    : ~ i k 0
    ~ < k n {
        : ~ i ent 0
        ? <= + + poff * k 8 8 memlen { = ent & ( __mem_load it + poff * k 8 8 0 ) 4294967295 } {}
        ( nurl_poke hostp k ? == ent 0 0 + base ent )
        = k + k 1
    }
    : i rc # i ( nvrtcCompileProgram prog # i32 nopt hostp )
    ( nurl_free # s hostp )
    ( __push it rc )
}

@ __nvrtc_ptx_size * Interp it → v {
    : i sz ( __pop it )
    : i prog ( __pop it )
    ( __push it # i ( nvrtcGetPTXSize prog ( __gpu_ptr it sz ) ) )
}

@ __nvrtc_get_ptx * Interp it → v {
    : i ptx ( __pop it )
    : i prog ( __pop it )
    ( __push it # i ( nvrtcGetPTX prog ( __gpu_ptr it ptx ) ) )
}

@ __nvrtc_log_size * Interp it → v {
    : i sz ( __pop it )
    : i prog ( __pop it )
    ( __push it # i ( nvrtcGetProgramLogSize prog ( __gpu_ptr it sz ) ) )
}

@ __nvrtc_get_log * Interp it → v {
    : i log ( __pop it )
    : i prog ( __pop it )
    ( __push it # i ( nvrtcGetProgramLog prog ( __gpu_ptr it log ) ) )
}

@ __nvrtc_destroy * Interp it → v {
    : i prog ( __pop it )
    ( __push it # i ( nvrtcDestroyProgram ( __gpu_ptr it prog ) ) )
}

// GPU host-import dispatch (module "env"). Returns T if handled.
@ __gpu_dispatch * Interp it ( Vec u ) field → b {
    ? ( __feq field `cuInit` ) { ( __cu_init it ) ^ T } {}
    ? ( __feq field `cuDeviceGetCount` ) { ( __cu_device_get_count it ) ^ T } {}
    ? ( __feq field `cuDeviceGet` ) { ( __cu_device_get it ) ^ T } {}
    ? ( __feq field `cuDeviceGetName` ) { ( __cu_device_get_name it ) ^ T } {}
    ? ( __feq field `cuCtxCreate` ) { ( __cu_ctx_create it ) ^ T } {}
    ? ( __feq field `cuCtxCreate_v2` ) { ( __cu_ctx_create it ) ^ T } {}
    ? ( __feq field `cuCtxDestroy` ) { ( __cu_ctx_destroy it ) ^ T } {}
    ? ( __feq field `cuCtxSynchronize` ) { ( __cu_ctx_sync it ) ^ T } {}
    ? ( __feq field `cuModuleLoadData` ) { ( __cu_module_load it ) ^ T } {}
    ? ( __feq field `cuModuleUnload` ) { ( __cu_module_unload it ) ^ T } {}
    ? ( __feq field `cuModuleGetFunction` ) { ( __cu_module_get_function it ) ^ T } {}
    ? ( __feq field `cuMemAlloc` ) { ( __cu_mem_alloc it ) ^ T } {}
    ? ( __feq field `cuMemAlloc_v2` ) { ( __cu_mem_alloc it ) ^ T } {}
    ? ( __feq field `cuMemFree` ) { ( __cu_mem_free it ) ^ T } {}
    ? ( __feq field `cuMemFree_v2` ) { ( __cu_mem_free it ) ^ T } {}
    ? ( __feq field `cuMemcpyHtoD` ) { ( __cu_memcpy_htod it ) ^ T } {}
    ? ( __feq field `cuMemcpyHtoD_v2` ) { ( __cu_memcpy_htod it ) ^ T } {}
    ? ( __feq field `cuMemcpyDtoH` ) { ( __cu_memcpy_dtoh it ) ^ T } {}
    ? ( __feq field `cuMemcpyDtoH_v2` ) { ( __cu_memcpy_dtoh it ) ^ T } {}
    ? ( __feq field `cuLaunchKernel` ) { ( __cu_launch_kernel it ) ^ T } {}
    ? ( __feq field `cuGetErrorName` ) { ( __cu_get_error_name it ) ^ T } {}
    ? ( __feq field `nvrtcCreateProgram` ) { ( __nvrtc_create it ) ^ T } {}
    ? ( __feq field `nvrtcCompileProgram` ) { ( __nvrtc_compile it ) ^ T } {}
    ? ( __feq field `nvrtcGetPTXSize` ) { ( __nvrtc_ptx_size it ) ^ T } {}
    ? ( __feq field `nvrtcGetPTX` ) { ( __nvrtc_get_ptx it ) ^ T } {}
    ? ( __feq field `nvrtcGetProgramLogSize` ) { ( __nvrtc_log_size it ) ^ T } {}
    ? ( __feq field `nvrtcGetProgramLog` ) { ( __nvrtc_get_log it ) ^ T } {}
    ? ( __feq field `nvrtcDestroyProgram` ) { ( __nvrtc_destroy it ) ^ T } {}
    ^ F
}

// ── module "nurl_net": the guest's sockets are this process's ──────
//
// stdlib's runtime_ffi.c has no socket layer under __wasi__ (WASI
// preview1 can only accept on a socket the host preopened), so a NURL
// program compiled to wasm imports one function per raw socket call.
// Here they land on the very same runtime entry points a host build
// links directly — `nurl_tcp_listen` and friends are preamble-declared,
// so the guest's connect IS our connect. TLS needs nothing extra:
// stdlib's TLS 1.3 is pure NURL and runs inside the guest over these
// plaintext sockets.
//
// The guest is handed a TABLE INDEX, never the host's handle. Two
// reasons, and both are load-bearing:
//   • The host handle is a 64-bit pointer, and the guest's stdlib keeps
//     socket handles in an `s` field — 4 bytes on wasm32. A real handle
//     came back truncated and the next call dereferenced rubble.
//   • A handle the guest can forge is a host pointer the runtime would
//     dereference on demand. An index can only miss.

// Guest (ptr,len) span → host pointer; 0 when it leaves linear memory.
@ __net_span * Interp it i off i len → s {
    : i o & off 4294967295
    : i n . it mem_bytes
    ? | < len 0 > + o len n { ^ # s 0 } {}
    ^ # s + # i ( vec_data [u] . it mem ) o
}

// Guest pointer to a NUL-terminated string → host `s`. A string with no
// terminator inside linear memory reads as empty rather than running off
// the end of the buffer.
@ __net_cstr * Interp it i off → s {
    : i o & off 4294967295
    : i n . it mem_bytes
    ? >= o n { ^ `` } {}
    : ~ i k o
    : ~ b term F
    ~ & < k n ! term {
        ?? ( vec_get [u] . it mem k ) {
            T c → { ? == # i c 0 { = term T } { = k + k 1 } }
            F → { = k n }
        }
    }
    ? term { ^ # s + # i ( vec_data [u] . it mem ) o } {}
    ^ ``
}

// Copy a host string into the guest's buffer, truncating at `cap`, and
// answer the byte count — the import ABI for every host call that
// produces text (addresses, DNS answers), because the host cannot
// allocate inside the guest's linear memory.
@ __net_put_str * Interp it i off i cap s src → i {
    ? == # i src 0 { ^ 0 } {}
    : i n ( nurl_str_len src )
    : ~ i m n
    ? > m cap { = m cap } {}
    ? < m 0 { = m 0 } {}
    : ~ i k 0
    ~ < k m { ( __mem_store it + off k 1 ( nurl_str_get src k ) ) = k + k 1 }
    ^ m
}

// Same, for an OWNED host string: copied out, then freed.
@ __net_put_owned * Interp it i off i cap s src → i {
    ? == # i src 0 { ^ 0 } {}
    : i n ( __net_put_str it off cap src )
    ( nurl_free src )
    ^ n
}

// The handle table is per-INSTANCE, so every thread of a threaded guest
// shares it — and they open sockets concurrently (a relay's accept
// fibers, a worker, an MCP coordinator, all in one module). Without a
// lock two registrations race for the same free slot: one handle
// overwrites the other, and the loser then reads a socket that belongs
// to somebody else. That surfaced far away as a wild pointer inside the
// guest's own frame parser. The critical sections here are table-only —
// no blocking host call happens while the lock is held.
@ __net_reg * Interp it0 i h i kind → i {
    ? == h 0 { ^ 0 } {}
    : *Interp it ( __host it0 )
    ( __atom_lock )
    : i n ( vec_len [i] . it nethandles )
    : ~ i slot 0
    : ~ i k 1
    ~ & < k n == slot 0 {
        ?? ( vec_get [i] . it nethandles k ) { T v → { ? == v 0 { = slot k } {} } F → {} }
        = k + k 1
    }
    ? == slot 0 {
        ( vec_push [i] . it nethandles h )
        ( vec_push [i] . it netkinds kind )
        ( __atom_unlock )
        ^ n
    } {}
    ( vec_set [i] . it nethandles slot h )
    ( vec_set [i] . it netkinds slot kind )
    ( __atom_unlock )
    ^ slot
}

// Guest index → host handle; 0 for anything the guest made up.
@ __net_h * Interp it0 i idx → i {
    : *Interp it ( __host it0 )
    ? <= idx 0 { ^ 0 } {}
    ( __atom_lock )
    : ~ i h 0
    ? < idx ( vec_len [i] . it nethandles ) {
        = h ?? ( vec_get [i] . it nethandles idx ) { T v → v F → 0 }
    } {}
    ( __atom_unlock )
    ^ h
}

// Retire an index — the host handle is already closed by the caller.
@ __net_drop * Interp it0 i idx → v {
    : *Interp it ( __host it0 )
    ( __atom_lock )
    ? | <= idx 0 >= idx ( vec_len [i] . it nethandles ) { ( __atom_unlock ) ^ v } {}
    ( vec_set [i] . it nethandles idx 0 )
    ( vec_set [i] . it netkinds idx 0 )
    ( __atom_unlock )
}

// Close every socket the guest left open. A wasm module that exits (or
// traps) mid-flight would otherwise leak the host's descriptors, which
// matters most for the embedded case: swarm-mcp runs kernels in-process.
@ interp_net_close_all * Interp it → v {
    : i n ( vec_len [i] . it nethandles )
    : ~ i k 1
    ~ < k n {
        : i h ?? ( vec_get [i] . it nethandles k ) { T v → v F → 0 }
        ? != h 0 {
            : i kind ?? ( vec_get [i] . it netkinds k ) { T v → v F → 0 }
            ? == kind 2 { ( nurl_udp_close h ) } { ( nurl_tcp_close h ) }
            ( vec_set [i] . it nethandles k 0 )
            ( vec_set [i] . it netkinds k 0 )
        } {}
        = k + k 1
    }
}

@ __net_dispatch * Interp it ( Vec u ) field → b {
    // ── TCP ──
    ? ( __feq field `tcp_listen` ) {
        : i backlog ( __pop it ) : i port ( __pop it ) : i hp ( __pop it )
        ( __push it ( __net_reg it ( nurl_tcp_listen ( __net_cstr it hp ) port backlog ) 1 ) ) ^ T } {}
    ? ( __feq field `tcp_connect` ) {
        : i port ( __pop it ) : i hp ( __pop it )
        ( __push it ( __net_reg it ( nurl_tcp_connect ( __net_cstr it hp ) port ) 1 ) ) ^ T } {}
    ? ( __feq field `tcp_accept` ) {
        : i h ( __net_h it ( __pop it ) )
        ( __push it ? == h 0 0 ( __net_reg it ( nurl_tcp_accept h ) 1 ) ) ^ T } {}
    ? ( __feq field `tcp_read` ) {
        : i n ( __pop it ) : i bp ( __pop it ) : i h ( __net_h it ( __pop it ) )
        : s p ( __net_span it bp n )
        ( __push it ? | == h 0 == # i p 0 -1 ( nurl_tcp_read h p n ) ) ^ T } {}
    ? ( __feq field `tcp_write` ) {
        : i n ( __pop it ) : i bp ( __pop it ) : i h ( __net_h it ( __pop it ) )
        : s p ( __net_span it bp n )
        ( __push it ? | == h 0 == # i p 0 -1 ( nurl_tcp_write h p n ) ) ^ T } {}
    ? ( __feq field `tcp_close` ) {
        : i idx ( __pop it ) : i h ( __net_h it idx )
        ? != h 0 { ( nurl_tcp_close h ) ( __net_drop it idx ) } {}
        ^ T } {}
    ? ( __feq field `tcp_shutdown` ) {
        : i h ( __net_h it ( __pop it ) )
        ? != h 0 { ( nurl_tcp_shutdown h ) } {}
        ^ T } {}
    ? ( __feq field `tcp_err_kind` ) {
        : i h ( __net_h it ( __pop it ) )
        ( __push it ? == h 0 8 ( nurl_tcp_err_kind h ) ) ^ T } {}
    ? ( __feq field `tcp_set_timeout` ) {
        : i ms ( __pop it ) : i h ( __net_h it ( __pop it ) )
        ? != h 0 { ( nurl_tcp_set_timeout h ms ) } {}
        ^ T } {}
    ? ( __feq field `tcp_timeout_ms` ) {
        : i h ( __net_h it ( __pop it ) )
        ( __push it ? == h 0 0 ( nurl_tcp_timeout_ms h ) ) ^ T } {}
    ? ( __feq field `tcp_peer_addr` ) {
        : i cap ( __pop it ) : i bp ( __pop it ) : i h ( __net_h it ( __pop it ) )
        ( __push it ? == h 0 0 ( __net_put_str it bp cap ( nurl_tcp_peer_addr h ) ) ) ^ T } {}
    ? ( __feq field `tcp_local_addr` ) {
        : i cap ( __pop it ) : i bp ( __pop it ) : i h ( __net_h it ( __pop it ) )
        ( __push it ? == h 0 0 ( __net_put_owned it bp cap ( nurl_tcp_local_addr h ) ) ) ^ T } {}
    ? ( __feq field `tcp_get_fd` ) {
        : i h ( __net_h it ( __pop it ) )
        ( __push it ? == h 0 -1 ( nurl_tcp_get_fd h ) ) ^ T } {}
    ? ( __feq field `tcp_set_nonblock` ) {
        : i on ( __pop it ) : i h ( __net_h it ( __pop it ) )
        ? != h 0 { ( nurl_tcp_set_nonblock h on ) } {}
        ^ T } {}
    ? ( __feq field `tcp_ref` ) {
        : i h ( __net_h it ( __pop it ) )
        ? != h 0 { ( nurl_tcp_ref h ) } {}
        ^ T } {}
    ? ( __feq field `tcp_unref` ) {
        : i h ( __net_h it ( __pop it ) )
        ? != h 0 { ( nurl_tcp_unref h ) } {}
        ^ T } {}
    // ── UDP ──
    ? ( __feq field `udp_bind` ) {
        : i port ( __pop it ) : i hp ( __pop it )
        ( __push it ( __net_reg it ( nurl_udp_bind ( __net_cstr it hp ) port ) 2 ) ) ^ T } {}
    ? ( __feq field `udp_connect` ) {
        : i port ( __pop it ) : i hp ( __pop it ) : i h ( __net_h it ( __pop it ) )
        ( __push it ? == h 0 -1 ( nurl_udp_connect h ( __net_cstr it hp ) port ) ) ^ T } {}
    ? ( __feq field `udp_send` ) {
        : i n ( __pop it ) : i bp ( __pop it ) : i h ( __net_h it ( __pop it ) )
        : s p ( __net_span it bp n )
        ( __push it ? | == h 0 == # i p 0 -1 ( nurl_udp_send h p n ) ) ^ T } {}
    ? ( __feq field `udp_recv` ) {
        : i n ( __pop it ) : i bp ( __pop it ) : i h ( __net_h it ( __pop it ) )
        : s p ( __net_span it bp n )
        ( __push it ? | == h 0 == # i p 0 -1 ( nurl_udp_recv h p n ) ) ^ T } {}
    ? ( __feq field `udp_send_to` ) {
        : i port ( __pop it ) : i hp ( __pop it ) : i n ( __pop it ) : i bp ( __pop it ) : i h ( __net_h it ( __pop it ) )
        : s p ( __net_span it bp n )
        ( __push it ? | == h 0 == # i p 0 -1 ( nurl_udp_send_to h p n ( __net_cstr it hp ) port ) ) ^ T } {}
    ? ( __feq field `udp_recv_from` ) {
        : i n ( __pop it ) : i bp ( __pop it ) : i h ( __net_h it ( __pop it ) )
        : s p ( __net_span it bp n )
        ( __push it ? | == h 0 == # i p 0 -1 ( nurl_udp_recv_from h p n ) ) ^ T } {}
    ? ( __feq field `udp_close` ) {
        : i idx ( __pop it ) : i h ( __net_h it idx )
        ? != h 0 { ( nurl_udp_close h ) ( __net_drop it idx ) } {}
        ^ T } {}
    ? ( __feq field `udp_err_kind` ) {
        : i h ( __net_h it ( __pop it ) )
        ( __push it ? == h 0 8 ( nurl_udp_err_kind h ) ) ^ T } {}
    ? ( __feq field `udp_peer_addr` ) {
        : i cap ( __pop it ) : i bp ( __pop it ) : i h ( __net_h it ( __pop it ) )
        ( __push it ? == h 0 0 ( __net_put_str it bp cap ( nurl_udp_peer_addr h ) ) ) ^ T } {}
    ? ( __feq field `udp_local_addr` ) {
        : i cap ( __pop it ) : i bp ( __pop it ) : i h ( __net_h it ( __pop it ) )
        ( __push it ? == h 0 0 ( __net_put_owned it bp cap ( nurl_udp_local_addr h ) ) ) ^ T } {}
    ? ( __feq field `udp_set_timeout` ) {
        : i ms ( __pop it ) : i h ( __net_h it ( __pop it ) )
        ? != h 0 { ( nurl_udp_set_timeout h ms ) } {}
        ^ T } {}
    ? ( __feq field `udp_set_nonblock` ) {
        : i on ( __pop it ) : i h ( __net_h it ( __pop it ) )
        ? != h 0 { ( nurl_udp_set_nonblock h on ) } {}
        ^ T } {}
    ? ( __feq field `udp_family` ) {
        : i h ( __net_h it ( __pop it ) )
        ( __push it ? == h 0 -1 ( nurl_udp_family h ) ) ^ T } {}
    ? ( __feq field `udp_get_fd` ) {
        : i h ( __net_h it ( __pop it ) )
        ( __push it ? == h 0 -1 ( nurl_udp_get_fd h ) ) ^ T } {}
    ? ( __feq field `udp_set_broadcast` ) {
        : i on ( __pop it ) : i h ( __net_h it ( __pop it ) )
        ( __push it ? == h 0 -1 ( nurl_udp_set_broadcast h on ) ) ^ T } {}
    ? ( __feq field `udp_join_group` ) {
        : i ip ( __pop it ) : i gp ( __pop it ) : i h ( __net_h it ( __pop it ) )
        ( __push it ? == h 0 -1 ( nurl_udp_join_group h ( __net_cstr it gp ) ( __net_cstr it ip ) ) ) ^ T } {}
    ? ( __feq field `udp_leave_group` ) {
        : i ip ( __pop it ) : i gp ( __pop it ) : i h ( __net_h it ( __pop it ) )
        ( __push it ? == h 0 -1 ( nurl_udp_leave_group h ( __net_cstr it gp ) ( __net_cstr it ip ) ) ) ^ T } {}
    ? ( __feq field `udp_set_multicast_ttl` ) {
        : i ttl ( __pop it ) : i h ( __net_h it ( __pop it ) )
        ( __push it ? == h 0 -1 ( nurl_udp_set_multicast_ttl h ttl ) ) ^ T } {}
    ? ( __feq field `udp_set_multicast_loop` ) {
        : i on ( __pop it ) : i h ( __net_h it ( __pop it ) )
        ( __push it ? == h 0 -1 ( nurl_udp_set_multicast_loop h on ) ) ^ T } {}
    // ── DNS ──
    ? ( __feq field `dns_resolve` ) {
        : i cap ( __pop it ) : i bp ( __pop it ) : i hp ( __pop it )
        ( __push it ( __net_put_owned it bp cap ( nurl_dns_resolve ( __net_cstr it hp ) ) ) ) ^ T } {}
    ? ( __feq field `dns_resolve_port` ) {
        : i cap ( __pop it ) : i bp ( __pop it ) : i port ( __pop it ) : i hp ( __pop it )
        ( __push it ( __net_put_owned it bp cap ( nurl_dns_resolve_port ( __net_cstr it hp ) port ) ) ) ^ T } {}
    ? ( __feq field `dns_reverse` ) {
        : i cap ( __pop it ) : i bp ( __pop it ) : i ip ( __pop it )
        ( __push it ( __net_put_owned it bp cap ( nurl_dns_reverse ( __net_cstr it ip ) ) ) ) ^ T } {}
    ^ F
}

// ── module "wasi": thread-spawn ───────────────────────────────────
//
// wasi-threads' one import. The guest hands over a pointer to its own
// start-argument block; the runtime creates a thread, gives it a fresh
// instance of the module (own stacks, own globals) over the SAME linear
// memory, and calls the module's exported `wasi_thread_start(tid, arg)`.
//
// The one thing done here that the proposal leaves to the guest's libc
// is setting `__stack_pointer`: a thread needs a stack of its own, and
// C cannot assign a wasm global. So the guest allocates the stack, writes
// its top into the start block (offset 8, our runtime_ffi.c layout), and
// the host sets the new instance's exported `__stack_pointer` from it
// before the first call. Without the export the spawn is refused rather
// than letting two threads share one stack.
@ __wasi_thread_spawn * Interp it → v {
    : i start_arg ( __pop it )
    : *Interp ho ( __host it )
    : *Module m # *Module . ho mod
    ? == . ho tstart_fidx -2 {
        = . ho tstart_fidx ( module_export_func m `wasi_thread_start` )
        = . ho sp_global ( module_export_global m `__stack_pointer` )
    } {}
    : i fidx . ho tstart_fidx
    : i spg . ho sp_global
    ? | < fidx 0 < spg 0 { ( __push it -1 ) ^ v } {}
    : i stack_top ( __m_get_u32 it + start_arg 8 )
    ? == stack_top 0 { ( __push it -1 ) ^ v } {}
    ( __atom_lock )
    : i tid . ho next_tid
    = . ho next_tid + tid 1
    ( __atom_unlock )
    : *TStart th # *TStart ( nurl_alloc Z TStart )
    = . th f \ → v {
        : *Interp child ( interp_thread_new ho )
        ( vec_set [i] . child globals spg stack_top )
        ( vec_push [i] . child vs tid )
        ( vec_push [i] . child vs start_arg )
        ( exec_func child fidx )
        // A trap kills only this thread, so it has to be reported here or
        // it is silent: the guest's join just never completes.
        ? ( interp_trapped child ) {
            ( nurl_eprint `wasmtime: thread trap: ` )
            ( nurl_eprintln ( string_data ( bytes_to_str . child trapmsg ) ) )
        } {}
        ( interp_flush child )
        ( interp_free child )
    }
    ( __atom_lock )
    ( vec_push [s] . ho thread_holders # s th )
    ( __atom_unlock )
    ?? ( thread_spawn . th f ) {
        T t → {
            ( __atom_lock )
            ( vec_push [i] . ho thread_joins # i . t raw )
            ( __atom_unlock )
            ( __push it tid )
        }
        F e → { ( __push it -1 ) }
    }
}

@ __wasi_dispatch * Interp it ( Vec u ) mod ( Vec u ) field → v {
    ? ( __feq mod `wasi` ) {
        ? ( __feq field `thread-spawn` ) { ( __wasi_thread_spawn it ) ^ v } {}
        ( __trap_named it `unsupported wasi import: ` field ) ^ v
    } {}
    ? ( __feq mod `nurl_net` ) {
        ? ! . it net_ok { ( __trap it `nurl_net host imports are disabled (pass --allow-net to enable)` ) ^ v } {}
        ? ( __net_dispatch it field ) { ^ v } {}
        ( __trap_named it `unsupported nurl_net import: ` field ) ^ v
    } {}
    ? ( __feq mod `env` ) {
        ? ! . it gpu_ok { ( __trap it `env/GPU host imports are disabled (pass --allow-gpu to enable)` ) ^ v } {}
        ? ( __gpu_dispatch it field ) { ^ v } {}
        ( __trap_named it `unsupported env import: ` field ) ^ v
    } {}
    ? ! ( __feq mod `wasi_snapshot_preview1` ) {
        ( __trap_named it `unsupported import module: ` mod ) ^ v } {}
    ? ( __feq field `proc_exit` ) { ( __wasi_proc_exit it ) ^ v } {}
    ? ( __feq field `fd_write` ) { ( __wasi_fd_write it ) ^ v } {}
    ? ( __feq field `fd_read` ) { ( __wasi_fd_read it ) ^ v } {}
    ? ( __feq field `fd_seek` ) { ( __wasi_fd_seek it ) ^ v } {}
    ? ( __feq field `fd_tell` ) { ( __wasi_fd_tell it ) ^ v } {}
    ? ( __feq field `fd_pread` ) { ( __wasi_fd_pread it ) ^ v } {}
    ? ( __feq field `fd_pwrite` ) { ( __wasi_fd_pwrite it ) ^ v } {}
    ? ( __feq field `fd_sync` ) { ( __wasi_fd_sync it ) ^ v } {}
    ? ( __feq field `fd_datasync` ) { ( __wasi_fd_sync it ) ^ v } {}
    ? ( __feq field `fd_close` ) { ( __wasi_fd_close it ) ^ v } {}
    ? ( __feq field `fd_readdir` ) { ( __wasi_fd_readdir it ) ^ v } {}
    ? ( __feq field `path_open` ) { ( __wasi_path_open it ) ^ v } {}
    ? ( __feq field `path_create_directory` ) { ( __wasi_path_create_directory it ) ^ v } {}
    ? ( __feq field `path_remove_directory` ) { ( __wasi_path_remove_directory it ) ^ v } {}
    ? ( __feq field `path_unlink_file` ) { ( __wasi_path_unlink_file it ) ^ v } {}
    ? ( __feq field `path_rename` ) { ( __wasi_path_rename it ) ^ v } {}
    ? ( __feq field `path_filestat_get` ) { ( __wasi_path_filestat_get it ) ^ v } {}
    ? ( __feq field `args_sizes_get` ) { ( __wasi_args_sizes_get it ) ^ v } {}
    ? ( __feq field `args_get` ) { ( __wasi_args_get it ) ^ v } {}
    ? ( __feq field `fd_prestat_get` ) { ( __wasi_fd_prestat_get it ) ^ v } {}
    ? ( __feq field `fd_prestat_dir_name` ) { ( __wasi_fd_prestat_dir_name it ) ^ v } {}
    ? ( __feq field `fd_fdstat_get` ) { ( __wasi_fd_fdstat_get it ) ^ v } {}
    ? ( __feq field `fd_filestat_get` ) { ( __wasi_fd_filestat_get it ) ^ v } {}
    ? ( __feq field `environ_sizes_get` ) { ( __wasi_environ_sizes_get it ) ^ v } {}
    ? ( __feq field `environ_get` ) { ( __wasi_environ_get it ) ^ v } {}
    ? ( __feq field `clock_time_get` ) { ( __wasi_clock_time_get it ) ^ v } {}
    ? ( __feq field `random_get` ) { ( __wasi_random_get it ) ^ v } {}
    ? ( __feq field `poll_oneoff` ) { ( __wasi_poll_oneoff it ) ^ v } {}
    ? ( __feq field `fd_fdstat_set_flags` ) { ( __pop it ) ( __pop it ) ( __push it 0 ) ^ v } {}
    ? ( __feq field `sched_yield` ) { ( __push it 0 ) ^ v } {}
    ( __trap_named it `unsupported wasi import: ` field )
}

// ── sign-extension ops + 0xfc-prefixed bulk memory / saturating trunc ──

// Sign-extend the low `nbits` of v.
@ __sext i v i nbits → i {
    : i mask - << 1 nbits 1
    : i lo & v mask
    ? != 0 & lo << 1 - nbits 1 { ^ - lo << 1 nbits } { ^ lo }
}

// Callers bounds-check dst/src/n before calling (memory.copy / memory.fill
// / memory.init do it up front, spec-style); these just move the bytes.
// nurl_memmove is the overlap-safe one — memory.copy allows aliasing.
@ __mem_copy * Interp it i dst i src i n → v {
    ? <= n 0 { ^ v } {}
    : s base # s ( vec_data [u] . it mem )
    ( nurl_memmove # s + # i base dst # s + # i base src n )
}

@ __mem_fill * Interp it i dst i val i n → v {
    ? <= n 0 { ^ v } {}
    : s base # s ( vec_data [u] . it mem )
    ( nurl_memset # s + # i base dst & val 255 n )
}

// The *DataSeg / *ElemSeg at segment index k (#s 0 if out of range).
@ __data_at * Module m i k → s {
    ? | < k 0 >= k ( vec_len [s] . m datas ) { ^ # s 0 } {}
    ^ ?? ( vec_get [s] . m datas k ) { T x → x F → # s 0 }
}

@ __elem_at * Module m i k → s {
    ? | < k 0 >= k ( vec_len [s] . m elems ) { ^ # s 0 } {}
    ^ ?? ( vec_get [s] . m elems k ) { T x → x F → # s 0 }
}

// `sub` and the one index operand some subops carry (`bop`) arrive predecoded.
// ── 0xfe: the threads proposal's atomics ──────────────────────────
//
// Guest threads run on real host threads over one shared linear memory,
// so "atomic" has to mean atomic on the host too. An interpreter cannot
// lean on the CPU's atomics for a read-modify-write it performs as three
// separate steps, so every atomic op takes one process-wide lock. That
// makes the whole family sequentially consistent by construction —
// slower than a JIT's lock-free lowering, and the semantics the guest
// was promised.
//
// `wait` / `notify` are the futex pair the guest's mutexes and joins are
// built from. Waiters block on a single condvar and re-check their own
// address on wake, which is why a notify may wake more sleepers than it
// names: spurious wakeups are explicitly allowed, and the guest already
// re-tests its condition in a loop.

: ~ i g_atom_mx 0  // *pthread_mutex_t, the one atomics lock
: ~ i g_atom_cv 0  // *pthread_cond_t, where waiters sleep
: ~ i g_atom_gen 0  // bumped by every notify; a waiter watches it change
: ~ i g_atom_waiters 0  // sleepers right now, for notify's return value

// Created once, from the thread that instantiates — before any guest
// thread exists, so this is not itself a race.
@ __atom_init → v {
    ? != g_atom_mx 0 { ^ v } {}
    : s m ( nurl_zalloc ( nurl_native_sizeof `pthread_mutex_t` ) )
    ( pthread_mutex_init # *u m # *u 0 )
    = g_atom_mx # i m
    : s c ( nurl_zalloc ( nurl_native_sizeof `pthread_cond_t` ) )
    ( pthread_cond_init # *u c # *u 0 )
    = g_atom_cv # i c
}

@ __atom_lock → v { ( __atom_init ) ( pthread_mutex_lock # *u # s g_atom_mx ) }

@ __atom_unlock → v { ( pthread_mutex_unlock # *u # s g_atom_mx ) }

// Natural alignment is required by the spec: an unaligned atomic traps
// rather than being emulated.
@ __atom_check * Interp it i ea i w → b {
    ? != 0 % ea w { ( __trap it `unaligned atomic access` ) ^ F } {}
    ? | < ea 0 > + ea w . it mem_bytes { ( __trap it `atomic access out of bounds` ) ^ F } {}
    ^ T
}

// Mask a value to `w` bytes (w = 8 leaves it alone).
@ __atom_mask i v i w → i {
    ? >= w 8 { ^ v } {}
    ^ & v - << 1 * 8 w 1
}

@ __atom_notify i count → i {
    ( __atom_lock )
    = g_atom_gen + g_atom_gen 1
    : i woke ? < count g_atom_waiters count g_atom_waiters
    ( pthread_cond_broadcast # *u # s g_atom_cv )
    ( __atom_unlock )
    ^ ? < woke 0 0 woke
}

// 0 = woken, 1 = the value had already changed, 2 = timed out.
// `timeout` is nanoseconds, negative for "no timeout".
@ __atom_wait * Interp it i ea i w i expected i timeout → i {
    ( __atom_lock )
    : i cur ( __mem_load it ea w 0 )
    ? != cur ( __atom_mask expected w ) { ( __atom_unlock ) ^ 1 } {}
    : i g0 g_atom_gen
    = g_atom_waiters + g_atom_waiters 1
    : ~ i res 0
    ? < timeout 0 {
        ~ == g_atom_gen g0 { ( pthread_cond_wait # *u # s g_atom_cv # *u # s g_atom_mx ) }
    } {
        // A finite timeout polls rather than using pthread_cond_timedwait:
        // one less FFI surface (and one less struct timespec) for a path
        // the guest's own mutexes take only when they gave up spinning.
        : i deadline + ( monotonic_ns ) timeout
        ~ & == g_atom_gen g0 == res 0 {
            ( __atom_unlock )
            ( sleep_ms 1 )
            ( __atom_lock )
            ? >= ( monotonic_ns ) deadline { = res 2 } {}
        }
    }
    = g_atom_waiters - g_atom_waiters 1
    ( __atom_unlock )
    ^ res
}

// Byte width of an atomic load/store/rmw sub-opcode's access, given the
// position inside its seven-op group: [.rmw, i64.rmw, rmw8_u, rmw16_u,
// i64.rmw8_u, i64.rmw16_u, i64.rmw32_u].
@ __atom_rmw_width i k → i {
    ? == k 0 { ^ 4 } {}
    ? == k 1 { ^ 8 } {}
    ? == k 2 { ^ 1 } {}
    ? == k 3 { ^ 2 } {}
    ? == k 4 { ^ 1 } {}
    ? == k 5 { ^ 2 } {}
    ^ 4
}

// Operand counts, so the predecoder can size the bridge. Returns
// pops << 1 | push.
@ __atom_shape i sub → i {
    ? == sub 0 { ^ 5 } {}  // notify: 2 pops, 1 push
    ? | == sub 1 == sub 2 { ^ 7 } {}  // wait32/wait64: 3 pops, 1 push
    ? == sub 3 { ^ 0 } {}  // fence
    ? & >= sub 16 <= sub 22 { ^ 3 } {}  // load: 1 pop, 1 push
    ? & >= sub 23 <= sub 29 { ^ 4 } {}  // store: 2 pops, no push
    ? & >= sub 72 <= sub 78 { ^ 7 } {}  // cmpxchg: 3 pops, 1 push
    ^ 5  // rmw: 2 pops, 1 push
}

@ __exec_atomic * Interp it i sub i off → v {
    ? == sub 3 { ^ v } {}  // atomic.fence — the lock is the fence
    ? == sub 0 {  // memory.atomic.notify
        : i count ( __pop it )
        : i ea + & ( __pop it ) 4294967295 off
        ? ( __atom_check it ea 4 ) {} { ^ v }
        ( __push it ( __atom_notify count ) )
        ^ v
    } {}
    ? | == sub 1 == sub 2 {  // memory.atomic.wait32 / wait64
        : i w ? == sub 1 4 8
        : i timeout ( __pop it )
        : i expected ( __pop it )
        : i ea + & ( __pop it ) 4294967295 off
        ? ( __atom_check it ea w ) {} { ^ v }
        ( __push it ( __atom_wait it ea w expected timeout ) )
        ^ v
    } {}
    ? & >= sub 16 <= sub 22 {  // atomic loads — zero-extended
        : i w ? == sub 16 4 ? == sub 17 8 ? == sub 18 1 ? == sub 19 2 ? == sub 20 1 ? == sub 21 2 4
        : i ea + & ( __pop it ) 4294967295 off
        ? ( __atom_check it ea w ) {} { ^ v }
        ( __atom_lock )
        : i got ( __mem_load it ea w 0 )
        ( __atom_unlock )
        ( __push it got )
        ^ v
    } {}
    ? & >= sub 23 <= sub 29 {  // atomic stores
        : i w ? == sub 23 4 ? == sub 24 8 ? == sub 25 1 ? == sub 26 2 ? == sub 27 1 ? == sub 28 2 4
        : i val ( __pop it )
        : i ea + & ( __pop it ) 4294967295 off
        ? ( __atom_check it ea w ) {} { ^ v }
        ( __atom_lock )
        ( __mem_store it ea w val )
        ( __atom_unlock )
        ^ v
    } {}
    ? & >= sub 72 <= sub 78 {  // atomic cmpxchg
        : i w ( __atom_rmw_width - sub 72 )
        : i replacement ( __pop it )
        : i expected ( __pop it )
        : i ea + & ( __pop it ) 4294967295 off
        ? ( __atom_check it ea w ) {} { ^ v }
        ( __atom_lock )
        : i old ( __mem_load it ea w 0 )
        ? == old ( __atom_mask expected w ) { ( __mem_store it ea w replacement ) } {}
        ( __atom_unlock )
        ( __push it old )
        ^ v
    } {}
    ? & >= sub 30 <= sub 71 {  // add/sub/and/or/xor/xchg, seven ops each
        : i group / - sub 30 7
        : i w ( __atom_rmw_width % - sub 30 7 )
        : i val ( __pop it )
        : i ea + & ( __pop it ) 4294967295 off
        ? ( __atom_check it ea w ) {} { ^ v }
        ( __atom_lock )
        : i old ( __mem_load it ea w 0 )
        : i nv ? == group 0 + old val ? == group 1 - old val ? == group 2 & old val ? == group 3 | old val ? == group 4 ^^ old val val
        ( __mem_store it ea w ( __atom_mask nv w ) )
        ( __atom_unlock )
        ( __push it old )
        ^ v
    } {}
    ( __trap it `unsupported atomic opcode` )
}

@ __exec_fc * Interp it i sub i bop → v {
    ? == sub 8 {  // memory.init dataidx: copy from a passive data segment
        : i didx bop
        : i n ( __u32 ( __pop it ) )
        : i src ( __u32 ( __pop it ) )
        : i dst ( __u32 ( __pop it ) )
        : *Module m # *Module . it mod
        : s dp ( __data_at m didx )
        : i dropped ?? ( vec_get [i] . it data_dropped didx ) { T x → x F → 1 }
        ? | == # i dp 0 & == dropped 1 > n 0 { ( __trap it `memory.init: dropped or bad data segment` ) ^ v } {}
        : *DataSeg ds # *DataSeg dp
        ? | > + src n ( vec_len [u] . ds bytes ) > + dst n . it mem_bytes {
            ( __trap it `out of bounds memory access` ) ^ v } {}
        : ~ i k 0
        ~ < k n {
            ( vec_set [u] . it mem + dst k ?? ( vec_get [u] . ds bytes + src k ) { T x → x F → # u 0 } )
            = k + k 1
        }
        ^ v
    } {}
    ? == sub 9 {  // data.drop
        : i didx bop
        ? < didx ( vec_len [i] . it data_dropped ) { ( vec_set [i] . it data_dropped didx 1 ) } {}
        ^ v
    } {}
    ? == sub 10 {  // memory.copy — bounds checked up front (no partial writes)
        : i n ( __u32 ( __pop it ) )
        : i src ( __u32 ( __pop it ) )
        : i dst ( __u32 ( __pop it ) )
        : i mn . it mem_bytes
        ? | > + src n mn > + dst n mn { ( __trap it `out of bounds memory access` ) ^ v } {}
        ( __mem_copy it dst src n )
        ^ v
    } {}
    ? == sub 11 {  // memory.fill — bounds checked up front
        : i n ( __u32 ( __pop it ) )
        : i val & ( __pop it ) 255
        : i dst ( __u32 ( __pop it ) )
        ? > + dst n . it mem_bytes { ( __trap it `out of bounds memory access` ) ^ v } {}
        ( __mem_fill it dst val n )
        ^ v
    } {}
    ? == sub 12 {  // table.init elemidx: copy from a passive element segment
        : i eidx bop
        : i n ( __u32 ( __pop it ) )
        : i src ( __u32 ( __pop it ) )
        : i dst ( __u32 ( __pop it ) )
        : *Module m # *Module . it mod
        : s ep ( __elem_at m eidx )
        : i dropped ?? ( vec_get [i] . it elem_dropped eidx ) { T x → x F → 1 }
        ? | == # i ep 0 & == dropped 1 > n 0 { ( __trap it `table.init: dropped or bad element segment` ) ^ v } {}
        : *ElemSeg es # *ElemSeg ep
        ? | > + src n ( vec_len [i] . es funcs ) > + dst n ( vec_len [i] . it table ) {
            ( __trap it `out of bounds table access` ) ^ v } {}
        : ~ i k 0
        ~ < k n {
            ( vec_set [i] . it table + dst k ?? ( vec_get [i] . es funcs + src k ) { T x → x F → -1 } )
            = k + k 1
        }
        ^ v
    } {}
    ? == sub 13 {  // elem.drop
        : i eidx bop
        ? < eidx ( vec_len [i] . it elem_dropped ) { ( vec_set [i] . it elem_dropped eidx 1 ) } {}
        ^ v
    } {}
    ? == sub 14 {  // table.copy — overlap-safe within the one table
        : i n ( __u32 ( __pop it ) )
        : i src ( __u32 ( __pop it ) )
        : i dst ( __u32 ( __pop it ) )
        : i tn ( vec_len [i] . it table )
        ? | > + src n tn > + dst n tn { ( __trap it `out of bounds table access` ) ^ v } {}
        ? > dst src {
            : ~ i k - n 1
            ~ >= k 0 { ( vec_set [i] . it table + dst k ?? ( vec_get [i] . it table + src k ) { T x → x F → -1 } ) = k - k 1 }
        } {
            : ~ i k 0
            ~ < k n { ( vec_set [i] . it table + dst k ?? ( vec_get [i] . it table + src k ) { T x → x F → -1 } ) = k + k 1 }
        }
        ^ v
    } {}
    ? == sub 15 {  // table.grow: [init n] → old size, or −1 past the maximum
        : i n ( __u32 ( __pop it ) )
        : i init ( __pop it )
        : *Module m # *Module . it mod
        : i old ( vec_len [i] . it table )
        : ~ i limit 10000000
        ? > . m table_max 0 { = limit . m table_max } {}
        ? > + old n limit { ( __push it -1 ) ^ v } {}
        : ~ i k 0
        ~ < k n { ( vec_push [i] . it table init ) = k + k 1 }
        ( __push it old )
        ^ v
    } {}
    ? == sub 16 { ( __push it ( vec_len [i] . it table ) ) ^ v } {}  // table.size
    ? == sub 17 {  // table.fill
        : i n ( __u32 ( __pop it ) )
        : i val ( __pop it )
        : i dst ( __u32 ( __pop it ) )
        ? > + dst n ( vec_len [i] . it table ) { ( __trap it `out of bounds table access` ) ^ v } {}
        : ~ i k 0
        ~ < k n { ( vec_set [i] . it table + dst k val ) = k + k 1 }
        ^ v
    } {}
    // saturating float→int truncation (0..7): NaN → 0, clamp out-of-range
    ? == sub 0 {  // i32.trunc_sat_f32_s
        : i ab ( __pop it )
        ( __push it ( __w32 ( __trunc_sat ( __f32_nan ab ) # f ( bits_to_f32 ab ) -2147483648.0 2147483648.0 -2147483648 2147483647 ) ) ) ^ v } {}
    ? == sub 1 {  // i32.trunc_sat_f32_u
        : i ab ( __pop it )
        ( __push it ( __w32 ( __trunc_sat ( __f32_nan ab ) # f ( bits_to_f32 ab ) 0.0 4294967296.0 0 4294967295 ) ) ) ^ v } {}
    ? == sub 2 {  // i32.trunc_sat_f64_s
        : i ab ( __pop it )
        ( __push it ( __w32 ( __trunc_sat ( __f64_nan ab ) ( bits_to_f64 ab ) -2147483648.0 2147483648.0 -2147483648 2147483647 ) ) ) ^ v } {}
    ? == sub 3 {  // i32.trunc_sat_f64_u
        : i ab ( __pop it )
        ( __push it ( __w32 ( __trunc_sat ( __f64_nan ab ) ( bits_to_f64 ab ) 0.0 4294967296.0 0 4294967295 ) ) ) ^ v } {}
    ? == sub 4 {  // i64.trunc_sat_f32_s
        : i ab ( __pop it )
        ( __push it ( __trunc_sat ( __f32_nan ab ) # f ( bits_to_f32 ab ) - 0.0 ( __f_2p63 ) ( __f_2p63 ) -9223372036854775808 9223372036854775807 ) ) ^ v } {}
    ? == sub 5 {  // i64.trunc_sat_f32_u
        : i ab ( __pop it )
        ( __push it ( __trunc_sat_u64 ( __f32_nan ab ) # f ( bits_to_f32 ab ) ) ) ^ v } {}
    ? == sub 6 {  // i64.trunc_sat_f64_s
        : i ab ( __pop it )
        ( __push it ( __trunc_sat ( __f64_nan ab ) ( bits_to_f64 ab ) - 0.0 ( __f_2p63 ) ( __f_2p63 ) -9223372036854775808 9223372036854775807 ) ) ^ v } {}
    ? == sub 7 {  // i64.trunc_sat_f64_u
        : i ab ( __pop it )
        ( __push it ( __trunc_sat_u64 ( __f64_nan ab ) ( bits_to_f64 ab ) ) ) ^ v } {}
    ( __trap it `unsupported 0xfc op` )
}
