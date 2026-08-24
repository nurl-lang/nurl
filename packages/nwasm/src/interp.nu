// packages/nwasm/src/interp.nu — a small WebAssembly interpreter (pure NURL).
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

// The JIT substrate: an executable page and a call through a raw address.
// On wasm32 alloc returns 0 (no executable memory) and the runtime stays
// on the interpreter — a capability probe, not an error.
& `c` @ nurl_code_alloc i n → *u

& `c` @ nurl_code_seal *u p i n → i

& `c` @ nurl_call_code *u fn *u a → i

& `c` @ nurl_call_code_at *u fn *u a i off → i

& `c` @ nurl_call_code2 *u fn *u a *u b → i

& `c` @ nurl_call_code_at2 *u fn i off *u a *u b → i

& `c` @ nurl_code_free *u p i n → v

// Guard-page linear memory: an 8 GiB PROT_NONE reservation swallows every
// address a 32-bit index + 32-bit offset can form, so JIT code needs no
// bounds checks — an out-of-bounds access faults and the runtime's SIGSEGV
// handler steers the faulting frame to its function's trap stub. Reserve
// returning 0 means the platform has no fault-to-trap plumbing and the
// bounds-checked path stays — a capability probe, like nurl_code_alloc.
& `c` @ nurl_vmem_reserve i span → *u

& `c` @ nurl_vmem_commit *u base i old i new → i

& `c` @ nurl_vmem_release *u base i span → v

& `c` @ nurl_guard_mem_add *u base i span → i

& `c` @ nurl_guard_mem_del *u base → v

& `c` @ nurl_guard_code_room → i

& `c` @ nurl_guard_code_add *u code i len *u stub → i

& `c` @ nurl_guard_code_del *u code → v

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
// onnx → objdet) imports these under module "env"; nwasm resolves them
// to the real libcuda/libnvrtc here, marshalling guest linear memory ↔
// host. nurl.sh auto-links libcuda/libnvrtc when these symbols appear, and
// links stub objects on a GPU-less host (so nwasm always builds; the
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
    // Guard-page mode: the raw base of an 8 GiB PROT_NONE reservation
    // (0 = the memory lives in the `mem` Vec instead). Growth commits
    // pages in place, so this address never moves; every reader goes
    // through __mem_base, which picks whichever representation is live.
    i mem_raw
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
    i jit_ctx_free  // freelist of reusable 7-word JIT call contexts (0 = empty)
    i jit_lc_fidx  // last JIT callee fidx (-1 = none) and its resolved PFunc
    i jit_lc_pf
    // Tier-6 direct-call state. The slab is a bump stack of raw slot
    // frames for JIT execution. jit_spcell is the JIT anchor block, held
    // in r8 for the whole native execution: word 0 = the absolute
    // address of the next free slab slot, word 1 = the slab end, words
    // 2.. = one direct-entry address per defined function (0 = call
    // through the driver).
    i jit_slab  // raw slab base address (0 = not yet allocated)
    i jit_slab_end  // slab base + byte length
    i jit_spcell  // address of the anchor block [sp, slab end, ftab..]
    // The pause chain: when JIT code needs the driver (imports, grow,
    // call_indirect, the fc bridge), every native frame between the
    // call-out and the driver parks itself here as (page, resume, rbx,
    // args) and returns, so the driver can resume them innermost-first.
    i jit_chain  // chain base address
    i jit_chain_cell  // address of the 8-byte chain-top cell
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
: Frame { i fidx ( Vec i ) regs i pos i end i code_start s pins i ret_dst s prev i depth }

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
: PFunc { ( Vec i ) code ( Vec i ) aux i count i nlocals i nslots i nparams i nresults i code_start i sbase ( Vec i ) kv s free ( Vec i ) bytes s jit i jitlen }

@ __page → i { ^ 65536 }

// The guard reservation: 4 GiB of index + 4 GiB of constant offset + the
// widest access, rounded up a page. Every address wasm32 can form from
// a masked index and a u32 offset lands inside it.
@ __vmem_span → i { ^ + 17179869184 65536 }

// Guard-page memory is on wherever the runtime supports it; main.nu turns
// it off for NURL_NWASM_GUARD=0 (the A/B and debugging escape).
: ~ i g_guard 1

@ interp_disable_guard → v { = g_guard 0 }

// The linear memory's base address, whichever representation is live.
inline @ __mem_base * Interp it → i {
    ? != 0 . it mem_raw { ^ . it mem_raw } { ^ # i ( vec_data [u] . it mem ) }
}

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
    // Guard-page mode first (non-shared memory only): reserve 8 GiB of
    // PROT_NONE, commit the declared minimum, register the region with
    // the fault-to-trap handler. Any step failing falls back to the Vec —
    // the two representations are behaviour-identical, guard mode just
    // lets the JIT drop its bounds checks.
    = . it mem_raw 0
    ? & & == . m has_mem 1 == . m mem_shared 0 != 0 g_guard {
        : *u gbase ( nurl_vmem_reserve ( __vmem_span ) )
        ? != # i gbase 0 {
            ? == 0 ( nurl_vmem_commit gbase 0 * __mpages ( __page ) ) {
                ? == 0 ( nurl_guard_mem_add gbase ( __vmem_span ) ) {
                    = . it mem_raw # i gbase
                } { ( nurl_vmem_release gbase ( __vmem_span ) ) }
            } { ( nurl_vmem_release gbase ( __vmem_span ) ) }
        } {}
    } {}
    = . it mem ? != 0 . it mem_raw ( vec_new [u] ) ( vec_zeroed [u] * __mreserve ( __page ) )
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
    = . it jit_ctx_free 0
    = . it jit_lc_fidx -1
    = . it jit_slab 0
    = . it jit_slab_end 0
    = . it jit_spcell 0
    = . it jit_chain 0
    = . it jit_chain_cell 0
    = . it jit_lc_pf 0
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
                        : s dst # s + ( __mem_base it ) off
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
        ~ != 0 . it jit_ctx_free { : *i cb # *i . it jit_ctx_free = . it jit_ctx_free . cb 0 ( nurl_free # s cb ) }
        ? != 0 . it jit_slab { ( nurl_free # s . it jit_slab ) = . it jit_slab 0 } {}
        ? != 0 . it jit_spcell { ( nurl_free # s . it jit_spcell ) = . it jit_spcell 0 } {}
        ? != 0 . it jit_chain { ( nurl_free # s . it jit_chain ) = . it jit_chain 0 } {}
        ? != 0 . it jit_chain_cell { ( nurl_free # s . it jit_chain_cell ) = . it jit_chain_cell 0 } {}
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
    ? != 0 . it mem_raw {
        ( nurl_guard_mem_del # *u . it mem_raw )
        ( nurl_vmem_release # *u . it mem_raw ( __vmem_span ) )
        = . it mem_raw 0
    } {}
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
    : s base # s ( __mem_base it )
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
    : *u mb # *u ( __mem_base it )
    : ~ i k 0
    ~ < k n {
        = . mb + ea k # u & ( __lshr64 val * 8 k ) 255
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
    : s base # s ( __mem_base it )
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
    ? != 0 . it mem_raw {
        // Guard-page mode: commit the new pages in place — the base
        // never moves, the pages arrive zeroed from the kernel.
        ? != 0 ( nurl_vmem_commit # *u . it mem_raw * old ( __page ) * + old delta ( __page ) ) { ^ -1 } {}
    } {
        // One resize, zero-filling the new tail in a single memset, instead
        // of a push per byte: growing by a single page was 65 536 pushes.
        : b _ok ( vec_resize_zeroed [u] . it mem * + old delta ( __page ) )
    }
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
    : s rf . pfc free
    ? != # i rf 0 {
        : *Frame rf9 # *Frame rf
        = . pfc free . rf9 prev
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

// Write the current frame's saved position through the MUTABLE frame
// handle — the driver rebinds `tp` on inline call/return, so no arm may
// hold the frame through an immutable binding.
inline @ __fr_setpos s tp i v → v {
    : *Frame fr # *Frame tp
    = . fr pos v
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
    = . fr prev . pf free
    = . pf free pp
}

@ __pf_free s pp → v {
    ? == # i pp 0 { ^ v } {}
    : *PFunc pf # *PFunc pp
    : ~ s fp . pf free
    ~ != # i fp 0 {
        : *Frame fr # *Frame fp
        : s nx . fr prev
        ( vec_free [i] . fr regs )
        ( nurl_free fp )
        = fp nx
    }
    ( vec_free [i] . pf code )
    ( vec_free [i] . pf aux )
    ( vec_free [i] . pf kv )
    ( vec_free [i] . pf bytes )
    ? > . pf jitlen 0 {
        ( nurl_guard_code_del # *u . pf jit )  // no-op when never registered
        ( nurl_code_free # *u . pf jit . pf jitlen )
    } {}
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
@ __R_CALLIMP → i { ^ 210 }  // A=fidx B=argbase — an import, known at predecode
@ __R_LOADMULI64 → i { ^ 211 }  // A=dst B=base C=off D=x: dst = mem64 * x
@ __R_LOADADDI64 → i { ^ 212 }  // A=dst B=base C=off D=x: dst = mem64 + x
@ __R_UNREACH → i { ^ 172 }

@ __R_TRAPUN → i { ^ 173 }  // unsupported opcode (0xfd/unknown)

@ __R_ATOM → i { ^ 174 }  // vs bridge: A=sub B=memarg offset C=srcbase D=pops<<1|push
@ __R_FCB → i { ^ 171 }  // vs bridge: A=sub B=idx-imm C=srcbase D=pops<<1|push
@ __R_IFZ → i { ^ 48 }  // A=target B=cond — jump when cond == 0
@ __R_BRIFC → i { ^ 45 }  // A=target B=lhs C=rhs D=compare op — jump when it holds
// 38 was i64.extend_i32_s, which the canonical-form skip removed from
// every record stream — the number is recycled into the hot first-64
// dispatch table (the loop idiom runs on every back edge), and the
// never-emitted extend keeps 175 in the cold one in case a future
// change re-emits it.
@ __R_ADDBRIFC64 → i { ^ 38 }  // A=target B=dst C=s1 D=s2 W5=cmpop<<53|rhs<<32|byte: dst=s1+s2, branch on the compare
@ __R_ADDBRIFC32 → i { ^ 177 }  // the i32.add spelling of the same

// ── fused i64 ALU pairs ─────────────────────────────────────────
// `t = s1 OP1 s2; dst = x OP2 t` (or `t OP2 x`) is two records where one
// will do whenever `t` is a single-use stack temp — which adjacency plus
// `A == the consumed slot` proves, `__fuse_selc`-style. The eight pairs
// below are the measured top of the corpus (mul→add alone is a quarter of
// packet_classifier, lcg and prefix_scan); they take the hot dispatch
// numbers of eight ops the same corpus shows at ≤0.05 % — those move to
// the cold table (178+), keeping the compare block 56..75 untouched.
// Record: A=dst B=s1 C=s2 D=x.
@ __R_MULADD64 → i { ^ 13 }  // dst = (s1*s2) + x
@ __R_ADDAND64 → i { ^ 14 }  // dst = (s1+s2) & x
@ __R_ADDMUL64 → i { ^ 15 }  // dst = (s1+s2) * x
@ __R_ADDSHRU64 → i { ^ 16 }  // dst = (s1+s2) >>u x — t-left only
@ __R_SHRUAND64 → i { ^ 17 }  // dst = (s1 >>u s2) & x
@ __R_ADDADD64 → i { ^ 22 }  // dst = (s1+s2) + x
@ __R_SHRUXOR64 → i { ^ 30 }  // dst = (s1 >>u s2) ^ x
@ __R_XORMUL64 → i { ^ 33 }  // dst = (s1^s2) * x
@ __R_LOADSHL64 → i { ^ 205 }  // A=dst B=x C=off D=kslot: dst = mem64[(x<<k) w32]
@ __R_LOADSHL32 → i { ^ 206 }  // the i32.load spelling
@ __R_LOADSHLADD64 → i { ^ 207 }  // A=dst B=base C=off D=x W5=kslot<<32|byte: dst = mem64[base + (x<<k)]
@ __R_LOADSHLADD32 → i { ^ 208 }  // the i32.load spelling

// The pair table: micro-op of the producer × micro-op of the consumer →
// fused op, or -1. Only commutative consumers accept the temp on either
// side; ADDSHRU is the one measured non-commutative shape (lcg's
// `(v*a+c) >> 16`) and its caller enforces t-left.
@ __alu2 i lop i io → i {
    ? == lop 0 {  // i64.add feeding …
        ? == io 0 { ^ ( __R_ADDADD64 ) } {}
        ? == io 1 { ^ ( __R_ADDMUL64 ) } {}
        ? == io 2 { ^ ( __R_ADDAND64 ) } {}
        ? == io 3 { ^ ( __R_ADDSHRU64 ) } {}
        ^ -1
    } {}
    ? == lop 1 { ^ ? == io 0 ( __R_MULADD64 ) -1 } {}  // i64.mul → i64.add
    ? == lop 3 {  // i64.shr_u feeding …
        ? == io 2 { ^ ( __R_SHRUAND64 ) } {}
        ? == io 4 { ^ ( __R_SHRUXOR64 ) } {}
        ^ -1
    } {}
    ? == lop 4 { ^ ? == io 1 ( __R_XORMUL64 ) -1 } {}  // i64.xor → i64.mul
    ^ -1
}

// ── fused f64 pairs ─────────────────────────────────────────────
// The same single-use-temp fold over the f64 arithmetic that nbody-shaped
// code is made of, plus the two memory-edge shapes: a load whose result
// feeds one arithmetic op, and an add whose result a store consumes. The
// numbers are the eight hot-table slots the corpus shows at exactly zero
// (f32 and the narrow i64 loads/stores — demoted to 186+). Two rounding
// steps stay two: the handlers spell fmul-then-fadd, and nurlc emits no
// fast-math flags, so LLVM cannot contract them into an fma.
@ __R_LOADMULF64 → i { ^ 194 }  // A=dst B=base C=off D=x: dst = mem[f64] * x
@ __R_ADDSTOREF64 → i { ^ 197 }  // A=addr B=s1 C=s2 D=off: mem[f64] = s1 + s2
@ __R_MULADDF64 → i { ^ 198 }  // A=dst B=s1 C=s2 D=x: dst = (s1*s2) + x
@ __R_MULSUBAF64 → i { ^ 199 }  // dst = (s1*s2) - x
@ __R_MULSUBBF64 → i { ^ 200 }  // dst = x - (s1*s2)
@ __R_LOADADDF64 → i { ^ 195 }  // A=dst B=base C=off D=x: dst = mem[f64] + x
@ __R_LOADSUBBF64 → i { ^ 196 }  // A=dst B=base C=off D=x: dst = x - mem[f64]
@ __R_SUBMULF64 → i { ^ 201 }  // A=dst B=s1 C=s2 D=x: dst = (s1-s2) * x

// `f64.add; f64.store` — the accumulate-in-memory tail nbody's inner
// loop ends with. The add record keeps its B/C operands; the store's
// address slot takes A and its offset takes D. The value slot must be
// the add's destination, a stack temp.
@ __fuse_addstoref * PFunc pf i lastp i sb i addr i val i off → b {
    ? < lastp 0 { ^ F } {}
    ? != ( vec_len [i] . pf code ) * + lastp 1 6 { ^ F } {}
    : i base * lastp 6
    ? != ?? ( vec_get [i] . pf code base ) { T x → x F → -1 } 40 { ^ F } {}  // f64.add
    : i tA ?? ( vec_get [i] . pf code + base 1 ) { T x → x F → -1 }
    ? | != tA val < tA sb { ^ F } {}
    ( vec_set [i] . pf code base ( __R_ADDSTOREF64 ) )
    ( vec_set [i] . pf code + base 1 addr )
    ( vec_set [i] . pf code + base 4 off )
    ^ T
}

@ __fuse_loadshl * PFunc pf i lastp i io i sb i dst i adr i off → b {
    ? ! | == io 18 == io 20 { ^ F } {}  // i64.load / i32.load only
    ? < lastp 0 { ^ F } {}
    ? != ( vec_len [i] . pf code ) * + lastp 1 6 { ^ F } {}
    : i base * lastp 6
    ? != ?? ( vec_get [i] . pf code base ) { T x → x F → -1 } 10 { ^ F } {}  // i32.shl
    : i tA ?? ( vec_get [i] . pf code + base 1 ) { T x → x F → -1 }
    ? | != tA adr < tA sb { ^ F } {}
    : i kslot ?? ( vec_get [i] . pf code + base 3 ) { T x → x F → 0 }
    ( vec_set [i] . pf code base ? == io 18 ( __R_LOADSHL64 ) ( __R_LOADSHL32 ) )
    ( vec_set [i] . pf code + base 1 dst )
    ( vec_set [i] . pf code + base 3 off )
    ( vec_set [i] . pf code + base 4 kslot )
    ^ T
}

@ __fuse_loadshladd * PFunc pf i labfloor i io i sb i dst i fz i off i byte → b {
    ? ! | == io 18 == io 20 { ^ F } {}
    ? | < byte 0 >= byte 4294967296 { ^ F } {}
    : i ti - / ( vec_len [i] . pf code ) 6 1
    ? | < ti 0 > labfloor ti { ^ F } {}
    : i base * ti 6
    ? != ?? ( vec_get [i] . pf code base ) { T x → x F → -1 } 10 { ^ F } {}  // i32.shl
    : i tA ?? ( vec_get [i] . pf code + base 1 ) { T x → x F → -1 }
    ? < tA sb { ^ F } {}
    : i s1 >> fz 21
    : i s2 & fz 2097151
    : ~ i other -2
    ? == tA s2 { = other s1 } { ? == tA s1 { = other s2 } {} }
    ? | == other -2 == other tA { ^ F } {}
    : i x ?? ( vec_get [i] . pf code + base 2 ) { T x → x F → 0 }
    : i kslot ?? ( vec_get [i] . pf code + base 3 ) { T x → x F → 0 }
    ( vec_set [i] . pf code base ? == io 18 ( __R_LOADSHLADD64 ) ( __R_LOADSHLADD32 ) )
    ( vec_set [i] . pf code + base 1 dst )
    ( vec_set [i] . pf code + base 2 other )
    ( vec_set [i] . pf code + base 3 off )
    ( vec_set [i] . pf code + base 4 x )
    ( vec_set [i] . pf code + base 5 kslot )
    ^ T
}

// The f64 analogue of __fuse_alu2, with two extra clauses: a load
// producer folds only while its index operand is still the pool zero —
// the D slot is what the fused form takes for `x` — and f64.sub picks
// its fused spelling by which side the temp is on.
@ __fuse_aluf * PFunc pf i lastp i io i sb i dst i x1 i x2 i zslot → b {
    ? < lastp 0 { ^ F } {}
    ? != ( vec_len [i] . pf code ) * + lastp 1 6 { ^ F } {}
    : i base * lastp 6
    : i lop ?? ( vec_get [i] . pf code base ) { T x → x F → -1 }
    : i tA ?? ( vec_get [i] . pf code + base 1 ) { T x → x F → -1 }
    ? < tA sb { ^ F } {}
    : ~ i other -2
    ? == tA x1 { = other x2 } { ? == tA x2 { = other x1 } {} }
    ? | == other -2 == other tA { ^ F } {}
    : ~ i fop -1
    ? == lop 19 {  // f64.load feeding …
        ? != ?? ( vec_get [i] . pf code + base 4 ) { T x → x F → -1 } zslot { ^ F } {}
        ? == io 39 { = fop ( __R_LOADMULF64 ) } {}
        ? == io 40 { = fop ( __R_LOADADDF64 ) } {}
        ? & == io 41 == tA x2 { = fop ( __R_LOADSUBBF64 ) } {}
    } {
        ? == lop 39 {  // f64.mul feeding …
            ? == io 40 { = fop ( __R_MULADDF64 ) } {}
            ? == io 41 { = fop ? == tA x1 ( __R_MULSUBAF64 ) ( __R_MULSUBBF64 ) } {}
        } {
            ? & == lop 41 == io 39 { = fop ( __R_SUBMULF64 ) } {}  // f64.sub → f64.mul
        }
    }
    ? < fop 0 { ^ F } {}
    ( vec_set [i] . pf code base fop )
    ( vec_set [i] . pf code + base 1 dst )
    ( vec_set [i] . pf code + base 4 other )
    ^ T
}

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
    ? == op 53 { ^ 182 } {}  // i64.load32_u (demoted — 22 = __R_ADDADD64)
    ? == op 54 { ^ 183 } {}  // i32.store (demoted — 30 = __R_SHRUXOR64)
    ? == op 55 { ^ 27 } {}  // i64.store
    ? == op 56 { ^ 31 } {}  // f32.store
    ? == op 57 { ^ 28 } {}  // f64.store
    ? == op 58 { ^ 29 } {}  // i32.store8
    ? == op 59 { ^ 178 } {}  // i32.store16 (demoted — 33 = __R_XORMUL64)
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
    ? == op 107 { ^ 185 } {}  // i32.sub (demoted — 13 = __R_MULADD64)
    ? == op 108 { ^ 181 } {}  // i32.mul (demoted — 17 = __R_SHRUAND64)
    ? == op 109 { ^ 96 } {}  // i32.div_s
    ? == op 110 { ^ 97 } {}  // i32.div_u
    ? == op 111 { ^ 98 } {}  // i32.rem_s
    ? == op 112 { ^ 99 } {}  // i32.rem_u
    ? == op 113 { ^ 11 } {}  // i32.and
    ? == op 114 { ^ 184 } {}  // i32.or (demoted — 14 = __R_ADDAND64)
    ? == op 115 { ^ 180 } {}  // i32.xor (demoted — 15 = __R_ADDMUL64)
    ? == op 116 { ^ 10 } {}  // i32.shl
    ? == op 117 { ^ 179 } {}  // i32.shr_s (demoted — 16 = __R_ADDSHRU64)
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
    ? == op 172 { ^ 175 } {}  // i64.extend_i32_s (never emitted — the canonical-form skip; 38 = __R_ADDBRIFC64)
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
// Emit one record; the source byte offset goes to the SIDE table (read
// only by the trap backtrace), so every record word is operand payload.
@ __pf_emit * PFunc pf i op i a i b i cc i dd i byte → i {
    : ( Vec i ) code . pf code
    : i idx / ( vec_len [i] code ) 6
    ( vec_push [i] code op ) ( vec_push [i] code a ) ( vec_push [i] code b )
    ( vec_push [i] code cc ) ( vec_push [i] code dd ) ( vec_push [i] code 0 )
    ( vec_push [i] . pf bytes byte )
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

// `add; cmp; br_if` — the loop idiom `i = i + k; branch while i <> n` —
// collapses to ONE record when the add's result is what the compare tests.
// The add keeps its write (its destination is usually the loop counter
// local, which stays live), the compare and the branch fold in behind it,
// and two dispatches disappear.
//
// The add is the record directly before the compare. Between the two
// EMISSIONS no label may have been created at the compare's own index, or
// a branch could land on the compare and reach it without the add; labels
// are created only while processing block/loop/if/else/end, and `labfloor`
// is the record count at the most recent of those, so `labfloor ≤` the
// add's index proves every label so far points at or before the add. (The
// instructions BETWEEN the two records — local.get/tee, pooled consts —
// emit nothing and create no labels, which is exactly why the records are
// adjacent.) A label ON the add itself is fine: the fused record performs
// the same three effects in the same order from that address. The branch
// record just rewritten at `lastp` is dropped by tail truncation,
// `__fuse_addr`'s trick: every earlier record index still means what it
// did, and the caller records the fused record's own index as the patch
// site — forward targets filled at a later `end` are the record count at
// that `end`, which is past the fused record, never inside the pair.
//
// W5 packs cmpop<<21 | rhs-slot; the byte offset lives in the side table.
@ __fuse_addbr * PFunc pf i lastp i labfloor i tgt i lop i lb i lc i byte → i {
    ? | < lastp 1 > labfloor - lastp 1 { ^ -1 } {}
    ? | < byte 0 >= byte 4294967296 { ^ -1 } {}
    ? | < lc 0 >= lc 2097152 { ^ -1 } {}
    : i abase * - lastp 1 6
    : i aop ?? ( vec_get [i] . pf code abase ) { T x → x F → -1 }
    ? ! | == aop 0 == aop 9 { ^ -1 } {}  // i64.add / i32.add
    ? != ?? ( vec_get [i] . pf code + abase 1 ) { T x → x F → -1 } lb { ^ -1 } {}
    : i as1 ?? ( vec_get [i] . pf code + abase 2 ) { T x → x F → 0 }
    : i as2 ?? ( vec_get [i] . pf code + abase 3 ) { T x → x F → 0 }
    ( vec_set [i] . pf code abase ? == aop 0 ( __R_ADDBRIFC64 ) ( __R_ADDBRIFC32 ) )
    ( vec_set [i] . pf code + abase 1 tgt )
    ( vec_set [i] . pf code + abase 2 lb )
    ( vec_set [i] . pf code + abase 3 as1 )
    ( vec_set [i] . pf code + abase 4 as2 )
    ( vec_set [i] . pf code + abase 5 | << lop 21 lc )
    : b _ok ( vec_set_len [i] . pf code * lastp 6 )
    : b _ok2 ( vec_set_len [i] . pf bytes lastp )
    ^ - lastp 1
}

// `cmp; br_if L` is two records where one will do: the compare writes a 0/1
// into a slot the very next record reads and then throws away. When the
// compare is the record just emitted and the branch needs no result move,
// the compare is rewritten IN PLACE into a branch that does its own test,
// and no branch record is emitted at all. Returns the record index of the
// branch (the compare's, or the add's when `__fuse_addbr` reached one
// further back), or -1 when nothing fused.
//
// `i32.eqz x; br_if L` needs no new opcode: it is exactly `br_if_zero x`,
// the record `if` already uses — unless an add feeds it, where it becomes
// an ADDBRIFC comparing equal against the constant pool's always-present
// zero (interned first, so its slot is exactly nlocals).
//
// The safety argument is `__fold_set`'s: `lastp` is only non-negative when
// the previous instruction was straight-line, and no control opcode is, so
// no label can sit between the compare and the branch — which is the only
// way a path could reach the branch without the compare.
@ __fuse_branch * PFunc pf i lastp i labfloor i cond i tgt i byte → i {
    ? < lastp 0 { ^ -1 } {}
    ? != ( vec_len [i] . pf code ) * + lastp 1 6 { ^ -1 } {}
    : i base * lastp 6
    : i lop ?? ( vec_get [i] . pf code base ) { T x → x F → 0 }
    ? != ?? ( vec_get [i] . pf code + base 1 ) { T x → x F → -1 } cond { ^ -1 } {}
    : i lb ?? ( vec_get [i] . pf code + base 2 ) { T x → x F → 0 }
    : i lc ?? ( vec_get [i] . pf code + base 3 ) { T x → x F → 0 }
    ? | == lop 43 == lop 44 {  // eqz → branch when the operand itself is zero
        : i f2 ( __fuse_addbr pf lastp labfloor tgt ? == lop 43 56 66 lb . pf nlocals byte )
        ? >= f2 0 { ^ f2 } {}
        ( vec_set [i] . pf code base ( __R_IFZ ) )
        ( vec_set [i] . pf code + base 1 tgt )
        ( vec_set [i] . pf code + base 2 lb )
        ( vec_set [i] . pf code + base 5 byte )
        ^ lastp
    } {}
    ? & >= lop 56 <= lop 75 {  // the integer compares
        : i f2 ( __fuse_addbr pf lastp labfloor tgt lop lb lc byte )
        ? >= f2 0 { ^ f2 } {}
        ( vec_set [i] . pf code base ( __R_BRIFC ) )
        ( vec_set [i] . pf code + base 1 tgt )
        ( vec_set [i] . pf code + base 2 lb )
        ( vec_set [i] . pf code + base 3 lc )
        ( vec_set [i] . pf code + base 4 lop )
        ( vec_set [i] . pf code + base 5 byte )
        ^ lastp
    } {}
    ^ -1
}

// Emit a branch to label depth `k` (top of `open` = depth 0). `cond` is the
// condition slot for br_if (-1 = unconditional). `h` is the height AFTER any
// condition pop. Fills patch sites for forward targets. Returns nothing; the
// caller handles liveness.
@ __emit_branch * PFunc pf ( Vec s ) open i k i cond i sb i h i byte i lastp i labfloor → v {
    : i n ( vec_len [s] open )
    ? >= k n { ( __pf_emit pf ( __R_TRAPUN ) 0 0 0 0 byte ) ^ v } {}
    : s bp ?? ( vec_get [s] open - - n 1 k ) { T x → x F → # s 0 }
    ? == # i bp 0 { ( __pf_emit pf ( __R_TRAPUN ) 0 0 0 0 byte ) ^ v } {}
    : *PBlk blk # *PBlk bp
    : i arity ? == . blk kind 1 . blk params . blk results
    : i dst + sb . blk base
    : i src + sb - h arity
    // `t0` is a record index (it doubles as a patch site for `if`); a stored
    // jump target is the same thing scaled to the driver's word cursor.
    : i tgt ? == . blk kind 1 * . blk t0 6 -1
    : ~ i rec 0
    ? | == arity 0 == dst src {
        ? < cond 0 { = rec ( __pf_emit pf ( __R_BR ) tgt 0 0 0 byte ) } {
            : i fb ( __fuse_branch pf lastp labfloor cond tgt byte )
            ? >= fb 0 { = rec fb }
            { = rec ( __pf_emit pf ( __R_BRIF ) tgt cond 0 0 byte ) }
        }
    } {
        ? < cond 0 { = rec ( __pf_emit pf ( __R_BRM ) tgt dst src arity byte ) }
        { = rec ( __pf_emit pf ( __R_BRIFM ) tgt cond | << dst 20 src arity byte ) }
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
        ? != 0 live { ( __pf_emit pf ( __R_CONST ) + sb h cv 0 0 byte ) } {}
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
            ? & < k h != 0 live { ( __pf_emit pf ( __R_MOV ) + sb k sl 0 0 byte ) } {}
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
    ? & >= op 65 <= op 68 { ^ T } {}  // consts (pooled: no record; else one CONST)
    ? | | == op 32 == op 208 == op 210 { ^ T } {}  // local.get / ref.null / ref.func: alias only
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
            ? != 0 live { ( __pf_emit pf ( __R_MOV ) + sb k li 0 0 byte ) } {}
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
    : b _ok2 ( vec_set_len [i] . pf bytes lastp )
    ^ | << s1 21 s2
}

// ── narrowing/widening moves that need no record ─────────────────
// Every i32-typed slot holds the CANONICAL form: the low 32 bits
// sign-extended to 64. Every producer guarantees it — i32 arithmetic wraps
// its result through `__w32`, i32 loads sign- or zero-extend into it,
// `i32.const` is interned wrapped, and a copy of a canonical value is
// canonical. The interpreter already banks on this: `i32.eqz` tests the
// whole word against zero. Two conversions collapse under that invariant:
//
//   * `i64.extend_i32_s` IS the identity on the canonical form — the wide
//     value it must produce is bit-for-bit what the slot already holds. It
//     emits nothing, unconditionally. (`extend_i32_u` is not: a negative
//     canonical i32 has high bits the zero-extension must clear.)
//   * `i32.wrap_i64` genuinely truncates — but when the NEXT instruction is
//     the wrap's only consumer (stack discipline: adjacent means the value
//     lands in its operand slot) and that consumer reads the operand
//     insensitively to bits 32.. — it masks the address, wraps the result,
//     canonicalises the input, or stores only the low bytes — the unwrapped
//     value is indistinguishable from the wrapped one, and the wrap emits
//     nothing.
//
// A skipped record leaves `lastp` pointing at the previous producer. That is
// safe: for the extend, the producer's canonical result IS the extended
// value, so a `local.set` fold that reaches it stores exactly what the
// extend would have; for the wrap, the gate below admits only consumers
// whose arms never read `lastp`.
// Try to fold the record just emitted (an i64 ALU producer) into the
// binary op now being emitted, per the __alu2 table. `dst` is the
// consumer's canonical destination, `x1`/`x2` its two operand slots; the
// producer's A must be one of them AND a stack slot (>= sb) — the same
// single-use argument as __fuse_selc, with __fuse_addr's stack-slot
// clause. The `other == tA` rejection covers `t OP t`, where the second
// read has no slot to read from once the temp is never written.
@ __fuse_alu2 * PFunc pf i lastp i io i sb i dst i x1 i x2 i byte → b {
    ? < lastp 0 { ^ F } {}
    ? != ( vec_len [i] . pf code ) * + lastp 1 6 { ^ F } {}
    : i base * lastp 6
    : i lop ?? ( vec_get [i] . pf code base ) { T x → x F → -1 }
    : ~ i fop -1
    // an i64.load whose index operand is still the pool zero can absorb
    // the mul/add it feeds — the D slot is what the fused form takes for x
    ? == lop 18 {
        ? != ?? ( vec_get [i] . pf code + base 4 ) { T x → x F → -1 } . pf nlocals { ^ F } {}
        ? == io 1 { = fop ( __R_LOADMULI64 ) } {}
        ? == io 0 { = fop ( __R_LOADADDI64 ) } {}
    } { = fop ( __alu2 lop io ) }
    ? < fop 0 { ^ F } {}
    : i tA ?? ( vec_get [i] . pf code + base 1 ) { T x → x F → -1 }
    ? < tA sb { ^ F } {}
    : ~ i other -2
    ? == tA x1 { = other x2 } { ? == tA x2 { = other x1 } {} }
    ? == other -2 { ^ F } {}
    ? == other tA { ^ F } {}
    ? & == fop ( __R_ADDSHRU64 ) != tA x1 { ^ F } {}
    ( vec_set [i] . pf code base fop )
    ( vec_set [i] . pf code + base 1 dst )
    ( vec_set [i] . pf code + base 4 other )
    ( vec_set [i] . pf code + base 5 byte )
    ^ T
}

// The wrapped value's consumer may sit one PUSH away: `wrap; i32.const k;
// i32.shl` (a shift or mask) parks a pooled constant or a local.get —
// neither emits a record — between the wrap and the instruction that
// reads it. The wrap's value is then the consumer's FIRST operand, and
// the first-operand position of every op below is exactly as insensitive
// as the second: results re-wrapped, inputs canonicalised, addresses
// masked, stores narrow.
@ __insens_binop i nx → b {
    ? & >= nx 70 <= nx 79 { ^ T } {}  // i32 compares: both inputs canonicalised
    ? & >= nx 106 <= nx 108 { ^ T } {}  // i32 add/sub/mul: result re-wrapped
    ? & >= nx 113 <= nx 118 { ^ T } {}  // i32 and/or/xor/shl/shr_s/shr_u
    ? | | == nx 54 == nx 58 == nx 59 { ^ T } {}  // i32.store/8/16: addr masked, value low bytes
    ^ F
}

@ __wrap_skippable * Module m * Wc c → b {
    ? >= . c pos . c len { ^ F } {}
    : i nx # i ?? ( vec_get [u] . m code . c pos ) { T x → x F → # u 0 }
    ? ( __insens_binop nx ) { ^ T } {}
    ? & >= nx 40 <= nx 53 { ^ T } {}  // loads: the address is masked to u32
    // one interposed push: i32.const (sleb) or local.get (uleb), then the
    // consumer — the wrap's value is its first operand
    ? | == nx 65 == nx 32 {
        : *Wc pk ( wc_new . m code )
        = . pk pos + . c pos 1
        = . pk len . c len
        ? == nx 65 { : i _v ( wc_sleb pk ) } { : i _v ( wc_uleb pk ) }
        : ~ b ok F
        ? < . pk pos . c len {
            : i n2 # i ?? ( vec_get [u] . m code . pk pos ) { T x → x F → # u 0 }
            = ok ( __insens_binop n2 )
        } {}
        ( wc_free pk )
        ^ ok
    } {}
    ^ F
}

@ __predecode * Module m * WFunc f → s {
    : *PFunc pf # *PFunc ( nurl_alloc Z PFunc )
    = . pf code ( vec_new [i] )
    = . pf aux ( vec_new [i] )
    = . pf bytes ( vec_new [i] )
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
    // record count at the most recent label-creating opcode
    // (block/loop/if/else/end) — see __fuse_addbr
    : ~ i labfloor 0
    : ( Vec i ) vm ( vec_new [i] )
    ~ & < . c pos . f code_end > ( vec_len [s] open ) 0 {
        : i byte . c pos
        : i recs0 ( vec_len [i] . pf code )
        : i op ( wc_u8 c )
        ? | == op 2 == op 3 {  // block / loop
            = labfloor / ( vec_len [i] . pf code ) 6
            ( __vflush pf vm SB h live byte )
            : i bt ( wc_sleb c )
            : i p ( __bt_params m bt )
            : i r ( __bt_results m bt )
            : i t0 ? == op 3 / ( vec_len [i] . pf code ) 6 -1
            ( vec_push [s] open ( __pblk_new ? == op 3 1 0 - h p p r live t0 ) )
        } {
            ? == op 4 {  // if: pop cond, IFZ to else/end (patched)
                = labfloor / ( vec_len [i] . pf code ) 6
                : i bt ( wc_sleb c )
                : i p ( __bt_params m bt )
                : i r ( __bt_results m bt )
                ? != 0 live {
                    = h - h 1
                    : i cnd ( __vg vm SB h )
                    ( __vflush pf vm SB h live byte )
                    : i rec ( __pf_emit pf ( __R_IFZ ) -1 cnd 0 0 byte )
                    : s kp ( __pblk_new 2 - h p p r 1 rec )
                    ( vec_push [s] open kp )
                } { ( vec_push [s] open ( __pblk_new 2 h p r 0 -1 ) ) }
            } {
                ? == op 5 {  // else
                    = labfloor / ( vec_len [i] . pf code ) 6
                    ( __vflush pf vm SB h live byte )
                    : i n ( vec_len [s] open )
                    : s bp ?? ( vec_get [s] open - n 1 ) { T x → x F → # s 0 }
                    ? != # i bp 0 {
                        : *PBlk blk # *PBlk bp
                        ? != 0 . blk live_entry {
                            // end of a live then-arm jumps past the else arm
                            ? != 0 live { = . blk else_br ( __pf_emit pf ( __R_BR ) -1 0 0 0 byte ) } {}
                            // the cond==0 edge lands here
                            ? >= . blk t0 0 { ( vec_set [i] . pf code + * . blk t0 6 1 ( vec_len [i] . pf code ) ) = . blk t0 -1 } {}
                            = h + . blk base . blk params
                            = live 1
                        } {}
                    } {}
                } {
                    ? == op 11 {  // end: close the frame, patch all forward targets here
                        = labfloor / ( vec_len [i] . pf code ) 6
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
                            ? != 0 live { ( __vflush pf vm SB h live byte ) ( __emit_branch pf open k -1 SB h byte -1 -1 ) = live 0 } {}
                        } {
                            ? == op 13 {  // br_if: pop cond, branch on it, fall through otherwise
                                : i k ( wc_uleb c )
                                ? != 0 live {
                                    = h - h 1
                                    : i cnd ( __vg vm SB h )
                                    ( __vflush pf vm SB h live byte )
                                    ( __emit_branch pf open k cnd SB h byte lastp labfloor )
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
                                        ( __pf_emit pf ( __R_BRTBL ) astart idxs nl 0 byte )
                                        = live 0
                                    }
                                } {
                                    ? == op 15 {  // return
                                        ? != 0 live {
                                            ( __vflush pf vm SB h live byte )
                                            ( __pf_emit pf ( __R_RET ) + SB - h nresults nresults 0 0 byte )
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
                                                ( __pf_emit pf ? < fi . m num_import_funcs ( __R_CALLIMP ) ( __R_CALL ) fi + SB - h cp 0 0 byte )
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
                                                    ( __pf_emit pf ( __R_CALLIND ) ti + SB - h cp idxs 0 byte )
                                                    = h + - h cp cr
                                                    ? > h maxh { = maxh h } {}
                                                } {}
                                            } {
                                                ? == op 0 { ? != 0 live { ( __vflush pf vm SB 0 live byte ) ( __pf_emit pf ( __R_UNREACH ) 0 0 0 0 byte ) = live 0 } {} } {
                                                    ? == op 1 {} {  // nop
                                                        ? == op 26 { ? != 0 live { = h - h 1 } {} } {  // drop
                                                            ? | == op 27 == op 28 {  // select (typed select folds to the same record)
                                                                ? == op 28 { : i tc ( wc_uleb c ) ( wc_skip c tc ) } {}
                                                                ? != 0 live {
                                                                    ( __pf_emit pf ( __R_SEL ) + SB - h 3 ( __vg vm SB - h 3 ) ( __vg vm SB - h 2 ) ( __vg vm SB - h 1 ) byte ) ( __vset vm - h 3 -1 )
                                                                    = h - h 2
                                                                } {}
                                                            } {
                                                                ? == op 32 { : i li ( wc_uleb c ) ? != 0 live { ( __vset vm h li ) = h + h 1 ? > h maxh { = maxh h } {} } {} } {
                                                                    ? == op 33 { : i li ( wc_uleb c ) ? != 0 live { ? ( __fold_set pf vm lastp SB - h 1 li ) {} { : i sv ( __vg vm SB - h 1 ) ( __vkill pf vm SB - h 1 li live byte ) ( __pf_emit pf ( __R_MOV ) li sv 0 0 byte ) } = h - h 1 } {} } {
                                                                        ? == op 34 { : i li ( wc_uleb c ) ? != 0 live { ? ( __fold_set pf vm lastp SB - h 1 li ) {} { : i sv ( __vg vm SB - h 1 ) ( __vkill pf vm SB - h 1 li live byte ) ( __pf_emit pf ( __R_MOV ) li sv 0 0 byte ) } ( __vset vm - h 1 li ) } {} } {
                                                                            ? == op 35 { : i gi ( wc_uleb c ) ? != 0 live { ( __pf_emit pf ( __R_GG ) + SB h gi 0 0 byte ) ( __vset vm h -1 ) = h + h 1 ? > h maxh { = maxh h } {} } {} } {
                                                                                ? == op 36 { : i gi ( wc_uleb c ) ? != 0 live { ( __pf_emit pf ( __R_GS ) gi ( __vg vm SB - h 1 ) 0 0 byte ) = h - h 1 } {} } {
                                                                                    ? == op 37 { ( wc_uleb c ) ? != 0 live { ( __pf_emit pf ( __R_TABGET ) + SB - h 1 ( __vg vm SB - h 1 ) 0 0 byte ) ( __vset vm - h 1 -1 ) } {} } {
                                                                                        ? == op 38 { ( wc_uleb c ) ? != 0 live { ( __pf_emit pf ( __R_TABSET ) ( __vg vm SB - h 2 ) ( __vg vm SB - h 1 ) 0 0 byte ) = h - h 2 } {} } {
                                                                                            ? == op 65 { : i cv ( wc_sleb c ) ? != 0 live { ( __kbind pf vm kv L SB h ( __w32 cv ) live byte ) = h + h 1 ? > h maxh { = maxh h } {} } {} } {
                                                                                                ? == op 66 { : i cv ( wc_sleb c ) ? != 0 live { ( __kbind pf vm kv L SB h cv live byte ) = h + h 1 ? > h maxh { = maxh h } {} } {} } {
                                                                                                    ? == op 67 { : i cv ( __read_le c 4 ) ? != 0 live { ( __kbind pf vm kv L SB h cv live byte ) = h + h 1 ? > h maxh { = maxh h } {} } {} } {
                                                                                                        ? == op 68 { : i cv ( __read_le c 8 ) ? != 0 live { ( __kbind pf vm kv L SB h cv live byte ) = h + h 1 ? > h maxh { = maxh h } {} } {} } {
                                                                                                            ? & >= op 40 <= op 53 {  // loads: A=dst B=base C=off D=index
                                                                                                                ( wc_uleb c )
                                                                                                                : i off & ( wc_uleb c ) 4294967295
                                                                                                                ? != 0 live {
                                                                                                                    : i adr ( __vg vm SB - h 1 )
                                                                                                                    : i ldst + SB - h 1
                                                                                                                    : i lio ( __iop op )
                                                                                                                    ? ( __fuse_loadshl pf lastp lio SB ldst adr off ) {} {
                                                                                                                        : i fz ( __fuse_addr pf lastp adr SB )
                                                                                                                        ? & >= fz 0 ( __fuse_loadshladd pf labfloor lio SB ldst fz off byte ) {} {
                                                                                                                            ( __pf_emit pf lio ldst ? < fz 0 adr >> fz 21 off ? < fz 0 L & fz 2097151 byte )
                                                                                                                        }
                                                                                                                    }
                                                                                                                    ( __vset vm - h 1 -1 )
                                                                                                                } {}
                                                                                                            } {
                                                                                                                ? & >= op 54 <= op 62 {  // stores: A=addr B=val C=off
                                                                                                                    ( wc_uleb c )
                                                                                                                    : i off & ( wc_uleb c ) 4294967295
                                                                                                                    ? != 0 live {
                                                                                                                        : i sad ( __vg vm SB - h 2 )
                                                                                                                        : i sva ( __vg vm SB - h 1 )
                                                                                                                        ? & == op 57 ( __fuse_addstoref pf lastp SB sad sva off ) {} {
                                                                                                                            ( __pf_emit pf ( __iop op ) sad sva off 0 byte )
                                                                                                                        }
                                                                                                                        = h - h 2
                                                                                                                    } {}
                                                                                                                } {
                                                                                                                    ? == op 63 { ( wc_u8 c ) ? != 0 live { ( __pf_emit pf ( __R_MEMSZ ) + SB h 0 0 0 byte ) ( __vset vm h -1 ) = h + h 1 ? > h maxh { = maxh h } {} } {} } {
                                                                                                                        ? == op 64 { ( wc_u8 c ) ? != 0 live { ( __pf_emit pf ( __R_MEMGROW ) + SB - h 1 ( __vg vm SB - h 1 ) 0 0 byte ) ( __vset vm - h 1 -1 ) } {} } {
                                                                                                                            ? | == op 69 | == op 80 | & >= op 103 <= op 105 | & >= op 121 <= op 123 & >= op 192 <= op 196 {
                                                                                                                                // integer unary: in place at the top slot
                                                                                                                                ? != 0 live { ( __pf_emit pf ( __iop op ) + SB - h 1 ( __vg vm SB - h 1 ) 0 0 byte ) ( __vset vm - h 1 -1 ) } {}
                                                                                                                            } {
                                                                                                                                ? | & >= op 70 <= op 79 | & >= op 81 <= op 90 | & >= op 106 <= op 120 & >= op 124 <= op 138 {
                                                                                                                                    // integer binary: dst = h-2, operands h-2 / h-1
                                                                                                                                    ? != 0 live {
                                                                                                                                        : i bio ( __iop op )
                                                                                                                                        : i bdst + SB - h 2
                                                                                                                                        : i bx1 ( __vg vm SB - h 2 )
                                                                                                                                        : i bx2 ( __vg vm SB - h 1 )
                                                                                                                                        ? ( __fuse_alu2 pf lastp bio SB bdst bx1 bx2 byte ) {} {
                                                                                                                                            ( __pf_emit pf bio bdst bx1 bx2 0 byte )
                                                                                                                                        }
                                                                                                                                        ( __vset vm - h 2 -1 )
                                                                                                                                        = h - h 1
                                                                                                                                    } {}
                                                                                                                                } {
                                                                                                                                    ? | & >= op 91 <= op 102 & >= op 139 <= op 191 {
                                                                                                                                        // float arithmetic / compares and the int↔float conversions:
                                                                                                                                        // the same register shape as the integer unary and binary arms
                                                                                                                                        // above, dst = the slot of the first operand.
                                                                                                                                        ? != 0 live {
                                                                                                                                            // extend_i32_s / a wrap the next consumer cannot
                                                                                                                                            // observe: no record (see __wrap_skippable)
                                                                                                                                            ? | == op 172 & == op 167 ( __wrap_skippable m c ) {} {
                                                                                                                                                : i np ( __float_pops op )
                                                                                                                                                : i fio ( __iop op )
                                                                                                                                                : i fdst + SB - h np
                                                                                                                                                : i fx1 ( __vg vm SB - h np )
                                                                                                                                                : i fx2 ? == np 2 ( __vg vm SB - h 1 ) 0
                                                                                                                                                ? & == np 2 ( __fuse_aluf pf lastp fio SB fdst fx1 fx2 . pf nlocals ) {} {
                                                                                                                                                    ( __pf_emit pf fio fdst fx1 fx2 0 byte )
                                                                                                                                                }
                                                                                                                                                ( __vset vm - h np -1 )
                                                                                                                                                = h + - h np 1
                                                                                                                                            }
                                                                                                                                        } {}
                                                                                                                                    } {
                                                                                                                                        ? == op 208 { ( wc_u8 c ) ? != 0 live { ( __kbind pf vm kv L SB h -1 live byte ) = h + h 1 ? > h maxh { = maxh h } {} } {} } {
                                                                                                                                            ? == op 209 { ? != 0 live { ( __pf_emit pf ( __R_ISNULL ) + SB - h 1 ( __vg vm SB - h 1 ) 0 0 byte ) ( __vset vm - h 1 -1 ) } {} } {
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
                                                                                                                                                            ( __pf_emit pf ( __R_FCB ) sub bop + SB - h pops | << pops 1 push byte )
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
                                                                                                                                                                ( __pf_emit pf ( __R_ATOM ) asub aoff + SB - h pops | << pops 1 push byte )
                                                                                                                                                                = h + - h pops push
                                                                                                                                                                ? > h maxh { = maxh h } {}
                                                                                                                                                            } {}
                                                                                                                                                        } {
                                                                                                                                                            // unsupported (0xfd and anything unknown): keep alignment,
                                                                                                                                                            // trap if ever executed
                                                                                                                                                            ? == op 253 { ( __skip_imm c op ) } {}
                                                                                                                                                            ? != 0 live { ( __vflush pf vm SB 0 live byte ) ( __pf_emit pf ( __R_TRAPUN ) 0 0 0 0 byte ) } {}
                                                                                                                                                        }
                                                                                                                                                    } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } }
        // Arm the fold for the next instruction. Every arm above that is
        // straight-line emitted exactly one record when live, and it is the
        // last one; everything else — control flow, calls, the bridges, the
        // instructions that emit nothing — leaves -1, so no fold can reach
        // across a label or a record that is not a pure producer.
        // (A skipped extend/wrap, a pooled const or a local.get emits
        // nothing: lastp then stays on the PREVIOUS producer, so a fold
        // can reach across them. Every fold guards itself by slot
        // identity — the producer's A must equal the very slot being
        // consumed, and be a stack slot — so an alias sitting in between
        // can enable a fold but never corrupt one; __wrap_skippable's
        // comment covers the skipped-wrap case.)
        = lastp ? & != 0 live ( __straightline op ) ? == recs0 ( vec_len [i] . pf code ) lastp - / ( vec_len [i] . pf code ) 6 1 -1
    }
    // The body's last record is always an explicit return when the final
    // `end` was reachable — the return arm performs the whole frame
    // transition inline, so falling off the end (an outer-loop round
    // trip) is left to hostile modules only.
    ? != 0 live { ( __pf_emit pf ( __R_RET ) + SB - h nresults nresults 0 0 . f code_end ) } {}
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
        ( vec_free [i] . pf bytes )
        = . pf code ( vec_new [i] )
        = . pf kv ( vec_new [i] )
        = . pf bytes ( vec_new [i] )
        ( __pf_emit pf ( __R_TRAPUN ) 0 0 0 0 . f code_start )
        = . pf count 1
        = . pf nlocals nparams
        = . pf sbase nparams
        = . pf nslots + nparams 4
        = . pf nparams nparams
        = . pf nresults nresults
        = . pf code_start . f code_start
        = . pf free # s 0
        = . pf jit # s 0
        = . pf jitlen 0
        ^ # s pf
    } {}
    = . pf count / ( vec_len [i] . pf code ) 6
    = . pf nslots + SB + maxh 4
    = . pf nparams nparams
    = . pf nresults nresults
    = . pf code_start . f code_start
    = . pf free # s 0
    = . pf jit # s 0
    = . pf jitlen 0
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
@ __trap_backtrace * Interp it * Module m s top → v {
    : ( Vec u ) msg . it trapmsg
    : ~ s pp top
    : ~ i shown 0
    ~ & != # i pp 0 < shown 16 {
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
            ? >= bpos 0 {
                : i bw5 ?? ( vec_get [i] . bpf bytes / bpos 6 ) { T x → x F → . fr code_start }
                = boff - bw5 . fr code_start
            } {}
            ( __msg_push_int msg boff )
            ( __msg_push_str msg `)` )
        } {}
        = shown + shown 1
        : *Frame pfr # *Frame pp
        = pp . pfr prev
    }
    ? != # i pp 0 { ( __msg_push_str msg `\n  …` ) } {}
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
: ~ i g_jit 0  // tier-0 JIT opt-in (NURL_NWASM_JIT); off by default
: ~ i g_jit_depth 0  // JIT call-out nesting; beyond a cap, callees interpret (1M-deep-safe)
: ~ i g_pin 1  // tier-7 slot pinning (NURL_NWASM_PIN=0 keeps every slot in memory; A/B, debug)
: ~ i g_jitdump 0  // NURL_NWASM_JIT_DUMP=1: emit every sealed page as decimal bytes on stderr
@ interp_enable_jit → v { = g_jit 1 }

@ interp_disable_pin → v { = g_pin 0 }

@ interp_enable_jitdump → v { = g_jitdump 1 }

// ── template JIT (x86-64), tier above the interpreter ────────────
// The predecoder's register-form records are already the IR a template
// JIT lowers: the micro-op is the tag, and every operand is an absolute
// slot index — so slot `k` is `disp32(%rdi)` when %rdi holds the frame's
// register base, which is exactly the one argument the JIT calling
// convention (nurl_call_code) passes. A function whose records are all in
// the straight-line integer set below (no memory, no calls, no branches,
// no trapping divide) compiles to a flat run of loads, one ALU op and a
// store each, then a return; anything else leaves `jit` at -1 and the
// whole function stays on the interpreter. This is tier 0 — leaf integer
// kernels — and it grows one record class at a time, each gated on
// byte-identical output against the interpreter it falls back to.
@ __jit_b ( Vec u ) buf i x → v { ( vec_push [u] buf # u & x 255 ) }

@ __jit_d ( Vec u ) buf i x → v {
    ( __jit_b buf x ) ( __jit_b buf ( __lshr64 x 8 ) )
    ( __jit_b buf ( __lshr64 x 16 ) ) ( __jit_b buf ( __lshr64 x 24 ) )
}

@ __jit_q ( Vec u ) buf i x → v { ( __jit_d buf x ) ( __jit_d buf ( __lshr64 x 32 ) ) }
// mov rax,[rdi+s*8] / mov rcx,[rdi+s*8] / mov [rdi+s*8],rax
@ __jit_ldrax ( Vec u ) buf i s → v { ( __jit_b buf 72 ) ( __jit_b buf 139 ) ( __jit_b buf 131 ) ( __jit_d buf * s 8 ) }

@ __jit_ldrcx ( Vec u ) buf i s → v { ( __jit_b buf 72 ) ( __jit_b buf 139 ) ( __jit_b buf 139 ) ( __jit_d buf * s 8 ) }

@ __jit_strax ( Vec u ) buf i s → v { ( __jit_b buf 72 ) ( __jit_b buf 137 ) ( __jit_b buf 131 ) ( __jit_d buf * s 8 ) }

@ __jit_movslq ( Vec u ) buf → v { ( __jit_b buf 72 ) ( __jit_b buf 99 ) ( __jit_b buf 192 ) }  // movslq rax,eax
// f64 scalar SSE: xmm0 <- [rbx+s*8], op, [rbx+s*8] <- xmm0. Slots hold the
// IEEE-754 bit pattern, so a movsd is an exact round trip.
@ __jit_movsd_ld ( Vec u ) buf i s → v { ( __jit_b buf 242 ) ( __jit_b buf 15 ) ( __jit_b buf 16 ) ( __jit_b buf 131 ) ( __jit_d buf * s 8 ) }  // movsd xmm0,[rbx+s]
@ __jit_movsd_st ( Vec u ) buf i s → v { ( __jit_b buf 242 ) ( __jit_b buf 15 ) ( __jit_b buf 17 ) ( __jit_b buf 131 ) ( __jit_d buf * s 8 ) }  // movsd [rbx+s],xmm0
@ __jit_sd_op ( Vec u ) buf i opc i s → v { ( __jit_b buf 242 ) ( __jit_b buf 15 ) ( __jit_b buf opc ) ( __jit_b buf 131 ) ( __jit_d buf * s 8 ) }  // <op>sd xmm0,[rbx+s]
// The xmm twins of the pinned-slot accessors: slots whose every access
// is an xmm-path operand can live in xmm8..xmm15 (xmap[slot] = 0..7).
// movsd reg,reg copies only the low 64 bits — exactly a slot's width.
@ __jit_xr ( Vec i ) xmap i s → i { ^ ?? ( vec_get [i] xmap s ) { T x → x F → -1 } }

@ __jit_movsd_ld_m ( Vec u ) buf ( Vec i ) xmap i s → v {
    : i p ( __jit_xr xmap s )
    ? >= p 0 { ( __jit_b buf 65 ) ( __jit_b buf 15 ) ( __jit_b buf 40 ) ( __jit_b buf + 192 p ) } { ( __jit_movsd_ld buf s ) }  // movaps xmm0,xmm8+p — full copy, no merge dependency
}

@ __jit_movsd_st_m ( Vec u ) buf ( Vec i ) xmap i s → v {
    : i p ( __jit_xr xmap s )
    ? >= p 0 { ( __jit_b buf 68 ) ( __jit_b buf 15 ) ( __jit_b buf 40 ) ( __jit_b buf + 192 * p 8 ) } { ( __jit_movsd_st buf s ) }  // movaps xmm8+p,xmm0 — full copy, no merge dependency
}

@ __jit_sd_op_m ( Vec u ) buf ( Vec i ) xmap i opc i s → v {
    : i p ( __jit_xr xmap s )
    ? >= p 0 { ( __jit_b buf 242 ) ( __jit_b buf 65 ) ( __jit_b buf 15 ) ( __jit_b buf opc ) ( __jit_b buf + 192 p ) } { ( __jit_sd_op buf opc s ) }  // <op>sd xmm0,xmm8+p
}
// xmm registers are caller-saved, so parks and exits need no pushes —
// only the same sync-before-outside-reader / reload-at-join protocol.
@ __jit_sync_xpins ( Vec u ) buf ( Vec i ) xpins → v {
    : i n ( vec_len [i] xpins )
    : ~ i k 0
    ~ < k n {  // movsd [rbx+slot*8], xmm8+k
        ( __jit_b buf 242 ) ( __jit_b buf 68 ) ( __jit_b buf 15 ) ( __jit_b buf 17 ) ( __jit_b buf + 131 * k 8 ) ( __jit_d buf * ?? ( vec_get [i] xpins k ) { T x → x F → 0 } 8 )
        = k + k 1
    }
}

@ __jit_reload_xpins ( Vec u ) buf ( Vec i ) xpins → v {
    : i n ( vec_len [i] xpins )
    : ~ i k 0
    ~ < k n {  // movsd xmm8+k, [rbx+slot*8]
        ( __jit_b buf 242 ) ( __jit_b buf 68 ) ( __jit_b buf 15 ) ( __jit_b buf 16 ) ( __jit_b buf + 131 * k 8 ) ( __jit_d buf * ?? ( vec_get [i] xpins k ) { T x → x F → 0 } 8 )
        = k + k 1
    }
}

@ __jit_movsd_x1x0 ( Vec u ) buf → v { ( __jit_b buf 15 ) ( __jit_b buf 40 ) ( __jit_b buf 200 ) }  // movaps xmm1,xmm0 — full copy, no merge dependency
@ __jit_subsd_x0x1 ( Vec u ) buf → v { ( __jit_b buf 242 ) ( __jit_b buf 15 ) ( __jit_b buf 92 ) ( __jit_b buf 193 ) }  // subsd xmm0,xmm1

// ── Tier 7: function-wide slot pinning ───────────────────────────────
// The hottest integer slots live in callee-saved registers (r12..r15)
// for the whole function; every access site consults pmap and uses the
// register form when the slot is pinned. Memory stays the slot's home:
// the pinned registers are written back (__jit_sync_pins) before
// anything that reads the frame from outside — a call's argument area,
// a call-out the driver services — and reloaded (__jit_reload_pins) at
// every resume and post-call join, where memory is the fresher copy.
// Trap paths read no slots, so they only rebalance the stack.
// pmap[slot] = the register's low 3 bits (4..7 for r12..r15), -1 unpinned.
@ __jit_pr ( Vec i ) pmap i s → i { ^ ?? ( vec_get [i] pmap s ) { T x → x F → -1 } }

@ __jit_cv ( Vec i ) cvals i s → i { ^ ?? ( vec_get [i] cvals s ) { T x → x F → 0 } }
// Does v encode as a sign-extended imm32?
@ __jit_imm32 i v → i { ^ ? & >= v -2147483648 <= v 2147483647 1 0 }

// Set by an emitter that used a pin-direct form: the record ran without
// touching rax, so the walk keeps its rax cache instead of assuming the
// result went through it. Consumed (and reset) once per record.
: ~ i g_jit_noax 0

// The rax-cache update for a record that did NOT touch rax: keep the
// cached slot unless this record overwrote it (then the register is
// stale). Mirrors the write-sets __jit_newrax knows about.
@ __jit_newrax_noax i op i a i b i prev → i {
    ? & | == op 38 == op 177 == b prev { ^ -1 } {}  // ADDBRIFC writes b
    ? == a prev { ^ -1 } {}  // this record wrote the cached slot
    ^ prev
}

// ── pin-direct emitters: operate on r12+p without going through rax ──
// <op> r_pd, r_ps (reg-form opcode: add 3, sub 43, and 35, or 11,
// xor 51, cmp 59); both operands pinned.
@ __jit_prr ( Vec u ) buf i opc i pd i ps → v { ( __jit_b buf 77 ) ( __jit_b buf opc ) ( __jit_b buf + 192 + * pd 8 ps ) }
// <op> r_pd, [rbx+s*8]
@ __jit_prm ( Vec u ) buf i opc i pd i s → v { ( __jit_b buf 76 ) ( __jit_b buf opc ) ( __jit_b buf + 131 * pd 8 ) ( __jit_d buf * s 8 ) }
// <op> r_pd, imm (ALU /ext form; imm8 when it fits)
@ __jit_pri ( Vec u ) buf i ext i pd i iv → v {
    ? != 0 ( __jit_imm8 iv ) { ( __jit_b buf 73 ) ( __jit_b buf 131 ) ( __jit_b buf + 192 + * ext 8 pd ) ( __jit_b buf & iv 255 ) } {
        ( __jit_b buf 73 ) ( __jit_b buf 129 ) ( __jit_b buf + 192 + * ext 8 pd ) ( __jit_d buf iv ) }
}
// mov r_pd, imm64 (shortest form; flags untouched)
@ __jit_pmovi ( Vec u ) buf i pd i iv → v {
    ? & >= iv 0 <= iv 4294967295 { ( __jit_b buf 65 ) ( __jit_b buf + 184 pd ) ( __jit_d buf iv ) ^ v } {}  // mov r_pd d,imm32 (zero-extends)
    ( __jit_b buf 73 ) ( __jit_b buf 199 ) ( __jit_b buf + 192 pd ) ( __jit_d buf iv )  // mov r_pd,sign-ext imm32 (callers ensure imm32)
}
// mov r_pd, rax
@ __jit_pmovrax ( Vec u ) buf i pd → v { ( __jit_b buf 73 ) ( __jit_b buf 137 ) ( __jit_b buf + 192 pd ) }
// mov r_pd ← slot s through whatever home it has; emits nothing rax-touching.
// Returns 1 on success, 0 when the source needs the rax path (xmm home).
@ __jit_pmovsrc ( Vec u ) buf ( Vec i ) pmap ( Vec i ) xmap ( Vec i ) cvals i pd i s i raxslot → i {
    : i p ( __jit_pr pmap s )
    ? >= p 0 { ? != p pd { ( __jit_prr buf 139 pd p ) } {} ^ 1 } {}  // mov r_pd,r_ps (139 = 8B mov reg,rm)
    ? == p -2 {
        : i cv ( __jit_cv cvals s )
        ? != 0 ( __jit_imm32 cv ) { ( __jit_pmovi buf pd cv ) ^ 1 } {}
        ? & >= cv 0 <= cv 4294967295 { ( __jit_pmovi buf pd cv ) ^ 1 } {}
    } {}
    ? >= ( __jit_xr xmap s ) 0 { ^ 0 } {}  // xmm home: leave to the rax path
    ? == raxslot s { ( __jit_pmovrax buf pd ) ^ 1 } {}
    ( __jit_prm buf 139 pd s ) ^ 1  // mov r_pd,[rbx+s*8]
}

@ __jit_ldrax_m ( Vec u ) buf ( Vec i ) pmap ( Vec i ) xmap ( Vec i ) cvals i s → v {
    : i p ( __jit_pr pmap s )
    ? >= p 0 { ( __jit_b buf 73 ) ( __jit_b buf 139 ) ( __jit_b buf + 192 p ) ^ v } {}  // mov rax,r1X
    ? == p -2 {  // compact constant: materialize instead of loading
        : i cv ( __jit_cv cvals s )
        ? & >= cv 0 <= cv 4294967295 { ( __jit_b buf 184 ) ( __jit_d buf cv ) ^ v } {}  // mov eax,imm32 (zero-extends)
        ? != 0 ( __jit_imm32 cv ) { ( __jit_b buf 72 ) ( __jit_b buf 199 ) ( __jit_b buf 192 ) ( __jit_d buf cv ) ^ v } {}  // mov rax,sign-ext imm32
    } {}
    : i x ( __jit_xr xmap s )
    ? >= x 0 { ( __jit_b buf 102 ) ( __jit_b buf 76 ) ( __jit_b buf 15 ) ( __jit_b buf 126 ) ( __jit_b buf + 192 * x 8 ) ^ v } {}  // movq rax,xmm8+x
    ( __jit_ldrax buf s )
}

@ __jit_ldrcx_m ( Vec u ) buf ( Vec i ) pmap ( Vec i ) xmap ( Vec i ) cvals i s → v {
    : i p ( __jit_pr pmap s )
    ? >= p 0 { ( __jit_b buf 73 ) ( __jit_b buf 139 ) ( __jit_b buf + 200 p ) ^ v } {}  // mov rcx,r1X
    ? == p -2 {
        : i cv ( __jit_cv cvals s )
        ? & >= cv 0 <= cv 4294967295 { ( __jit_b buf 185 ) ( __jit_d buf cv ) ^ v } {}  // mov ecx,imm32 (zero-extends)
        ? != 0 ( __jit_imm32 cv ) { ( __jit_b buf 72 ) ( __jit_b buf 199 ) ( __jit_b buf 193 ) ( __jit_d buf cv ) ^ v } {}  // mov rcx,sign-ext imm32
    } {}
    : i x ( __jit_xr xmap s )
    ? >= x 0 { ( __jit_b buf 102 ) ( __jit_b buf 76 ) ( __jit_b buf 15 ) ( __jit_b buf 126 ) ( __jit_b buf + 193 * x 8 ) ^ v } {}  // movq rcx,xmm8+x
    ( __jit_ldrcx buf s )
}

@ __jit_strax_m ( Vec u ) buf ( Vec i ) pmap ( Vec i ) xmap ( Vec i ) cvals i s → v {
    : i p ( __jit_pr pmap s )
    ? >= p 0 { ( __jit_b buf 73 ) ( __jit_b buf 137 ) ( __jit_b buf + 192 p ) ^ v } {}  // mov r1X,rax
    : i x ( __jit_xr xmap s )
    ? >= x 0 { ( __jit_b buf 102 ) ( __jit_b buf 76 ) ( __jit_b buf 15 ) ( __jit_b buf 110 ) ( __jit_b buf + 192 * x 8 ) ^ v } {}  // movq xmm8+x,rax
    ( __jit_strax buf s )
}
// Fused second operands: <op> rax,r1X / <op> eax,r1Xd where the memory
// template would have used [rbx+s*8] directly. opc is the r64,r/m64
// (resp. r32,r/m32) opcode byte; 15-escape spellings get their own body.
@ __jit_oprax_pr ( Vec u ) buf i opc i p → v { ( __jit_b buf 73 ) ( __jit_b buf opc ) ( __jit_b buf + 192 p ) }

@ __jit_opeax_pr ( Vec u ) buf i opc i p → v { ( __jit_b buf 65 ) ( __jit_b buf opc ) ( __jit_b buf + 192 p ) }
// Entry/exit bracketing. Pinned registers are callee-saved, so every
// entry point (the prologue and each call-out resume) pushes them and
// every exit (RET, trap/overflow stubs, each call-out park) pops them —
// the stack layout keeps [rsp] = the saved args pointer either way.
@ __jit_push_pins ( Vec u ) buf i npin → v {
    : ~ i k 0
    ~ < k npin { ( __jit_b buf 65 ) ( __jit_b buf + 84 k ) = k + k 1 }  // push r12+k
}

// A driver-side resume entry: rebalance the stack and re-establish
// every invariant register (r8 = anchor, rbx = frame base, r11/r10/r9 =
// memory base/bytes/globals) — the driver round trip clobbers them all.
@ __jit_resume_entry ( Vec u ) buf i npin i spcell → v {
    ( __jit_push_pins buf npin )
    ( __jit_b buf 83 )  // push rbx
    ( __jit_b buf 86 )  // push rsi (args ptr, from call_code_at2)
    ( __jit_b buf 73 ) ( __jit_b buf 184 ) ( __jit_q buf spcell )  // movabs r8, anchor
    ( __jit_b buf 72 ) ( __jit_b buf 139 ) ( __jit_b buf 31 )  // mov rbx,[rdi]
    ( __jit_b buf 76 ) ( __jit_b buf 139 ) ( __jit_b buf 95 ) ( __jit_b buf 8 )  // mov r11,[rdi+8]
    ( __jit_b buf 76 ) ( __jit_b buf 139 ) ( __jit_b buf 87 ) ( __jit_b buf 16 )  // mov r10,[rdi+16]
    ( __jit_b buf 76 ) ( __jit_b buf 139 ) ( __jit_b buf 79 ) ( __jit_b buf 24 )  // mov r9,[rdi+24]
}

// Pad with multi-byte NOPs to the next 16-byte boundary (loop heads).
@ __jit_align16 ( Vec u ) buf → v {
    : ~ i pad & - 16 & ( vec_len [u] buf ) 15 15
    ~ > pad 0 {
        : i ch ? > pad 9 9 pad
        ? == ch 1 { ( __jit_b buf 144 ) } {}
        ? == ch 2 { ( __jit_b buf 102 ) ( __jit_b buf 144 ) } {}
        ? == ch 3 { ( __jit_b buf 15 ) ( __jit_b buf 31 ) ( __jit_b buf 0 ) } {}
        ? == ch 4 { ( __jit_b buf 15 ) ( __jit_b buf 31 ) ( __jit_b buf 64 ) ( __jit_b buf 0 ) } {}
        ? == ch 5 { ( __jit_b buf 15 ) ( __jit_b buf 31 ) ( __jit_b buf 68 ) ( __jit_b buf 0 ) ( __jit_b buf 0 ) } {}
        ? == ch 6 { ( __jit_b buf 102 ) ( __jit_b buf 15 ) ( __jit_b buf 31 ) ( __jit_b buf 68 ) ( __jit_b buf 0 ) ( __jit_b buf 0 ) } {}
        ? == ch 7 { ( __jit_b buf 15 ) ( __jit_b buf 31 ) ( __jit_b buf 128 ) ( __jit_d buf 0 ) } {}
        ? == ch 8 { ( __jit_b buf 15 ) ( __jit_b buf 31 ) ( __jit_b buf 132 ) ( __jit_b buf 0 ) ( __jit_d buf 0 ) } {}
        ? == ch 9 { ( __jit_b buf 102 ) ( __jit_b buf 15 ) ( __jit_b buf 31 ) ( __jit_b buf 132 ) ( __jit_b buf 0 ) ( __jit_d buf 0 ) } {}
        = pad - pad ch
    }
}

@ __jit_retseq ( Vec u ) buf i npin → v {
    ( __jit_b buf 94 ) ( __jit_b buf 91 )  // pop rsi; pop rbx
    : ~ i k npin
    ~ > k 0 { = k - k 1 ( __jit_b buf 65 ) ( __jit_b buf + 92 k ) }  // pop r12+k, innermost first
    ( __jit_b buf 195 )  // ret
}

@ __jit_sync_pins ( Vec u ) buf ( Vec i ) pins → v {
    : i n ( vec_len [i] pins )
    : ~ i k 0
    ~ < k n {  // mov [rbx+slot*8], r12+k
        ( __jit_b buf 76 ) ( __jit_b buf 137 ) ( __jit_b buf + 163 * k 8 ) ( __jit_d buf * ?? ( vec_get [i] pins k ) { T x → x F → 0 } 8 )
        = k + k 1
    }
}

@ __jit_reload_pins ( Vec u ) buf ( Vec i ) pins → v {
    : i n ( vec_len [i] pins )
    : ~ i k 0
    ~ < k n {  // mov r12+k, [rbx+slot*8]
        ( __jit_b buf 76 ) ( __jit_b buf 139 ) ( __jit_b buf + 163 * k 8 ) ( __jit_d buf * ?? ( vec_get [i] pins k ) { T x → x F → 0 } 8 )
        = k + k 1
    }
}

// Is every record templatable? Returns 1 if so (single trailing RET).
// True if op is templatable (tier 0 straight-line + tier 1 branches and
// value-producing compares). Anything else — memory, calls, trapping
// divide, the vs-bridge, select — leaves the whole function on the
// interpreter.
@ __jit_op_ok i op → i {
    ? & >= op 0 <= op 12 { ^ 1 } {}  // base i64 (0-8) + i32 add/shl/and/shr_u (9-12)
    ? & >= op 179 <= op 185 { ^ 1 } {}  // demoted i32 shr_s(179)/xor(180)/mul(181)/store(182,183)/or(184)/sub(185) — only ALU ones reach here
    ? & >= op 13 <= op 17 { ^ 1 } {}  // fused i64 ALU pairs MULADD/ADDAND/ADDMUL/ADDSHRU/SHRUAND
    ? | == op 22 | == op 30 == op 33 { ^ 1 } {}  // ADDADD/SHRUXOR/XORMUL
    ? | == op 47 == op 51 { ^ 1 } {}  // MOV, CONST
    ? == op 55 { ^ 1 } {}  // RET
    ? | == op 43 == op 44 { ^ 1 } {}  // i32/i64 eqz
    ? & >= op 56 <= op 75 { ^ 1 } {}  // integer compares
    ? | | | == op 48 == op 49 == op 54 == op 45 { ^ 1 } {}  // IFZ BR BRIF BRIFC
    ? | == op 38 == op 177 { ^ 1 } {}  // ADDBRIFC64/32
    ? >= ( __jit_memkind op ) 0 { ^ 1 } {}  // loads/stores (tier 2)
    ? | == op 50 == op 210 { ^ 1 } {}  // CALL / CALLIMP (tier 3)
    ? | == op 52 == op 53 { ^ 1 } {}  // global.get/set (tier 4)
    ? & >= op 39 <= op 42 { ^ 1 } {}  // f64 mul/add/sub/div (tier 4b)
    ? == op 172 { ^ 1 } {}  // unreachable → status 3
    ? | == op 36 == op 37 { ^ 1 } {}  // i32.wrap_i64 / i64.extend_i32_u
    ? == op 46 { ^ 1 } {}  // SEL
    ? | == op 211 == op 212 { ^ 1 } {}  // LOADMULI64 / LOADADDI64
    ? & >= op 194 <= op 201 { ^ 1 } {}  // fused f64 family
    ? & >= op 205 <= op 208 { ^ 1 } {}  // LOADSHL / LOADSHLADD
    ? == op 131 { ^ 1 } {}  // f64.sqrt
    ? | == op 125 == op 126 { ^ 1 } {}  // f64.abs / f64.neg — sign-bit ops on the raw slot
    ? == op 93 { ^ 1 } {}  // i32.clz
    ? | == op 99 == op 108 { ^ 1 } {}  // i32/i64.rem_u
    ? | | & >= op 96 <= op 98 == op 105 | == op 106 == op 107 { ^ 1 } {}  // div_s/div_u/rem_s, i32+i64
    ? == op 170 { ^ 1 } {}  // call_indirect (tier 5b)
    ? & >= op 153 <= op 156 { ^ 1 } {}  // reinterprets (slot copies)
    ? & >= op 157 <= op 161 { ^ 1 } {}  // extendN_s family
    ? | == op 162 == op 163 { ^ 1 } {}  // memory.size / memory.grow (call-out)
    ? | == op 169 == op 171 { ^ 1 } {}  // br_table (jump table) / FCB bridge (call-out)
    ^ 0
}

// Is every record templatable, and does every branch target a real
// record? Targets are word-offsets (record*6); a target past the last
// record aborts the JIT (the always-emitted trailing RET makes it
// unreachable in practice). JIT only unlimited-fuel runs: a metered run
// keeps the interpreter, which charges fuel exactly, so no fuel
// accounting is emitted.
@ __jit_ok * PFunc pf → i {
    : i n . pf count
    ? == n 0 { ^ 0 } {}
    : ( Vec i ) code . pf code
    : ~ i r 0
    ~ < r n {
        : i base * r 6
        : i op ?? ( vec_get [i] code base ) { T x → x F → -1 }
        ? == 0 ( __jit_op_ok op ) { ^ 0 } {}
        // Offset-magnitude gate for every memory template: the SIB access
        // and the bounds check both encode the constant offset as a
        // sign-extended disp32, so an offset at or past 2^31 (legal wasm —
        // predecode also folds constant indexes in) would flip negative in
        // the encoding. Those functions stay on the interpreter, which is
        // exact at any offset.
        : i offw ? == op 197 4 3  // ADDSTOREF64 keeps its offset in D, the rest in C
        ? | >= ( __jit_memkind op ) 0 | | & >= op 194 <= op 197 & >= op 205 <= op 208 | == op 211 == op 212 {
            : i moff ?? ( vec_get [i] code + base offw ) { T x → x F → 0 }
            ? | < moff 0 > moff 2147483639 { ^ 0 } {}  // 2^31-1-8: off+wid must fit disp32
        } {}
        ? | | | == op 48 == op 49 == op 54 | == op 45 | == op 38 == op 177 {
            : i tgt / ?? ( vec_get [i] code + base 1 ) { T x → x F → 0 } 6
            ? | < tgt 0 >= tgt n { ^ 0 } {}
        } {}
        ? == op 169 {  // br_table: every row target must be a real record
            : ( Vec i ) auxok . pf aux
            : i ab7 ?? ( vec_get [i] code + base 1 ) { T x → x F → 0 }
            : i rows7 + ?? ( vec_get [i] code + base 3 ) { T x → x F → 0 } 1
            : ~ i rw7 0
            ~ < rw7 rows7 {
                : i t7 / ?? ( vec_get [i] auxok + ab7 * rw7 4 ) { T x → x F → -6 } 6
                ? | < t7 0 >= t7 n { ^ 0 } {}
                = rw7 + rw7 1
            }
        } {}
        = r + r 1
    }
    : i lastop ?? ( vec_get [i] code * - n 1 6 ) { T x → x F → -1 }
    ^ ? | == lastop 55 == lastop 172 1 0
}

// __rcmp code → the x86 condition nibble for `jcc` (0F 8x) and `setcc`
// (0F 9x). Codes 56..65 are the i32 compares, 66..75 the i64 ones, each
// in the order eq ne lt_s lt_u gt_s gt_u le_s le_u ge_s ge_u.
@ __jit_cctab → ( Vec i ) {
    : ( Vec i ) t ( vec_new [i] )
    ( vec_push [i] t 132 ) ( vec_push [i] t 133 ) ( vec_push [i] t 140 ) ( vec_push [i] t 130 ) ( vec_push [i] t 143 )
    ( vec_push [i] t 135 ) ( vec_push [i] t 142 ) ( vec_push [i] t 134 ) ( vec_push [i] t 141 ) ( vec_push [i] t 131 )
    ^ t
}

@ __jit_settab → ( Vec i ) {
    : ( Vec i ) t ( vec_new [i] )
    ( vec_push [i] t 148 ) ( vec_push [i] t 149 ) ( vec_push [i] t 156 ) ( vec_push [i] t 146 ) ( vec_push [i] t 159 )
    ( vec_push [i] t 151 ) ( vec_push [i] t 158 ) ( vec_push [i] t 150 ) ( vec_push [i] t 157 ) ( vec_push [i] t 147 )
    ^ t
}

@ __jit_jcc ( Vec i ) tab i code → i { ^ ?? ( vec_get [i] tab % - code 56 10 ) { T x → x F → 132 } }

// The memory ops the JIT handles, with their width and sign. Returns
// width*4 + (signed?2:0) + (is_store?1:0), or -1 if not a memory op.
// Loads: 18 i64.load(8) 19 f64.load(8) 20 i32.load(4) 21 i32.load8_u(1)
// 22 i64.load32_u(4) 23 i32.load16_u(2) 24 f32.load(4) 25 i64.load8_u(1)
// 26 i64.load16_u(2) 76 i32.load8_s 77 i32.load16_s 78 i64.load8_s
// 79 i64.load16_s 80 i64.load32_s. Stores: 27 i64(8) 28 f64(8)
// 29 i32.store8(1) 30 i32(4) 31 f32(4) 32 i64.store32(4) 33 i32.store16(2)
// 34 i64.store8(1) 35 i64.store16(2).
@ __jit_memkind i op → i {
    // loads (width<<2 | signed<<1)
    ? == op 18 { ^ 32 } {}  // i64.load 8
    ? == op 19 { ^ 32 } {}  // f64.load 8
    ? == op 20 { ^ 18 } {}  // i32.load 4 signed (interp applies __w32)
    ? == op 24 { ^ 16 } {}  // f32.load 4
    ? == op 182 { ^ 16 } {}  // i64.load32_u 4
    ? == op 80 { ^ 18 } {}  // i64.load32_s 4 signed
    ? == op 23 { ^ 8 } {}  // i32.load16_u 2
    ? == op 26 { ^ 8 } {}  // i64.load16_u 2
    ? == op 77 { ^ 10 } {}  // i32.load16_s 2 signed
    ? == op 79 { ^ 10 } {}  // i64.load16_s 2 signed
    ? == op 21 { ^ 4 } {}  // i32.load8_u 1
    ? == op 25 { ^ 4 } {}  // i64.load8_u 1
    ? == op 76 { ^ 6 } {}  // i32.load8_s 1 signed
    ? == op 78 { ^ 6 } {}  // i64.load8_s 1 signed
    // stores (width<<2 | 1)
    ? == op 27 { ^ 33 } {}  // i64.store 8
    ? == op 28 { ^ 33 } {}  // f64.store 8
    ? == op 183 { ^ 17 } {}  // i32.store 4
    ? == op 31 { ^ 17 } {}  // f32.store 4
    ? == op 32 { ^ 17 } {}  // i64.store32 4
    ? == op 178 { ^ 9 } {}  // i32.store16 2
    ? == op 35 { ^ 9 } {}  // i64.store16 2
    ? == op 29 { ^ 5 } {}  // i32.store8 1
    ? == op 34 { ^ 5 } {}  // i64.store8 1
    ^ -1
}

// Emit the i64/i32 binary or shift body for op into buf (operands already
// mirror the interpreter's arms exactly, shifts masked by CL width).
// A load of a slot into rcx as the second operand, then a 64-bit ALU op
// rax OP= rcx, for the fused-pair emitters below.
// reg-reg opcode byte → the 81 /ext extension for the imm32 spelling
@ __jit_op_ext i opc → i {
    ? == opc 1 { ^ 0 } {}  // add
    ? == opc 9 { ^ 1 } {}  // or
    ? == opc 33 { ^ 4 } {}  // and
    ? == opc 41 { ^ 5 } {}  // sub
    ? == opc 49 { ^ 6 } {}  // xor
    ^ -1
}

@ __jit_rax_op_slot ( Vec u ) buf ( Vec i ) pmap ( Vec i ) xmap ( Vec i ) cvals i opc i s → v {
    ? == -2 ( __jit_pr pmap s ) {
        : i ov ( __jit_cv cvals s )
        ? & == opc 33 == ov 4294967295 { ( __jit_b buf 137 ) ( __jit_b buf 192 ) ^ v } {}  // and rax,0xffffffff = mov eax,eax
        : i oe ( __jit_op_ext opc )
        ? & >= oe 0 != 0 ( __jit_imm32 ov ) {
            ( __jit_b buf 72 ) ( __jit_b buf 129 ) ( __jit_b buf + 192 * oe 8 ) ( __jit_d buf ov ) ^ v  // <op> rax,imm32
        } {}
    } {}
    ( __jit_ldrcx_m buf pmap xmap cvals s )
    ( __jit_b buf 72 ) ( __jit_b buf opc ) ( __jit_b buf 200 )  // <op> rax,rcx
}

@ __jit_rax_imul_slot ( Vec u ) buf ( Vec i ) pmap ( Vec i ) xmap ( Vec i ) cvals i s → v {
    ? == -2 ( __jit_pr pmap s ) {
        : i mv ( __jit_cv cvals s )
        ? != 0 ( __jit_imm32 mv ) { ( __jit_b buf 72 ) ( __jit_b buf 105 ) ( __jit_b buf 192 ) ( __jit_d buf mv ) ^ v } {}  // imul rax,rax,imm32
    } {}
    ( __jit_ldrcx_m buf pmap xmap cvals s )
    ( __jit_b buf 72 ) ( __jit_b buf 15 ) ( __jit_b buf 175 ) ( __jit_b buf 193 )  // imul rax,rcx
}

@ __jit_rax_shr_slot ( Vec u ) buf ( Vec i ) pmap ( Vec i ) xmap ( Vec i ) cvals i s → v {
    ? == -2 ( __jit_pr pmap s ) {
        ( __jit_b buf 72 ) ( __jit_b buf 193 ) ( __jit_b buf 232 ) ( __jit_b buf & ( __jit_cv cvals s ) 63 ) ^ v  // shr rax,imm8
    } {}
    ( __jit_ldrcx_m buf pmap xmap cvals s )
    ( __jit_b buf 72 ) ( __jit_b buf 211 ) ( __jit_b buf 232 )  // shr rax,cl
}

@ __jit_imm8 i v → i { ^ ? & >= v -128 <= v 127 1 0 }

// rax ← imm64 in the shortest mov spelling (flags untouched by all three)
@ __jit_movrax_imm ( Vec u ) buf i iv → v {
    ? & >= iv 0 <= iv 4294967295 { ( __jit_b buf 184 ) ( __jit_d buf iv ) ^ v } {}  // mov eax,imm32 (zero-extends)
    ? != 0 ( __jit_imm32 iv ) { ( __jit_b buf 72 ) ( __jit_b buf 199 ) ( __jit_b buf 192 ) ( __jit_d buf iv ) ^ v } {}  // mov rax,sign-ext imm32
    ( __jit_b buf 72 ) ( __jit_b buf 184 ) ( __jit_q buf iv )  // movabs rax,imm64
}

@ __jit_alu_ci64 ( Vec u ) buf i op i cv → i {
    ? == op 1 {
        ? != 0 ( __jit_imm8 cv ) { ( __jit_b buf 72 ) ( __jit_b buf 107 ) ( __jit_b buf 192 ) ( __jit_b buf & cv 255 ) ^ 1 } {}  // imul rax,rax,imm8
        ? != 0 ( __jit_imm32 cv ) { ( __jit_b buf 72 ) ( __jit_b buf 105 ) ( __jit_b buf 192 ) ( __jit_d buf cv ) ^ 1 } {} ^ 0 } {}  // imul rax,rax,imm32
    ? == op 8 { ( __jit_b buf 72 ) ( __jit_b buf 193 ) ( __jit_b buf 224 ) ( __jit_b buf & cv 63 ) ^ 1 } {}  // shl rax,imm8
    ? == op 3 { ( __jit_b buf 72 ) ( __jit_b buf 193 ) ( __jit_b buf 232 ) ( __jit_b buf & cv 63 ) ^ 1 } {}  // shr rax,imm8
    ? == op 6 { ( __jit_b buf 72 ) ( __jit_b buf 193 ) ( __jit_b buf 248 ) ( __jit_b buf & cv 63 ) ^ 1 } {}  // sar rax,imm8
    ? & == op 2 == cv 4294967295 { ( __jit_b buf 137 ) ( __jit_b buf 192 ) ^ 1 } {}  // and rax,0xffffffff = mov eax,eax
    : i ext ? == op 0 0 ? == op 5 5 ? == op 2 4 ? == op 7 1 ? == op 4 6 -1
    ? >= ext 0 {
        ? != 0 ( __jit_imm8 cv ) { ( __jit_b buf 72 ) ( __jit_b buf 131 ) ( __jit_b buf + 192 * ext 8 ) ( __jit_b buf & cv 255 ) ^ 1 } {}  // <op> rax,imm8
        ? != 0 ( __jit_imm32 cv ) { ( __jit_b buf 72 ) ( __jit_b buf 129 ) ( __jit_b buf + 192 * ext 8 ) ( __jit_d buf cv ) ^ 1 } {} } {}
    ^ 0
}

@ __jit_alu_ci32 ( Vec u ) buf i op i cv → i {
    ? == op 181 {
        ? != 0 ( __jit_imm8 cv ) { ( __jit_b buf 107 ) ( __jit_b buf 192 ) ( __jit_b buf & cv 255 ) ^ 1 } {}  // imul eax,eax,imm8
        ( __jit_b buf 105 ) ( __jit_b buf 192 ) ( __jit_d buf cv ) ^ 1 } {}  // imul eax,eax,imm32
    ? == op 10 { ( __jit_b buf 193 ) ( __jit_b buf 224 ) ( __jit_b buf & cv 31 ) ^ 1 } {}  // shl eax,imm8
    ? == op 12 { ( __jit_b buf 193 ) ( __jit_b buf 232 ) ( __jit_b buf & cv 31 ) ^ 1 } {}  // shr eax,imm8
    ? == op 179 { ( __jit_b buf 193 ) ( __jit_b buf 248 ) ( __jit_b buf & cv 31 ) ^ 1 } {}  // sar eax,imm8
    : i ext ? == op 9 0 ? == op 185 5 ? == op 11 4 ? == op 184 1 ? == op 180 6 -1
    ? >= ext 0 {
        ? != 0 ( __jit_imm8 cv ) { ( __jit_b buf 131 ) ( __jit_b buf + 192 * ext 8 ) ( __jit_b buf & cv 255 ) ^ 1 } {}  // <op> eax,imm8
        ( __jit_b buf 129 ) ( __jit_b buf + 192 * ext 8 ) ( __jit_d buf cv ) ^ 1 } {}  // <op> eax,imm32 — low 32 bits only, always encodable
    ^ 0
}

// Pin-direct i64 ALU: dst pinned → run the whole record in r12..r15
// without touching rax. Returns 1 when emitted, 0 to take the rax path.
// The compact-constant discipline matches __jit_kv_writes: a -2 slot is
// only read from memory when its value is not imm-encodable (those keep
// their prologue write).
@ __jit_alu_pin ( Vec u ) buf ( Vec i ) pmap ( Vec i ) xmap ( Vec i ) cvals i op i a i b i c i raxslot → i {
    : i pa ( __jit_pr pmap a )
    ? & == c a != b a { ^ 0 } {}  // mov r_pa ← b would clobber the rhs
    ? >= ( __jit_xr xmap b ) 0 { ^ 0 } {}  // xmm-homed operands stay on the rax path
    ? >= ( __jit_xr xmap c ) 0 { ^ 0 } {}
    : i pc ( __jit_pr pmap c )
    : i ccv ? == pc -2 ( __jit_cv cvals c ) 0
    // imul by a compact constant: one 3-operand instruction, any b home
    ? & & == op 1 == pc -2 != 0 ( __jit_imm32 ccv ) {
        : i pb1 ( __jit_pr pmap b )
        ? >= pb1 0 {
            ? != 0 ( __jit_imm8 ccv ) { ( __jit_b buf 77 ) ( __jit_b buf 107 ) ( __jit_b buf + 192 + * pa 8 pb1 ) ( __jit_b buf & ccv 255 ) } {
                ( __jit_b buf 77 ) ( __jit_b buf 105 ) ( __jit_b buf + 192 + * pa 8 pb1 ) ( __jit_d buf ccv ) }  // imul r_pa,r_pb,imm
            ^ 1
        } {}
        ? == pb1 -1 {
            ? != 0 ( __jit_imm8 ccv ) { ( __jit_b buf 76 ) ( __jit_b buf 107 ) ( __jit_b buf + 131 * pa 8 ) ( __jit_d buf * b 8 ) ( __jit_b buf & ccv 255 ) } {
                ( __jit_b buf 76 ) ( __jit_b buf 105 ) ( __jit_b buf + 131 * pa 8 ) ( __jit_d buf * b 8 ) ( __jit_d buf ccv ) }  // imul r_pa,[rbx+b],imm
            ^ 1
        } {}
    } {}
    // r_pa ← b (skipped when accumulating in place)
    ? != b a { ? == 0 ( __jit_pmovsrc buf pmap xmap cvals pa b raxslot ) { ^ 0 } {} } {}
    ? | | == op 8 == op 3 == op 6 {  // shifts: count in cl, or imm8 for constants
        : i sext ? == op 8 4 ? == op 3 5 7
        ? == pc -2 { ( __jit_b buf 73 ) ( __jit_b buf 193 ) ( __jit_b buf + 192 + * sext 8 pa ) ( __jit_b buf & ccv 63 ) ^ 1 } {}  // sh r_pa,imm8
        ( __jit_ldrcx_m buf pmap xmap cvals c )
        ( __jit_b buf 73 ) ( __jit_b buf 211 ) ( __jit_b buf + 192 + * sext 8 pa ) ^ 1  // sh r_pa,cl
    } {}
    ? == op 1 {  // imul
        ? >= pc 0 { ( __jit_b buf 77 ) ( __jit_b buf 15 ) ( __jit_b buf 175 ) ( __jit_b buf + 192 + * pa 8 pc ) ^ 1 } {}  // imul r_pa,r_pc
        ? & == pc -2 != 0 ( __jit_imm32 ccv ) {
            ( __jit_b buf 77 ) ( __jit_b buf 105 ) ( __jit_b buf + 192 + * pa 8 pa ) ( __jit_d buf ccv ) ^ 1 } {}  // imul r_pa,r_pa,imm
        ( __jit_b buf 76 ) ( __jit_b buf 15 ) ( __jit_b buf 175 ) ( __jit_b buf + 131 * pa 8 ) ( __jit_d buf * c 8 ) ^ 1  // imul r_pa,[rbx+c]
    } {}
    : i ropc ? == op 0 3 ? == op 5 43 ? == op 2 35 ? == op 7 11 51  // reg-form add/sub/and/or/xor
    ? >= pc 0 { ( __jit_prr buf ropc pa pc ) ^ 1 } {}
    ? & == pc -2 != 0 ( __jit_imm32 ccv ) {
        : i iext ? == op 0 0 ? == op 5 5 ? == op 2 4 ? == op 7 1 6
        ( __jit_pri buf iext pa ccv ) ^ 1
    } {}
    ( __jit_prm buf ropc pa c ) ^ 1  // memory rhs (wide constants keep their slot write)
}

@ __jit_alu ( Vec u ) buf ( Vec i ) pmap ( Vec i ) xmap ( Vec i ) cvals i op i a i b i c i d i raxslot → v {
    // pin-direct i64 forms first: dst pinned + plain op → no rax at all
    ? & & >= op 0 <= op 8 >= ( __jit_pr pmap a ) 0 {
        ? != 0 ( __jit_alu_pin buf pmap xmap cvals op a b c raxslot ) { = g_jit_noax 1 ^ v } {}
    } {}
    // every arm consumes s1 from rax first — one shared, cache-aware load
    ? != raxslot b { ( __jit_ldrax_m buf pmap xmap cvals b ) } {}
    // fused i64 pairs (a=dst b=s1 c=s2 d=x): dst = (s1 OP1 s2) OP2 x
    ? == op 13 { ( __jit_rax_imul_slot buf pmap xmap cvals c ) ( __jit_rax_op_slot buf pmap xmap cvals 1 d ) ( __jit_strax_m buf pmap xmap cvals a ) ^ v } {}  // MULADD: *,+
    ? == op 14 { ( __jit_rax_op_slot buf pmap xmap cvals 1 c ) ( __jit_rax_op_slot buf pmap xmap cvals 33 d ) ( __jit_strax_m buf pmap xmap cvals a ) ^ v } {}  // ADDAND: +,&
    ? == op 15 { ( __jit_rax_op_slot buf pmap xmap cvals 1 c ) ( __jit_rax_imul_slot buf pmap xmap cvals d ) ( __jit_strax_m buf pmap xmap cvals a ) ^ v } {}  // ADDMUL: +,*
    ? == op 16 { ( __jit_rax_op_slot buf pmap xmap cvals 1 c ) ( __jit_rax_shr_slot buf pmap xmap cvals d ) ( __jit_strax_m buf pmap xmap cvals a ) ^ v } {}  // ADDSHRU: +,>>u
    ? == op 17 { ( __jit_rax_shr_slot buf pmap xmap cvals c ) ( __jit_rax_op_slot buf pmap xmap cvals 33 d ) ( __jit_strax_m buf pmap xmap cvals a ) ^ v } {}  // SHRUAND: >>u,&
    ? == op 22 { ( __jit_rax_op_slot buf pmap xmap cvals 1 c ) ( __jit_rax_op_slot buf pmap xmap cvals 1 d ) ( __jit_strax_m buf pmap xmap cvals a ) ^ v } {}  // ADDADD: +,+
    ? == op 30 { ( __jit_rax_shr_slot buf pmap xmap cvals c ) ( __jit_rax_op_slot buf pmap xmap cvals 49 d ) ( __jit_strax_m buf pmap xmap cvals a ) ^ v } {}  // SHRUXOR: >>u,^
    ? == op 33 { ( __jit_rax_op_slot buf pmap xmap cvals 49 c ) ( __jit_rax_imul_slot buf pmap xmap cvals d ) ( __jit_strax_m buf pmap xmap cvals a ) ^ v } {}  // XORMUL: ^,*
    // i32 family (9-12 base, 179/180/181/184/185 demoted): 32-bit op then movslq
    ? | & >= op 9 <= op 12 & >= op 179 <= op 185 {
        : ~ i cdone 0
        ? == -2 ( __jit_pr pmap c ) { = cdone ( __jit_alu_ci32 buf op ( __jit_cv cvals c ) ) } {}
        ? != 0 cdone { ( __jit_movslq buf ) ( __jit_strax_m buf pmap xmap cvals a ) ^ v } {}
        ( __jit_ldrcx_m buf pmap xmap cvals c )
        ? == op 9 { ( __jit_b buf 1 ) ( __jit_b buf 200 ) } {}  // add eax,ecx
        ? == op 185 { ( __jit_b buf 41 ) ( __jit_b buf 200 ) } {}  // sub
        ? == op 181 { ( __jit_b buf 15 ) ( __jit_b buf 175 ) ( __jit_b buf 193 ) } {}  // imul
        ? == op 11 { ( __jit_b buf 33 ) ( __jit_b buf 200 ) } {}  // and
        ? == op 184 { ( __jit_b buf 9 ) ( __jit_b buf 200 ) } {}  // or
        ? == op 180 { ( __jit_b buf 49 ) ( __jit_b buf 200 ) } {}  // xor
        ? == op 10 { ( __jit_b buf 211 ) ( __jit_b buf 224 ) } {}  // shl eax,cl
        ? == op 12 { ( __jit_b buf 211 ) ( __jit_b buf 232 ) } {}  // shr eax,cl
        ? == op 179 { ( __jit_b buf 211 ) ( __jit_b buf 248 ) } {}  // sar eax,cl
        ( __jit_movslq buf ) ( __jit_strax_m buf pmap xmap cvals a )
    } {
        : ~ i cdone 0
        ? == -2 ( __jit_pr pmap c ) { = cdone ( __jit_alu_ci64 buf op ( __jit_cv cvals c ) ) } {}
        ? != 0 cdone { ( __jit_strax_m buf pmap xmap cvals a ) ^ v } {}
        ( __jit_ldrcx_m buf pmap xmap cvals c )
        ? == op 0 { ( __jit_b buf 72 ) ( __jit_b buf 1 ) ( __jit_b buf 200 ) } {}  // add rax,rcx
        ? == op 5 { ( __jit_b buf 72 ) ( __jit_b buf 41 ) ( __jit_b buf 200 ) } {}  // sub
        ? == op 1 { ( __jit_b buf 72 ) ( __jit_b buf 15 ) ( __jit_b buf 175 ) ( __jit_b buf 193 ) } {}  // imul
        ? == op 2 { ( __jit_b buf 72 ) ( __jit_b buf 33 ) ( __jit_b buf 200 ) } {}  // and
        ? == op 7 { ( __jit_b buf 72 ) ( __jit_b buf 9 ) ( __jit_b buf 200 ) } {}  // or
        ? == op 4 { ( __jit_b buf 72 ) ( __jit_b buf 49 ) ( __jit_b buf 200 ) } {}  // xor
        ? == op 8 { ( __jit_b buf 72 ) ( __jit_b buf 211 ) ( __jit_b buf 224 ) } {}  // shl rax,cl
        ? == op 3 { ( __jit_b buf 72 ) ( __jit_b buf 211 ) ( __jit_b buf 232 ) } {}  // shr rax,cl
        ? == op 6 { ( __jit_b buf 72 ) ( __jit_b buf 211 ) ( __jit_b buf 248 ) } {}  // sar rax,cl
        ( __jit_strax_m buf pmap xmap cvals a )
    }
}

@ __jit_kvw_mark ( Vec i ) need i s → v {
    ? & >= s 0 < s ( vec_len [i] need ) { ( vec_set [i] need s 1 ) } {}
}

// Which constant-pool slots must the prologue still write to memory?
// A compact (-2-marked) constant is materialized as an immediate at
// every use site that goes through the mapped accessors, so its frame
// slot is never read and the per-call write is pure waste. A use that
// falls back to a raw [rbx+slot] read keeps the write: wide values,
// xmm-path operands (the f64 templates read slots directly), the raw
// slot templates (wrap/extend/clz/rem_u/shifted loads), call arguments
// (the callee reads them through the args pointer), and the FCB operand
// window (the driver reads it from frame memory). Unknown ops keep
// every write. Returns 0/1 per slot (1 = must write).
@ __jit_kv_writes * PFunc pf ( Vec i ) pmap ( Vec i ) xmap ( Vec i ) cvals → ( Vec i ) {
    : i nsl . pf nslots
    : i nl . pf nlocals
    : i knum ( vec_len [i] . pf kv )
    : ( Vec i ) need ( vec_new [i] )
    : ~ i s 0
    ~ < s nsl { ( vec_push [i] need 0 ) = s + s 1 }
    // pinned, xmm-pinned or wide slots always keep the write
    : ~ i kk 0
    ~ < kk knum {
        : i cs + nl kk
        ? < cs nsl {
            : ~ i keep 0
            ? != -2 ( __jit_pr pmap cs ) { = keep 1 } {}
            ? >= ( __jit_xr xmap cs ) 0 { = keep 1 } {}
            ? == 0 ( __jit_imm32 ( __jit_cv cvals cs ) ) { = keep 1 } {}
            ? != 0 keep { ( vec_set [i] need cs 1 ) } {}
        } {}
        = kk + kk 1
    }
    : ( Vec i ) code . pf code
    : i n . pf count
    : ~ i markall 0
    : ~ i r 0
    ~ & < r n == 0 markall {
        : i base * r 6
        : i op ?? ( vec_get [i] code base ) { T x → x F → -1 }
        : i b ?? ( vec_get [i] code + base 2 ) { T x → x F → 0 }
        : i c ?? ( vec_get [i] code + base 3 ) { T x → x F → 0 }
        : i d ?? ( vec_get [i] code + base 4 ) { T x → x F → 0 }
        // raw-slot readers of b: wrap/extend_u (36,37), clz (93), sqrt
        // (131), extendN_s (157-161), LOADSHL (205,206)
        ? | == op 36 | == op 37 | == op 93 | == op 131 | & >= op 157 <= op 161 | == op 205 == op 206 { ( __jit_kvw_mark need b ) } {}
        ? == op 99 { ( __jit_kvw_mark need b ) ( __jit_kvw_mark need c ) } {}  // i32.rem_u: raw 32-bit loads
        ? | & >= op 39 <= op 42 == op 197 { ( __jit_kvw_mark need b ) ( __jit_kvw_mark need c ) } {}  // f64 alu / ADDSTOREF64
        ? & >= op 194 <= op 196 { ( __jit_kvw_mark need d ) } {}  // LOADMUL/ADD/SUBBF64: x from the slot
        ? & >= op 198 <= op 201 { ( __jit_kvw_mark need b ) ( __jit_kvw_mark need c ) ( __jit_kvw_mark need d ) } {}  // fused f64 triples
        ? | == op 207 == op 208 { ( __jit_kvw_mark need b ) ( __jit_kvw_mark need d ) } {}  // LOADSHLADD: base + x raw
        ? | | == op 50 == op 210 == op 170 {  // calls: the callee reads [argbase..] from memory
            : ~ i ck 0
            ~ < ck knum { ? >= + nl ck b { ( __jit_kvw_mark need + nl ck ) } {} = ck + ck 1 }
        } {}
        ? == op 171 {  // FCB: the driver reads slots [c, c+pops) from memory
            : i fpops ( __lshr64 d 1 )
            : ~ i fk 0
            ~ < fk fpops { ( __jit_kvw_mark need + c fk ) = fk + fk 1 }
        } {}
        // every op the scan understands (marked above or read via mapped
        // accessors only); anything else keeps every write
        : ~ i known 0
        ? & >= op 0 <= op 17 { = known 1 } {}
        ? | == op 22 | == op 30 == op 33 { = known 1 } {}
        ? & >= op 36 <= op 75 { = known 1 } {}
        ? & >= op 179 <= op 185 { = known 1 } {}
        ? | == op 93 | & >= op 96 <= op 99 | & >= op 105 <= op 108 | == op 125 == op 126 { = known 1 } {}
        ? | == op 131 | & >= op 153 <= op 156 | & >= op 157 <= op 163 & >= op 169 <= op 172 { = known 1 } {}
        ? | & >= op 194 <= op 201 | & >= op 205 <= op 208 | == op 177 | | == op 210 == op 211 == op 212 { = known 1 } {}
        ? >= ( __jit_memkind op ) 0 { = known 1 } {}
        ? == 0 known { = markall 1 } {}
        = r + r 1
    }
    ? != 0 markall {
        = s 0
        ~ < s nsl { ( vec_set [i] need s 1 ) = s + s 1 }
    } {}
    ^ need
}

// Build the machine code for `pf`, seal a page, store the handle. Sets
// jit to -1 (do not retry) when the function is not templatable or no
// executable memory is available.
// Emit `test rax,rax` then a conditional jump on jcc-nibble to record
// `tgt`, deferring the rel32 to the patch list. `cond`<0 means the flags
// are already set (a fused compare); otherwise rax holds the tested slot.
@ __jit_jmp ( Vec u ) buf ( Vec i ) pat_at ( Vec i ) pat_rec i jcc i tgt → v {
    ? == jcc 233 { ( __jit_b buf 233 ) } { ( __jit_b buf 15 ) ( __jit_b buf jcc ) }  // jmp rel32 vs 0F 8x rel32
    ( vec_push [i] pat_at ( vec_len [u] buf ) )
    ( vec_push [i] pat_rec tgt )
    ( __jit_d buf 0 )
}
// Effective-address + bounds check shared by every memory template:
// rax = r11 + ((slot & 0xffffffff) + off), trapping when off+wid runs
// past r10 (the byte count). Mirrors the plain load/store emitters.
@ __jit_membc ( Vec u ) buf ( Vec i ) pmap ( Vec i ) xmap ( Vec i ) cvals ( Vec i ) pat_at ( Vec i ) pat_rec i trap_rec i baseslot i off i wid i raxslot i guard → v {
    ? != raxslot baseslot { ( __jit_ldrax_m buf pmap xmap cvals baseslot ) } {}
    ( __jit_bc buf pat_at pat_rec trap_rec off wid guard )
}

// The same check when the caller has already computed the unmasked
// address into rax (the shifted-index load templates).
// Leaves rax = the masked guest index; the access itself is one SIB
// instruction [rax + r11 + off] emitted via __jit_mem below.
// Guard-page mode keeps only the index mask: with r11 the base of an
// 8 GiB PROT_NONE reservation, every (masked index + u32 offset) lands
// inside it, and an access past the committed pages faults into the
// runtime's SIGSEGV handler, which steers this frame to the same trap
// stub the explicit check jumps to. The mask is NOT optional — a slot
// holds a canonically sign-extended i32, and a negative index without
// it would reach 2 GiB below the reservation.
@ __jit_bc ( Vec u ) buf ( Vec i ) pat_at ( Vec i ) pat_rec i trap_rec i off i wid i guard → v {
    ( __jit_b buf 137 ) ( __jit_b buf 192 )  // mov eax,eax (& 0xffffffff)
    ? != 0 guard { ^ v } {}
    ( __jit_b buf 72 ) ( __jit_b buf 141 ) ( __jit_b buf 136 ) ( __jit_d buf + off wid )  // lea rcx,[rax+off+wid]
    ( __jit_b buf 73 ) ( __jit_b buf 57 ) ( __jit_b buf 202 )  // cmp r10,rcx
    ( __jit_jmp buf pat_at pat_rec 130 trap_rec )  // jb trap
}

// One bounds-checked access: optional prefix byte, optional 0F escape,
// opcode, then ModRM/SIB for [rax + r11*1 + off]; 64-bit operand size.
@ __jit_mem ( Vec u ) buf i pfx i esc i opc i reg i off → v {
    ? != 0 pfx { ( __jit_b buf pfx ) } {}
    ( __jit_b buf 74 )  // REX.W+X
    ? != 0 esc { ( __jit_b buf 15 ) } {}
    ( __jit_b buf opc )
    ( __jit_b buf | 132 << reg 3 )  // ModRM: mod10 reg rm=100 (SIB)
    ( __jit_b buf 24 )  // SIB: base=rax, index=r11, scale=1
    ( __jit_d buf off )
}

// The 32/16/8-bit-operand spelling (REX.X only).
@ __jit_mem32 ( Vec u ) buf i pfx i esc i opc i reg i off → v {
    ? != 0 pfx { ( __jit_b buf pfx ) } {}
    ( __jit_b buf 66 )  // REX.X
    ? != 0 esc { ( __jit_b buf 15 ) } {}
    ( __jit_b buf opc )
    ( __jit_b buf | 132 << reg 3 )
    ( __jit_b buf 24 )
    ( __jit_d buf off )
}

// cmp of two slots (i64 or i32), leaving flags for a following jcc/setcc.
// `raxslot` is the emitter's one-register cache: the slot whose value rax
// already holds (-1 = none) — a matching load is skipped.
@ __jit_cmp ( Vec u ) buf ( Vec i ) pmap ( Vec i ) xmap ( Vec i ) cvals i b i c i is32 i raxslot → v {
    // pin-direct: compare r_pb against the rhs without loading rax.
    // Callers that go on to write rax (setcc paths) clear g_jit_noax.
    : i pbd ( __jit_pr pmap b )
    ? >= pbd 0 {
        : i pcd ( __jit_pr pmap c )
        ? >= pcd 0 {
            ? == 0 is32 { ( __jit_prr buf 59 pbd pcd ) } {
                ( __jit_b buf 69 ) ( __jit_b buf 59 ) ( __jit_b buf + 192 + * pbd 8 pcd ) }  // cmp r_pb d,r_pc d
            = g_jit_noax 1 ^ v
        } {}
        ? == pcd -2 {
            : i dcv ( __jit_cv cvals c )
            ? != 0 ( __jit_imm32 dcv ) {
                ? == 0 is32 { ( __jit_pri buf 7 pbd dcv ) } {
                    ? != 0 ( __jit_imm8 dcv ) { ( __jit_b buf 65 ) ( __jit_b buf 131 ) ( __jit_b buf + 248 pbd ) ( __jit_b buf & dcv 255 ) } {
                        ( __jit_b buf 65 ) ( __jit_b buf 129 ) ( __jit_b buf + 248 pbd ) ( __jit_d buf dcv ) } }  // cmp r_pb d,imm
                = g_jit_noax 1 ^ v
            } {}
        } {}
        ? < ( __jit_xr xmap c ) 0 {  // memory rhs (xmm-homed slots stay on the rax path)
            ? == 0 is32 { ( __jit_prm buf 59 pbd c ) } {
                ( __jit_b buf 68 ) ( __jit_b buf 59 ) ( __jit_b buf + 131 * pbd 8 ) ( __jit_d buf * c 8 ) }  // cmp r_pb d,dword[rbx+c]
            = g_jit_noax 1 ^ v
        } {}
    } {}
    ? != raxslot b { ( __jit_ldrax_m buf pmap xmap cvals b ) } {}
    : i pcc ( __jit_pr pmap c )
    ? == pcc -2 {
        : i ccv ( __jit_cv cvals c )
        ? != 0 ( __jit_imm8 ccv ) {
            ? == 0 is32 { ( __jit_b buf 72 ) } {}
            ( __jit_b buf 131 ) ( __jit_b buf 248 ) ( __jit_b buf & ccv 255 ) ^ v  // cmp e/rax, imm8
        } {}
        ? != 0 ( __jit_imm32 ccv ) {
            ? == 0 is32 { ( __jit_b buf 72 ) } {}
            ( __jit_b buf 129 ) ( __jit_b buf 248 ) ( __jit_d buf ccv ) ^ v  // cmp e/rax, imm32
        } {}
    } {}
    ( __jit_ldrcx_m buf pmap xmap cvals c )
    ? != 0 is32 { ( __jit_b buf 57 ) ( __jit_b buf 200 ) } { ( __jit_b buf 72 ) ( __jit_b buf 57 ) ( __jit_b buf 200 ) }  // cmp e/rax, e/rcx
}

// A reusable 7-word JIT call context from the per-Interp freelist (word 0
// links the free chain). This replaces a Vec per call-out — the profile
// showed vec_new/push/grow/free dominating recursive guest calls.
@ __jit_ctx_get * Interp it → *i {
    : i h . it jit_ctx_free
    ? != h 0 {
        : *i b # *i h
        = . it jit_ctx_free . b 0
        ^ b
    } {}
    ^ # *i ( nurl_zalloc 64 )
}

@ __jit_ctx_put * Interp it * i b → v {
    = . b 0 . it jit_ctx_free
    = . it jit_ctx_free # i b
}

// Park this native frame on the pause chain: (page, resume, rbx, args).
// Preserves rax (the propagate path carries the callee's status in it);
// clobbers rcx/rdx/r8. The page address is patched post-copy (pta lists,
// stub offset 0 = page base); the resume imm is patched by the caller —
// its byte offset is returned.
@ __jit_pause ( Vec u ) buf i chaincell ( Vec i ) pta_off ( Vec i ) pta_stub → i {
    ( __jit_b buf 72 ) ( __jit_b buf 185 ) ( __jit_q buf chaincell )  // mov rcx,&chain-top
    ( __jit_b buf 72 ) ( __jit_b buf 139 ) ( __jit_b buf 17 )  // mov rdx,[rcx]
    ( vec_push [i] pta_off + ( vec_len [u] buf ) 2 )  // imm64 operand of the next insn
    ( vec_push [i] pta_stub 0 )  // page base
    ( __jit_b buf 73 ) ( __jit_b buf 184 ) ( __jit_q buf 0 )  // mov r8, SELF (patched)
    ( __jit_b buf 76 ) ( __jit_b buf 137 ) ( __jit_b buf 2 )  // mov [rdx],r8
    ( __jit_b buf 199 ) ( __jit_b buf 66 ) ( __jit_b buf 8 ) ( __jit_d buf 0 )  // mov dword[rdx+8], resume (patched; driver masks)
    : i rimm - ( vec_len [u] buf ) 4
    ( __jit_b buf 72 ) ( __jit_b buf 137 ) ( __jit_b buf 90 ) ( __jit_b buf 16 )  // mov [rdx+16],rbx
    ( __jit_b buf 76 ) ( __jit_b buf 139 ) ( __jit_b buf 4 ) ( __jit_b buf 36 )  // mov r8,[rsp] — the saved args ptr
    ( __jit_b buf 76 ) ( __jit_b buf 137 ) ( __jit_b buf 66 ) ( __jit_b buf 24 )  // mov [rdx+24],r8
    ( __jit_b buf 72 ) ( __jit_b buf 131 ) ( __jit_b buf 1 ) ( __jit_b buf 32 )  // add qword[rcx],32
    ^ rimm
}

// The ops beyond the original tier set: extend/wrap, select, and the
// fused memory/f64 records the predecoder emits. Falls through to the
// plain ALU emitter for everything else.
@ __jit_ext ( Vec u ) buf ( Vec i ) pmap ( Vec i ) pins i npin ( Vec i ) xmap ( Vec i ) xpins ( Vec i ) cvals ( Vec i ) pat_at ( Vec i ) pat_rec i trap_rec i op i a i b i c i d i w5 i raxslot ( Vec i ) auxv ( Vec i ) pta_off ( Vec i ) pta_stub i chaincell i spcell i guard i xmmslot → v {
    ? == op 36 {  // i32.wrap_i64: dst = sign-extended low 32 of src
        ? == raxslot b { ( __jit_movslq buf ) } {  // rax already holds the slot
            : i pw ( __jit_pr pmap b )
            ? >= pw 0 { ( __jit_oprax_pr buf 99 pw ) } {  // movsxd rax,r1Xd
                ( __jit_b buf 72 ) ( __jit_b buf 99 ) ( __jit_b buf 131 ) ( __jit_d buf * b 8 )  // movsxd rax,dword[rbx+b]
            }
        }
        ( __jit_strax_m buf pmap xmap cvals a ) ^ v
    } {}
    ? == op 37 {  // i64.extend_i32_u: dst = src & 0xffffffff
        ? == raxslot b { ( __jit_b buf 137 ) ( __jit_b buf 192 ) } {  // mov eax,eax
            : i pu ( __jit_pr pmap b )
            ? >= pu 0 { ( __jit_opeax_pr buf 139 pu ) } {  // mov eax,r1Xd (zero-extends)
                ( __jit_b buf 139 ) ( __jit_b buf 131 ) ( __jit_d buf * b 8 )  // mov eax,dword[rbx+b] (zero-extends)
            }
        }
        ( __jit_strax_m buf pmap xmap cvals a ) ^ v
    } {}
    ? == op 46 {  // SEL: dst = cond(d) != 0 ? srcT(b) : srcF(c)
        ? != raxslot d { ( __jit_ldrax_m buf pmap xmap cvals d ) } {}
        ( __jit_b buf 72 ) ( __jit_b buf 133 ) ( __jit_b buf 192 )  // test rax,rax
        ( __jit_ldrax_m buf pmap xmap cvals c )  // srcF (mov leaves flags)
        ( __jit_ldrcx_m buf pmap xmap cvals b )  // srcT
        ( __jit_b buf 72 ) ( __jit_b buf 15 ) ( __jit_b buf 69 ) ( __jit_b buf 193 )  // cmovne rax,rcx
        ( __jit_strax_m buf pmap xmap cvals a ) ^ v
    } {}
    ? | == op 211 == op 212 {  // LOADMULI64 / LOADADDI64: dst = mem64[b+off] OP x(d)
        ( __jit_membc buf pmap xmap cvals pat_at pat_rec trap_rec b c 8 raxslot guard )
        ( __jit_mem buf 0 0 139 0 c )  // mov rax,[mem]
        ? == op 211 { ( __jit_rax_imul_slot buf pmap xmap cvals d ) } { ( __jit_rax_op_slot buf pmap xmap cvals 1 d ) }
        ( __jit_strax_m buf pmap xmap cvals a ) ^ v
    } {}
    ? | == op 194 == op 195 {  // LOADMULF64 / LOADADDF64: dst = mem[f64] OP x(d)
        ( __jit_membc buf pmap xmap cvals pat_at pat_rec trap_rec b c 8 raxslot guard )
        ( __jit_mem32 buf 242 1 16 0 c )  // movsd xmm0,[mem]
        ( __jit_sd_op_m buf xmap ? == op 194 89 88 d )  // mulsd / addsd
        ( __jit_movsd_st_m buf xmap a ) ^ v
    } {}
    ? == op 196 {  // LOADSUBBF64: dst = x(d) - mem[f64]
        ( __jit_membc buf pmap xmap cvals pat_at pat_rec trap_rec b c 8 raxslot guard )
        ( __jit_mem32 buf 242 1 16 0 c )  // movsd xmm0,[mem]
        ( __jit_movsd_x1x0 buf )
        ( __jit_movsd_ld_m buf xmap d )
        ( __jit_subsd_x0x1 buf )
        ( __jit_movsd_st_m buf xmap a ) ^ v
    } {}
    ? == op 197 {  // ADDSTOREF64: mem[a+off(d)] = s1(b) + s2(c)
        ? != xmmslot b { ( __jit_movsd_ld_m buf xmap b ) } {}
        ( __jit_sd_op_m buf xmap 88 c )  // addsd
        ( __jit_membc buf pmap xmap cvals pat_at pat_rec trap_rec a d 8 raxslot guard )
        ( __jit_mem32 buf 242 1 17 0 d )  // movsd [mem],xmm0
        ^ v
    } {}
    ? | == op 198 == op 199 {  // MULADDF64 / MULSUBAF64: dst = (s1*s2) ± x
        ? != xmmslot b { ( __jit_movsd_ld_m buf xmap b ) } {}
        ( __jit_sd_op_m buf xmap 89 c )  // mulsd
        ( __jit_sd_op_m buf xmap ? == op 198 88 92 d )  // addsd / subsd
        ( __jit_movsd_st_m buf xmap a ) ^ v
    } {}
    ? == op 200 {  // MULSUBBF64: dst = x - (s1*s2)
        ? != xmmslot b { ( __jit_movsd_ld_m buf xmap b ) } {}
        ( __jit_sd_op_m buf xmap 89 c )  // mulsd
        ( __jit_movsd_x1x0 buf )
        ( __jit_movsd_ld_m buf xmap d )
        ( __jit_subsd_x0x1 buf )
        ( __jit_movsd_st_m buf xmap a ) ^ v
    } {}
    ? == op 201 {  // SUBMULF64: dst = (s1-s2) * x
        ? != xmmslot b { ( __jit_movsd_ld_m buf xmap b ) } {}
        ( __jit_sd_op_m buf xmap 92 c )  // subsd
        ( __jit_sd_op_m buf xmap 89 d )  // mulsd
        ( __jit_movsd_st_m buf xmap a ) ^ v
    } {}
    ? == op 131 {  // f64.sqrt
        ? == xmmslot b { ( __jit_b buf 242 ) ( __jit_b buf 15 ) ( __jit_b buf 81 ) ( __jit_b buf 192 ) } {  // sqrtsd xmm0,xmm0
            : i pq7 ( __jit_xr xmap b )
            ? >= pq7 0 { ( __jit_b buf 242 ) ( __jit_b buf 65 ) ( __jit_b buf 15 ) ( __jit_b buf 81 ) ( __jit_b buf + 192 pq7 ) } {  // sqrtsd xmm0,xmm8+p
                ( __jit_b buf 242 ) ( __jit_b buf 15 ) ( __jit_b buf 81 ) ( __jit_b buf 131 ) ( __jit_d buf * b 8 ) } }  // sqrtsd xmm0,[rbx+b]
        ( __jit_movsd_st_m buf xmap a ) ^ v
    } {}
    ? == op 93 {  // i32.clz — bsr+cmov (baseline x86-64, no lzcnt)
        : i pz ( __jit_pr pmap b )
        ? >= pz 0 { ( __jit_opeax_pr buf 139 pz ) } {  // mov eax,r1Xd
            ( __jit_b buf 139 ) ( __jit_b buf 131 ) ( __jit_d buf * b 8 )  // mov eax,dword[rbx+b]
        }
        ( __jit_b buf 186 ) ( __jit_d buf -1 )  // mov edx,-1
        ( __jit_b buf 15 ) ( __jit_b buf 189 ) ( __jit_b buf 200 )  // bsr ecx,eax (ZF=1 on zero)
        ( __jit_b buf 15 ) ( __jit_b buf 68 ) ( __jit_b buf 202 )  // cmovz ecx,edx
        ( __jit_b buf 184 ) ( __jit_d buf 31 )  // mov eax,31
        ( __jit_b buf 41 ) ( __jit_b buf 200 )  // sub eax,ecx → 31-bsr, or 32 when src==0
        ( __jit_strax_m buf pmap xmap cvals a ) ^ v
    } {}
    ? == op 99 {  // i32.rem_u — trap on zero divisor
        : i pn ( __jit_pr pmap b )
        ? >= pn 0 { ( __jit_opeax_pr buf 139 pn ) } {  // mov eax,r1Xd
            ( __jit_b buf 139 ) ( __jit_b buf 131 ) ( __jit_d buf * b 8 )  // mov eax,dword[rbx+b]
        }
        : i pd ( __jit_pr pmap c )
        ? >= pd 0 { ( __jit_b buf 65 ) ( __jit_b buf 139 ) ( __jit_b buf + 200 pd ) } {  // mov ecx,r1Xd
            ( __jit_b buf 139 ) ( __jit_b buf 139 ) ( __jit_d buf * c 8 )  // mov ecx,dword[rbx+c]
        }
        ( __jit_b buf 133 ) ( __jit_b buf 201 )  // test ecx,ecx
        ( __jit_jmp buf pat_at pat_rec 132 + trap_rec 1 )  // jz div-trap
        ( __jit_b buf 49 ) ( __jit_b buf 210 )  // xor edx,edx
        ( __jit_b buf 247 ) ( __jit_b buf 241 )  // div ecx → edx=rem
        ( __jit_b buf 137 ) ( __jit_b buf 208 )  // mov eax,edx
        ( __jit_movslq buf )  // canonical i32
        ( __jit_strax_m buf pmap xmap cvals a ) ^ v
    } {}
    ? == op 106 {  // i64.div_u — trap on zero divisor
        ? != raxslot b { ( __jit_ldrax_m buf pmap xmap cvals b ) } {}
        ( __jit_ldrcx_m buf pmap xmap cvals c )
        ( __jit_b buf 72 ) ( __jit_b buf 133 ) ( __jit_b buf 201 )  // test rcx,rcx
        ( __jit_jmp buf pat_at pat_rec 132 + trap_rec 1 )  // jz div-trap
        ( __jit_b buf 49 ) ( __jit_b buf 210 )  // xor edx,edx
        ( __jit_b buf 72 ) ( __jit_b buf 247 ) ( __jit_b buf 241 )  // div rcx → rax=quot
        ( __jit_strax_m buf pmap xmap cvals a ) ^ v
    } {}
    ? == op 105 {  // i64.div_s — trap on zero divisor and on MIN/-1
        ? != raxslot b { ( __jit_ldrax_m buf pmap xmap cvals b ) } {}
        ( __jit_ldrcx_m buf pmap xmap cvals c )
        ( __jit_b buf 72 ) ( __jit_b buf 133 ) ( __jit_b buf 201 )  // test rcx,rcx
        ( __jit_jmp buf pat_at pat_rec 132 + trap_rec 1 )  // jz div-trap
        ( __jit_b buf 72 ) ( __jit_b buf 131 ) ( __jit_b buf 249 ) ( __jit_b buf 255 )  // cmp rcx,-1
        ( __jit_b buf 117 ) ( __jit_b buf 19 )  // jne +19 — over the movabs/cmp/je below
        ( __jit_b buf 72 ) ( __jit_b buf 186 ) ( __jit_q buf -9223372036854775808 )  // movabs rdx,INT64_MIN
        ( __jit_b buf 72 ) ( __jit_b buf 57 ) ( __jit_b buf 208 )  // cmp rax,rdx
        ( __jit_jmp buf pat_at pat_rec 132 + trap_rec 4 )  // je overflow-trap
        ( __jit_b buf 72 ) ( __jit_b buf 153 )  // cqo
        ( __jit_b buf 72 ) ( __jit_b buf 247 ) ( __jit_b buf 249 )  // idiv rcx → rax=quot
        ( __jit_strax_m buf pmap xmap cvals a ) ^ v
    } {}
    ? == op 107 {  // i64.rem_s — trap on zero divisor; MIN rem -1 = 0, no trap
        ? != raxslot b { ( __jit_ldrax_m buf pmap xmap cvals b ) } {}
        ( __jit_ldrcx_m buf pmap xmap cvals c )
        ( __jit_b buf 72 ) ( __jit_b buf 133 ) ( __jit_b buf 201 )  // test rcx,rcx
        ( __jit_jmp buf pat_at pat_rec 132 + trap_rec 1 )  // jz div-trap
        ( __jit_b buf 72 ) ( __jit_b buf 131 ) ( __jit_b buf 249 ) ( __jit_b buf 255 )  // cmp rcx,-1
        ( __jit_b buf 117 ) ( __jit_b buf 4 )  // jne +4 — to the cqo
        ( __jit_b buf 49 ) ( __jit_b buf 192 )  // xor eax,eax — x rem -1 = 0
        ( __jit_b buf 235 ) ( __jit_b buf 8 )  // jmp +8 — over cqo/idiv/mov
        ( __jit_b buf 72 ) ( __jit_b buf 153 )  // cqo
        ( __jit_b buf 72 ) ( __jit_b buf 247 ) ( __jit_b buf 249 )  // idiv rcx
        ( __jit_b buf 72 ) ( __jit_b buf 137 ) ( __jit_b buf 208 )  // mov rax,rdx
        ( __jit_strax_m buf pmap xmap cvals a ) ^ v
    } {}
    ? == op 97 {  // i32.div_u — trap on zero divisor
        ? != raxslot b { ( __jit_ldrax_m buf pmap xmap cvals b ) } {}
        ( __jit_b buf 137 ) ( __jit_b buf 192 )  // mov eax,eax — unsigned view
        ( __jit_ldrcx_m buf pmap xmap cvals c )
        ( __jit_b buf 137 ) ( __jit_b buf 201 )  // mov ecx,ecx
        ( __jit_b buf 133 ) ( __jit_b buf 201 )  // test ecx,ecx
        ( __jit_jmp buf pat_at pat_rec 132 + trap_rec 1 )  // jz div-trap
        ( __jit_b buf 49 ) ( __jit_b buf 210 )  // xor edx,edx
        ( __jit_b buf 247 ) ( __jit_b buf 241 )  // div ecx → eax=quot
        ( __jit_movslq buf )  // canonical i32
        ( __jit_strax_m buf pmap xmap cvals a ) ^ v
    } {}
    ? == op 96 {  // i32.div_s — trap on zero divisor and on MIN/-1
        ? != raxslot b { ( __jit_ldrax_m buf pmap xmap cvals b ) } {}
        ( __jit_ldrcx_m buf pmap xmap cvals c )
        ( __jit_b buf 133 ) ( __jit_b buf 201 )  // test ecx,ecx
        ( __jit_jmp buf pat_at pat_rec 132 + trap_rec 1 )  // jz div-trap
        ( __jit_b buf 131 ) ( __jit_b buf 249 ) ( __jit_b buf 255 )  // cmp ecx,-1
        ( __jit_b buf 117 ) ( __jit_b buf 11 )  // jne +11 — over the cmp/je below
        ( __jit_b buf 61 ) ( __jit_d buf -2147483648 )  // cmp eax,INT32_MIN
        ( __jit_jmp buf pat_at pat_rec 132 + trap_rec 4 )  // je overflow-trap
        ( __jit_b buf 153 )  // cdq
        ( __jit_b buf 247 ) ( __jit_b buf 249 )  // idiv ecx → eax=quot
        ( __jit_movslq buf )  // canonical i32
        ( __jit_strax_m buf pmap xmap cvals a ) ^ v
    } {}
    ? == op 98 {  // i32.rem_s — trap on zero divisor; MIN rem -1 = 0, no trap
        ? != raxslot b { ( __jit_ldrax_m buf pmap xmap cvals b ) } {}
        ( __jit_ldrcx_m buf pmap xmap cvals c )
        ( __jit_b buf 133 ) ( __jit_b buf 201 )  // test ecx,ecx
        ( __jit_jmp buf pat_at pat_rec 132 + trap_rec 1 )  // jz div-trap
        ( __jit_b buf 131 ) ( __jit_b buf 249 ) ( __jit_b buf 255 )  // cmp ecx,-1
        ( __jit_b buf 117 ) ( __jit_b buf 4 )  // jne +4 — to the cdq
        ( __jit_b buf 49 ) ( __jit_b buf 192 )  // xor eax,eax
        ( __jit_b buf 235 ) ( __jit_b buf 5 )  // jmp +5 — over cdq/idiv/mov
        ( __jit_b buf 153 )  // cdq
        ( __jit_b buf 247 ) ( __jit_b buf 249 )  // idiv ecx
        ( __jit_b buf 137 ) ( __jit_b buf 208 )  // mov eax,edx
        ( __jit_movslq buf )  // canonical i32
        ( __jit_strax_m buf pmap xmap cvals a ) ^ v
    } {}
    ? == op 108 {  // i64.rem_u — trap on zero divisor
        ? != raxslot b { ( __jit_ldrax_m buf pmap xmap cvals b ) } {}
        ( __jit_ldrcx_m buf pmap xmap cvals c )
        ( __jit_b buf 72 ) ( __jit_b buf 133 ) ( __jit_b buf 201 )  // test rcx,rcx
        ( __jit_jmp buf pat_at pat_rec 132 + trap_rec 1 )  // jz div-trap
        ( __jit_b buf 49 ) ( __jit_b buf 210 )  // xor edx,edx
        ( __jit_b buf 72 ) ( __jit_b buf 247 ) ( __jit_b buf 241 )  // div rcx → rdx=rem
        ( __jit_b buf 72 ) ( __jit_b buf 137 ) ( __jit_b buf 208 )  // mov rax,rdx
        ( __jit_strax_m buf pmap xmap cvals a ) ^ v
    } {}
    ? | == op 205 == op 206 {  // LOADSHL64/32: dst = mem[(x<<k) w32 + off]; b=x d=kslot
        : i kc ( __jit_pr pmap d )
        ? != kc -2 { ( __jit_ldrcx_m buf pmap xmap cvals d ) } {}  // k (shl masks cl by 31)
        : i px ( __jit_pr pmap b )
        ? >= px 0 { ( __jit_opeax_pr buf 139 px ) } {  // mov eax,r1Xd
            ( __jit_b buf 139 ) ( __jit_b buf 131 ) ( __jit_d buf * b 8 )  // mov eax,dword[rbx+b] (low 32 of x)
        }
        ? == kc -2 { ( __jit_b buf 193 ) ( __jit_b buf 224 ) ( __jit_b buf & ( __jit_cv cvals d ) 31 ) } {  // shl eax,imm8
            ( __jit_b buf 211 ) ( __jit_b buf 224 ) }  // shl eax,cl
        ( __jit_movslq buf )  // __w32
        ( __jit_bc buf pat_at pat_rec trap_rec c ? == op 205 8 4 guard )
        ? == op 205 { ( __jit_mem buf 0 0 139 0 c ) } { ( __jit_mem buf 0 0 99 0 c ) }  // mov rax,[mem] / movsxd rax,dword[mem]
        ( __jit_strax_m buf pmap xmap cvals a ) ^ v
    } {}
    ? | == op 125 == op 126 {  // f64.abs / f64.neg: clear/flip the sign bit of the raw slot
        ? != raxslot b { ( __jit_ldrax_m buf pmap xmap cvals b ) } {}
        ( __jit_b buf 72 ) ( __jit_b buf 15 ) ( __jit_b buf 186 ) ( __jit_b buf ? == op 125 240 248 ) ( __jit_b buf 63 )  // btr/btc rax,63
        ( __jit_strax_m buf pmap xmap cvals a ) ^ v
    } {}
    ? & >= op 153 <= op 156 {  // reinterprets: raw slot copy
        ? != raxslot b { ( __jit_ldrax_m buf pmap xmap cvals b ) } {}
        ( __jit_strax_m buf pmap xmap cvals a ) ^ v
    } {}
    ? | | == op 157 == op 159 | == op 158 == op 160 {  // extend8/16_s (i32+i64): movsx from the slot's low byte/word
        : i is8 ? | == op 157 == op 159 1 0
        ? == raxslot b {
            ( __jit_b buf 72 ) ( __jit_b buf 15 ) ( __jit_b buf ? != 0 is8 190 191 ) ( __jit_b buf 192 )  // movsx rax,al/ax
        } {
            : i pe ( __jit_pr pmap b )
            ? >= pe 0 { ( __jit_b buf 73 ) ( __jit_b buf 15 ) ( __jit_b buf ? != 0 is8 190 191 ) ( __jit_b buf + 192 pe ) } {  // movsx rax,r1Xb/w
                ( __jit_b buf 72 ) ( __jit_b buf 15 ) ( __jit_b buf ? != 0 is8 190 191 ) ( __jit_b buf 131 ) ( __jit_d buf * b 8 )  // movsx rax,byte/word[rbx+b]
            }
        }
        ( __jit_strax_m buf pmap xmap cvals a ) ^ v
    } {}
    ? == op 161 {  // i64.extend32_s
        ? == raxslot b { ( __jit_movslq buf ) } {
            : i pq ( __jit_pr pmap b )
            ? >= pq 0 { ( __jit_oprax_pr buf 99 pq ) } {  // movsxd rax,r1Xd
                ( __jit_b buf 72 ) ( __jit_b buf 99 ) ( __jit_b buf 131 ) ( __jit_d buf * b 8 )  // movsxd rax,dword[rbx+b]
            }
        }
        ( __jit_strax_m buf pmap xmap cvals a ) ^ v
    } {}
    ? == op 162 {  // memory.size: pages = r10 >> 16
        ( __jit_b buf 76 ) ( __jit_b buf 137 ) ( __jit_b buf 208 )  // mov rax,r10
        ( __jit_b buf 72 ) ( __jit_b buf 193 ) ( __jit_b buf 232 ) ( __jit_b buf 16 )  // shr rax,16
        ( __jit_strax_m buf pmap xmap cvals a ) ^ v
    } {}
    ? == op 163 {  // memory.grow: call-out (status 6) — the driver reallocs and resumes
        // ctx[4]=delta(src b) ctx[6]=resume ctx[7]=dst slot(a)
        ( __jit_sync_pins buf pins ) ( __jit_sync_xpins buf xpins )  // the driver writes the dst slot in memory
        ? != raxslot b { ( __jit_ldrax_m buf pmap xmap cvals b ) } {}
        ( __jit_b buf 137 ) ( __jit_b buf 192 )  // mov eax,eax — keep ctx[4]'s upper bytes zero
        ( __jit_b buf 72 ) ( __jit_b buf 137 ) ( __jit_b buf 71 ) ( __jit_b buf 32 )  // mov [rdi+32], rax
        ( __jit_b buf 199 ) ( __jit_b buf 71 ) ( __jit_b buf 48 ) ( __jit_d buf 0 )  // mov [rdi+48], resume (patched)
        : i gimm_at - ( vec_len [u] buf ) 4
        ( __jit_b buf 199 ) ( __jit_b buf 71 ) ( __jit_b buf 56 ) ( __jit_d buf a )  // mov [rdi+56], dst slot
        ( __jit_b buf 72 ) ( __jit_b buf 137 ) ( __jit_b buf 31 )  // mov [rdi],rbx — the handler reads the frame base here
        : i prim ( __jit_pause buf chaincell pta_off pta_stub )
        ( __jit_b buf 184 ) ( __jit_d buf 18 )  // mov eax,18 (grow call-out)
        ( __jit_retseq buf npin )
        : i gresume ( vec_len [u] buf )
        ( vec_set [u] buf gimm_at # u & gresume 255 )
        ( vec_set [u] buf + gimm_at 1 # u & ( __lshr64 gresume 8 ) 255 )
        ( vec_set [u] buf + gimm_at 2 # u & ( __lshr64 gresume 16 ) 255 )
        ( vec_set [u] buf + gimm_at 3 # u & ( __lshr64 gresume 24 ) 255 )
        ( vec_set [u] buf prim # u & gresume 255 )
        ( vec_set [u] buf + prim 1 # u & ( __lshr64 gresume 8 ) 255 )
        ( vec_set [u] buf + prim 2 # u & ( __lshr64 gresume 16 ) 255 )
        ( vec_set [u] buf + prim 3 # u & ( __lshr64 gresume 24 ) 255 )
        ( __jit_resume_entry buf npin spcell )
        ( __jit_reload_pins buf pins ) ( __jit_reload_xpins buf xpins )  // the dst slot may be pinned; memory is fresher
        ^ v
    } {}
    ? == op 169 {  // BRTBL: clamp the index, jump through an absolute table; each row = slot moves + jmp
        ? != raxslot b { ( __jit_ldrax_m buf pmap xmap cvals b ) } {}
        ( __jit_b buf 137 ) ( __jit_b buf 192 )  // mov eax,eax (u32)
        ( __jit_b buf 185 ) ( __jit_d buf c )  // mov ecx, n (default row index)
        ( __jit_b buf 72 ) ( __jit_b buf 57 ) ( __jit_b buf 200 )  // cmp rax,rcx
        ( __jit_b buf 72 ) ( __jit_b buf 15 ) ( __jit_b buf 67 ) ( __jit_b buf 193 )  // cmovae rax,rcx
        ( __jit_b buf 72 ) ( __jit_b buf 141 ) ( __jit_b buf 13 ) ( __jit_d buf 3 )  // lea rcx,[rip+3] → the table below
        ( __jit_b buf 255 ) ( __jit_b buf 36 ) ( __jit_b buf 193 )  // jmp [rcx+rax*8]
        : i tabo ( vec_len [u] buf )
        : i rows + c 1
        : ~ i rw 0
        ~ < rw rows { ( __jit_q buf 0 ) = rw + rw 1 }
        = rw 0
        ~ < rw rows {
            ( vec_push [i] pta_off + tabo * rw 8 )
            ( vec_push [i] pta_stub ( vec_len [u] buf ) )
            : i rowb + a * rw 4
            : i stgt ?? ( vec_get [i] auxv rowb ) { T x → x F → 0 }
            : i mdst ?? ( vec_get [i] auxv + rowb 1 ) { T x → x F → 0 }
            : i msrc ?? ( vec_get [i] auxv + rowb 2 ) { T x → x F → 0 }
            : i mn ?? ( vec_get [i] auxv + rowb 3 ) { T x → x F → 0 }
            : ~ i mk 0
            ~ < mk mn { ( __jit_ldrax_m buf pmap xmap cvals + msrc mk ) ( __jit_strax_m buf pmap xmap cvals + mdst mk ) = mk + mk 1 }
            ( __jit_jmp buf pat_at pat_rec 233 / stgt 6 )
            = rw + rw 1
        }
        ^ v
    } {}
    ? == op 171 {  // FCB bridge: hand the record's operands to the driver (status 7)
        // ctx[4]=fcode(a) ctx[5]=idx-imm(b) ctx[6]=resume ctx[7]=pops<<33|push<<32|srcbase(c,d)
        ( __jit_sync_pins buf pins ) ( __jit_sync_xpins buf xpins )  // the driver reads the operand slots from memory
        ( __jit_b buf 199 ) ( __jit_b buf 71 ) ( __jit_b buf 32 ) ( __jit_d buf a )  // mov [rdi+32], a
        ( __jit_b buf 199 ) ( __jit_b buf 71 ) ( __jit_b buf 40 ) ( __jit_d buf b )  // mov [rdi+40], b
        ( __jit_b buf 199 ) ( __jit_b buf 71 ) ( __jit_b buf 56 ) ( __jit_d buf c )  // mov [rdi+56], srcbase
        ( __jit_b buf 199 ) ( __jit_b buf 71 ) ( __jit_b buf 60 ) ( __jit_d buf d )  // mov [rdi+60], pops<<1|push
        ( __jit_b buf 199 ) ( __jit_b buf 71 ) ( __jit_b buf 48 ) ( __jit_d buf 0 )  // mov [rdi+48], resume (patched)
        : i fimm_at - ( vec_len [u] buf ) 4
        ( __jit_b buf 72 ) ( __jit_b buf 137 ) ( __jit_b buf 31 )  // mov [rdi],rbx — the handler reads the frame base here
        : i prim ( __jit_pause buf chaincell pta_off pta_stub )
        ( __jit_b buf 184 ) ( __jit_d buf 19 )  // mov eax,19 (FCB call-out)
        ( __jit_retseq buf npin )
        : i fresume ( vec_len [u] buf )
        ( vec_set [u] buf fimm_at # u & fresume 255 )
        ( vec_set [u] buf + fimm_at 1 # u & ( __lshr64 fresume 8 ) 255 )
        ( vec_set [u] buf + fimm_at 2 # u & ( __lshr64 fresume 16 ) 255 )
        ( vec_set [u] buf + fimm_at 3 # u & ( __lshr64 fresume 24 ) 255 )
        ( vec_set [u] buf prim # u & fresume 255 )
        ( vec_set [u] buf + prim 1 # u & ( __lshr64 fresume 8 ) 255 )
        ( vec_set [u] buf + prim 2 # u & ( __lshr64 fresume 16 ) 255 )
        ( vec_set [u] buf + prim 3 # u & ( __lshr64 fresume 24 ) 255 )
        ( __jit_resume_entry buf npin spcell )
        ( __jit_reload_pins buf pins ) ( __jit_reload_xpins buf xpins )  // the dst slot may be pinned; memory is fresher
        ^ v
    } {}
    ? == op 170 {  // CALLIND: hand the runtime-resolved index to the driver
        // ctx[4]=table-index value (from slot c) ctx[5]=argbase(b) ctx[6]=resume ctx[7]=typeidx(a); return 5
        ( __jit_sync_pins buf pins ) ( __jit_sync_xpins buf xpins )  // the callee's arguments live in this frame's memory
        ? != raxslot c { ( __jit_ldrax_m buf pmap xmap cvals c ) } {}
        ( __jit_b buf 137 ) ( __jit_b buf 192 )  // mov eax,eax — keep ctx[4]'s upper bytes zero (CALL writes only a dword there)
        ( __jit_b buf 72 ) ( __jit_b buf 137 ) ( __jit_b buf 71 ) ( __jit_b buf 32 )  // mov [rdi+32], rax
        ( __jit_b buf 199 ) ( __jit_b buf 71 ) ( __jit_b buf 40 ) ( __jit_d buf b )  // mov [rdi+40], argbase
        ( __jit_b buf 199 ) ( __jit_b buf 71 ) ( __jit_b buf 48 ) ( __jit_d buf 0 )  // mov [rdi+48], resume (patched)
        : i imm_at - ( vec_len [u] buf ) 4
        ( __jit_b buf 199 ) ( __jit_b buf 71 ) ( __jit_b buf 56 ) ( __jit_d buf a )  // mov [rdi+56], typeidx
        ( __jit_b buf 72 ) ( __jit_b buf 137 ) ( __jit_b buf 31 )  // mov [rdi],rbx — the handler reads the frame base here
        : i prim ( __jit_pause buf chaincell pta_off pta_stub )
        ( __jit_b buf 184 ) ( __jit_d buf 17 )  // mov eax,17 (indirect call-out)
        ( __jit_retseq buf npin )
        : i resume ( vec_len [u] buf )
        ( vec_set [u] buf imm_at # u & resume 255 )
        ( vec_set [u] buf + imm_at 1 # u & ( __lshr64 resume 8 ) 255 )
        ( vec_set [u] buf + imm_at 2 # u & ( __lshr64 resume 16 ) 255 )
        ( vec_set [u] buf + imm_at 3 # u & ( __lshr64 resume 24 ) 255 )
        ( vec_set [u] buf prim # u & resume 255 )
        ( vec_set [u] buf + prim 1 # u & ( __lshr64 resume 8 ) 255 )
        ( vec_set [u] buf + prim 2 # u & ( __lshr64 resume 16 ) 255 )
        ( vec_set [u] buf + prim 3 # u & ( __lshr64 resume 24 ) 255 )
        // resume point: reload the frame/memory/globals registers
        ( __jit_resume_entry buf npin spcell )
        ( __jit_reload_pins buf pins ) ( __jit_reload_xpins buf xpins )  // result slots were written in memory
        ^ v
    } {}
    ? | == op 207 == op 208 {  // LOADSHLADD64/32: dst = mem[(base + (x<<k)) w32 + off]; b=base d=x w5=kslot
        : i kc2 ( __jit_pr pmap w5 )
        ? != kc2 -2 { ( __jit_ldrcx_m buf pmap xmap cvals w5 ) } {}  // k
        : i ps ( __jit_pr pmap d )
        ? >= ps 0 { ( __jit_opeax_pr buf 139 ps ) } {  // mov eax,r1Xd
            ( __jit_b buf 139 ) ( __jit_b buf 131 ) ( __jit_d buf * d 8 )  // mov eax,dword[rbx+d] (low 32 of x)
        }
        ? == kc2 -2 { ( __jit_b buf 193 ) ( __jit_b buf 224 ) ( __jit_b buf & ( __jit_cv cvals w5 ) 31 ) } {  // shl eax,imm8
            ( __jit_b buf 211 ) ( __jit_b buf 224 ) }  // shl eax,cl
        ( __jit_movslq buf )  // __w32
        : i pb ( __jit_pr pmap b )
        ? >= pb 0 { ( __jit_oprax_pr buf 3 pb ) } {  // add rax,r1X
            ( __jit_b buf 72 ) ( __jit_b buf 3 ) ( __jit_b buf 131 ) ( __jit_d buf * b 8 )  // add rax,[rbx+base]
        }
        ( __jit_bc buf pat_at pat_rec trap_rec c ? == op 207 8 4 guard )
        ? == op 207 { ( __jit_mem buf 0 0 139 0 c ) } { ( __jit_mem buf 0 0 99 0 c ) }  // mov rax,[mem] / movsxd rax,dword[mem]
        ( __jit_strax_m buf pmap xmap cvals a ) ^ v
    } {}
    ( __jit_alu buf pmap xmap cvals op a b c d raxslot )
}

// Lazy tier-6 state: the frame slab, its top-of-stack cell and the
// direct-call table, sized once per Interp. 4 MiB of slots; a frame that
// does not fit returns status 8 and the driver bridges to the
// interpreter, so deep recursion degrades instead of trapping.
@ __jit_state_init * Interp it * Module m → v {
    ? != 0 . it jit_slab { ^ v } {}
    : i bytes 16777216
    = . it jit_slab # i ( nurl_zalloc bytes )
    = . it jit_slab_end + . it jit_slab bytes
    // anchor block, held in r8 by the emitted code: [sp, slab end,
    // direct-entry table]; sized from the MODULE — pfuncs grows lazily
    // and may still be short
    : i nf ( vec_len [s] . m funcs )
    = . it jit_spcell # i ( nurl_zalloc + 16 * nf 8 )
    : *i spc # *i . it jit_spcell
    = . spc 0 . it jit_slab
    = . spc 1 . it jit_slab_end
    // one 32-byte pause entry per (at worst one-slot) frame
    = . it jit_chain # i ( nurl_zalloc * bytes 4 )
    = . it jit_chain_cell # i ( nurl_zalloc 8 )
    : *i chc # *i . it jit_chain_cell
    = . chc 0 . it jit_chain
}

// After a record is emitted, which slot does rax hold (-1 = none)?
// Drives the one-register load-elision cache; must match the emitters.
// After a record is emitted, which slot's value does xmm0 hold (-1 =
// none)? The f64 twin of __jit_newrax: every f64 writer ends with a
// movsd to its dst slot, so xmm0 = dst; a native call or any call-out
// clobbers xmm0 (caller-saved); anything that writes the cached slot
// through rax makes the cache stale.
@ __jit_newxmm i op i a i b i prev → i {
    ? | | & >= op 39 <= op 42 & >= op 194 <= op 196 | & >= op 198 <= op 201 == op 131 { ^ a } {}
    ? == op 197 { ^ -1 } {}  // stored a sum to memory; no slot holds it
    ? | | | == op 50 == op 210 | == op 170 == op 171 | == op 163 == op 169 { ^ -1 } {}  // calls / call-outs / br_table
    ? | == op 55 == op 172 { ^ -1 } {}  // terminal
    ? & | == op 38 == op 177 == b prev { ^ -1 } {}  // ADDBRIFC writes b
    ? == a prev { ^ -1 } {}  // this record wrote the cached slot
    ^ prev
}

@ __jit_newrax i op i a i b i prev → i {
    ? | | | == op 55 == op 172 | == op 50 == op 210 == op 170 { ^ -1 } {}  // terminal / call-out clobbers
    ? == op 163 { ^ -1 } {}  // memory.grow call-out
    ? | == op 169 == op 171 { ^ -1 } {}  // br_table dispatch / FCB call-out
    ? & >= op 194 <= op 197 { ^ -1 } {}  // membc leaves rax = host address
    ? >= ( __jit_memkind op ) 0 { ^ ? == 0 & ( __jit_memkind op ) 1 a -1 } {}  // load → dst; store leaves an address
    ? | & >= op 39 <= op 42 | & >= op 198 <= op 201 == op 131 { ^ ? == a prev -1 prev } {}  // xmm-only writers: rax untouched, dst may go stale
    ? == op 53 { ^ b } {}  // global.set: rax = src
    ? | | == op 48 == op 54 == op 45 { ^ b } {}  // IFZ/BRIF cond, BRIFC lhs
    ? | == op 38 == op 177 { ^ b } {}  // ADDBRIFC: rax = stored sum
    ? == op 49 { ^ prev } {}  // BR: untouched
    ^ a  // everything else stores its result through rax
}

@ __jit_sc_add ( Vec i ) sc i s i wt → v {
    : i n ( vec_len [i] sc )
    ? & >= s 0 < s n { ( vec_set [i] sc s + ?? ( vec_get [i] sc s ) { T x → x F → 0 } wt ) } {}
}

@ __jit_hd_add ( Vec i ) hd i s → v {
    : i n ( vec_len [i] hd )
    ? & >= s 0 < s n { ( vec_set [i] hd s 1 ) } {}
}

@ __jit_ex_add ( Vec i ) ex i s i wt → v {
    : i n ( vec_len [i] ex )
    ? & >= s 0 < s n { ( vec_set [i] ex s + ?? ( vec_get [i] ex s ) { T x → x F → 0 } wt ) } {}
}

// Score one record's integer-path slot accesses into sc, mark its
// xmm-path operands in ex (those slots live behind xmm0 and cannot also
// live in an integer register), and return the record's contribution to
// the call weight — every call site costs each pinned register one sync
// and one reload. The arms mirror the emitters' operand roles exactly;
// an op scored wrong here costs performance, never correctness.
@ __jit_pin_scan1 ( Vec i ) sc ( Vec i ) ex ( Vec i ) hd ( Vec i ) auxv i op i a i b i c i d i w5 i wt → i {
    ? == op 51 { ( __jit_sc_add sc a wt ) ^ 0 } {}  // CONST
    ? == op 47 { ( __jit_sc_add sc a wt ) ( __jit_sc_add sc b wt ) ^ 0 } {}  // MOV
    ? == op 55 {  // RET reads slots a..a+b-1
        : ~ i k 0
        ~ < k b { ( __jit_sc_add sc + a k wt ) = k + k 1 }
        ^ 0
    } {}
    ? == op 172 { ^ 0 } {}  // unreachable
    ? & >= op 39 <= op 42 { ( __jit_ex_add ex a wt ) ( __jit_ex_add ex b wt ) ( __jit_ex_add ex c wt ) ^ 0 } {}  // f64 alu
    ? == op 52 { ( __jit_sc_add sc a wt ) ^ 0 } {}  // global.get (b is a global index)
    ? == op 53 { ( __jit_sc_add sc b wt ) ^ 0 } {}  // global.set (a is a global index)
    ? | == op 50 == op 210 { ^ wt } {}  // CALL / CALLIMP: args/results go through memory
    : i mk ( __jit_memkind op )
    ? >= mk 0 {
        ? == 0 & mk 1 { ( __jit_sc_add sc a wt ) ( __jit_sc_add sc b wt ) ( __jit_sc_add sc d wt ) ( __jit_hd_add hd d ) } {  // load: dst base index (index d is a fused operand)
            ( __jit_sc_add sc a wt ) ( __jit_sc_add sc b wt )  // store: addr value
        }
        ^ 0
    } {}
    ? | == op 43 == op 44 { ( __jit_sc_add sc a wt ) ( __jit_sc_add sc b wt ) ^ 0 } {}  // eqz
    ? & >= op 56 <= op 75 { ( __jit_sc_add sc a wt ) ( __jit_sc_add sc b wt ) ( __jit_sc_add sc c wt ) ^ 0 } {}  // compares
    ? == op 49 { ^ 0 } {}  // BR
    ? | == op 48 == op 54 { ( __jit_sc_add sc b wt ) ^ 0 } {}  // IFZ / BRIF
    ? == op 45 { ( __jit_sc_add sc b wt ) ( __jit_sc_add sc c wt ) ^ 0 } {}  // BRIFC
    ? | == op 38 == op 177 {  // ADDBRIFC: dst=b s1=c s2=d rhs in w5; d and rhs are fused operands
        ( __jit_sc_add sc b wt ) ( __jit_sc_add sc c wt ) ( __jit_sc_add sc d wt ) ( __jit_sc_add sc & w5 2097151 wt )
        ( __jit_hd_add hd d ) ( __jit_hd_add hd & w5 2097151 ) ^ 0
    } {}
    ? | == op 36 == op 37 { ( __jit_sc_add sc a wt ) ( __jit_sc_add sc b wt ) ( __jit_hd_add hd b ) ^ 0 } {}  // wrap / extend_u: 32-bit read of b
    ? == op 46 { ( __jit_sc_add sc a wt ) ( __jit_sc_add sc b wt ) ( __jit_sc_add sc c wt ) ( __jit_sc_add sc d wt ) ^ 0 } {}  // SEL
    ? | == op 211 == op 212 { ( __jit_sc_add sc a wt ) ( __jit_sc_add sc b wt ) ( __jit_sc_add sc d wt ) ^ 0 } {}  // LOADMUL/ADDI64
    ? | | == op 194 == op 195 == op 196 { ( __jit_sc_add sc b wt ) ( __jit_ex_add ex a wt ) ( __jit_ex_add ex d wt ) ^ 0 } {}  // LOADxF64: int base, f64 dst/x
    ? == op 197 { ( __jit_sc_add sc a wt ) ( __jit_ex_add ex b wt ) ( __jit_ex_add ex c wt ) ^ 0 } {}  // ADDSTOREF64: int addr, f64 sources
    ? & >= op 198 <= op 201 { ( __jit_ex_add ex a wt ) ( __jit_ex_add ex b wt ) ( __jit_ex_add ex c wt ) ( __jit_ex_add ex d wt ) ^ 0 } {}  // fused f64
    ? == op 131 { ( __jit_ex_add ex a wt ) ( __jit_ex_add ex b wt ) ^ 0 } {}  // f64.sqrt
    ? | == op 125 == op 126 { ( __jit_ex_add ex a wt ) ( __jit_ex_add ex b wt ) ^ 0 } {}  // f64.abs/neg: served via movq when pinned
    ? == op 93 { ( __jit_sc_add sc a wt ) ( __jit_sc_add sc b wt ) ( __jit_hd_add hd b ) ^ 0 } {}  // i32.clz: 32-bit read
    ? == op 99 { ( __jit_sc_add sc a wt ) ( __jit_sc_add sc b wt ) ( __jit_sc_add sc c wt ) ( __jit_hd_add hd b ) ( __jit_hd_add hd c ) ^ 0 } {}  // i32.rem_u: 32-bit reads
    ? == op 108 { ( __jit_sc_add sc a wt ) ( __jit_sc_add sc b wt ) ( __jit_sc_add sc c wt ) ^ 0 } {}  // i64.rem_u
    ? | | & >= op 96 <= op 98 == op 105 | == op 106 == op 107 { ( __jit_sc_add sc a wt ) ( __jit_sc_add sc b wt ) ( __jit_sc_add sc c wt ) ^ 0 } {}  // div family (i32 forms consume via full loads)
    ? | == op 205 == op 206 { ( __jit_sc_add sc a wt ) ( __jit_sc_add sc b wt ) ( __jit_sc_add sc d wt ) ( __jit_hd_add hd b ) ^ 0 } {}  // LOADSHL: 32-bit read of x
    ? | == op 207 == op 208 { ( __jit_sc_add sc a wt ) ( __jit_sc_add sc b wt ) ( __jit_sc_add sc d wt ) ( __jit_sc_add sc w5 wt ) ( __jit_hd_add hd b ) ( __jit_hd_add hd d ) ^ 0 } {}  // LOADSHLADD: fused base + 32-bit x
    ? & >= op 153 <= op 156 { ( __jit_sc_add sc a wt ) ( __jit_sc_add sc b wt ) ^ 0 } {}  // reinterprets: raw 64-bit copies
    ? & >= op 157 <= op 161 { ( __jit_sc_add sc a wt ) ( __jit_sc_add sc b wt ) ( __jit_hd_add hd b ) ^ 0 } {}  // extendN_s: partial-width read of b
    ? == op 162 { ( __jit_sc_add sc a wt ) ^ 0 } {}  // memory.size
    ? == op 163 { ( __jit_sc_add sc b wt ) ^ wt } {}  // memory.grow: call-out
    ? == op 169 {  // br_table: index + each row's slot moves
        ( __jit_sc_add sc b wt )
        : ~ i rw 0
        ~ < rw + c 1 {
            : i rowb + a * rw 4
            : i mdst ?? ( vec_get [i] auxv + rowb 1 ) { T x → x F → 0 }
            : i msrc ?? ( vec_get [i] auxv + rowb 2 ) { T x → x F → 0 }
            : i mn ?? ( vec_get [i] auxv + rowb 3 ) { T x → x F → 0 }
            : ~ i mk2 0
            ~ < mk2 mn { ( __jit_sc_add sc + msrc mk2 wt ) ( __jit_sc_add sc + mdst mk2 wt ) = mk2 + mk2 1 }
            = rw + rw 1
        }
        ^ 0
    } {}
    ? == op 170 { ( __jit_sc_add sc c wt ) ^ wt } {}  // call_indirect: call-out
    ? == op 171 { ^ wt } {}  // FCB bridge: call-out, operands via memory
    ? | | & >= op 13 <= op 17 | == op 22 == op 30 == op 33 {  // fused i64 pairs
        ( __jit_sc_add sc a wt ) ( __jit_sc_add sc b wt ) ( __jit_sc_add sc c wt ) ( __jit_sc_add sc d wt ) ^ 0
    } {}
    ( __jit_sc_add sc a wt ) ( __jit_sc_add sc b wt ) ( __jit_sc_add sc c wt )  // plain ALU
    ^ 0
}

// Which slots earn a register? Static access counts weighted by loop
// depth (a record inside a backward-branch span counts 8× per nesting
// level, capped), against the protocol cost of syncing around every
// call site. At most four integer winners (r12 first) in the returned
// vec; slots whose every access is an xmm-path operand compete for
// xmm8..xmm15 instead and land in `xpins`. NURL_NWASM_PIN=0 turns the
// whole tier off (A/B and debugging).
@ __jit_pin_select * PFunc pf ( Vec i ) xpins → ( Vec i ) {
    : i kvbase . pf nlocals
    : i kvn ( vec_len [i] . pf kv )
    : ( Vec i ) pins ( vec_new [i] )
    ? == 0 g_pin { ^ pins } {}
    : i n . pf count
    : i ns . pf nslots
    ? | | <= n 0 > n 2048 > ns 65536 { ^ pins } {}  // keep the weighting pass linear-ish
    : ( Vec i ) code . pf code
    : ( Vec i ) w ( vec_new [i] )
    : ~ i k0 0
    ~ < k0 n { ( vec_push [i] w 1 ) = k0 + k0 1 }
    : ~ i rb 0
    ~ < rb n {
        : i opb ?? ( vec_get [i] code * rb 6 ) { T x → x F → 0 }
        ? | | | | == opb 48 == opb 49 == opb 54 == opb 45 | == opb 38 == opb 177 {
            : i tb / ?? ( vec_get [i] code + * rb 6 1 ) { T x → x F → 0 } 6
            ? & >= tb 0 <= tb rb {  // backward branch: everything in the span is a loop body
                : ~ i kk tb
                ~ <= kk rb {
                    : i cw ?? ( vec_get [i] w kk ) { T x → x F → 1 }
                    ? < cw 4096 { ( vec_set [i] w kk * cw 8 ) } {}
                    = kk + kk 1
                }
            } {}
        } {}
        = rb + rb 1
    }
    : ( Vec i ) sc ( vec_new [i] )
    : ( Vec i ) ex ( vec_new [i] )
    : ( Vec i ) hd ( vec_new [i] )
    : ~ i k1 0
    ~ < k1 ns { ( vec_push [i] sc 0 ) ( vec_push [i] ex 0 ) ( vec_push [i] hd 0 ) = k1 + k1 1 }
    : ( Vec i ) auxv . pf aux
    : ~ i callw 0
    : ~ i r 0
    ~ < r n {
        : i base * r 6
        : i op ?? ( vec_get [i] code base ) { T x → x F → 0 }
        : i a ?? ( vec_get [i] code + base 1 ) { T x → x F → 0 }
        : i b ?? ( vec_get [i] code + base 2 ) { T x → x F → 0 }
        : i c ?? ( vec_get [i] code + base 3 ) { T x → x F → 0 }
        : i d ?? ( vec_get [i] code + base 4 ) { T x → x F → 0 }
        : i w5 ?? ( vec_get [i] code + base 5 ) { T x → x F → 0 }
        : i wt ?? ( vec_get [i] w r ) { T x → x F → 1 }
        = callw + callw ( __jit_pin_scan1 sc ex hd auxv op a b c d w5 wt )
        = r + r 1
    }
    // Constants the code stream can carry as immediates never earn a
    // register; a constant too wide for imm32 competes like any slot.
    : ~ i cz 0
    ~ < cz kvn {
        : i czs + kvbase cz
        : i czv ?? ( vec_get [i] . pf kv cz ) { T x → x F → 0 }
        : ~ i imm 0
        ? & >= czv 0 <= czv 4294967295 { = imm 1 } {}
        ? != 0 ( __jit_imm32 czv ) { = imm 1 } {}
        ? & < czs ns != 0 imm { ( vec_set [i] sc czs 0 ) ( vec_set [i] ex czs 0 ) } {}
        = cz + cz 1
    }
    // Break-even: each pinned register pays a sync and a reload at every
    // call site, and when the calls recurse, every call is also a fresh
    // entry paying the push/reload/pop trio — so the call weight carries
    // the entry cost too (measured: fib regressed 4% at 2*callw+6).
    : i thr + * 4 callw 6
    : ~ i pk 0
    ~ < pk 4 {
        : ~ i best -1
        : ~ i bsc thr
        : ~ i si 0
        ~ < si ns {
            : i sv ?? ( vec_get [i] sc si ) { T x → x F → 0 }
            : i ev ?? ( vec_get [i] ex si ) { T x → x F → 1 }
            ? & > sv bsc == 0 ev { = best si = bsc sv } {}
            = si + si 1
        }
        ? < best 0 { = pk 4 } {
            ( vec_push [i] pins best )
            ( vec_set [i] sc best 0 )
            = pk + pk 1
        }
    }
    // The xmm winners: xmm-dominant slots never read at a fused or
    // partial-width integer site (plain integer accesses go through
    // movq; a slot picked above had ex = 0, so no overlap with pins).
    // Slightly cheaper protocol — caller-saved, so no push/pop, entry is
    // one reload — hence the smaller constant.
    : i xthr + * 4 callw 4
    : ~ i xk 0
    ~ < xk 8 {  // xmm8..xmm15 — all caller-saved, none used elsewhere
        : ~ i xbest -1
        // the fifth register on are luxury seats: each one still costs a
        // sync+reload at every call site, so they must earn double
        : ~ i xbsc ? < xk 4 xthr + xthr xthr
        : ~ i xi 0
        ~ < xi ns {
            : i xev ?? ( vec_get [i] ex xi ) { T x → x F → 0 }
            : i xsv ?? ( vec_get [i] sc xi ) { T x → x F → 1 }
            : i xhv ?? ( vec_get [i] hd xi ) { T x → x F → 1 }
            // xmm-dominant and never read at a fused/partial-width site:
            // plain integer accesses of an xmm-pinned slot go through movq.
            ? & & > xev xbsc > xev xsv == 0 xhv { = xbest xi = xbsc xev } {}
            = xi + xi 1
        }
        ? < xbest 0 { = xk 8 } {
            ( vec_push [i] xpins xbest )
            ( vec_set [i] ex xbest 0 )
            = xk + xk 1
        }
    }
    ^ pins
}

@ __jit_try * Interp it * Module m * PFunc pf → v {
    ? != # i . pf jit 0 { ^ v } {}  // already tried (handle or -1)
    ? == 0 ( __jit_ok pf ) { = . pf jit # s -1 ^ v } {}
    ( __jit_state_init it m )
    // Tier 7: the hottest slots ride in r12.. (and pure-f64 slots in
    // xmm8..) for the whole function.
    : ( Vec i ) xpins ( vec_new [i] )
    : ( Vec i ) pins ( __jit_pin_select pf xpins )
    : i npin ( vec_len [i] pins )
    : i nxpin ( vec_len [i] xpins )
    : ( Vec i ) pmap ( vec_new [i] )
    : ( Vec i ) xmap ( vec_new [i] )
    : i nsl . pf nslots
    : ~ i pmk 0
    ~ < pmk nsl { ( vec_push [i] pmap -1 ) ( vec_push [i] xmap -1 ) = pmk + pmk 1 }
    = pmk 0
    ~ < pmk npin { ( vec_set [i] pmap ?? ( vec_get [i] pins pmk ) { T x → x F → 0 } + 4 pmk ) = pmk + pmk 1 }
    = pmk 0
    ~ < pmk nxpin { ( vec_set [i] xmap ?? ( vec_get [i] xpins pmk ) { T x → x F → 0 } pmk ) = pmk + pmk 1 }
    // Guard-page mode: bounds checks stay out of the emitted code, and the
    // sealed page is registered with the fault-to-trap handler below. The
    // registry pre-check keeps a full table from producing a function whose
    // faults nobody converts — such a function keeps its explicit checks.
    : i guard ? & != 0 . it mem_raw != 0 ( nurl_guard_code_room ) 1 0
    : i spcell . it jit_spcell  // anchor block, held in r8: [sp, slab end, ftab..]
    : i chaincell . it jit_chain_cell
    : i nimp . m num_import_funcs
    : i np . pf nparams
    : i nl . pf nlocals
    : i knum ( vec_len [i] . pf kv )
    : i kvdata # i ( vec_data [i] . pf kv )
    // Constant slots become immediates at their use sites: mark them in
    // pmap (-2) and keep their values at hand. The prologue still writes
    // the pool to memory — the f64 templates and any site without an
    // immediate form read the slot as before.
    : ( Vec i ) cvals ( vec_new [i] )
    : ~ i cvk 0
    ~ < cvk nsl { ( vec_push [i] cvals 0 ) = cvk + cvk 1 }
    = cvk 0
    ~ < cvk knum {
        : i cslot + . pf nlocals cvk
        ? & < cslot nsl == -1 ( __jit_pr pmap cslot ) {
            ( vec_set [i] cvals cslot ?? ( vec_get [i] . pf kv cvk ) { T x → x F → 0 } )
            ( vec_set [i] pmap cslot -2 )
        } {}
        = cvk + cvk 1
    }
    // pool slots whose every use is an immediate skip their per-call write
    : ( Vec i ) kvwr ( __jit_kv_writes pf pmap xmap cvals )
    : ( Vec u ) buf ( vec_new [u] )
    : ( Vec i ) code . pf code
    : i n . pf count
    : i sb . pf sbase
    : ( Vec i ) cctab ( __jit_cctab )
    : ( Vec i ) lab ( vec_new [i] )  // record index → code offset
    : ( Vec i ) pat_at ( vec_new [i] )  // rel32 site → …
    : ( Vec i ) pat_rec ( vec_new [i] )  // … target record
    : ( Vec i ) pta_off ( vec_new [i] )  // jump-table entry byte offset → …
    : ( Vec i ) pta_stub ( vec_new [i] )  // … stub code offset (absolute address patched post-copy)
    : ( Vec i ) auxe . pf aux  // br_table rows live here
    // Prologue v2 (self-allocating entry): rdi = context, rsi = the
    // caller's argument slots. The frame lives on the per-Interp slab —
    // bump-allocated here, freed on every exit — so a direct JIT-to-JIT
    // call is one native `call` with no driver round trip. rbx = frame
    // base (also written to ctx[0] for the resume path); the args pointer
    // is kept at [rsp] for the RET result copy. Pinned registers are
    // callee-saved: pushed here (and at every resume entry), popped on
    // every exit — the extra pushes sit below [rsp]'s args pointer.
    // Driver entry (page base): establish the invariant registers —
    // r8 = the anchor block, r11/r10/r9 = memory base/bytes/globals.
    // A direct JIT-to-JIT call inherits all four and enters at the
    // fixed 22-byte offset just past them (the ftab publishers add it).
    ( __jit_b buf 73 ) ( __jit_b buf 184 ) ( __jit_q buf spcell )  // movabs r8, anchor
    ( __jit_b buf 76 ) ( __jit_b buf 139 ) ( __jit_b buf 95 ) ( __jit_b buf 8 )  // mov r11,[rdi+8]
    ( __jit_b buf 76 ) ( __jit_b buf 139 ) ( __jit_b buf 87 ) ( __jit_b buf 16 )  // mov r10,[rdi+16]
    ( __jit_b buf 76 ) ( __jit_b buf 139 ) ( __jit_b buf 79 ) ( __jit_b buf 24 )  // mov r9,[rdi+24]
    // Direct entry (offset 22):
    ( __jit_push_pins buf npin )
    ( __jit_b buf 83 )  // push rbx
    ( __jit_b buf 86 )  // push rsi (args pointer, read back at RET)
    ( __jit_b buf 73 ) ( __jit_b buf 139 ) ( __jit_b buf 24 )  // mov rbx,[r8] — frame base
    ( __jit_b buf 72 ) ( __jit_b buf 141 ) ( __jit_b buf 139 ) ( __jit_d buf * . pf nslots 8 )  // lea rcx,[rbx+nslots*8]
    ( __jit_b buf 73 ) ( __jit_b buf 59 ) ( __jit_b buf 72 ) ( __jit_b buf 8 )  // cmp rcx,[r8+8] — slab end
    ( __jit_jmp buf pat_at pat_rec 135 + n 3 )  // ja overflow stub (status 8, nothing allocated)
    ( __jit_b buf 73 ) ( __jit_b buf 137 ) ( __jit_b buf 8 )  // mov [r8],rcx — bump
    // Small counts unroll to plain moves — `rep` has a fixed start-up
    // cost that dwarfs a couple of copies, and this runs per call.
    ? > np 0 {
        ? <= np 4 {
            : ~ i pk 0
            ~ < pk np {
                ( __jit_b buf 72 ) ( __jit_b buf 139 ) ( __jit_b buf 134 ) ( __jit_d buf * pk 8 )  // mov rax,[rsi+k*8]
                ( __jit_strax buf pk )
                = pk + pk 1
            }
        } {
            ( __jit_b buf 87 )  // push rdi
            ( __jit_b buf 72 ) ( __jit_b buf 137 ) ( __jit_b buf 223 )  // mov rdi,rbx
            ( __jit_b buf 185 ) ( __jit_d buf np )  // mov ecx, nparams
            ( __jit_b buf 243 ) ( __jit_b buf 72 ) ( __jit_b buf 165 )  // rep movsq — params from [rsi]
            ( __jit_b buf 95 )  // pop rdi
        }
    } {}
    ? > nl np {
        ( __jit_b buf 49 ) ( __jit_b buf 192 )  // xor eax,eax
        ? <= - nl np 8 {
            : ~ i zk np
            ~ < zk nl { ( __jit_strax buf zk ) = zk + zk 1 }
        } {
            ( __jit_b buf 87 )  // push rdi
            ( __jit_b buf 72 ) ( __jit_b buf 141 ) ( __jit_b buf 187 ) ( __jit_d buf * np 8 )  // lea rdi,[rbx+np*8]
            ( __jit_b buf 185 ) ( __jit_d buf - nl np )  // mov ecx, nlocals-nparams
            ( __jit_b buf 243 ) ( __jit_b buf 72 ) ( __jit_b buf 171 )  // rep stosq — zero locals
            ( __jit_b buf 95 )  // pop rdi
        }
    } {}
    ? > knum 0 {
        : ~ i kneed 0  // pool slots that still need their memory write
        : ~ i kkc 0
        ~ < kkc knum { ? != 0 ?? ( vec_get [i] kvwr + nl kkc ) { T x → x F → 1 } { = kneed + kneed 1 } {} = kkc + kkc 1 }
        ? <= kneed 8 {  // constants are known here — materialize the needed ones directly
            : ~ i kk 0
            ~ < kk knum {
                ? != 0 ?? ( vec_get [i] kvwr + nl kk ) { T x → x F → 1 } {
                    ( __jit_movrax_imm buf ?? ( vec_get [i] . pf kv kk ) { T x → x F → 0 } )  // rax ← kv[k], shortest form
                    ( __jit_strax buf + nl kk )
                } {}
                = kk + kk 1
            }
        } {
            ( __jit_b buf 87 )  // push rdi
            ( __jit_b buf 72 ) ( __jit_b buf 141 ) ( __jit_b buf 187 ) ( __jit_d buf * nl 8 )  // lea rdi,[rbx+nl*8]
            ( __jit_b buf 72 ) ( __jit_b buf 190 ) ( __jit_q buf kvdata )  // mov rsi, kv data (saved copy at [rsp] serves RET)
            ( __jit_b buf 185 ) ( __jit_d buf knum )  // mov ecx, knum
            ( __jit_b buf 243 ) ( __jit_b buf 72 ) ( __jit_b buf 165 )  // rep movsq — constant pool
            ( __jit_b buf 95 )  // pop rdi
        }
    } {}
    ( __jit_reload_pins buf pins ) ( __jit_reload_xpins buf xpins )  // params/locals/constants are in memory now — lift the pinned ones
    // Branch-target prepass for the rax cache: a record entered by a jump
    // must not trust what fell through in rax. A BACKWARD target (2) is a
    // loop head: its emission is padded to a 16-byte boundary so a loop's
    // speed stops depending on where earlier code happened to end.
    : ( Vec i ) tgt ( vec_new [i] )
    : ~ i tk 0
    ~ < tk n { ( vec_push [i] tgt 0 ) = tk + tk 1 }
    : ~ i trr 0
    ~ < trr n {
        : i top ?? ( vec_get [i] code * trr 6 ) { T x → x F → 0 }
        ? | | | | == top 48 == top 49 == top 54 == top 45 | == top 38 == top 177 {
            : i ta / ?? ( vec_get [i] code + * trr 6 1 ) { T x → x F → 0 } 6
            ? & >= ta 0 < ta n {
                ? & <= ta trr != 2 ?? ( vec_get [i] tgt ta ) { T x → x F → 0 } { ( vec_set [i] tgt ta 2 ) } {
                    ? == 0 ?? ( vec_get [i] tgt ta ) { T x → x F → 0 } { ( vec_set [i] tgt ta 1 ) } {} }
            } {}
        } {}
        ? == top 169 {  // br_table: mark every row target
            : ( Vec i ) auxpp . pf aux
            : i abp ?? ( vec_get [i] code + * trr 6 1 ) { T x → x F → 0 }
            : i rowsp + ?? ( vec_get [i] code + * trr 6 3 ) { T x → x F → 0 } 1
            : ~ i rwp 0
            ~ < rwp rowsp {
                : i tap / ?? ( vec_get [i] auxpp + abp * rwp 4 ) { T x → x F → 0 } 6
                ? & >= tap 0 < tap n {
                    ? & <= tap trr != 2 ?? ( vec_get [i] tgt tap ) { T x → x F → 0 } { ( vec_set [i] tgt tap 2 ) } {
                        ? == 0 ?? ( vec_get [i] tgt tap ) { T x → x F → 0 } { ( vec_set [i] tgt tap 1 ) } {} }
                } {}
                = rwp + rwp 1
            }
        } {}
        = trr + trr 1
    }
    : ~ i raxslot -1
    : ~ i xmmslot -1
    = g_jit_noax 0  // belt: never inherit a stale flag from a previous function
    // cmp+SEL fusion: when a compare's only consumer is the SEL right
    // after it, the select is emitted on the live flags inside the
    // compare's own iteration and the SEL record is skipped here.
    : ~ i selskip 0
    : ~ i fseldst -1
    : ~ i r 0
    ~ < r n {
        ? == 2 ?? ( vec_get [i] tgt r ) { T x → x F → 0 } { ( __jit_align16 buf ) } {}  // loop head: fixed alignment
        ( vec_push [i] lab ( vec_len [u] buf ) )  // this record starts here
        ? > selskip 0 { = selskip - selskip 1 = r + r 1 } {
            ? != 0 ?? ( vec_get [i] tgt r ) { T x → x F → 1 } { = raxslot -1 = xmmslot -1 } {}
            : i base * r 6
            : i op ?? ( vec_get [i] code base ) { T x → x F → 0 }
            : i a ?? ( vec_get [i] code + base 1 ) { T x → x F → 0 }
            : i b ?? ( vec_get [i] code + base 2 ) { T x → x F → 0 }
            : i c ?? ( vec_get [i] code + base 3 ) { T x → x F → 0 }
            : i d ?? ( vec_get [i] code + base 4 ) { T x → x F → 0 }
            : i w5 ?? ( vec_get [i] code + base 5 ) { T x → x F → 0 }
            ? == op 51 { ( __jit_movrax_imm buf b ) ( __jit_strax_m buf pmap xmap cvals a ) } {  // CONST
                ? == op 47 {  // MOV: pin-direct when the dst is pinned, else through rax
                    : i mvp ( __jit_pr pmap a )
                    : ~ i mvd 0
                    ? >= mvp 0 { = mvd ( __jit_pmovsrc buf pmap xmap cvals mvp b raxslot ) } {}
                    ? != 0 mvd { = g_jit_noax 1 } {
                        ? != raxslot b { ( __jit_ldrax_m buf pmap xmap cvals b ) } {} ( __jit_strax_m buf pmap xmap cvals a ) }
                } {  // MOV
                    ? == op 55 {  // RET: results to the caller's args area, free the frame
                        ( __jit_b buf 72 ) ( __jit_b buf 139 ) ( __jit_b buf 52 ) ( __jit_b buf 36 )  // mov rsi,[rsp] — saved args ptr
                        : ~ i k 0
                        ~ < k b {
                            ? | != k 0 != raxslot + a k { ( __jit_ldrax_m buf pmap xmap cvals + a k ) } {}  // first result may already be in rax
                            ( __jit_b buf 72 ) ( __jit_b buf 137 ) ( __jit_b buf 134 ) ( __jit_d buf * k 8 )  // mov [rsi+k*8],rax
                            = k + k 1
                        }
                        ( __jit_b buf 73 ) ( __jit_b buf 137 ) ( __jit_b buf 24 )  // mov [r8],rbx — free frame
                        ( __jit_b buf 49 ) ( __jit_b buf 192 )  // xor eax,eax (rc = 0, no trap)
                        ( __jit_retseq buf npin )
                    } {
                        ? == op 172 {  // unreachable → status 3, via the freeing exit stub
                            ( __jit_b buf 184 ) ( __jit_d buf 3 )
                            ( __jit_jmp buf pat_at pat_rec 233 + n 2 )
                        } {
                            ? & >= op 39 <= op 42 {  // f64 mul/add/sub/div
                                ? != xmmslot b { ( __jit_movsd_ld_m buf xmap b ) } {}
                                ( __jit_sd_op_m buf xmap ? == op 39 89 ? == op 40 88 ? == op 41 92 94 c )
                                ( __jit_movsd_st_m buf xmap a )
                            } {
                                ? == op 52 {  // global.get: rax=[r9+gidx*8]; store dst
                                    ( __jit_b buf 73 ) ( __jit_b buf 139 ) ( __jit_b buf 129 ) ( __jit_d buf * b 8 )
                                    ( __jit_strax_m buf pmap xmap cvals a )
                                } {
                                    ? == op 53 {  // global.set: [r9+gidx*8]=rax(src)
                                        ? != raxslot b { ( __jit_ldrax_m buf pmap xmap cvals b ) } {}
                                        ( __jit_b buf 73 ) ( __jit_b buf 137 ) ( __jit_b buf 129 ) ( __jit_d buf * a 8 )
                                    } {
                                        ? | == op 50 == op 210 {  // CALL / CALLIMP
                                            // Direct path (defined callee only): a compiled, call-out-free
                                            // callee is one native call. ftab[di] is 0 until the callee is
                                            // compiled and proven pure — then the same site goes direct.
                                            // Either path reads the arguments from this frame's memory.
                                            ( __jit_sync_pins buf pins )
                                            ( __jit_sync_xpins buf xpins )
                                            : ~ i jz_at -1
                                            : ~ i je8_at -1
                                            : ~ i skip_at -1
                                            : ~ i jok_at -1
                                            ? & == op 50 >= a nimp {
                                                : i fto + 16 * - a nimp 8  // anchor offset of ftab[di]
                                                ? <= fto 127 { ( __jit_b buf 73 ) ( __jit_b buf 139 ) ( __jit_b buf 64 ) ( __jit_b buf fto ) } {  // mov rax,[r8+fto]
                                                    ( __jit_b buf 73 ) ( __jit_b buf 139 ) ( __jit_b buf 128 ) ( __jit_d buf fto ) }
                                                ( __jit_b buf 72 ) ( __jit_b buf 133 ) ( __jit_b buf 192 )  // test rax,rax
                                                ( __jit_b buf 15 ) ( __jit_b buf 132 ) ( __jit_d buf 0 )  // jz call-out (patched)
                                                = jz_at - ( vec_len [u] buf ) 4
                                                ( __jit_b buf 72 ) ( __jit_b buf 141 ) ( __jit_b buf 179 ) ( __jit_d buf * b 8 )  // lea rsi,[rbx+argbase*8]
                                                ( __jit_b buf 255 ) ( __jit_b buf 208 )  // call rax
                                                ( __jit_b buf 133 ) ( __jit_b buf 192 )  // test eax,eax — the common case first
                                                ( __jit_b buf 15 ) ( __jit_b buf 132 ) ( __jit_d buf 0 )  // jz → after the call-out (patched with skip_at)
                                                = jok_at - ( vec_len [u] buf ) 4
                                                ( __jit_b buf 131 ) ( __jit_b buf 248 ) ( __jit_b buf 8 )  // cmp eax,8
                                                ( __jit_b buf 15 ) ( __jit_b buf 132 ) ( __jit_d buf 0 )  // je call-out (slab full: retry through the driver)
                                                = je8_at - ( vec_len [u] buf ) 4
                                                ( __jit_b buf 131 ) ( __jit_b buf 248 ) ( __jit_b buf 16 )  // cmp eax,16
                                                ( __jit_jmp buf pat_at pat_rec 130 + n 2 )  // jb: terminal — propagate the trap status
                                                // resumable status from the callee: park this frame too and
                                                // hand the same status up; the driver resumes us afterwards.
                                                : i primp ( __jit_pause buf chaincell pta_off pta_stub )
                                                ( __jit_retseq buf npin )  // eax carries the status up
                                                : i prop_resume ( vec_len [u] buf )
                                                ( vec_set [u] buf primp # u & prop_resume 255 )
                                                ( vec_set [u] buf + primp 1 # u & ( __lshr64 prop_resume 8 ) 255 )
                                                ( vec_set [u] buf + primp 2 # u & ( __lshr64 prop_resume 16 ) 255 )
                                                ( vec_set [u] buf + primp 3 # u & ( __lshr64 prop_resume 24 ) 255 )
                                                ( __jit_resume_entry buf npin spcell )
                                                ( __jit_b buf 233 ) ( __jit_d buf 0 )  // jmp past the call-out (patched)
                                                = skip_at - ( vec_len [u] buf ) 4
                                                : i co_here ( vec_len [u] buf )
                                                ( vec_set [u] buf jz_at # u & - co_here + jz_at 4 255 )
                                                ( vec_set [u] buf + jz_at 1 # u & ( __lshr64 - co_here + jz_at 4 8 ) 255 )
                                                ( vec_set [u] buf + jz_at 2 # u & ( __lshr64 - co_here + jz_at 4 16 ) 255 )
                                                ( vec_set [u] buf + jz_at 3 # u & ( __lshr64 - co_here + jz_at 4 24 ) 255 )
                                                ( vec_set [u] buf je8_at # u & - co_here + je8_at 4 255 )
                                                ( vec_set [u] buf + je8_at 1 # u & ( __lshr64 - co_here + je8_at 4 8 ) 255 )
                                                ( vec_set [u] buf + je8_at 2 # u & ( __lshr64 - co_here + je8_at 4 16 ) 255 )
                                                ( vec_set [u] buf + je8_at 3 # u & ( __lshr64 - co_here + je8_at 4 24 ) 255 )
                                            } {}
                                            // ctx[4]=callee(a) ctx[5]=argbase(b) ctx[6]=resume; park; return 16
                                            ( __jit_b buf 199 ) ( __jit_b buf 71 ) ( __jit_b buf 32 ) ( __jit_d buf a )  // mov [rdi+32], fidx
                                            ( __jit_b buf 199 ) ( __jit_b buf 71 ) ( __jit_b buf 40 ) ( __jit_d buf b )  // mov [rdi+40], argbase
                                            ( __jit_b buf 199 ) ( __jit_b buf 71 ) ( __jit_b buf 48 ) ( __jit_d buf 0 )  // mov [rdi+48], resume (patched)
                                            : i imm_at - ( vec_len [u] buf ) 4
                                            ( __jit_b buf 72 ) ( __jit_b buf 137 ) ( __jit_b buf 31 )  // mov [rdi],rbx — the handler reads the frame base here
                                            : i prim2 ( __jit_pause buf chaincell pta_off pta_stub )
                                            ( __jit_b buf 184 ) ( __jit_d buf 16 )  // mov eax,16 (call-out)
                                            ( __jit_retseq buf npin )
                                            : i resume ( vec_len [u] buf )
                                            ( vec_set [u] buf imm_at # u & resume 255 )
                                            ( vec_set [u] buf + imm_at 1 # u & ( __lshr64 resume 8 ) 255 )
                                            ( vec_set [u] buf + imm_at 2 # u & ( __lshr64 resume 16 ) 255 )
                                            ( vec_set [u] buf + imm_at 3 # u & ( __lshr64 resume 24 ) 255 )
                                            ( vec_set [u] buf prim2 # u & resume 255 )
                                            ( vec_set [u] buf + prim2 1 # u & ( __lshr64 resume 8 ) 255 )
                                            ( vec_set [u] buf + prim2 2 # u & ( __lshr64 resume 16 ) 255 )
                                            ( vec_set [u] buf + prim2 3 # u & ( __lshr64 resume 24 ) 255 )
                                            // resume point: rebalance the stack, reload the frame registers
                                            ( __jit_resume_entry buf npin spcell )
                                            ? >= skip_at 0 {  // land the direct path's jumps here
                                                : i after ( vec_len [u] buf )
                                                ( vec_set [u] buf skip_at # u & - after + skip_at 4 255 )
                                                ( vec_set [u] buf + skip_at 1 # u & ( __lshr64 - after + skip_at 4 8 ) 255 )
                                                ( vec_set [u] buf + skip_at 2 # u & ( __lshr64 - after + skip_at 4 16 ) 255 )
                                                ( vec_set [u] buf + skip_at 3 # u & ( __lshr64 - after + skip_at 4 24 ) 255 )
                                                ( vec_set [u] buf jok_at # u & - after + jok_at 4 255 )
                                                ( vec_set [u] buf + jok_at 1 # u & ( __lshr64 - after + jok_at 4 8 ) 255 )
                                                ( vec_set [u] buf + jok_at 2 # u & ( __lshr64 - after + jok_at 4 16 ) 255 )
                                                ( vec_set [u] buf + jok_at 3 # u & ( __lshr64 - after + jok_at 4 24 ) 255 )
                                            } {}
                                            // both paths join here: the callee wrote its results into
                                            // this frame's memory, so memory is the fresher copy.
                                            ( __jit_reload_pins buf pins )
                                            ( __jit_reload_xpins buf xpins )
                                        } {
                                            ? >= ( __jit_memkind op ) 0 {  // load / store, bounds-checked
                                                : i mk ( __jit_memkind op )
                                                : i wid >> mk 2
                                                ? == 0 & mk 1 {  // ── load: a=dst b=base c=off d=index ──
                                                    ? != raxslot b { ( __jit_ldrax_m buf pmap xmap cvals b ) } {}
                                                    : i pix ( __jit_pr pmap d )
                                                    ? >= pix 0 { ( __jit_oprax_pr buf 3 pix ) } {  // add rax,r1X
                                                        : ~ i ixd 0
                                                        ? == pix -2 { = ixd ( __jit_alu_ci64 buf 0 ( __jit_cv cvals d ) ) } {}
                                                        ? == 0 ixd { ( __jit_b buf 72 ) ( __jit_b buf 3 ) ( __jit_b buf 131 ) ( __jit_d buf * d 8 ) } {}  // add rax,[rbx+d]
                                                    }
                                                    ( __jit_bc buf pat_at pat_rec n c wid guard )
                                                    ? == wid 8 { ( __jit_mem buf 0 0 139 0 c ) } {}  // mov rax,[mem]
                                                    ? & == wid 4 == 0 & mk 2 { ( __jit_mem32 buf 0 0 139 0 c ) } {}  // mov eax,[mem] (zero-ext)
                                                    ? & == wid 4 != 0 & mk 2 { ( __jit_mem buf 0 0 99 0 c ) } {}  // movsxd rax,[mem]
                                                    ? & == wid 2 == 0 & mk 2 { ( __jit_mem buf 0 1 183 0 c ) } {}  // movzx rax,word[mem]
                                                    ? & == wid 2 != 0 & mk 2 { ( __jit_mem buf 0 1 191 0 c ) } {}  // movsx rax,word[mem]
                                                    ? & == wid 1 == 0 & mk 2 { ( __jit_mem buf 0 1 182 0 c ) } {}  // movzx rax,byte[mem]
                                                    ? & == wid 1 != 0 & mk 2 { ( __jit_mem buf 0 1 190 0 c ) } {}  // movsx rax,byte[mem]
                                                    ( __jit_strax_m buf pmap xmap cvals a )
                                                } {  // ── store: a=addr b=val c=off ──
                                                    ? != raxslot a { ( __jit_ldrax_m buf pmap xmap cvals a ) } {}
                                                    ( __jit_bc buf pat_at pat_rec n c wid guard )
                                                    ( __jit_ldrcx_m buf pmap xmap cvals b )  // value → rcx
                                                    ? == wid 8 { ( __jit_mem buf 0 0 137 1 c ) } {}  // mov [mem],rcx
                                                    ? == wid 4 { ( __jit_mem32 buf 0 0 137 1 c ) } {}  // mov [mem],ecx
                                                    ? == wid 2 { ( __jit_mem32 buf 102 0 137 1 c ) } {}  // mov [mem],cx
                                                    ? == wid 1 { ( __jit_mem32 buf 0 0 136 1 c ) } {}  // mov [mem],cl
                                                }
                                            } {
                                                ? | == op 43 == op 44 {  // eqz: dst = (src == 0) ? 1 : 0
                                                    ? != raxslot b { ( __jit_ldrax_m buf pmap xmap cvals b ) } {}
                                                    ? == op 43 { ( __jit_b buf 133 ) ( __jit_b buf 192 ) } { ( __jit_b buf 72 ) ( __jit_b buf 133 ) ( __jit_b buf 192 ) }  // test e/rax,e/rax
                                                    ( __jit_b buf 15 ) ( __jit_b buf 148 ) ( __jit_b buf 192 )  // sete al
                                                    ( __jit_b buf 15 ) ( __jit_b buf 182 ) ( __jit_b buf 192 )  // movzx eax,al
                                                    ( __jit_strax_m buf pmap xmap cvals a )
                                                } {
                                                    ? & >= op 56 <= op 75 {  // compare → 0/1 in dst
                                                        ( __jit_cmp buf pmap xmap cvals b c ? < op 66 1 0 raxslot )
                                                        = g_jit_noax 0  // setcc/movzx below write rax whatever the compare did
                                                        ( __jit_b buf 15 ) ( __jit_b buf ?? ( vec_get [i] ( __jit_settab ) % - op 56 10 ) { T x → x F → 148 } ) ( __jit_b buf 192 )  // setcc al
                                                        ( __jit_b buf 15 ) ( __jit_b buf 182 ) ( __jit_b buf 192 )  // movzx eax,al
                                                        ( __jit_strax_m buf pmap xmap cvals a )
                                                        // setcc/movzx/mov leave the flags alone: a SEL right
                                                        // behind us keyed by this result can cmov on them and
                                                        // skip its own load-test round trip.
                                                        = fseldst a  // rax holds the compare's 0/1; pin-direct SELs below leave it there
                                                        : ~ i fr + r 1
                                                        : ~ i fgo 1
                                                        ~ & != 0 fgo < fr n {
                                                            : i sbase * fr 6
                                                            : i sop ?? ( vec_get [i] code sbase ) { T x → x F → 0 }
                                                            : i sa ?? ( vec_get [i] code + sbase 1 ) { T x → x F → 0 }
                                                            : i sb ?? ( vec_get [i] code + sbase 2 ) { T x → x F → 0 }
                                                            : i sc ?? ( vec_get [i] code + sbase 3 ) { T x → x F → 0 }
                                                            : i sd ?? ( vec_get [i] code + sbase 4 ) { T x → x F → 0 }
                                                            : i st2 ?? ( vec_get [i] tgt fr ) { T x → x F → 1 }
                                                            = fgo 0
                                                            ? & & == sop 46 == sd a == 0 st2 {
                                                                : i cc4 & ( __jit_jcc cctab op ) 15
                                                                : i pselp ( __jit_pr pmap sa )
                                                                : ~ i seld 0  // 1 = emitted pin-direct (rax untouched)
                                                                ? >= pselp 0 {  // pin-direct: cmov straight into r_sa (mov/cmov only — flags stay live)
                                                                    ? == sa sc {  // dst == srcF: cmov<cc> r_sa, srcT
                                                                        : i pt ( __jit_pr pmap sb )
                                                                        ? >= pt 0 { ( __jit_b buf 77 ) ( __jit_b buf 15 ) ( __jit_b buf + 64 cc4 ) ( __jit_b buf + 192 + * pselp 8 pt ) } {
                                                                            ( __jit_ldrcx_m buf pmap xmap cvals sb )
                                                                            ( __jit_b buf 76 ) ( __jit_b buf 15 ) ( __jit_b buf + 64 cc4 ) ( __jit_b buf + 193 * pselp 8 ) }  // cmov r_sa,rcx
                                                                        = seld 1
                                                                    } {
                                                                        ? == sa sb {  // dst == srcT: cmov<!cc> r_sa, srcF
                                                                            : i icc ? == % cc4 2 0 + cc4 1 - cc4 1
                                                                            : i pf2 ( __jit_pr pmap sc )
                                                                            ? >= pf2 0 { ( __jit_b buf 77 ) ( __jit_b buf 15 ) ( __jit_b buf + 64 icc ) ( __jit_b buf + 192 + * pselp 8 pf2 ) } {
                                                                                ( __jit_ldrcx_m buf pmap xmap cvals sc )
                                                                                ( __jit_b buf 76 ) ( __jit_b buf 15 ) ( __jit_b buf + 64 icc ) ( __jit_b buf + 193 * pselp 8 ) }
                                                                            = seld 1
                                                                        } {  // dst distinct: mov r_sa ← srcF, then cmov<cc> r_sa ← srcT
                                                                            ? != 0 ( __jit_pmovsrc buf pmap xmap cvals pselp sc -1 ) {
                                                                                : i pt2 ( __jit_pr pmap sb )
                                                                                ? >= pt2 0 { ( __jit_b buf 77 ) ( __jit_b buf 15 ) ( __jit_b buf + 64 cc4 ) ( __jit_b buf + 192 + * pselp 8 pt2 ) } {
                                                                                    ( __jit_ldrcx_m buf pmap xmap cvals sb )
                                                                                    ( __jit_b buf 76 ) ( __jit_b buf 15 ) ( __jit_b buf + 64 cc4 ) ( __jit_b buf + 193 * pselp 8 ) }
                                                                                = seld 1
                                                                            } {}
                                                                        }
                                                                    }
                                                                } {}
                                                                ? == 0 seld {  // through rax as before
                                                                    ( __jit_ldrax_m buf pmap xmap cvals sc )  // srcF (mov leaves flags)
                                                                    ( __jit_ldrcx_m buf pmap xmap cvals sb )  // srcT
                                                                    ( __jit_b buf 72 ) ( __jit_b buf 15 ) ( __jit_b buf + 64 cc4 ) ( __jit_b buf 193 )  // cmov<cc> rax,rcx — flags stay live for the next SEL
                                                                    ( __jit_strax_m buf pmap xmap cvals sa )
                                                                    = fseldst sa  // rax now holds the SEL result
                                                                } {
                                                                    ? == sa fseldst { = fseldst -1 } {}  // rax kept its old value; stale if this SEL overwrote that slot
                                                                }
                                                                ? == xmmslot sa { = xmmslot -1 } {}
                                                                = selskip + selskip 1
                                                                = fgo 1
                                                                = fr + fr 1
                                                                ? == sa a { = fgo 0 } {}  // the SEL overwrote the condition — later SELs read the new value
                                                            } {}
                                                        }
                                                    } {
                                                        ? == op 49 { ( __jit_jmp buf pat_at pat_rec 233 / a 6 ) } {  // BR
                                                            ? == op 48 {  // IFZ: jump if rbase[b]==0
                                                                : i zp ( __jit_pr pmap b )
                                                                ? >= zp 0 { ( __jit_b buf 77 ) ( __jit_b buf 133 ) ( __jit_b buf + 192 * zp 9 ) = g_jit_noax 1 } {  // test r_pb,r_pb
                                                                    ? != raxslot b { ( __jit_ldrax_m buf pmap xmap cvals b ) } {} ( __jit_b buf 72 ) ( __jit_b buf 133 ) ( __jit_b buf 192 ) }  // test rax,rax
                                                                ( __jit_jmp buf pat_at pat_rec 132 / a 6 )  // je
                                                            } {
                                                                ? == op 54 {  // BRIF: jump if rbase[b]!=0
                                                                    : i np2 ( __jit_pr pmap b )
                                                                    ? >= np2 0 { ( __jit_b buf 77 ) ( __jit_b buf 133 ) ( __jit_b buf + 192 * np2 9 ) = g_jit_noax 1 } {
                                                                        ? != raxslot b { ( __jit_ldrax_m buf pmap xmap cvals b ) } {} ( __jit_b buf 72 ) ( __jit_b buf 133 ) ( __jit_b buf 192 ) }
                                                                    ( __jit_jmp buf pat_at pat_rec 133 / a 6 )  // jne
                                                                } {
                                                                    ? == op 45 {  // BRIFC: cmp lhs,rhs; jcc target (cmpop in d)
                                                                        ( __jit_cmp buf pmap xmap cvals b c ? < d 66 1 0 raxslot )
                                                                        ( __jit_jmp buf pat_at pat_rec ( __jit_jcc cctab d ) / a 6 )
                                                                    } {
                                                                        ? | == op 38 == op 177 {  // ADDBRIFC: v=s1+s2; dst=v; cmp v,rhs; jcc
                                                                            : i cmpop >> w5 21
                                                                            : i rhs & w5 2097151
                                                                            : i pd2 ( __jit_pr pmap d )
                                                                            : i pr2 ( __jit_pr pmap rhs )
                                                                            ? == op 38 {  // i64
                                                                                ? != raxslot c { ( __jit_ldrax_m buf pmap xmap cvals c ) } {}
                                                                                ? >= pd2 0 { ( __jit_oprax_pr buf 3 pd2 ) } {  // add rax,r1X
                                                                                    : ~ i ad64 0
                                                                                    ? == pd2 -2 { = ad64 ( __jit_alu_ci64 buf 0 ( __jit_cv cvals d ) ) } {}
                                                                                    ? == 0 ad64 { ( __jit_b buf 72 ) ( __jit_b buf 3 ) ( __jit_b buf 131 ) ( __jit_d buf * d 8 ) } {} }  // add rax,[rbx+s2]
                                                                                ( __jit_strax_m buf pmap xmap cvals b )
                                                                                ? >= pr2 0 { ( __jit_oprax_pr buf 59 pr2 ) } {  // cmp rax,r1X
                                                                                    : ~ i cr64 0
                                                                                    ? == pr2 -2 {
                                                                                        : i rv64 ( __jit_cv cvals rhs )
                                                                                        ? != 0 ( __jit_imm8 rv64 ) { ( __jit_b buf 72 ) ( __jit_b buf 131 ) ( __jit_b buf 248 ) ( __jit_b buf & rv64 255 ) = cr64 1 } {
                                                                                            ? != 0 ( __jit_imm32 rv64 ) { ( __jit_b buf 72 ) ( __jit_b buf 129 ) ( __jit_b buf 248 ) ( __jit_d buf rv64 ) = cr64 1 } {} } } {}
                                                                                    ? == 0 cr64 { ( __jit_b buf 72 ) ( __jit_b buf 59 ) ( __jit_b buf 131 ) ( __jit_d buf * rhs 8 ) } {} }  // cmp rax,[rbx+rhs]
                                                                            } {  // i32
                                                                                ? != raxslot c { ( __jit_ldrax_m buf pmap xmap cvals c ) } {}
                                                                                ? >= pd2 0 { ( __jit_opeax_pr buf 3 pd2 ) } {  // add eax,r1Xd
                                                                                    : ~ i ad32 0
                                                                                    ? == pd2 -2 { = ad32 ( __jit_alu_ci32 buf 9 ( __jit_cv cvals d ) ) } {}
                                                                                    ? == 0 ad32 { ( __jit_b buf 3 ) ( __jit_b buf 131 ) ( __jit_d buf * d 8 ) } {} }  // add eax,[rbx+s2]
                                                                                ( __jit_movslq buf ) ( __jit_strax_m buf pmap xmap cvals b )
                                                                                ? >= pr2 0 { ( __jit_opeax_pr buf 59 pr2 ) } {  // cmp eax,r1Xd
                                                                                    ? == pr2 -2 {
                                                                                        : i rv32 ( __jit_cv cvals rhs )
                                                                                        ? != 0 ( __jit_imm8 rv32 ) { ( __jit_b buf 131 ) ( __jit_b buf 248 ) ( __jit_b buf & rv32 255 ) } {  // cmp eax,imm8
                                                                                            ( __jit_b buf 129 ) ( __jit_b buf 248 ) ( __jit_d buf rv32 ) } } {  // cmp eax,imm32
                                                                                        ( __jit_b buf 59 ) ( __jit_b buf 131 ) ( __jit_d buf * rhs 8 ) } }  // cmp eax,[rbx+rhs]
                                                                            }
                                                                            ( __jit_jmp buf pat_at pat_rec ( __jit_jcc cctab cmpop ) / a 6 )
                                                                        } { ( __jit_ext buf pmap pins npin xmap xpins cvals pat_at pat_rec n op a b c d w5 raxslot auxe pta_off pta_stub chaincell spcell guard xmmslot ) }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            ? != 0 selskip {  // fseldst tracks what rax holds across the fused chain
                = raxslot fseldst
                ? == xmmslot fseldst { = xmmslot -1 } {}
                = g_jit_noax 0
            } {
                ? != 0 g_jit_noax {  // pin-direct record: rax untouched, cache survives
                    = g_jit_noax 0
                    = raxslot ( __jit_newrax_noax op a b raxslot )
                    = xmmslot ( __jit_newxmm op a b xmmslot )
                } {
                    = raxslot ( __jit_newrax op a b raxslot )
                    = xmmslot ( __jit_newxmm op a b xmmslot )
                }
            }
            = r + r 1
        }
    }
    // The trap stub, at label index n (where every bounds check jumps):
    // status 1 (out of bounds), through the freeing exit below.
    ( vec_push [i] lab ( vec_len [u] buf ) )
    ( __jit_b buf 184 ) ( __jit_d buf 1 )  // mov eax,1
    ( __jit_jmp buf pat_at pat_rec 233 + n 2 )
    // The divide-by-zero stub, at label index n+1: status 4.
    ( vec_push [i] lab ( vec_len [u] buf ) )
    ( __jit_b buf 184 ) ( __jit_d buf 4 )  // mov eax,4
    ( __jit_jmp buf pat_at pat_rec 233 + n 2 )
    // n+2: exit with whatever status eax holds, freeing this frame —
    // also the propagation target when a direct callee returns a trap.
    ( vec_push [i] lab ( vec_len [u] buf ) )
    ( __jit_b buf 73 ) ( __jit_b buf 137 ) ( __jit_b buf 24 )  // mov [r8],rbx — free frame
    ( __jit_retseq buf npin )
    // n+3: prologue overflow — status 8, nothing was allocated.
    ( vec_push [i] lab ( vec_len [u] buf ) )
    ( __jit_b buf 184 ) ( __jit_d buf 8 )  // mov eax,8
    ( __jit_retseq buf npin )
    // n+4: signed-division overflow — status 10, through the freeing exit.
    ( vec_push [i] lab ( vec_len [u] buf ) )
    ( __jit_b buf 184 ) ( __jit_d buf 10 )  // mov eax,10
    ( __jit_jmp buf pat_at pat_rec 233 + n 2 )
    // resolve forward/backward rel32s now that every record's offset is known
    : i np ( vec_len [i] pat_at )
    : ~ i pk 0
    ~ < pk np {
        : i at ?? ( vec_get [i] pat_at pk ) { T x → x F → 0 }
        : i trec ?? ( vec_get [i] pat_rec pk ) { T x → x F → 0 }
        : i dst ?? ( vec_get [i] lab trec ) { T x → x F → 0 }
        : i rel - dst + at 4
        ( vec_set [u] buf at # u & rel 255 )
        ( vec_set [u] buf + at 1 # u & ( __lshr64 rel 8 ) 255 )
        ( vec_set [u] buf + at 2 # u & ( __lshr64 rel 16 ) 255 )
        ( vec_set [u] buf + at 3 # u & ( __lshr64 rel 24 ) 255 )
        = pk + pk 1
    }
    : i len ( vec_len [u] buf )
    : *u page ( nurl_code_alloc + len 16 )
    ? == # i page 0 { = . pf jit # s -1 ^ v } {}  // no executable memory (wasm)
    : ~ i k 0
    ~ < k len { = . page k ?? ( vec_get [u] buf k ) { T x → x F → # u 0 } = k + k 1 }
    // jump-table entries become absolute addresses now that the page is known
    : i npt ( vec_len [i] pta_off )
    : ~ i ptk 0
    ~ < ptk npt {
        : i eo ?? ( vec_get [i] pta_off ptk ) { T x → x F → 0 }
        : i av + # i page ?? ( vec_get [i] pta_stub ptk ) { T x → x F → 0 }
        : ~ i bb 0
        ~ < bb 8 { = . page + eo bb # u & ( __lshr64 av * bb 8 ) 255 = bb + bb 1 }
        = ptk + ptk 1
    }
    ? != 0 ( nurl_code_seal page + len 16 ) { ( nurl_code_free page + len 16 ) = . pf jit # s -1 ^ v } {}
    ? != 0 g_jitdump {  // decimal byte stream; tools/jitdump.py turns it back into objdump input
        ( nurl_eprint `[jitdump] cs=` ) ( nurl_eprint ( nurl_str_int . pf code_start ) )
        ( nurl_eprint ` len=` ) ( nurl_eprint ( nurl_str_int len ) )
        ( nurl_eprint ` bytes=` )
        : ~ i jdk 0
        ~ < jdk len {
            ? > jdk 0 { ( nurl_eprint `,` ) } {}
            ( nurl_eprint ( nurl_str_int # i . page jdk ) )
            = jdk + jdk 1
        }
        ( nurl_eprint `\n` )
    } {}
    // Register the sealed page for fault-to-trap conversion: a guest
    // access past the committed pages faults, and the handler steers the
    // frame to this function's out-of-bounds stub (label n). Room was
    // checked before emitting; failing here anyway would leave unguarded
    // uncheckable code, so the page is dropped instead.
    ? != 0 guard {
        : i oobs ?? ( vec_get [i] lab n ) { T x → x F → 0 }
        ? != 0 ( nurl_guard_code_add page + len 16 # *u + # i page oobs ) {
            ( nurl_code_free page + len 16 ) = . pf jit # s -1 ^ v
        } {}
    } {}
    = . pf jit # s page
    = . pf jitlen + len 16
}

// Run an already-built, JIT-compiled frame `fj` to completion, handling
// its guest calls without leaving for the interpreter's driver. Returns
// 0 (done), 1 (out-of-bounds trap), 3 (unreachable); it.halt / trapmsg
// may also be set. Results are left in the frame's slots for the caller
// to read.
// Handle one pending call-out (the request is in cd; `st` says which
// kind). Returns 0 to continue, 1 when a trap/halt was recorded.
@ __jit_callout * Interp it * Module m i st * i cd → i {
    : ~ i callee . cd 4
    : i argbase . cd 5
    : *i jrb # *i . cd 0
    ? == st 19 {  // FCB bridge: run the fc op through the interpreter's own handler
        : i fc7 & . cd 7 4294967295
        : i fdd ( __lshr64 . cd 7 32 )
        : i fpops >> fdd 1
        : ~ i fbk 0
        ~ < fbk fpops { ( __push it . jrb + fc7 fbk ) = fbk + fbk 1 }
        ( __exec_fc it callee argbase )
        ? & != 0 & fdd 1 ! ( interp_trapped it ) { = . jrb fc7 ( __pop it ) } {}
        ^ ? | ( interp_trapped it ) != 0 . it halt 1 0
    } {}
    ? == st 18 {  // memory.grow: realloc on the host side, result to the dst slot
        // the dst is a dword store into cd[7] — mask off whatever an
        // earlier FCB call-out left in the upper half
        = . jrb & . cd 7 4294967295 ( __mem_grow it ( __u32 callee ) )
        ^ 0
    } {}
    ? == st 17 {  // call_indirect: resolve through the table, trapping like the interpreter
        : i ei & callee 4294967295
        ? | < ei 0 >= ei ( vec_len [i] . it table ) { ( __trap it `call_indirect: index out of range` ) ^ 1 } {}
        = callee ?? ( vec_get [i] . it table ei ) { T x → x F → -1 }
        ? < callee 0 { ( __trap it `call_indirect: null table element` ) ^ 1 } {}
        : s want ?? ( vec_get [s] . m types & . cd 7 4294967295 ) { T x → x F → # s 0 }
        : s have ( module_func_type m callee )
        ? | == # i want 0 == # i have 0 { ( __trap it `call_indirect: bad type index` ) ^ 1 } {}
        ? ! ( functype_eq # *FuncType want # *FuncType have ) { ( __trap it `call_indirect: signature mismatch` ) ^ 1 } {}
    } {}
    // A non-zero tr means the callee trapped — the message is already
    // recorded; the halt check in the resume walk sees it.
    : i tr ( __jit_callee it m callee jrb argbase )
    ? != 0 tr { ^ 1 } {}
    ^ ? | ( interp_trapped it ) != 0 . it halt 1 0
}

// Resume the parked frames in [lo, hi) innermost-first. Before resuming
// a non-final entry the chain top is parked at `hi` so re-parks land in
// a fresh nested segment (walked recursively — depth is bounded by how
// many frames sit between a call-out and the driver, not by how many
// call-outs run). The FINAL entry re-parks over its own consumed
// segment and the walk tail-iterates in place, so a loop that calls out
// a million times uses constant chain space and constant driver depth.
@ __jit_resume * Interp it * Module m * i cd i lo0 i hi0 → i {
    : *i chc # *i . it jit_chain_cell
    : ~ i lo lo0
    : ~ i hi hi0
    : ~ i pos lo0
    ~ < pos hi {
        : i last ? == + pos 32 hi 1 0
        = . chc 0 ? != 0 last pos hi
        : *i e # *i pos
        : i ejh . e 0
        : i eres & . e 1 4294967295
        : i erbx . e 2
        : i eargs . e 3
        = . cd 0 erbx
        = . cd 1 ( __mem_base it )
        = . cd 2 . it mem_bytes
        : i st ( nurl_call_code_at2 # *u ejh eres # *u cd # *u eargs )
        ? >= st 16 {
            : i segend . chc 0
            ? != 0 ( __jit_callout it m st cd ) { ^ 0 } {}  // trap recorded
            ? != 0 last {
                = lo pos
                = hi segend
                = pos lo
            } {
                : i st2 ( __jit_resume it m cd hi segend )
                ? != 0 st2 { ^ st2 } {}
                ? | ( interp_trapped it ) != 0 . it halt { ^ 0 } {}
                = pos + pos 32
            }
        } {
            ? != 0 st { ^ st } {}
            ? | ( interp_trapped it ) != 0 . it halt { ^ 0 } {}
            = pos + pos 32
        }
    }
    ^ 0
}

@ __jit_run * Interp it * Module m * PFunc pfj i argsp → i {
    : s jh . pfj jit
    : *i cd ( __jit_ctx_get it )
    : *i spc # *i . it jit_spcell
    : *i chc # *i . it jit_chain_cell
    : i sp0 . spc 0
    : i chain0 . chc 0
    = . cd 0 0  // the entry writes its own slab frame base here
    = . cd 1 ( __mem_base it )
    = . cd 2 . it mem_bytes
    = . cd 3 # i ( vec_data [i] . it globals )
    = . cd 4 0 = . cd 5 0 = . cd 6 0 = . cd 7 0
    : ~ i status ( nurl_call_code2 # *u jh # *u cd # *u argsp )
    ? >= status 16 {
        : i segend . chc 0
        ? != 0 ( __jit_callout it m status cd ) { = status 0 } {  // trap recorded; the halt check catches it
            = status ( __jit_resume it m cd chain0 segend )
            ? >= status 16 { = status 0 } {}  // cannot happen; guard against relabeling
        }
    } {}
    // whatever this invocation allocated or parked is reclaimed here
    = . spc 0 sp0
    = . chc 0 chain0
    ( __jit_ctx_put it cd )
    ^ status
}

// Invoke guest function `callee` from a JIT'd caller: args are in
// `caller_rbase[argbase..]`, results go back there. A JIT-compilable
// callee runs directly through __jit_run on a pooled frame — no
// interpreter driver, no value-stack traffic; anything else (imports,
// non-templatable bodies, or past the recursion cap) falls back to the
// interpreter. Returns 0 on success, non-zero on trap/halt.
@ __jit_callee * Interp it * Module m i callee * i caller_rbase i argbase → i {
    // imports and the depth cap take the interpreter's bridge
    ? < callee . m num_import_funcs {
        ( __rdo_import it m callee argbase caller_rbase )
        ^ ? ( interp_trapped it ) 1 0
    } {}
    : ~ s cpins ? == callee . it jit_lc_fidx # s . it jit_lc_pf # s 0
    ? == # i cpins 0 {
        = cpins ( __pfunc_for it m callee )
        ? == # i cpins 0 { ( __trap it `bad function index` ) ^ 1 } {}
        = . it jit_lc_fidx callee
        = . it jit_lc_pf # i cpins
    } {}
    : *PFunc pfc # *PFunc cpins
    ? == # i . pfc jit 0 {
        ( __jit_try it m pfc )
        // compiled and call-out-free: publish the direct entry so JIT
        // callers stop coming through this driver at all
        : s njh . pfc jit
        ? & != # i njh 0 != # i njh -1 {
            // publish the DIRECT entry: page + the 22-byte driver preamble
            : *i ftw # *i + . it jit_spcell 16
            = . ftw - callee . m num_import_funcs + # i njh 22
        } {}
    } {}
    : s jh . pfc jit
    ? | == # i jh 0 == # i jh -1 {
        // not JIT-able: interpret it, bridging args/results through the vs
        : s ct ( module_func_type m callee )
        : ~ i cp 0
        : ~ i cr 0
        ? != # i ct 0 { : *FuncType ctt # *FuncType ct = cp ( vec_len [i] . ctt params ) = cr ( vec_len [i] . ctt results ) } {}
        : ~ i ak 0
        ~ < ak cp { ( __push it . caller_rbase + argbase ak ) = ak + ak 1 }
        ( exec_func it callee )
        ? | ( interp_trapped it ) != 0 . it halt { ^ 1 } {}
        : ~ i rk cr
        ~ > rk 0 { = rk - rk 1 = . caller_rbase + argbase rk ( __pop it ) }
        ^ 0
    } {}
    // JIT-able: the entry allocates its own slab frame, reads args
    // through the pointer and writes results back there — no Frame.
    : i argsp + # i caller_rbase * argbase 8
    = g_jit_depth + g_jit_depth 1
    : i st ? > g_jit_depth 100000 9 ( __jit_run it m pfc argsp )
    = g_jit_depth - g_jit_depth 1
    ? | == st 9 == st 8 {  // depth cap or slab full: the interpreter has no such limits
        : ~ i ak2 0
        : i np . pfc nparams
        ~ < ak2 np { ( __push it . caller_rbase + argbase ak2 ) = ak2 + ak2 1 }
        ( exec_func it callee )
        ? | ( interp_trapped it ) != 0 . it halt { ^ 1 } {}
        : s ct2 ( module_func_type m callee )
        : ~ i cr2 0
        ? != # i ct2 0 { : *FuncType ctt2 # *FuncType ct2 = cr2 ( vec_len [i] . ctt2 results ) } {}
        : ~ i rk2 cr2
        ~ > rk2 0 { = rk2 - rk2 1 = . caller_rbase + argbase rk2 ( __pop it ) }
        ^ 0
    } {}
    ? == st 3 { ( __trap it `unreachable` ) ^ 1 } {}
    ? == st 4 { ( __trap it `integer divide by zero` ) ^ 1 } {}
    ? == st 10 { ( __trap it `integer overflow` ) ^ 1 } {}
    ? == st 1 { ( __trap it `memory access out of bounds` ) ^ 1 } {}
    ? | ( interp_trapped it ) != 0 . it halt { ^ 1 } {}
    ^ 0
}

@ exec_func * Interp it i fidx → v {
    ? != 0 . it halt { ^ v } {}
    : *Module m # *Module . it mod
    // Imported functions occupy the low indices → dispatch to the host (WASI).
    ? < fidx . m num_import_funcs { ( __call_import it m fidx ) ^ v } {}
    // The activation stack is the frames themselves: `prev` links each to
    // its caller (and doubles as the recycle freelist link while parked),
    // `depth` bounds recursion — no vector, no counter register, and a
    // call or return is a handful of raw loads and stores.
    : s fr0 ( __frame_new it m fidx -1 )
    ? != # i fr0 0 {
        : *Frame f00 # *Frame fr0
        = . f00 prev # s 0
        = . f00 depth 1
    } {}
    // Tier-0 JIT: a templatable leaf integer function runs as sealed
    // machine code instead of the record loop. Correctness-preserving —
    // __jit_try leaves jit at -1 for anything it cannot lower, and the
    // interpreter below runs unchanged. Only the outermost frame is
    // routed here for now (no loops/calls in the tier, so termination is
    // the function's own straight-line length; fuel is unmetered).
    // JIT only unlimited-fuel, non-shared-memory runs: a metered run keeps
    // the interpreter (exact fuel), and shared memory needs the byte-wise
    // store path the templates skip.
    ? & & != 0 g_jit == 0 . it shared_mem & < . it fuel 0 != # i fr0 0 {
        : *Frame fj # *Frame fr0
        : *PFunc pfj # *PFunc . fj pins
        ? == # i . pfj jit 0 {
            ( __jit_try it m pfj )
            : s njh . pfj jit
            ? & != # i njh 0 != # i njh -1 {
                // publish the DIRECT entry: page + the 22-byte driver preamble
                : *i ftw2 # *i + . it jit_spcell 16
                = . ftw2 - fidx . m num_import_funcs + # i njh 22
            } {}
        } {}
        : s jh . pfj jit
        ? & != # i jh 0 != # i jh -1 {
            : *i jrb ( vec_data [i] . fj regs )
            : i status ( __jit_run it m pfj # i jrb )
            // status 8 (slab full before anything ran) falls through to the
            // interpreter driver below — the args are still in the frame.
            ? != status 8 {
                ? == status 3 { ( __trap it `unreachable` ) ( __frame_recycle fr0 ) ^ v } {}
                ? == status 4 { ( __trap it `integer divide by zero` ) ( __frame_recycle fr0 ) ^ v } {}
                ? == status 10 { ( __trap it `integer overflow` ) ( __frame_recycle fr0 ) ^ v } {}
                ? != 0 status { ( __trap it `memory access out of bounds` ) ( __frame_recycle fr0 ) ^ v } {}
                ? | ( interp_trapped it ) != 0 . it halt { ( __frame_recycle fr0 ) ^ v } {}
                // outermost: the entry wrote the results back to the args area
                : i nres . pfj nresults
                : ~ i rk 0
                ~ < rk nres { ( __push it . jrb rk ) = rk + rk 1 }
                ( __frame_recycle fr0 )
                ^ v
            } {}
        } {}
    } {}
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
    = tp fr0
    ~ & != # i tp 0 == 0 . it halt {
        : *Frame fr # *Frame tp
        : *PFunc npf # *PFunc . fr pins
        = pbase ( vec_data [i] . npf code )
        = rbase ( vec_data [i] . fr regs )
        = pc . fr pos
        = pend . fr end
        = tail 0
        ~ < pc pend {
            : i r0 pc
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
                                                                ? == op 13 { = . rbase ra + * . rbase rb . rbase rc . rbase . pbase + r0 4 } {  // __R_MULADD64
                                                                    ? == op 14 { = . rbase ra & + . rbase rb . rbase rc . rbase . pbase + r0 4 } {  // __R_ADDAND64
                                                                        ? == op 15 { = . rbase ra * + . rbase rb . rbase rc . rbase . pbase + r0 4 } {  // __R_ADDMUL64
                                                                            ? == op 16 { = . rbase ra ( __lshr64 + . rbase rb . rbase rc & . rbase . pbase + r0 4 63 ) } {  // __R_ADDSHRU64
                                                                                ? == op 17 { = . rbase ra & ( __lshr64 . rbase rb & . rbase rc 63 ) . rbase . pbase + r0 4 } {  // __R_SHRUAND64
                                                                                    ? == op 18 { = . rbase ra ( __mem_load it + & + . rbase rb . rbase . pbase + r0 4 4294967295 rc 8 0 ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // i64.load
                                                                                        ? == op 19 { = . rbase ra ( __mem_load it + & + . rbase rb . rbase . pbase + r0 4 4294967295 rc 8 0 ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // f64.load
                                                                                            ? == op 20 { = . rbase ra ( __w32 ( __mem_load it + & + . rbase rb . rbase . pbase + r0 4 4294967295 rc 4 0 ) ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // i32.load
                                                                                                ? == op 21 { = . rbase ra ( __mem_load it + & + . rbase rb . rbase . pbase + r0 4 4294967295 rc 1 0 ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // i32.load8_u
                                                                                                    ? == op 22 { = . rbase ra + + . rbase rb . rbase rc . rbase . pbase + r0 4 } {  // __R_ADDADD64
                                                                                                        ? == op 23 { = . rbase ra ( __mem_load it + & + . rbase rb . rbase . pbase + r0 4 4294967295 rc 2 0 ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // i32.load16_u
                                                                                                            ? == op 24 { = . rbase ra ( __mem_load it + & + . rbase rb . rbase . pbase + r0 4 4294967295 rc 4 0 ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // f32.load
                                                                                                                ? == op 25 { = . rbase ra ( __mem_load it + & + . rbase rb . rbase . pbase + r0 4 4294967295 rc 1 0 ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // i64.load8_u
                                                                                                                    ? == op 26 { = . rbase ra ( __mem_load it + & + . rbase rb . rbase . pbase + r0 4 4294967295 rc 2 0 ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // i64.load16_u
                                                                                                                        ? == op 27 { ( __mem_store it + & . rbase ra 4294967295 rc 8 . rbase rb ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // i64.store
                                                                                                                            ? == op 28 { ( __mem_store it + & . rbase ra 4294967295 rc 8 . rbase rb ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // f64.store
                                                                                                                                ? == op 29 { ( __mem_store it + & . rbase ra 4294967295 rc 1 . rbase rb ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // i32.store8
                                                                                                                                    ? == op 30 { = . rbase ra ^^ ( __lshr64 . rbase rb & . rbase rc 63 ) . rbase . pbase + r0 4 } {  // __R_SHRUXOR64
                                                                                                                                        ? == op 31 { ( __mem_store it + & . rbase ra 4294967295 rc 4 . rbase rb ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // f32.store
                                                                                                                                            ? == op 32 { ( __mem_store it + & . rbase ra 4294967295 rc 4 . rbase rb ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // i64.store32
                                                                                                                                                ? == op 33 { = . rbase ra * ^^ . rbase rb . rbase rc . rbase . pbase + r0 4 } {  // __R_XORMUL64
                                                                                                                                                    ? == op 34 { ( __mem_store it + & . rbase ra 4294967295 rc 1 . rbase rb ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // i64.store8
                                                                                                                                                        ? == op 35 { ( __mem_store it + & . rbase ra 4294967295 rc 2 . rbase rb ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // i64.store16
                                                                                                                                                            ? == op 36 { = . rbase ra ( __w32 . rbase rb ) } {  // i32.wrap_i64
                                                                                                                                                                ? == op 37 { = . rbase ra & . rbase rb 4294967295 } {  // i64.extend_i32_u
                                                                                                                                                                    ? == op 38 {  // __R_ADDBRIFC64: dst = s1 + s2, then compare-and-branch on it
                                                                                                                                                                        : i v + . rbase rc . rbase . pbase + r0 4
                                                                                                                                                                        = . rbase rb v
                                                                                                                                                                        : i w5 . pbase + r0 5
                                                                                                                                                                        ? != 0 ( __rcmp >> w5 21 v . rbase & w5 2097151 ) { = pc ra ? <= ra r0 { = fuel - fuel + / - r0 ra 6 1 ? < fuel 0 { ( __trap it `fuel exhausted` ) ( __fr_setpos tp r0 ) = pc pend } {} } {} } {}
                                                                                                                                                                    } {
                                                                                                                                                                        ? == op 39 { = . rbase ra ( f64_to_bits * ( bits_to_f64 . rbase rb ) ( bits_to_f64 . rbase rc ) ) } {  // f64.mul
                                                                                                                                                                            ? == op 40 { = . rbase ra ( f64_to_bits + ( bits_to_f64 . rbase rb ) ( bits_to_f64 . rbase rc ) ) } {  // f64.add
                                                                                                                                                                                ? == op 41 { = . rbase ra ( f64_to_bits - ( bits_to_f64 . rbase rb ) ( bits_to_f64 . rbase rc ) ) } {  // f64.sub
                                                                                                                                                                                    ? == op 42 { = . rbase ra ( f64_to_bits / ( bits_to_f64 . rbase rb ) ( bits_to_f64 . rbase rc ) ) } {  // f64.div
                                                                                                                                                                                        ? == op 43 { = . rbase ra ? == . rbase rb 0 1 0 } {  // i32.eqz
                                                                                                                                                                                            ? == op 44 { = . rbase ra ? == . rbase rb 0 1 0 } {  // i64.eqz
                                                                                                                                                                                                ? == op 45 { ? != 0 ( __rcmp . pbase + r0 4 . rbase rb . rbase rc ) { = pc ra ? <= ra r0 { = fuel - fuel + / - r0 ra 6 1 ? < fuel 0 { ( __trap it `fuel exhausted` ) ( __fr_setpos tp r0 ) = pc pend } {} } {} } {} } {  // __R_BRIFC
                                                                                                                                                                                                    ? == op 46 {  // __R_SEL
                                                                                                                                                                                                        : i cond . rbase . pbase + r0 4
                                                                                                                                                                                                        = . rbase ra ? != cond 0 . rbase rb . rbase rc
                                                                                                                                                                                                    } {
                                                                                                                                                                                                        ? == op 47 { = . rbase ra . rbase rb } {  // __R_MOV
                                                                                                                                                                                                            ? == op 48 { ? == . rbase rb 0 { = pc ra ? <= ra r0 { = fuel - fuel + / - r0 ra 6 1 ? < fuel 0 { ( __trap it `fuel exhausted` ) ( __fr_setpos tp r0 ) = pc pend } {} } {} } {} } {  // __R_IFZ
                                                                                                                                                                                                                ? == op 49 { = pc ra ? <= ra r0 { = fuel - fuel + / - r0 ra 6 1 ? < fuel 0 { ( __trap it `fuel exhausted` ) ( __fr_setpos tp r0 ) = pc pend } {} } {} } {  // __R_BR: backward = a loop edge — charge its length
                                                                                                                                                                                                                    ? == op 50 {  // __R_CALL
                                                                                                                                                                                                                        ( __fr_setpos tp pc )
                                                                                                                                                                                                                        = fuel - fuel 1
                                                                                                                                                                                                                        : s nf9 ( __rdo_call it m tp ra rb rbase pbase r0 )
                                                                                                                                                                                                                        ? != # i nf9 0 {  // defined callee: enter its frame without leaving the loop
                                                                                                                                                                                                                            = tp nf9
                                                                                                                                                                                                                            : *Frame f8 # *Frame tp
                                                                                                                                                                                                                            : *PFunc p8 # *PFunc . f8 pins
                                                                                                                                                                                                                            = pbase ( vec_data [i] . p8 code )
                                                                                                                                                                                                                            = rbase ( vec_data [i] . f8 regs )
                                                                                                                                                                                                                            = pc 0
                                                                                                                                                                                                                            = pend . f8 end
                                                                                                                                                                                                                        } {}  // import: nothing moved, continue with the next record
                                                                                                                                                                                                                        ? != 0 . it halt { ( __fr_setpos tp r0 ) = tail 1 = pc pend } {}
                                                                                                                                                                                                                    } {
                                                                                                                                                                                                                        ? == op 51 { = . rbase ra rb } {  // __R_CONST
                                                                                                                                                                                                                            ? == op 52 { = . rbase ra ?? ( vec_get [i] . it globals rb ) { T x → x F → 0 } } {  // __R_GG
                                                                                                                                                                                                                                ? == op 53 { ( vec_set [i] . it globals ra . rbase rb ) } {  // __R_GS
                                                                                                                                                                                                                                    ? == op 54 { ? != . rbase rb 0 { = pc ra ? <= ra r0 { = fuel - fuel + / - r0 ra 6 1 ? < fuel 0 { ( __trap it `fuel exhausted` ) ( __fr_setpos tp r0 ) = pc pend } {} } {} } {} } {  // __R_BRIF
                                                                                                                                                                                                                                        ? == op 55 {  // __R_RET: the whole return, inline — no outer-loop round trip
                                                                                                                                                                                                                                            : *Frame f9 # *Frame tp
                                                                                                                                                                                                                                            : i rdst9 . f9 ret_dst
                                                                                                                                                                                                                                            : s cp9 . f9 prev
                                                                                                                                                                                                                                            ? < rdst9 0 {
                                                                                                                                                                                                                                                : ~ i rk 0
                                                                                                                                                                                                                                                ~ < rk rb { ( __push it . rbase + ra rk ) = rk + rk 1 }
                                                                                                                                                                                                                                                ( __frame_recycle tp )
                                                                                                                                                                                                                                                = tp # s 0
                                                                                                                                                                                                                                                = tail 1
                                                                                                                                                                                                                                                = pc pend
                                                                                                                                                                                                                                            } {
                                                                                                                                                                                                                                                // results go STRAIGHT into the caller's slots
                                                                                                                                                                                                                                                : *Frame cf9 # *Frame cp9
                                                                                                                                                                                                                                                : *i crb9 ( vec_data [i] . cf9 regs )
                                                                                                                                                                                                                                                : ~ i rk 0
                                                                                                                                                                                                                                                ~ < rk rb { = . crb9 + rdst9 rk . rbase + ra rk = rk + rk 1 }
                                                                                                                                                                                                                                                ( __frame_recycle tp )
                                                                                                                                                                                                                                                = tp cp9
                                                                                                                                                                                                                                                : *PFunc p9 # *PFunc . cf9 pins
                                                                                                                                                                                                                                                = pbase ( vec_data [i] . p9 code )
                                                                                                                                                                                                                                                = rbase crb9
                                                                                                                                                                                                                                                = pc . cf9 pos
                                                                                                                                                                                                                                                = pend . cf9 end
                                                                                                                                                                                                                                            }
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
                                                                                                                                                                                                                                                                                                                            ? == op 76 { = . rbase ra ( __w32 ( __mem_load it + & + . rbase rb . rbase . pbase + r0 4 4294967295 rc 1 1 ) ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // i32.load8_s
                                                                                                                                                                                                                                                                                                                                ? == op 77 { = . rbase ra ( __w32 ( __mem_load it + & + . rbase rb . rbase . pbase + r0 4 4294967295 rc 2 1 ) ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // i32.load16_s
                                                                                                                                                                                                                                                                                                                                    ? == op 78 { = . rbase ra ( __mem_load it + & + . rbase rb . rbase . pbase + r0 4 4294967295 rc 1 1 ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // i64.load8_s
                                                                                                                                                                                                                                                                                                                                        ? == op 79 { = . rbase ra ( __mem_load it + & + . rbase rb . rbase . pbase + r0 4 4294967295 rc 2 1 ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // i64.load16_s
                                                                                                                                                                                                                                                                                                                                            ? == op 80 { = . rbase ra ( __mem_load it + & + . rbase rb . rbase . pbase + r0 4 4294967295 rc 4 1 ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // i64.load32_s
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
                                                                                                                                                                                                                                                                                                                                                                                                            ? == op 96 { = . rbase ra ( __rdiv it 109 . rbase rb . rbase rc ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // i32.div_s
                                                                                                                                                                                                                                                                                                                                                                                                                ? == op 97 { = . rbase ra ( __rdiv it 110 . rbase rb . rbase rc ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // i32.div_u
                                                                                                                                                                                                                                                                                                                                                                                                                    ? == op 98 { = . rbase ra ( __rdiv it 111 . rbase rb . rbase rc ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // i32.rem_s
                                                                                                                                                                                                                                                                                                                                                                                                                        ? == op 99 { = . rbase ra ( __rdiv it 112 . rbase rb . rbase rc ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // i32.rem_u
                                                                                                                                                                                                                                                                                                                                                                                                                            ? == op 100 { = . rbase ra ( __rotl32 . rbase rb . rbase rc ) } {  // i32.rotl
                                                                                                                                                                                                                                                                                                                                                                                                                                ? == op 101 { = . rbase ra ( __rotr32 . rbase rb . rbase rc ) } {  // i32.rotr
                                                                                                                                                                                                                                                                                                                                                                                                                                    ? == op 102 { = . rbase ra ( __runary 121 . rbase rb ) } {  // i64.clz
                                                                                                                                                                                                                                                                                                                                                                                                                                        ? == op 103 { = . rbase ra ( __runary 122 . rbase rb ) } {  // i64.ctz
                                                                                                                                                                                                                                                                                                                                                                                                                                            ? == op 104 { = . rbase ra ( __runary 123 . rbase rb ) } {  // i64.popcnt
                                                                                                                                                                                                                                                                                                                                                                                                                                                ? == op 105 { = . rbase ra ( __rdiv it 127 . rbase rb . rbase rc ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // i64.div_s
                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? == op 106 { = . rbase ra ( __rdiv it 128 . rbase rb . rbase rc ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // i64.div_u
                                                                                                                                                                                                                                                                                                                                                                                                                                                        ? == op 107 { = . rbase ra ( __rdiv it 129 . rbase rb . rbase rc ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // i64.rem_s
                                                                                                                                                                                                                                                                                                                                                                                                                                                            ? == op 108 { = . rbase ra ( __rdiv it 130 . rbase rb . rbase rc ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // i64.rem_u
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
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ? == op 135 { = . rbase ra ( __convert it 168 . rbase rb ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // i32.trunc_f32_s
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ? == op 136 { = . rbase ra ( __convert it 169 . rbase rb ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // i32.trunc_f32_u
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? == op 137 { = . rbase ra ( __convert it 170 . rbase rb ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // i32.trunc_f64_s
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? == op 138 { = . rbase ra ( __convert it 171 . rbase rb ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // i32.trunc_f64_u
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ? == op 139 { = . rbase ra ( __convert it 174 . rbase rb ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // i64.trunc_f32_s
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ? == op 140 { = . rbase ra ( __convert it 175 . rbase rb ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // i64.trunc_f32_u
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? == op 141 { = . rbase ra ( __convert it 176 . rbase rb ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // i64.trunc_f64_s
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? == op 142 { = . rbase ra ( __convert it 177 . rbase rb ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // i64.trunc_f64_u
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ? == op 143 { = . rbase ra ( __convert it 178 . rbase rb ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // f32.convert_i32_s
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ? == op 144 { = . rbase ra ( __convert it 179 . rbase rb ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // f32.convert_i32_u
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? == op 145 { = . rbase ra ( __convert it 180 . rbase rb ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // f32.convert_i64_s
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? == op 146 { = . rbase ra ( __convert it 181 . rbase rb ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // f32.convert_i64_u
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ? == op 147 { = . rbase ra ( __convert it 182 . rbase rb ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // f32.demote_f64
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ? == op 148 { = . rbase ra ( __convert it 183 . rbase rb ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // f64.convert_i32_s
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? == op 149 { = . rbase ra ( __convert it 184 . rbase rb ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // f64.convert_i32_u
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? == op 150 { = . rbase ra ( __convert it 185 . rbase rb ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // f64.convert_i64_s
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ? == op 151 { = . rbase ra ( __convert it 186 . rbase rb ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // f64.convert_i64_u
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ? == op 152 { = . rbase ra ( __convert it 187 . rbase rb ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // f64.promote_f32
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
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? >= ei ( vec_len [i] . it table ) { ( __trap it `out of bounds table access` ) ( __fr_setpos tp r0 ) = pc pend } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    = . rbase ra ?? ( vec_get [i] . it table ei ) { T x → x F → -1 } }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? == op 165 {  // __R_TABSET
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    : i ei ( __u32 . rbase ra )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? >= ei ( vec_len [i] . it table ) { ( __trap it `out of bounds table access` ) ( __fr_setpos tp r0 ) = pc pend } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ( vec_set [i] . it table ei . rbase rb ) }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? == op 166 { = . rbase ra ? == . rbase rb -1 1 0 } {  // __R_ISNULL
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ? == op 167 {  // __R_BRM
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            : i dd . pbase + r0 4
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            : ~ i mk 0
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ~ < mk dd { = . rbase + rb mk . rbase + rc mk = mk + mk 1 }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            = pc ra
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ? <= ra r0 { = fuel - fuel + / - r0 ra 6 1 ? < fuel 0 { ( __trap it `fuel exhausted` ) ( __fr_setpos tp r0 ) = pc pend } {} } {}
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ? == op 168 {  // __R_BRIFM
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? != . rbase rb 0 {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    : i dd . pbase + r0 4
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    : i mdst >> rc 20
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    : i msrc & rc 1048575
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    : ~ i mk 0
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ~ < mk dd { = . rbase + mdst mk . rbase + msrc mk = mk + mk 1 }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    = pc ra
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? <= ra r0 { = fuel - fuel + / - r0 ra 6 1 ? < fuel 0 { ( __trap it `fuel exhausted` ) ( __fr_setpos tp r0 ) = pc pend } {} } {}
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                } {}
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? == op 169 {  // __R_BRTBL
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    : *Frame ftb # *Frame tp
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    : *PFunc tpf # *PFunc . ftb pins
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
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? <= tgt r0 { = fuel - fuel + / - r0 tgt 6 1 ? < fuel 0 { ( __trap it `fuel exhausted` ) ( __fr_setpos tp r0 ) = pc pend } {} } {}
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? == op 170 {  // __R_CALLIND
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        : i ei & . rbase rc 4294967295
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ? | < ei 0 >= ei ( vec_len [i] . it table ) { ( __trap it `call_indirect: index out of range` ) ( __fr_setpos tp r0 ) = pc pend } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            : i cfi ?? ( vec_get [i] . it table ei ) { T x → x F → -1 }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ? < cfi 0 { ( __trap it `call_indirect: null table element` ) ( __fr_setpos tp r0 ) = pc pend } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                : s want ?? ( vec_get [s] . m types ra ) { T x → x F → # s 0 }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                : s have ( module_func_type m cfi )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? | == # i want 0 == # i have 0 { ( __trap it `call_indirect: bad type index` ) ( __fr_setpos tp r0 ) = pc pend } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? ! ( functype_eq # *FuncType want # *FuncType have ) { ( __trap it `call_indirect: signature mismatch` ) ( __fr_setpos tp r0 ) = pc pend } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ( __fr_setpos tp pc )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        = fuel - fuel 1
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        : s nf9 ( __rdo_dyn it m tp cfi rb rbase )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ? != # i nf9 0 {  // defined callee: enter its frame without leaving the loop
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            = tp nf9
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            : *Frame f8 # *Frame tp
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            : *PFunc p8 # *PFunc . f8 pins
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            = pbase ( vec_data [i] . p8 code )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            = rbase ( vec_data [i] . f8 regs )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            = pc 0
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            = pend . f8 end
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        } {}  // import: nothing moved, continue with the next record
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ? != 0 . it halt { ( __fr_setpos tp r0 ) = tail 1 = pc pend } {}
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
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {}
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ? == op 174 {  // __R_ATOM
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                : i dd . pbase + r0 4
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                : i pops >> dd 1
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                : ~ i bk 0
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ~ < bk pops { ( __push it . rbase + rc bk ) = bk + bk 1 }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ( __exec_atomic it ra rb )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? & != 0 & dd 1 ! ( interp_trapped it ) { = . rbase rc ( __pop it ) } {}
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {}
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? == op 205 {  // __R_LOADSHL64: dst = mem64[(x<<k) w32 + off]
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    : i v ( __mem_load it + & ( __w32 << . rbase rb & . rbase . pbase + r0 4 31 ) 4294967295 rc 8 0 )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } { = . rbase ra v }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? == op 206 {  // __R_LOADSHL32
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        : i v ( __mem_load it + & ( __w32 << . rbase rb & . rbase . pbase + r0 4 31 ) 4294967295 rc 4 0 )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } { = . rbase ra ( __w32 v ) }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ? == op 207 {  // __R_LOADSHLADD64: dst = mem64[(base + (x<<k)) w32 + off]
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            : i w5 . pbase + r0 5
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            : i ax + . rbase rb ( __w32 << . rbase . pbase + r0 4 & . rbase w5 31 )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            : i v ( __mem_load it + & ax 4294967295 rc 8 0 )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } { = . rbase ra v }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ? == op 208 {  // __R_LOADSHLADD32
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                : i w5 . pbase + r0 5
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                : i ax + . rbase rb ( __w32 << . rbase . pbase + r0 4 & . rbase w5 31 )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                : i v ( __mem_load it + & ax 4294967295 rc 4 0 )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } { = . rbase ra ( __w32 v ) }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? == op 211 {  // __R_LOADMULI64
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    : i v ( __mem_load it + & . rbase rb 4294967295 rc 8 0 )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } { = . rbase ra * v . rbase . pbase + r0 4 }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? == op 212 {  // __R_LOADADDI64
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        : i v ( __mem_load it + & . rbase rb 4294967295 rc 8 0 )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } { = . rbase ra + v . rbase . pbase + r0 4 }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ? == op 194 {  // __R_LOADMULF64
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            : i v ( __mem_load it + & . rbase rb 4294967295 rc 8 0 )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                = . rbase ra ( f64_to_bits * ( bits_to_f64 v ) ( bits_to_f64 . rbase . pbase + r0 4 ) )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ? == op 197 {  // __R_ADDSTOREF64
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ( __mem_store it + & . rbase ra 4294967295 . pbase + r0 4 8 ( f64_to_bits + ( bits_to_f64 . rbase rb ) ( bits_to_f64 . rbase rc ) ) )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {}
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? == op 198 { = . rbase ra ( f64_to_bits + * ( bits_to_f64 . rbase rb ) ( bits_to_f64 . rbase rc ) ( bits_to_f64 . rbase . pbase + r0 4 ) ) } {  // __R_MULADDF64
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? == op 199 { = . rbase ra ( f64_to_bits - * ( bits_to_f64 . rbase rb ) ( bits_to_f64 . rbase rc ) ( bits_to_f64 . rbase . pbase + r0 4 ) ) } {  // __R_MULSUBAF64
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ? == op 200 { = . rbase ra ( f64_to_bits - ( bits_to_f64 . rbase . pbase + r0 4 ) * ( bits_to_f64 . rbase rb ) ( bits_to_f64 . rbase rc ) ) } {  // __R_MULSUBBF64
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ? == op 195 {  // __R_LOADADDF64
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                : i v ( __mem_load it + & . rbase rb 4294967295 rc 8 0 )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    = . rbase ra ( f64_to_bits + ( bits_to_f64 v ) ( bits_to_f64 . rbase . pbase + r0 4 ) )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? == op 196 {  // __R_LOADSUBBF64
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    : i v ( __mem_load it + & . rbase rb 4294967295 rc 8 0 )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        = . rbase ra ( f64_to_bits - ( bits_to_f64 . rbase . pbase + r0 4 ) ( bits_to_f64 v ) )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? == op 201 { = . rbase ra ( f64_to_bits * - ( bits_to_f64 . rbase rb ) ( bits_to_f64 . rbase rc ) ( bits_to_f64 . rbase . pbase + r0 4 ) ) } {  // __R_SUBMULF64
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ? == op 185 { = . rbase ra ( __w32 - . rbase rb . rbase rc ) } {  // i32.sub (demoted)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ? == op 184 { = . rbase ra ( __w32 | . rbase rb . rbase rc ) } {  // i32.or (demoted)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? == op 180 { = . rbase ra ( __w32 ^^ . rbase rb . rbase rc ) } {  // i32.xor (demoted)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? == op 179 { = . rbase ra ( __w32 >> ( __w32 . rbase rb ) & . rbase rc 31 ) } {  // i32.shr_s (demoted)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ? == op 181 { = . rbase ra ( __w32 * . rbase rb . rbase rc ) } {  // i32.mul (demoted)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ? == op 182 { = . rbase ra ( __mem_load it + & + . rbase rb . rbase . pbase + r0 4 4294967295 rc 4 0 ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // i64.load32_u (demoted)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? == op 183 { ( __mem_store it + & . rbase ra 4294967295 rc 4 . rbase rb ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // i32.store (demoted)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? == op 178 { ( __mem_store it + & . rbase ra 4294967295 rc 2 . rbase rb ) ? != 0 . it halt { ( __fr_setpos tp r0 ) = pc pend } {} } {  // i32.store16 (demoted)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ? == op 210 {  // __R_CALLIMP: bridge a host import (known at predecode)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ( __fr_setpos tp pc )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            = fuel - fuel 1
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ( __rdo_import it m ra rb rbase )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ? != 0 . it halt { ( __fr_setpos tp r0 ) = tail 1 = pc pend } {}
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ? == op 175 { = . rbase ra ( __w32 . rbase rb ) } {  // i64.extend_i32_s (not emitted today — see __wrap_skippable)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ? == op 177 {  // __R_ADDBRIFC32
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    : i v ( __w32 + . rbase rc . rbase . pbase + r0 4 )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    = . rbase rb v
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    : i w5 . pbase + r0 5
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? != 0 ( __rcmp >> w5 21 v . rbase & w5 2097151 ) { = pc ra ? <= ra r0 { = fuel - fuel + / - r0 ra 6 1 ? < fuel 0 { ( __trap it `fuel exhausted` ) ( __fr_setpos tp r0 ) = pc pend } {} } {} } {}
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                } {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ? == op 172 { ( __trap it `unreachable` ) ( __fr_setpos tp r0 ) = pc pend } {  // __R_UNREACH
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ? == op 173 { ( __trap it `unsupported opcode` ) ( __fr_setpos tp r0 ) = pc pend } {  // __R_TRAPUN
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ( __trap it `unsupported opcode` ) ( __fr_setpos tp r0 ) = pc pend
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } }
                                                                                                                                                                                                                                                                                                                                } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } }
                                                                                                                                                                                                } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } }
                                                                } } } } } } } } } } } } } }
        }
        ? & == tail 0 == 0 . it halt {
            // fell off the end → return: results sit at slots lloc.. by
            // construction (the body ends at height = result count)
            // `sbase` / `nresults` are read from the frame being left rather
            // than carried in the driver: two loads on a frame transition
            // instead of two registers held across every record.
            : *Frame ff # *Frame tp
            : *PFunc dpf # *PFunc . ff pins
            : i lloc . dpf sbase
            : i nres . dpf nresults
            : i rdst . ff ret_dst
            : s cp2 . ff prev
            ? < rdst 0 {
                // outermost frame: results leave on the value stack
                : ~ i rk 0
                ~ < rk nres { ( __push it . rbase + lloc rk ) = rk + rk 1 }
            } {
                ? != # i cp2 0 {
                    : *Frame cfr # *Frame cp2
                    : *i crb ( vec_data [i] . cfr regs )
                    : ~ i rk 0
                    ~ < rk nres { = . crb + rdst rk . rbase + lloc rk = rk + rk 1 }
                } {}
            }
            ( __frame_recycle tp )
            = tp cp2
        } {}
    }
    ? ( interp_trapped it ) { ( __trap_backtrace it m tp ) } {}
    : ~ s cw tp
    ~ != # i cw 0 {
        : *Frame cf # *Frame cw
        : s nx . cf prev
        ( __frame_free cw )
        = cw nx
    }
    = . it fuel ? < fuel0 0 -1 ? < fuel 0 0 fuel
}

// Perform a call from the register driver: `argbase` is the caller slot of
// the first argument (and the destination of the results). Imports bridge
// through the value stack; defined functions get a fresh frame with the
// arguments copied straight into their first locals.
// Perform a guest-to-guest call: the callee is KNOWN to be a defined
// function (the predecoder gives imports their own record). `recp` points
// at the call record; its D word caches the callee's PFunc handle after
// the first execution, so the per-call cost is the freelist pop, the
// argument copy and the chain link — no lookups, no nested call on the
// pooled path. Returns the new frame, or 0 on trap.
@ __rdo_call * Interp it * Module m s caller i callee i argbase * i caller_rbase * i rpb i rec0 → s {
    : ~ s cpins # s . rpb + rec0 4
    ? == # i cpins 0 {
        = cpins ( __pfunc_for it m callee )
        ? == # i cpins 0 { ( __trap it `bad function index` ) ^ # s 0 } {}
        = . rpb + rec0 4 # i cpins
    } {}
    : *Frame cfr9 # *Frame caller
    ? >= . cfr9 depth . it max_depth { ( __trap it `call stack exhausted` ) ^ # s 0 } {}
    : *PFunc pfc # *PFunc cpins
    : s rf . pfc free
    ? != # i rf 0 {
        : *Frame rfr # *Frame rf
        = . pfc free . rfr prev
        : *i rb ( vec_data [i] . rfr regs )
        : ~ i zk . pfc nparams
        ~ < zk . pfc nlocals { = . rb zk 0 = zk + zk 1 }
        : i np . pfc nparams
        : ~ i ak 0
        ~ < ak np { = . rb ak . caller_rbase + argbase ak = ak + ak 1 }
        = . rfr pos 0
        = . rfr ret_dst argbase
        = . rfr prev caller
        = . rfr depth + . cfr9 depth 1
        ^ rf
    } {}
    // cold path: fresh frame through the general builder
    : s nf ( __frame_new it m callee argbase )
    ? == # i nf 0 { ^ # s 0 } {}
    : *Frame nfr # *Frame nf
    : *i nrb ( vec_data [i] . nfr regs )
    : *PFunc npf # *PFunc . nfr pins
    : i np . npf nparams
    : ~ i ak 0
    ~ < ak np { = . nrb ak . caller_rbase + argbase ak = ak + ak 1 }
    = . nfr prev caller
    = . nfr depth + . cfr9 depth 1
    ^ nf
}

// The import bridge (its own record since the predecoder knows), and the
// dynamic spelling call_indirect still needs: resolve at run time, bridge
// imports through the value stack.
@ __rdo_dyn * Interp it * Module m s caller i callee i argbase * i caller_rbase → s {
    ? < callee . m num_import_funcs {
        ( __rdo_import it m callee argbase caller_rbase )
        ^ # s 0
    } {}
    : ~ s cpins ( __pfunc_for it m callee )
    ? == # i cpins 0 { ( __trap it `bad function index` ) ^ # s 0 } {}
    : *Frame cfr9 # *Frame caller
    ? >= . cfr9 depth . it max_depth { ( __trap it `call stack exhausted` ) ^ # s 0 } {}
    : s nf ( __frame_new it m callee argbase )
    ? == # i nf 0 { ^ # s 0 } {}
    : *Frame nfr # *Frame nf
    : *i nrb ( vec_data [i] . nfr regs )
    : *PFunc npf # *PFunc . nfr pins
    : i np . npf nparams
    : ~ i ak 0
    ~ < ak np { = . nrb ak . caller_rbase + argbase ak = ak + ak 1 }
    = . nfr prev caller
    = . nfr depth + . cfr9 depth 1
    ^ nf
}

@ __rdo_import * Interp it * Module m i callee i argbase * i caller_rbase → v {
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

// `inline`: both the BRIFC and ADDBRIFC dispatch arms fold this chain
// into themselves; with two callers LLVM's threshold tips to an outlined
// call, which puts a call+spill on the hottest branch path in the
// interpreter (measured: sieve +12%).
inline @ __rcmp i op i a i b → i {  // the internal compare codes, i32 then i64 → 0/1
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
@ __gpu_base * Interp it → i { ^ ( __mem_base it ) }

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
    ^ # s + ( __mem_base it ) o
}

// Guest pointer to a NUL-terminated string → host `s`. A string with no
// terminator inside linear memory reads as empty rather than running off
// the end of the buffer.
@ __net_cstr * Interp it i off → s {
    : i o & off 4294967295
    : i n . it mem_bytes
    ? >= o n { ^ `` } {}
    : *u mb # *u ( __mem_base it )
    : ~ i k o
    : ~ b term F
    ~ & < k n ! term {
        ? == # i . mb k 0 { = term T } { = k + k 1 }
    }
    ? term { ^ # s + ( __mem_base it ) o } {}
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
            ( nurl_eprint `nwasm: thread trap: ` )
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
    : s base # s ( __mem_base it )
    ( nurl_memmove # s + # i base dst # s + # i base src n )
}

@ __mem_fill * Interp it i dst i val i n → v {
    ? <= n 0 { ^ v } {}
    : s base # s ( __mem_base it )
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
        : *u mb # *u ( __mem_base it )
        : ~ i k 0
        ~ < k n {
            = . mb + dst k ?? ( vec_get [u] . ds bytes + src k ) { T x → x F → # u 0 }
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
