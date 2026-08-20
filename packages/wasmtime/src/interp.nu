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
$ `stdlib/std/time.nu`
$ `module.nu`

// round-to-nearest-even (wasm f*.nearest) — libm rint honours the default mode.
& `m` @ rint f x → f

// OS entropy (runtime helper; getrandom/urandom under the hood).
& `c` @ nurl_rand_fill *u buf i n → i

// unlink(2): path_unlink_file must NOT remove directories (remove(3) would).
& `c` @ unlink s path → i32

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
    ( Vec i ) globals  // mutable global values
    ( Vec i ) table  // runtime funcref table (mutable via table.set/grow/…)
    ( Vec i ) data_dropped  // 1 per data segment once dropped / active
    ( Vec i ) elem_dropped  // 1 per element segment once dropped / active
    ( Vec s ) argv  // *Arg — WASI program arguments (argv[0] = program)
    ( Vec s ) envp  // *Arg — WASI environment entries ("NAME=VALUE")
    ( Vec s ) fds  // *WFd — file-descriptor table (0/1/2 stdio, 3 preopen, …)
    b exited  // set after proc_exit
    i exit_code
    b trap
    ( Vec u ) trapmsg
    i pending_call  // callee set by call/call_indirect for the driver (-1 none)
    i max_depth  // frame-stack depth limit (trap when exceeded)
    i fuel  // remaining instruction budget (-1 = unlimited)
    b gpu_ok  // env/CUDA host imports enabled (opt-in; default off)
    b cap  // capture stdout/stderr into capout/caperr instead of the host streams
    ( Vec u ) capout  // captured module stdout (raw bytes, NULs preserved)
    ( Vec u ) caperr  // captured module stderr
    ( Vec s ) pfuncs  // *PFunc per defined function, predecoded lazily (#s 0 until first call)
}

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
//   [0] micro-op   (wasm opcodes for numeric/load/store arms; 300+ for the
//                  register/control forms — see the constants below)
//   [1..4] A B C D operands: slot indices, jump targets (record indices),
//                  immediates, packed move triples
//   [5] BYTE       the instruction's byte offset in the module image, for
//                  trap backtraces — the one thing byte positions are
//                  still good for
// `aux` holds br_table rows, 4 words per label: target, dst, src, n.
// Cold ops (floats, conversions, the 0xfc family) bridge through the old
// value stack: the record copies their operands from slots onto it.vs, runs
// the existing executor arm, and copies the result back — correctness
// identical, speed unchanged for them, and no duplicated semantics.
: PFunc { ( Vec i ) code ( Vec i ) aux i count i nlocals i nslots i nparams ( Vec s ) pool }

@ __page → i { ^ 65536 }

@ interp_new * Module m → *Interp {
    : *Interp it # *Interp ( nurl_alloc Z Interp )
    = . it mod # s m
    = . it pfuncs ( vec_new [s] )
    = . it vs ( vec_new [i] )
    = . it mem ( vec_new [u] )
    = . it mem_pages 0
    = . it globals ( vec_new [i] )
    = . it argv ( vec_new [s] )
    = . it envp ( vec_new [s] )
    = . it fds ( vec_new [s] )
    // fds 0/1/2 = stdin/stdout/stderr (kind 1); higher slots filled by preopen.
    : ~ i sfd 0
    ~ < sfd 3 { ( vec_push [s] . it fds # s ( __mkfd 1 ) ) = sfd + sfd 1 }
    = . it exited F
    = . it exit_code 0
    = . it trap F
    = . it trapmsg ( vec_new [u] )
    = . it pending_call -1
    = . it max_depth 65536
    = . it fuel -1
    = . it gpu_ok F
    = . it cap F
    = . it capout ( vec_new [u] )
    = . it caperr ( vec_new [u] )
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
        : i bytes * . m mem_min ( __page )
        : ~ i k 0
        ~ < k bytes { ( vec_push [u] . it mem # u 0 ) = k + k 1 }
        = . it mem_pages . m mem_min
        // copy active data segments into memory
        : i nd ( vec_len [s] . m datas )
        : ~ i di 0
        ~ < di nd {
            : s dp ?? ( vec_get [s] . m datas di ) { T x → x F → # s 0 }
            ? & != # i dp 0 == . # *DataSeg dp passive 0 {  // passive: memory.init only
                : *DataSeg ds # *DataSeg dp
                : i dn ( vec_len [u] . ds bytes )
                : ~ i bi 0
                ~ < bi dn {
                    : i tgt + . ds offset bi
                    ? < tgt ( vec_len [u] . it mem ) {
                        ( vec_set [u] . it mem tgt ?? ( vec_get [u] . ds bytes bi ) { T x → x F → # u 0 } )
                    } {}
                    = bi + bi 1
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

// Grant the module one preopened host directory, visible to it as `guest_name`
// (the path it resolves opens against). Installed as fd 3.
@ interp_set_preopen * Interp it s host_path s guest_name → v {
    : *WFd f # *WFd ( __mkfd 2 )
    ( vec_free [u] . f host ) = . f host ( bytes_from_str host_path )
    ( vec_free [u] . f name ) = . f name ( bytes_from_str guest_name )
    ( vec_push [s] . it fds # s f )
}

// Run the module's start-section function, if any — the final instantiation
// step, before any export is invoked.
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
    = . it trap T
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
// Read n bytes little-endian from mem[ea]; sign-extend when `signed` and n<8.
// One bounds check up front, then raw word access on the linear-memory
// buffer. The old body did a bounds-checked vec_get + Option unwrap PER
// BYTE — an i64.load was eight of each. Aligned 8- and 4-byte accesses are
// a single machine load; everything else extracts bytes from their
// containing words, still one raw load per byte and zero per-byte checks.
// The base pointer is re-fetched from the Vec every call (one dereference)
// so memory.grow can never leave a stale pointer behind.
@ __mem_load * Interp it i ea i n i signed → i {
    ? | < ea 0 > + ea n ( vec_len [u] . it mem ) {
        ( __trap it `memory load out of bounds` ) ^ 0
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
    } {
        : ~ i k 0
        ~ < k n {
            : i off + ea k
            : i w ( nurl_peek base >> off 3 )
            = v | v << & ( __lshr64 w * & off 7 8 ) 255 * 8 k
            = k + k 1
        }
    }
    ? & == signed 1 < n 8 {
        : i bits * 8 n
        ? != 0 & v << 1 - bits 1 { = v - v << 1 bits } {}
    } {}
    ^ v
}

// Write the low n bytes of val little-endian to mem[ea].
@ __mem_store * Interp it i ea i n i val → v {
    ? | < ea 0 > + ea n ( vec_len [u] . it mem ) {
        ( __trap it `memory store out of bounds` ) ^ v
    } {}
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

// Grow linear memory by `delta` pages. Returns the old page count, or −1 when
// the declared maximum (or the wasm32 hard limit of 65536 pages) would be
// exceeded — the value memory.grow pushes.
@ __mem_grow * Interp it i delta → i {
    : i old . it mem_pages
    ? == delta 0 { ^ old } {}
    : *Module m # *Module . it mod
    : ~ i limit 65536
    ? & > . m mem_max 0 < . m mem_max limit { = limit . m mem_max } {}
    ? | < delta 0 > + old delta limit { ^ -1 } {}
    : i add * delta ( __page )
    : ~ i k 0
    ~ < k add { ( vec_push [u] . it mem # u 0 ) = k + k 1 }
    = . it mem_pages + old delta
    ^ old
}

// Execute a memory instruction (0x28..0x40). memarg = align + offset ulebs.
// Register-form memory access: effective address in, value in/out. The
// memarg offset was u32-masked at predecode so `ea` cannot wrap negative
// past the bounds check in __mem_load/__mem_store.
@ __rload * Interp it i op i ea → i {
    ? == op 40 { ^ ( __w32 ( __mem_load it ea 4 0 ) ) } {}  // i32.load
    ? == op 41 { ^ ( __mem_load it ea 8 0 ) } {}  // i64.load
    ? == op 42 { ^ ( __mem_load it ea 4 0 ) } {}  // f32.load (raw pattern)
    ? == op 43 { ^ ( __mem_load it ea 8 0 ) } {}  // f64.load
    ? == op 44 { ^ ( __w32 ( __mem_load it ea 1 1 ) ) } {}  // i32.load8_s
    ? == op 45 { ^ ( __mem_load it ea 1 0 ) } {}  // i32.load8_u
    ? == op 46 { ^ ( __w32 ( __mem_load it ea 2 1 ) ) } {}  // i32.load16_s
    ? == op 47 { ^ ( __mem_load it ea 2 0 ) } {}  // i32.load16_u
    ? == op 48 { ^ ( __mem_load it ea 1 1 ) } {}  // i64.load8_s
    ? == op 49 { ^ ( __mem_load it ea 1 0 ) } {}  // i64.load8_u
    ? == op 50 { ^ ( __mem_load it ea 2 1 ) } {}  // i64.load16_s
    ? == op 51 { ^ ( __mem_load it ea 2 0 ) } {}  // i64.load16_u
    ? == op 52 { ^ ( __mem_load it ea 4 1 ) } {}  // i64.load32_s
    ^ ( __mem_load it ea 4 0 )  // 53 i64.load32_u
}

@ __rstore * Interp it i op i ea i val → v {
    ? == op 54 { ( __mem_store it ea 4 val ) ^ v } {}  // i32.store
    ? == op 55 { ( __mem_store it ea 8 val ) ^ v } {}  // i64.store
    ? == op 56 { ( __mem_store it ea 4 val ) ^ v } {}  // f32.store
    ? == op 57 { ( __mem_store it ea 8 val ) ^ v } {}  // f64.store
    ? == op 58 { ( __mem_store it ea 1 val ) ^ v } {}  // i32.store8
    ? == op 59 { ( __mem_store it ea 2 val ) ^ v } {}  // i32.store16
    ? == op 60 { ( __mem_store it ea 1 val ) ^ v } {}  // i64.store8
    ? == op 61 { ( __mem_store it ea 2 val ) ^ v } {}  // i64.store16
    ( __mem_store it ea 4 val )  // 62 i64.store32
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
    : s fp ?? ( vec_get [s] . m funcs - fidx . m num_import_funcs ) { T x → x F → # s 0 }
    ? == # i fp 0 { ( __trap it `bad function index` ) ^ # s 0 } {}
    : *WFunc f # *WFunc fp
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
            : s rb # s ( vec_data [i] . rfr regs )
            : ~ i zk . pfc nparams
            ~ < zk . pfc nlocals { ( nurl_poke rb zk 0 ) = zk + zk 1 }
            = . rfr pos 0
            = . rfr ret_dst ret_dst
            ? < ret_dst 0 {
                : s tp0 ?? ( vec_get [s] . m types . f typeidx ) { T x → x F → # s 0 }
                ? != # i tp0 0 {
                    : *FuncType ft0 # *FuncType tp0
                    : ~ i pk0 ( vec_len [i] . ft0 params )
                    ~ > pk0 0 { = pk0 - pk0 1 ( nurl_poke rb pk0 ( __pop it ) ) }
                } {}
            } {}
            ^ rf
        } {}
    } {}
    : ( Vec i ) regs ( vec_new [i] )
    : ~ i k 0
    ~ < k . pfc nslots { ( vec_push [i] regs 0 ) = k + k 1 }
    ? < ret_dst 0 {
        // outermost: pop the arguments off the value stack, last first
        : s tp ?? ( vec_get [s] . m types . f typeidx ) { T x → x F → # s 0 }
        ? != # i tp 0 {
            : *FuncType ft # *FuncType tp
            : ~ i pk ( vec_len [i] . ft params )
            ~ > pk 0 { = pk - pk 1 ( vec_set [i] regs pk ( __pop it ) ) }
        } {}
    } {}
    : *Frame fr # *Frame ( nurl_alloc Z Frame )
    = . fr fidx fidx
    = . fr regs regs
    = . fr pos 0
    = . fr end . pfc count
    = . fr code_start . f code_start
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
    ( nurl_free # s pf )
}

// ── the register-form micro-ops (record slot [0]) ────────────────
// Numeric, load and store records keep their wasm opcode; everything that
// changed shape in register form gets a number ≥ 300 so the two spaces can
// never collide.
@ __R_MOV → i { ^ 300 }  // A=dst B=src
@ __R_CONST → i { ^ 301 }  // A=dst B=imm (f32/f64 consts carry raw bits)
@ __R_GG → i { ^ 302 }  // global.get: A=dst B=gidx
@ __R_GS → i { ^ 303 }  // global.set: A=gidx B=src
@ __R_SEL → i { ^ 304 }  // A=dst B=srcT C=srcF D=cond
@ __R_MEMSZ → i { ^ 305 }  // A=dst
@ __R_MEMGROW → i { ^ 306 }  // A=dst B=src
@ __R_TABGET → i { ^ 307 }  // A=dst B=idxslot
@ __R_TABSET → i { ^ 308 }  // A=idxslot B=valslot
@ __R_ISNULL → i { ^ 309 }  // A=dst B=src
@ __R_BR → i { ^ 310 }  // A=target
@ __R_BRM → i { ^ 311 }  // A=target B=dst C=src D=n
@ __R_BRIF → i { ^ 312 }  // A=target B=cond
@ __R_BRIFM → i { ^ 313 }  // A=target B=cond C=dst<<20|src D=n
@ __R_BRTBL → i { ^ 314 }  // A=aux base B=idxslot C=n labels (default row last)
@ __R_RET → i { ^ 315 }  // A=src base B=n results
@ __R_CALL → i { ^ 316 }  // A=fidx B=argbase (args in, results out)
@ __R_CALLIND → i { ^ 317 }  // A=typeidx B=argbase C=idxslot
@ __R_UNREACH → i { ^ 318 }

@ __R_TRAPUN → i { ^ 319 }  // unsupported opcode (0xfd/0xfe/unknown)
@ __R_FLOATB → i { ^ 320 }  // vs bridge: A=wasm op B=srcbase C=npops (dst=srcbase)
@ __R_FCB → i { ^ 321 }  // vs bridge: A=sub B=idx-imm C=srcbase D=pops<<1|push
@ __R_IFZ → i { ^ 322 }  // A=target B=cond — jump when cond == 0

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

// Emit a branch to label depth `k` (top of `open` = depth 0). `cond` is the
// condition slot for br_if (-1 = unconditional). `h` is the height AFTER any
// condition pop. Fills patch sites for forward targets. Returns nothing; the
// caller handles liveness.
@ __emit_branch * PFunc pf ( Vec s ) open i k i cond i L i h i byte → v {
    : i n ( vec_len [s] open )
    ? >= k n { ( __pf_emit . pf code ( __R_TRAPUN ) 0 0 0 0 byte ) ^ v } {}
    : s bp ?? ( vec_get [s] open - - n 1 k ) { T x → x F → # s 0 }
    ? == # i bp 0 { ( __pf_emit . pf code ( __R_TRAPUN ) 0 0 0 0 byte ) ^ v } {}
    : *PBlk blk # *PBlk bp
    : i arity ? == . blk kind 1 . blk params . blk results
    : i dst + L . blk base
    : i src + L - h arity
    : i tgt ? == . blk kind 1 . blk t0 -1
    : ~ i rec 0
    ? | == arity 0 == dst src {
        ? < cond 0 { = rec ( __pf_emit . pf code ( __R_BR ) tgt 0 0 0 byte ) }
        { = rec ( __pf_emit . pf code ( __R_BRIF ) tgt cond 0 0 byte ) }
    } {
        ? < cond 0 { = rec ( __pf_emit . pf code ( __R_BRM ) tgt dst src arity byte ) }
        { = rec ( __pf_emit . pf code ( __R_BRIFM ) tgt cond | << dst 20 src arity byte ) }
    }
    ? != . blk kind 1 { ( vec_push [i] . blk patches * rec 2 ) } {}
}

// ── the predecoder ───────────────────────────────────────────────
// One linear pass with an abstract stack height `h`: every reachable
// instruction knows exactly where its operands live, so records carry
// absolute slot indices. Code made unreachable by br/return/unreachable is
// parsed structurally (blocks still nest, immediates still skipped — record
// alignment survives hostile bytes exactly as before) but emits nothing;
// heights resume at the statically-known values at `else` and `end`.
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
    : ( Vec s ) open ( vec_new [s] )
    // the function body behaves as one enclosing block returning the results
    ( vec_push [s] open ( __pblk_new 0 0 0 nresults 1 -1 ) )
    : *Wc c ( wc_new . m code )
    = . c pos . f code_start
    = . c len . f code_end
    : ~ i h 0
    : ~ i maxh 0
    : ~ i live 1
    ~ & < . c pos . f code_end > ( vec_len [s] open ) 0 {
        : i byte . c pos
        : i op ( wc_u8 c )
        ? | == op 2 == op 3 {  // block / loop
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
                    : i rec ( __pf_emit . pf code ( __R_IFZ ) -1 + L h 0 0 byte )
                    : s kp ( __pblk_new 2 - h p p r 1 rec )
                    ( vec_push [s] open kp )
                } { ( vec_push [s] open ( __pblk_new 2 h p r 0 -1 ) ) }
            } {
                ? == op 5 {  // else
                    : i n ( vec_len [s] open )
                    : s bp ?? ( vec_get [s] open - n 1 ) { T x → x F → # s 0 }
                    ? != # i bp 0 {
                        : *PBlk blk # *PBlk bp
                        ? != 0 . blk live_entry {
                            // end of a live then-arm jumps past the else arm
                            ? != 0 live { = . blk else_br ( __pf_emit . pf code ( __R_BR ) -1 0 0 0 byte ) } {}
                            // the cond==0 edge lands here
                            ? >= . blk t0 0 { ( vec_set [i] . pf code + * . blk t0 6 1 / ( vec_len [i] . pf code ) 6 ) = . blk t0 -1 } {}
                            = h + . blk base . blk params
                            = live 1
                        } {}
                    } {}
                } {
                    ? == op 11 {  // end: close the frame, patch all forward targets here
                        : i n ( vec_len [s] open )
                        : s bp ?? ( vec_get [s] open - n 1 ) { T x → x F → # s 0 }
                        ( vec_pop [s] open )
                        ? != # i bp 0 {
                            : *PBlk blk # *PBlk bp
                            : i here / ( vec_len [i] . pf code ) 6
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
                            ? != 0 live { ( __emit_branch pf open k -1 L h byte ) = live 0 } {}
                        } {
                            ? == op 13 {  // br_if: pop cond, branch on it, fall through otherwise
                                : i k ( wc_uleb c )
                                ? != 0 live {
                                    = h - h 1
                                    ( __emit_branch pf open k + L h L h byte )
                                } {}
                            } {
                                ? == op 14 {  // br_table
                                    : i nl ( wc_uleb c )
                                    ? == 0 live { : ~ i sk 0 ~ <= sk nl { ( wc_uleb c ) = sk + sk 1 } } {
                                        = h - h 1
                                        : i astart ( vec_len [i] . pf aux )
                                        : i non ( vec_len [s] open )
                                        : ~ i lk 0
                                        ~ <= lk nl {
                                            : i dep ( wc_uleb c )
                                            ? >= dep non { ( vec_push [i] . pf aux -1 ) ( vec_push [i] . pf aux 0 ) ( vec_push [i] . pf aux 0 ) ( vec_push [i] . pf aux 0 ) } {
                                                : s bp2 ?? ( vec_get [s] open - - non 1 dep ) { T x → x F → # s 0 }
                                                : *PBlk b2 # *PBlk bp2
                                                : i ar ? == . b2 kind 1 . b2 params . b2 results
                                                : i tg ? == . b2 kind 1 . b2 t0 -1
                                                : i auxpos ( vec_len [i] . pf aux )
                                                ( vec_push [i] . pf aux tg )
                                                ( vec_push [i] . pf aux + L . b2 base )
                                                ( vec_push [i] . pf aux + L - h ar )
                                                ( vec_push [i] . pf aux ar )
                                                ? != . b2 kind 1 { ( vec_push [i] . b2 patches + * auxpos 2 1 ) } {}
                                            }
                                            = lk + lk 1
                                        }
                                        ( __pf_emit . pf code ( __R_BRTBL ) astart + L h nl 0 byte )
                                        = live 0
                                    }
                                } {
                                    ? == op 15 {  // return
                                        ? != 0 live {
                                            ( __pf_emit . pf code ( __R_RET ) + L - h nresults nresults 0 0 byte )
                                            = live 0
                                        } {}
                                    } {
                                        ? == op 16 {  // call
                                            : i fi ( wc_uleb c )
                                            ? != 0 live {
                                                : s ct ( module_func_type m fi )
                                                : ~ i cp 0
                                                : ~ i cr 0
                                                ? != # i ct 0 { : *FuncType ctt # *FuncType ct = cp ( vec_len [i] . ctt params ) = cr ( vec_len [i] . ctt results ) } {}
                                                ( __pf_emit . pf code ( __R_CALL ) fi + L - h cp 0 0 byte )
                                                = h + - h cp cr
                                                ? > h maxh { = maxh h } {}
                                            } {}
                                        } {
                                            ? == op 17 {  // call_indirect
                                                : i ti ( wc_uleb c ) ( wc_uleb c )
                                                ? != 0 live {
                                                    = h - h 1
                                                    : s ct ?? ( vec_get [s] . m types ti ) { T x → x F → # s 0 }
                                                    : ~ i cp 0
                                                    : ~ i cr 0
                                                    ? != # i ct 0 { : *FuncType ctt # *FuncType ct = cp ( vec_len [i] . ctt params ) = cr ( vec_len [i] . ctt results ) } {}
                                                    ( __pf_emit . pf code ( __R_CALLIND ) ti + L - h cp + L h 0 byte )
                                                    = h + - h cp cr
                                                    ? > h maxh { = maxh h } {}
                                                } {}
                                            } {
                                                ? == op 0 { ? != 0 live { ( __pf_emit . pf code ( __R_UNREACH ) 0 0 0 0 byte ) = live 0 } {} } {
                                                    ? == op 1 {} {  // nop
                                                        ? == op 26 { ? != 0 live { = h - h 1 } {} } {  // drop
                                                            ? | == op 27 == op 28 {  // select (typed select folds to the same record)
                                                                ? == op 28 { : i tc ( wc_uleb c ) ( wc_skip c tc ) } {}
                                                                ? != 0 live {
                                                                    ( __pf_emit . pf code ( __R_SEL ) + L - h 3 + L - h 3 + L - h 2 + L - h 1 byte )
                                                                    = h - h 2
                                                                } {}
                                                            } {
                                                                ? == op 32 { : i li ( wc_uleb c ) ? != 0 live { ( __pf_emit . pf code ( __R_MOV ) + L h li 0 0 byte ) = h + h 1 ? > h maxh { = maxh h } {} } {} } {
                                                                    ? == op 33 { : i li ( wc_uleb c ) ? != 0 live { ( __pf_emit . pf code ( __R_MOV ) li + L - h 1 0 0 byte ) = h - h 1 } {} } {
                                                                        ? == op 34 { : i li ( wc_uleb c ) ? != 0 live { ( __pf_emit . pf code ( __R_MOV ) li + L - h 1 0 0 byte ) } {} } {
                                                                            ? == op 35 { : i gi ( wc_uleb c ) ? != 0 live { ( __pf_emit . pf code ( __R_GG ) + L h gi 0 0 byte ) = h + h 1 ? > h maxh { = maxh h } {} } {} } {
                                                                                ? == op 36 { : i gi ( wc_uleb c ) ? != 0 live { ( __pf_emit . pf code ( __R_GS ) gi + L - h 1 0 0 byte ) = h - h 1 } {} } {
                                                                                    ? == op 37 { ( wc_uleb c ) ? != 0 live { ( __pf_emit . pf code ( __R_TABGET ) + L - h 1 + L - h 1 0 0 byte ) } {} } {
                                                                                        ? == op 38 { ( wc_uleb c ) ? != 0 live { ( __pf_emit . pf code ( __R_TABSET ) + L - h 2 + L - h 1 0 0 byte ) = h - h 2 } {} } {
                                                                                            ? == op 65 { : i cv ( wc_sleb c ) ? != 0 live { ( __pf_emit . pf code ( __R_CONST ) + L h ( __w32 cv ) 0 0 byte ) = h + h 1 ? > h maxh { = maxh h } {} } {} } {
                                                                                                ? == op 66 { : i cv ( wc_sleb c ) ? != 0 live { ( __pf_emit . pf code ( __R_CONST ) + L h cv 0 0 byte ) = h + h 1 ? > h maxh { = maxh h } {} } {} } {
                                                                                                    ? == op 67 { : i cv ( __read_le c 4 ) ? != 0 live { ( __pf_emit . pf code ( __R_CONST ) + L h cv 0 0 byte ) = h + h 1 ? > h maxh { = maxh h } {} } {} } {
                                                                                                        ? == op 68 { : i cv ( __read_le c 8 ) ? != 0 live { ( __pf_emit . pf code ( __R_CONST ) + L h cv 0 0 byte ) = h + h 1 ? > h maxh { = maxh h } {} } {} } {
                                                                                                            ? & >= op 40 <= op 53 {  // loads: A=dst B=addr C=off
                                                                                                                ( wc_uleb c )
                                                                                                                : i off & ( wc_uleb c ) 4294967295
                                                                                                                ? != 0 live { ( __pf_emit . pf code op + L - h 1 + L - h 1 off 0 byte ) } {}
                                                                                                            } {
                                                                                                                ? & >= op 54 <= op 62 {  // stores: A=addr B=val C=off
                                                                                                                    ( wc_uleb c )
                                                                                                                    : i off & ( wc_uleb c ) 4294967295
                                                                                                                    ? != 0 live { ( __pf_emit . pf code op + L - h 2 + L - h 1 off 0 byte ) = h - h 2 } {}
                                                                                                                } {
                                                                                                                    ? == op 63 { ( wc_u8 c ) ? != 0 live { ( __pf_emit . pf code ( __R_MEMSZ ) + L h 0 0 0 byte ) = h + h 1 ? > h maxh { = maxh h } {} } {} } {
                                                                                                                        ? == op 64 { ( wc_u8 c ) ? != 0 live { ( __pf_emit . pf code ( __R_MEMGROW ) + L - h 1 + L - h 1 0 0 byte ) } {} } {
                                                                                                                            ? | == op 69 | == op 80 | & >= op 103 <= op 105 | & >= op 121 <= op 123 & >= op 192 <= op 196 {
                                                                                                                                // integer unary: in place at the top slot
                                                                                                                                ? != 0 live { ( __pf_emit . pf code op + L - h 1 + L - h 1 0 0 byte ) } {}
                                                                                                                            } {
                                                                                                                                ? | & >= op 70 <= op 79 | & >= op 81 <= op 90 | & >= op 106 <= op 120 & >= op 124 <= op 138 {
                                                                                                                                    // integer binary: dst = h-2, operands h-2 / h-1
                                                                                                                                    ? != 0 live { ( __pf_emit . pf code op + L - h 2 + L - h 2 + L - h 1 0 byte ) = h - h 1 } {}
                                                                                                                                } {
                                                                                                                                    ? | & >= op 91 <= op 102 & >= op 139 <= op 191 {  // float / conversion: vs bridge
                                                                                                                                        ? != 0 live {
                                                                                                                                            : i np ( __float_pops op )
                                                                                                                                            ( __pf_emit . pf code ( __R_FLOATB ) op + L - h np np 0 byte )
                                                                                                                                            = h + - h np 1
                                                                                                                                            ? > h maxh { = maxh h } {}
                                                                                                                                        } {}
                                                                                                                                    } {
                                                                                                                                        ? == op 208 { ( wc_u8 c ) ? != 0 live { ( __pf_emit . pf code ( __R_CONST ) + L h -1 0 0 byte ) = h + h 1 ? > h maxh { = maxh h } {} } {} } {
                                                                                                                                            ? == op 209 { ? != 0 live { ( __pf_emit . pf code ( __R_ISNULL ) + L - h 1 + L - h 1 0 0 byte ) } {} } {
                                                                                                                                                ? == op 210 { : i rfi ( wc_uleb c ) ? != 0 live { ( __pf_emit . pf code ( __R_CONST ) + L h rfi 0 0 byte ) = h + h 1 ? > h maxh { = maxh h } {} } {} } {
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
                                                                                                                                                            ( __pf_emit . pf code ( __R_FCB ) sub bop + L - h pops | << pops 1 push byte )
                                                                                                                                                            = h + - h pops push
                                                                                                                                                            ? > h maxh { = maxh h } {}
                                                                                                                                                        } {}
                                                                                                                                                    } {
                                                                                                                                                        // unsupported (0xfd/0xfe and anything unknown): keep alignment,
                                                                                                                                                        // trap if ever executed
                                                                                                                                                        ? | == op 253 == op 254 { ( __skip_imm c op ) } {}
                                                                                                                                                        ? != 0 live { ( __pf_emit . pf code ( __R_TRAPUN ) 0 0 0 0 byte ) } {}
                                                                                                                                                    } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } } }
    }
    : i on ( vec_len [s] open )
    : ~ i ok 0
    ~ < ok on { ?? ( vec_get [s] open ok ) { T pp → ( __pblk_free pp ) F → {} } = ok + ok 1 }
    ( vec_free [s] open )
    ( wc_free c )
    = . pf count / ( vec_len [i] . pf code ) 6
    = . pf nslots + L + maxh 4
    = . pf nparams nparams
    = . pf pool ( vec_new [s] )
    ^ # s pf
}
// Get-or-build the PFunc for defined function `fidx`.
@ __pfunc_for * Interp it * Module m i fidx → s {
    : i di - fidx . m num_import_funcs
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
            // fr.pos is a record index; the record's BYTE slot maps it back
            // to the module image so the offset stays meaningful against a
            // wasm-objdump of the file. pos can sit one past the last record
            // (fell off the end) — clamp before reading.
            : *PFunc bpf # *PFunc . fr pins
            : ~ i bpos . fr pos
            ? >= bpos . bpf count { = bpos - . bpf count 1 } {}
            : ~ i boff 0
            ? >= bpos 0 { = boff - ?? ( vec_get [i] . bpf code + * bpos 6 5 ) { T x → x F → . fr code_start } . fr code_start } {}
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
@ exec_func * Interp it i fidx → v {
    ? | . it trap . it exited { ^ v } {}
    : *Module m # *Module . it mod
    // Imported functions occupy the low indices → dispatch to the host (WASI).
    ? < fidx . m num_import_funcs { ( __call_import it m fidx ) ^ v } {}
    : ( Vec s ) frames ( vec_new [s] )
    : s fr0 ( __frame_new it m fidx -1 )
    ? != # i fr0 0 { ( vec_push [s] frames fr0 ) } {}
    : *Wc c ( wc_new . m code )
    // Register-form driver. The cursor is the pc in record units; `rbase` is
    // the raw base of the top frame's flat register array (locals first,
    // stack slots after), refreshed only when the frame stack moves. Every
    // hot op is three raw word accesses: read operands, write the result.
    // There is no runtime control stack — branches carry their targets and
    // their statically-computed result moves in the record.
    : ~ s tp # s 0
    : ~ s pbase # s 0
    : ~ s abase # s 0
    : ~ s rbase # s 0
    : ~ i lloc 0
    : ~ i reload 1
    ~ & & > ( vec_len [s] frames ) 0 ! . it exited ! . it trap {
        ? != reload 0 {
            = tp ?? ( vec_get [s] frames - ( vec_len [s] frames ) 1 ) { T x → x F → # s 0 }
            : *Frame nfr # *Frame tp
            : *PFunc npf # *PFunc . nfr pins
            = pbase # s ( vec_data [i] . npf code )
            = abase # s ( vec_data [i] . npf aux )
            = rbase # s ( vec_data [i] . nfr regs )
            = lloc . npf nlocals
            = . c pos . nfr pos
            = . c len . nfr end
            = reload 0
        } {}
        : *Frame fr # *Frame tp
        ? >= . c pos . c len {
            // fell off the end → return: results sit at slots lloc.. by
            // construction (the body ends at height = result count)
            : s ct ( module_func_type m . fr fidx )
            : ~ i nres 0
            ? != # i ct 0 { : *FuncType ctt # *FuncType ct = nres ( vec_len [i] . ctt results ) } {}
            : i rdst . fr ret_dst
            ( vec_pop [s] frames )
            ? < rdst 0 {
                // outermost frame: results leave on the value stack
                : ~ i rk 0
                ~ < rk nres { ( __push it ( nurl_peek rbase + lloc rk ) ) = rk + rk 1 }
            } {
                : s cp2 ?? ( vec_get [s] frames - ( vec_len [s] frames ) 1 ) { T x → x F → # s 0 }
                ? != # i cp2 0 {
                    : *Frame cfr # *Frame cp2
                    : s crb # s ( vec_data [i] . cfr regs )
                    : ~ i rk 0
                    ~ < rk nres { ( nurl_poke crb + rdst rk ( nurl_peek rbase + lloc rk ) ) = rk + rk 1 }
                } {}
            }
            ( __frame_recycle tp )
            = reload 1
        } {
            ? == . it fuel 0 { ( __trap it `fuel exhausted` ) } {
                ? > . it fuel 0 { = . it fuel - . it fuel 1 } {}
                : i rrec * . c pos 6
                : i op ( nurl_peek pbase rrec )
                : i ra ( nurl_peek pbase + rrec 1 )
                : i rb ( nurl_peek pbase + rrec 2 )
                : i rc ( nurl_peek pbase + rrec 3 )
                = . c pos + . c pos 1
                // ── hot register ops, inline ──
                ? == op 300 { ( nurl_poke rbase ra ( nurl_peek rbase rb ) ) } {  // MOV
                    ? == op 301 { ( nurl_poke rbase ra rb ) } {  // CONST
                        ? & >= op 124 <= op 138 {  // i64 arithmetic/bitwise
                            : i x ( nurl_peek rbase rb )
                            : i y ( nurl_peek rbase rc )
                            ( nurl_poke rbase ra ( __rnum64 it op x y ) )
                        } {
                            ? & >= op 106 <= op 120 {  // i32 arithmetic/bitwise
                                : i x ( nurl_peek rbase rb )
                                : i y ( nurl_peek rbase rc )
                                ( nurl_poke rbase ra ( __rnum32 it op x y ) )
                            } {
                                ? | & >= op 70 <= op 79 & >= op 81 <= op 90 {  // comparisons
                                    : i x ( nurl_peek rbase rb )
                                    : i y ( nurl_peek rbase rc )
                                    ( nurl_poke rbase ra ( __rcmp op x y ) )
                                } {
                                    ? == op 322 { ? == ( nurl_peek rbase rb ) 0 { = . c pos ra } {} } {  // IFZ
                                        ? == op 310 { = . c pos ra } {  // BR
                                            ? == op 312 { ? != ( nurl_peek rbase rb ) 0 { = . c pos ra } {} } {  // BRIF
                                                ? == op 311 {  // BR_MOVE
                                                    : i dd ( nurl_peek pbase + rrec 4 )
                                                    : ~ i mk 0
                                                    ~ < mk dd { ( nurl_poke rbase + rb mk ( nurl_peek rbase + rc mk ) ) = mk + mk 1 }
                                                    = . c pos ra
                                                } {
                                                    ? == op 313 {  // BRIF_MOVE
                                                        ? != ( nurl_peek rbase rb ) 0 {
                                                            : i dd ( nurl_peek pbase + rrec 4 )
                                                            : i mdst >> rc 20
                                                            : i msrc & rc 1048575
                                                            : ~ i mk 0
                                                            ~ < mk dd { ( nurl_poke rbase + mdst mk ( nurl_peek rbase + msrc mk ) ) = mk + mk 1 }
                                                            = . c pos ra
                                                        } {}
                                                    } {
                                                        ? & >= op 40 <= op 53 {  // loads
                                                            : i ea + & ( nurl_peek rbase rb ) 4294967295 rc
                                                            ( nurl_poke rbase ra ( __rload it op ea ) )
                                                        } {
                                                            ? & >= op 54 <= op 62 {  // stores
                                                                : i ea + & ( nurl_peek rbase ra ) 4294967295 rc
                                                                ( __rstore it op ea ( nurl_peek rbase rb ) )
                                                            } {
                                                                ? | == op 69 == op 80 { : i x ( nurl_peek rbase rb ) ( nurl_poke rbase ra ? == x 0 1 0 ) } {  // eqz
                                                                    ? | & >= op 103 <= op 105 | & >= op 121 <= op 123 & >= op 192 <= op 196 {
                                                                        ( nurl_poke rbase ra ( __runary op ( nurl_peek rbase rb ) ) )
                                                                    } {
                                                                        ? == op 304 {  // SELECT
                                                                            : i dd ( nurl_peek pbase + rrec 4 )
                                                                            : i cond ( nurl_peek rbase dd )
                                                                            ( nurl_poke rbase ra ? != cond 0 ( nurl_peek rbase rb ) ( nurl_peek rbase rc ) )
                                                                        } {
                                                                            ? == op 316 {  // CALL
                                                                                = . fr pos . c pos
                                                                                ( __rdo_call it m frames ra rb rbase )
                                                                                = reload 1
                                                                            } {
                                                                                ? == op 317 {  // CALL_INDIRECT
                                                                                    : i ei & ( nurl_peek rbase rc ) 4294967295
                                                                                    ? | < ei 0 >= ei ( vec_len [i] . it table ) { ( __trap it `call_indirect: index out of range` ) } {
                                                                                        : i cfi ?? ( vec_get [i] . it table ei ) { T x → x F → -1 }
                                                                                        ? < cfi 0 { ( __trap it `call_indirect: null table element` ) } {
                                                                                            : s want ?? ( vec_get [s] . m types ra ) { T x → x F → # s 0 }
                                                                                            : s have ( module_func_type m cfi )
                                                                                            ? | == # i want 0 == # i have 0 { ( __trap it `call_indirect: bad type index` ) } {
                                                                                                ? ! ( functype_eq # *FuncType want # *FuncType have ) { ( __trap it `call_indirect: signature mismatch` ) } {
                                                                                                    = . fr pos . c pos
                                                                                                    ( __rdo_call it m frames cfi rb rbase )
                                                                                                    = reload 1
                                                                                                }
                                                                                            }
                                                                                        }
                                                                                    }
                                                                                } {
                                                                                    ? == op 315 {  // RETURN: move results to the canonical slots, fall off
                                                                                        : ~ i rk 0
                                                                                        ~ < rk rb { ( nurl_poke rbase + lloc rk ( nurl_peek rbase + ra rk ) ) = rk + rk 1 }
                                                                                        = . c pos . c len
                                                                                    } {
                                                                                        ? == op 314 {  // BR_TABLE: aux rows of (target, dst, src, n)
                                                                                            : i ui ( __u32 ( nurl_peek rbase rb ) )
                                                                                            : i pick ? < ui rc ui rc
                                                                                            : i rowb + ra * pick 4
                                                                                            : i tgt ( nurl_peek abase rowb )
                                                                                            : i mdst ( nurl_peek abase + rowb 1 )
                                                                                            : i msrc ( nurl_peek abase + rowb 2 )
                                                                                            : i mn ( nurl_peek abase + rowb 3 )
                                                                                            : ~ i mk 0
                                                                                            ~ < mk mn { ( nurl_poke rbase + mdst mk ( nurl_peek rbase + msrc mk ) ) = mk + mk 1 }
                                                                                            = . c pos tgt
                                                                                        } {
                                                                                            ? == op 302 { ( nurl_poke rbase ra ?? ( vec_get [i] . it globals rb ) { T x → x F → 0 } ) } {  // global.get
                                                                                                ? == op 303 { ( vec_set [i] . it globals ra ( nurl_peek rbase rb ) ) } {  // global.set
                                                                                                    ? == op 305 { ( nurl_poke rbase ra . it mem_pages ) } {  // memory.size
                                                                                                        ? == op 306 { ( nurl_poke rbase ra ( __mem_grow it ( __u32 ( nurl_peek rbase rb ) ) ) ) } {  // memory.grow
                                                                                                            ? == op 307 {  // table.get
                                                                                                                : i ei ( __u32 ( nurl_peek rbase rb ) )
                                                                                                                ? >= ei ( vec_len [i] . it table ) { ( __trap it `out of bounds table access` ) } {
                                                                                                                    ( nurl_poke rbase ra ?? ( vec_get [i] . it table ei ) { T x → x F → -1 } ) }
                                                                                                            } {
                                                                                                                ? == op 308 {  // table.set
                                                                                                                    : i ei ( __u32 ( nurl_peek rbase ra ) )
                                                                                                                    ? >= ei ( vec_len [i] . it table ) { ( __trap it `out of bounds table access` ) } {
                                                                                                                        ( vec_set [i] . it table ei ( nurl_peek rbase rb ) ) }
                                                                                                                } {
                                                                                                                    ? == op 309 { ( nurl_poke rbase ra ? == ( nurl_peek rbase rb ) -1 1 0 ) } {  // ref.is_null
                                                                                                                        ? == op 320 {  // float / conversion bridge through the value stack
                                                                                                                            : ~ i bk 0
                                                                                                                            ~ < bk rc { ( __push it ( nurl_peek rbase + rb bk ) ) = bk + bk 1 }
                                                                                                                            ( __exec_float it ra )
                                                                                                                            ? ! . it trap { ( nurl_poke rbase rb ( __pop it ) ) } {}
                                                                                                                        } {
                                                                                                                            ? == op 321 {  // 0xfc bridge through the value stack
                                                                                                                                : i dd ( nurl_peek pbase + rrec 4 )
                                                                                                                                : i pops >> dd 1
                                                                                                                                : ~ i bk 0
                                                                                                                                ~ < bk pops { ( __push it ( nurl_peek rbase + rc bk ) ) = bk + bk 1 }
                                                                                                                                ( __exec_fc it ra rb )
                                                                                                                                ? & != 0 & dd 1 ! . it trap { ( nurl_poke rbase rc ( __pop it ) ) } {}
                                                                                                                            } {
                                                                                                                                ? == op 318 { ( __trap it `unreachable` ) } {
                                                                                                                                    ? == op 319 { ( __trap it `unsupported opcode` ) } {
                                                                                                                                        ( __trap it `unsupported opcode` )
                                                                                                                                    } } } } } } } } } } } } } } } } } } } } } } } } } } } } } }
            }
        }
    }
    ? . it trap {
        ? & == reload 0 > ( vec_len [s] frames ) 0 {
            : s ttp ?? ( vec_get [s] frames - ( vec_len [s] frames ) 1 ) { T x → x F → # s 0 }
            ? != # i ttp 0 { : *Frame ftr # *Frame ttp = . ftr pos - . c pos 1 } {}
        } {}
        ( __trap_backtrace it m frames )
    } {}
    : i fn ( vec_len [s] frames )
    : ~ i fi 0
    ~ < fi fn { ?? ( vec_get [s] frames fi ) { T pp → ( __frame_free pp ) F → {} } = fi + fi 1 }
    ( vec_free [s] frames )
    ( wc_free c )
}

// Perform a call from the register driver: `argbase` is the caller slot of
// the first argument (and the destination of the results). Imports bridge
// through the value stack; defined functions get a fresh frame with the
// arguments copied straight into their first locals.
@ __rdo_call * Interp it * Module m ( Vec s ) frames i callee i argbase s caller_rbase → v {
    ? < callee . m num_import_funcs {
        : s wt ( module_func_type m callee )
        : ~ i np 0
        : ~ i nr 0
        ? != # i wt 0 { : *FuncType wft # *FuncType wt = np ( vec_len [i] . wft params ) = nr ( vec_len [i] . wft results ) } {}
        : ~ i ak 0
        ~ < ak np { ( __push it ( nurl_peek caller_rbase + argbase ak ) ) = ak + ak 1 }
        ( __call_import it m callee )
        ? ! . it trap {
            : ~ i rk nr
            ~ > rk 0 { = rk - rk 1 ( nurl_poke caller_rbase + argbase rk ( __pop it ) ) }
        } {}
        ^ v
    } {}
    ? >= ( vec_len [s] frames ) . it max_depth { ( __trap it `call stack exhausted` ) ^ v } {}
    : s nf ( __frame_new it m callee argbase )
    ? == # i nf 0 { ^ v } {}
    : *Frame nfr # *Frame nf
    : s nrb # s ( vec_data [i] . nfr regs )
    : s ct ( module_func_type m callee )
    : ~ i np 0
    ? != # i ct 0 { : *FuncType ctt # *FuncType ct = np ( vec_len [i] . ctt params ) } {}
    : ~ i ak 0
    ~ < ak np { ( nurl_poke nrb ak ( nurl_peek caller_rbase + argbase ak ) ) = ak + ak 1 }
    ( vec_push [s] frames nf )
}

// Value-form integer executors for the register core: operands in, result
// out, traps via `it`. Ported arm-for-arm from the old stack-form
// __exec_num; the semantics comments live with the arms.

@ __rnum64 * Interp it i op i a i b → i {  // 0x7c..0x8a
    ? == op 124 { ^ + a b } {}
    ? == op 125 { ^ - a b } {}
    ? == op 126 { ^ * a b } {}
    ? == op 127 { ^ ( __div_s it a b -9223372036854775808 ) } {}
    ? == op 128 { ? == b 0 { ( __trap it `integer divide by zero` ) ^ 0 } {} ^ ( __udiv64 a b ) } {}  // div_u
    ? == op 129 { ^ ( __rem_s it a b ) } {}
    ? == op 130 { ? == b 0 { ( __trap it `integer divide by zero` ) ^ 0 } {} ^ ( __urem64 a b ) } {}  // rem_u
    ? == op 131 { ^ & a b } {}
    ? == op 132 { ^ | a b } {}
    ? == op 133 { ^ ^^ a b } {}
    ? == op 134 { ^ << a & b 63 } {}
    ? == op 135 { ^ >> a & b 63 } {}  // shr_s
    ? == op 136 { ^ ( __lshr64 a & b 63 ) } {}  // shr_u
    ? == op 137 { ^ ( __rotl64 a b ) } {}  // rotl
    ^ ( __rotr64 a b )  // 138 rotr
}

@ __rnum32 * Interp it i op i a i b → i {  // 0x6a..0x78 → wrap 32
    ? == op 106 { ^ ( __w32 + a b ) } {}
    ? == op 107 { ^ ( __w32 - a b ) } {}
    ? == op 108 { ^ ( __w32 * a b ) } {}
    ? == op 109 { ^ ( __w32 ( __div_s it ( __w32 a ) ( __w32 b ) -2147483648 ) ) } {}
    ? == op 110 { ^ ( __w32 ( __div_u it ( __u32 a ) ( __u32 b ) ) ) } {}  // div_u
    ? == op 111 { ^ ( __w32 ( __rem_s it ( __w32 a ) ( __w32 b ) ) ) } {}
    ? == op 112 { ^ ( __w32 ( __rem_u it ( __u32 a ) ( __u32 b ) ) ) } {}  // rem_u
    ? == op 113 { ^ ( __w32 & a b ) } {}
    ? == op 114 { ^ ( __w32 | a b ) } {}
    ? == op 115 { ^ ( __w32 ^^ a b ) } {}
    ? == op 116 { ^ ( __w32 << a & b 31 ) } {}
    ? == op 117 { ^ ( __w32 >> ( __w32 a ) & b 31 ) } {}  // shr_s
    ? == op 118 { ^ ( __w32 >> ( __u32 a ) & b 31 ) } {}  // shr_u
    ? == op 119 { ^ ( __rotl32 a b ) } {}  // rotl
    ^ ( __rotr32 a b )  // 120 rotr
}

@ __rcmp i op i a i b → i {  // i32 0x46..0x4f, i64 0x51..0x5a → 0/1
    ? == op 70 { ^ ? == ( __w32 a ) ( __w32 b ) 1 0 } {}
    ? == op 71 { ^ ? != ( __w32 a ) ( __w32 b ) 1 0 } {}
    ? == op 72 { ^ ? < ( __w32 a ) ( __w32 b ) 1 0 } {}
    ? == op 73 { ^ ? < ( __u32 a ) ( __u32 b ) 1 0 } {}  // lt_u
    ? == op 74 { ^ ? > ( __w32 a ) ( __w32 b ) 1 0 } {}
    ? == op 75 { ^ ? > ( __u32 a ) ( __u32 b ) 1 0 } {}  // gt_u
    ? == op 76 { ^ ? <= ( __w32 a ) ( __w32 b ) 1 0 } {}
    ? == op 77 { ^ ? <= ( __u32 a ) ( __u32 b ) 1 0 } {}  // le_u
    ? == op 78 { ^ ? >= ( __w32 a ) ( __w32 b ) 1 0 } {}
    ? == op 79 { ^ ? >= ( __u32 a ) ( __u32 b ) 1 0 } {}  // ge_u
    ? == op 81 { ^ ? == a b 1 0 } {}
    ? == op 82 { ^ ? != a b 1 0 } {}
    ? == op 83 { ^ ? < a b 1 0 } {}
    ? == op 84 { ^ ? ( __ultb a b ) 1 0 } {}  // lt_u
    ? == op 85 { ^ ? > a b 1 0 } {}
    ? == op 86 { ^ ? ( __ultb b a ) 1 0 } {}  // gt_u
    ? == op 87 { ^ ? <= a b 1 0 } {}
    ? == op 88 { ^ ? ! ( __ultb b a ) 1 0 } {}  // le_u
    ? == op 89 { ^ ? >= a b 1 0 } {}
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

@ __f64_unary * Interp it i op → v {
    : i ab ( __pop it )
    ? == op 153 { ( __push it & ab 9223372036854775807 ) ^ v } {}  // f64.abs (clear sign)
    ? == op 154 { ( __push it ^^ ab -9223372036854775808 ) ^ v } {}  // f64.neg (flip sign)
    : f x ( bits_to_f64 ab )
    ? == op 155 { ( __push it ( f64_to_bits ( ceil x ) ) ) ^ v } {}  // f64.ceil
    ? == op 156 { ( __push it ( f64_to_bits ( floor x ) ) ) ^ v } {}  // f64.floor
    ? == op 157 { ( __push it ( f64_to_bits ( trunc x ) ) ) ^ v } {}  // f64.trunc
    ? == op 158 { ( __push it ( f64_to_bits ( rint x ) ) ) ^ v } {}  // f64.nearest
    ? == op 159 { ( __push it ( f64_to_bits ( sqrt x ) ) ) ^ v } {}  // f64.sqrt
}

@ __f64_binary * Interp it i op → v {
    : i bb ( __pop it )
    : i ab ( __pop it )
    ? == op 166 { ( __push it | & ab 9223372036854775807 & bb -9223372036854775808 ) ^ v } {}  // copysign
    : f a ( bits_to_f64 ab )
    : f b ( bits_to_f64 bb )
    ? == op 160 { ( __push it ( f64_to_bits + a b ) ) ^ v } {}
    ? == op 161 { ( __push it ( f64_to_bits - a b ) ) ^ v } {}
    ? == op 162 { ( __push it ( f64_to_bits * a b ) ) ^ v } {}
    ? == op 163 { ( __push it ( f64_to_bits / a b ) ) ^ v } {}
    // min/max, wasm semantics: any NaN → canonical NaN; min(±0,∓0) = −0 (sign
    // OR on the bits), max(±0,∓0) = +0 (sign AND).
    ? | ( __f64_nan ab ) ( __f64_nan bb ) { ( __push it 9221120237041090560 ) ^ v } {}
    ? & == & ab 9223372036854775807 0 == & bb 9223372036854775807 0 {
        ? == op 164 { ( __push it | ab bb ) } { ( __push it & ab bb ) }
        ^ v } {}
    ? == op 164 { ( __push it ( f64_to_bits ? < a b a b ) ) ^ v } {}  // min
    ? == op 165 { ( __push it ( f64_to_bits ? > a b a b ) ) ^ v } {}  // max
}

@ __f64_cmp * Interp it i op → v {
    : i bb ( __pop it )
    : i ab ( __pop it )
    // unordered: NaN makes `ne` true and every other comparison false
    ? | ( __f64_nan ab ) ( __f64_nan bb ) { ( __push it ? == op 98 1 0 ) ^ v } {}
    : f a ( bits_to_f64 ab )
    : f b ( bits_to_f64 bb )
    ? == op 97 { ( __push it ? == a b 1 0 ) ^ v } {}
    ? == op 98 { ( __push it ? != a b 1 0 ) ^ v } {}
    ? == op 99 { ( __push it ? < a b 1 0 ) ^ v } {}
    ? == op 100 { ( __push it ? > a b 1 0 ) ^ v } {}
    ? == op 101 { ( __push it ? <= a b 1 0 ) ^ v } {}
    ? == op 102 { ( __push it ? >= a b 1 0 ) ^ v } {}
}

@ __f32_unary * Interp it i op → v {
    : i ab ( __pop it )
    ? == op 139 { ( __push it & ab 2147483647 ) ^ v } {}  // f32.abs
    ? == op 140 { ( __push it & ^^ ab 2147483648 4294967295 ) ^ v } {}  // f32.neg
    : f x # f ( bits_to_f32 ab )
    ? == op 141 { ( __push it ( f32_to_bits # f32 ( ceil x ) ) ) ^ v } {}
    ? == op 142 { ( __push it ( f32_to_bits # f32 ( floor x ) ) ) ^ v } {}
    ? == op 143 { ( __push it ( f32_to_bits # f32 ( trunc x ) ) ) ^ v } {}
    ? == op 144 { ( __push it ( f32_to_bits # f32 ( rint x ) ) ) ^ v } {}
    ? == op 145 { ( __push it ( f32_to_bits # f32 ( sqrt x ) ) ) ^ v } {}
}

@ __f32_binary * Interp it i op → v {
    : i bb ( __pop it )
    : i ab ( __pop it )
    ? == op 152 { ( __push it & | & ab 2147483647 & bb 2147483648 4294967295 ) ^ v } {}  // copysign
    : f32 a ( bits_to_f32 ab )
    : f32 b ( bits_to_f32 bb )
    ? == op 146 { ( __push it ( f32_to_bits + a b ) ) ^ v } {}
    ? == op 147 { ( __push it ( f32_to_bits - a b ) ) ^ v } {}
    ? == op 148 { ( __push it ( f32_to_bits * a b ) ) ^ v } {}
    ? == op 149 { ( __push it ( f32_to_bits / a b ) ) ^ v } {}
    // min/max, wasm semantics (see the f64 twin)
    ? | ( __f32_nan ab ) ( __f32_nan bb ) { ( __push it 2143289344 ) ^ v } {}
    ? & == & ab 2147483647 0 == & bb 2147483647 0 {
        ? == op 150 { ( __push it | ab bb ) } { ( __push it & ab bb ) }
        ^ v } {}
    ? == op 150 { ( __push it ( f32_to_bits ? < a b a b ) ) ^ v } {}
    ? == op 151 { ( __push it ( f32_to_bits ? > a b a b ) ) ^ v } {}
}

@ __f32_cmp * Interp it i op → v {
    : i bb ( __pop it )
    : i ab ( __pop it )
    // unordered: NaN makes `ne` true and every other comparison false
    ? | ( __f32_nan ab ) ( __f32_nan bb ) { ( __push it ? == op 92 1 0 ) ^ v } {}
    : f32 b ( bits_to_f32 bb )
    : f32 a ( bits_to_f32 ab )
    ? == op 91 { ( __push it ? == a b 1 0 ) ^ v } {}
    ? == op 92 { ( __push it ? != a b 1 0 ) ^ v } {}
    ? == op 93 { ( __push it ? < a b 1 0 ) ^ v } {}
    ? == op 94 { ( __push it ? > a b 1 0 ) ^ v } {}
    ? == op 95 { ( __push it ? <= a b 1 0 ) ^ v } {}
    ? == op 96 { ( __push it ? >= a b 1 0 ) ^ v } {}
}

// Float ops + all int/float conversions. Reinterpret (0xbc..0xbf) is a no-op
// because values already live as their bit pattern.
@ __exec_float * Interp it i op → v {
    ? == op 167 { ( __push it ( __w32 ( __pop it ) ) ) ^ v } {}  // i32.wrap_i64
    ? == op 172 { ( __push it ( __w32 ( __pop it ) ) ) ^ v } {}  // i64.extend_i32_s
    ? == op 173 { ( __push it & ( __pop it ) 4294967295 ) ^ v } {}  // i64.extend_i32_u
    ? & >= op 188 <= op 191 { ^ v } {}  // *.reinterpret_* : no-op
    // trapping float→int truncation (NaN / out-of-range → trap, per spec)
    ? == op 168 {  // i32.trunc_f32_s
        : i ab ( __pop it )
        : f t ( __trunc_ck it ( __f32_nan ab ) # f ( bits_to_f32 ab ) -2147483648.0 2147483648.0 )
        ( __push it ( __w32 # i t ) ) ^ v } {}
    ? == op 169 {  // i32.trunc_f32_u  (trunc(-0.9) = -0.0 ≥ 0.0 → valid 0)
        : i ab ( __pop it )
        : f t ( __trunc_ck it ( __f32_nan ab ) # f ( bits_to_f32 ab ) 0.0 4294967296.0 )
        ( __push it ( __w32 # i t ) ) ^ v } {}
    ? == op 170 {  // i32.trunc_f64_s
        : i ab ( __pop it )
        : f t ( __trunc_ck it ( __f64_nan ab ) ( bits_to_f64 ab ) -2147483648.0 2147483648.0 )
        ( __push it ( __w32 # i t ) ) ^ v } {}
    ? == op 171 {  // i32.trunc_f64_u
        : i ab ( __pop it )
        : f t ( __trunc_ck it ( __f64_nan ab ) ( bits_to_f64 ab ) 0.0 4294967296.0 )
        ( __push it ( __w32 # i t ) ) ^ v } {}
    ? == op 174 {  // i64.trunc_f32_s
        : i ab ( __pop it )
        : f t ( __trunc_ck it ( __f32_nan ab ) # f ( bits_to_f32 ab ) - 0.0 ( __f_2p63 ) ( __f_2p63 ) )
        ( __push it # i t ) ^ v } {}
    ? == op 175 {  // i64.trunc_f32_u
        : i ab ( __pop it )
        : f t ( __trunc_ck it ( __f32_nan ab ) # f ( bits_to_f32 ab ) 0.0 ( __f_2p64 ) )
        ( __push it ( __f_to_u64 t ) ) ^ v } {}
    ? == op 176 {  // i64.trunc_f64_s
        : i ab ( __pop it )
        : f t ( __trunc_ck it ( __f64_nan ab ) ( bits_to_f64 ab ) - 0.0 ( __f_2p63 ) ( __f_2p63 ) )
        ( __push it # i t ) ^ v } {}
    ? == op 177 {  // i64.trunc_f64_u
        : i ab ( __pop it )
        : f t ( __trunc_ck it ( __f64_nan ab ) ( bits_to_f64 ab ) 0.0 ( __f_2p64 ) )
        ( __push it ( __f_to_u64 t ) ) ^ v } {}
    ? == op 178 { ( __push it ( f32_to_bits # f32 ( __w32 ( __pop it ) ) ) ) ^ v } {}  // f32.convert_i32_s
    ? == op 179 { ( __push it ( f32_to_bits # f32 & ( __pop it ) 4294967295 ) ) ^ v } {}  // f32.convert_i32_u
    ? == op 180 { ( __push it ( f32_to_bits # f32 ( __pop it ) ) ) ^ v } {}  // f32.convert_i64_s
    ? == op 181 {  // f32.convert_i64_u — u64 ≥ 2^63 via halve-with-sticky-bit + double
        : i a ( __pop it )
        ? >= a 0 { ( __push it ( f32_to_bits # f32 a ) ) } {
            : i h | ( __lshr64 a 1 ) & a 1
            : f32 t # f32 h
            ( __push it ( f32_to_bits + t t ) ) }
        ^ v } {}
    ? == op 182 { ( __push it ( f32_to_bits # f32 ( bits_to_f64 ( __pop it ) ) ) ) ^ v } {}  // f32.demote_f64
    ? == op 183 { ( __push it ( f64_to_bits # f ( __w32 ( __pop it ) ) ) ) ^ v } {}  // f64.convert_i32_s
    ? == op 184 { ( __push it ( f64_to_bits # f & ( __pop it ) 4294967295 ) ) ^ v } {}  // f64.convert_i32_u
    ? == op 185 { ( __push it ( f64_to_bits # f ( __pop it ) ) ) ^ v } {}  // f64.convert_i64_s
    ? == op 186 {  // f64.convert_i64_u — u64 ≥ 2^63 via halve-with-sticky-bit + double
        : i a ( __pop it )
        ? >= a 0 { ( __push it ( f64_to_bits # f a ) ) } {
            : i h | ( __lshr64 a 1 ) & a 1
            : f t # f h
            ( __push it ( f64_to_bits + t t ) ) }
        ^ v } {}
    ? == op 187 { ( __push it ( f64_to_bits # f # f ( bits_to_f32 ( __pop it ) ) ) ) ^ v } {}  // f64.promote_f32
    ? & >= op 153 <= op 159 { ( __f64_unary it op ) ^ v } {}
    ? & >= op 160 <= op 166 { ( __f64_binary it op ) ^ v } {}
    ? & >= op 97 <= op 102 { ( __f64_cmp it op ) ^ v } {}
    ? & >= op 139 <= op 145 { ( __f32_unary it op ) ^ v } {}
    ? & >= op 146 <= op 152 { ( __f32_binary it op ) ^ v } {}
    ? & >= op 91 <= op 96 { ( __f32_cmp it op ) ^ v } {}
    ( __trap it `unsupported float opcode` )
}

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
    ? > len ( vec_len [u] . it mem ) { ( __trap it `fd_write length exceeds memory` ) ^ v } {}
    : ( Vec u ) buf ( vec_with_cap [u] len )
    : ~ i k 0
    ~ < k len { ( vec_push [u] buf # u & ( __mem_load it + ptr k 1 0 ) 255 ) = k + k 1 }
    ? | == fd 1 == fd 2 {
        ? . it cap {
            // An embedder asked for the output as a value: raw bytes,
            // appended, NULs preserved — bytes_to_str would truncate at
            // the first NUL a binary-printing module emits.
            : ( Vec u ) dst ? == fd 2 . it caperr . it capout
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
    = . it exited T
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
    : i maxio ( vec_len [u] . it mem )
    : ~ i total 0
    : ~ i i 0
    ~ & & ! . it trap < i iovs_len <= i maxio {
        : i bufp ( __m_get_u32 it + iovs * i 8 )
        : i buflen ( __m_get_u32 it + + iovs * i 8 4 )
        ( __wasi_write_bytes it fd bufp buflen )
        = total + total buflen
        = i + i 1
    }
    ( __m_put_u32 it nwritten total )
    ( __push it 0 )
}

// Fetch the fd record for descriptor `fd`, or #s 0 if out of range / closed.
@ __fd_at * Interp it i fd → s {
    ? | < fd 0 >= fd ( vec_len [s] . it fds ) { ^ # s 0 } {}
    ^ ?? ( vec_get [s] . it fds fd ) { T x → x F → # s 0 }
}

// Read `len` bytes of linear memory at `ptr` into a fresh byte vector.
@ __mem_slice * Interp it i ptr i len → ( Vec u ) {
    // Clamp to memory size: a slice can never be longer than linear memory, so
    // a bogus guest length cannot force a multi-gigabyte allocation. Bytes past
    // the end still trap in __mem_load, so this only bounds the up-front cap.
    : ~ i n len
    ? < n 0 { = n 0 } {}
    ? > n ( vec_len [u] . it mem ) { = n ( vec_len [u] . it mem ) } {}
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
            ( __m_put_u32 it ofd_p ( vec_len [s] . it fds ) )
            ( vec_push [s] . it fds # s nf )
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
        ( __m_put_u32 it ofd_p ( vec_len [s] . it fds ) )
        ( vec_push [s] . it fds # s nf )
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
    ? & != creat 0 == exists 0 { = . nf dirty T } {}  // a created empty file must exist on disk
    ( __m_put_u32 it ofd_p ( vec_len [s] . it fds ) )
    ( vec_push [s] . it fds # s nf )
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
    : i maxio ( vec_len [u] . it mem )
    : ~ i at offset
    : ~ i total 0
    : ~ i iv 0
    ~ & & ! . it trap < iv iovs_len <= iv maxio {
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
    : i maxio ( vec_len [u] . it mem )
    : ~ i at offset
    : ~ i total 0
    : ~ i iv 0
    ~ & & ! . it trap < iv iovs_len <= iv maxio {
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
    : i maxio ( vec_len [u] . it mem )
    : ~ i total 0
    : ~ i iv 0
    ~ & & ! . it trap < iv iovs_len <= iv maxio {
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
@ __fd_flush * WFd f → v {
    ? & . f writable . f dirty {
        : String hs ( bytes_to_str . f host )
        : !v IoErr wr ( write_file_bytes ( string_data hs ) . f data )
        ?? wr { T x → { = . f dirty F } F e → {} }
        ( string_free hs )
    } {}
}

// Flush every open dirty file — called on proc_exit and when _start returns,
// so buffered writes are never lost to a missing fd_close.
@ interp_flush * Interp it → v {
    : i n ( vec_len [s] . it fds )
    : ~ i k 3
    ~ < k n { ?? ( vec_get [s] . it fds k ) { T pp → ? != # i pp 0 { ( __fd_flush # *WFd pp ) } {} F → {} } = k + k 1 }
}

@ __wasi_fd_close * Interp it → v {
    : i fd ( __pop it )
    : s fp ( __fd_at it fd )
    ? != # i fp 0 {
        : *WFd f # *WFd fp
        ( __fd_flush f )
        ? >= fd 3 { ( __freefd fp ) ( vec_set [s] . it fds fd # s 0 ) } {}  // keep stdio
    } {}
    ( __push it 0 )
}

@ __wasi_fd_sync * Interp it → v {
    : i fd ( __pop it )
    : s fp ( __fd_at it fd )
    ? == # i fp 0 { ( __push it 8 ) ^ v } {}  // EBADF
    ( __fd_flush # *WFd fp )
    ( __push it 0 )
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

// random_get(buf, len): real OS entropy via the runtime CSPRNG.
@ __wasi_random_get * Interp it → v {
    : i len ( __pop it )
    : i buf ( __pop it )
    // The destination buffer lives in linear memory, so a length larger than
    // memory is bogus — trap instead of allocating it.
    ? > len ( vec_len [u] . it mem ) { ( __trap it `random_get length exceeds memory` ) ( __push it 0 ) ^ v } {}
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

// Trap with a message that carries a dynamic name (import module/field).
@ __trap_named * Interp it s prefix ( Vec u ) name → v {
    = . it trap T
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
    : i memlen ( vec_len [u] . it mem )
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
    : i memlen ( vec_len [u] . it mem )
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

@ __wasi_dispatch * Interp it ( Vec u ) mod ( Vec u ) field → v {
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
        ? | > + src n ( vec_len [u] . ds bytes ) > + dst n ( vec_len [u] . it mem ) {
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
        : i mn ( vec_len [u] . it mem )
        ? | > + src n mn > + dst n mn { ( __trap it `out of bounds memory access` ) ^ v } {}
        ( __mem_copy it dst src n )
        ^ v
    } {}
    ? == sub 11 {  // memory.fill — bounds checked up front
        : i n ( __u32 ( __pop it ) )
        : i val & ( __pop it ) 255
        : i dst ( __u32 ( __pop it ) )
        ? > + dst n ( vec_len [u] . it mem ) { ( __trap it `out of bounds memory access` ) ^ v } {}
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
