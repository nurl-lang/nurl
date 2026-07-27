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
    ( Vec s ) pfuncs  // *PFunc per defined function, predecoded lazily (#s 0 until first call)
}

// One activation record on the explicit call stack: the function, its locals,
// its control stack, and the instruction cursor [pos, end) — pos/end are
// *record indices* into the function's predecoded instruction array, not byte
// positions; `pins` borrows the *PFunc owned by it.pfuncs.
: Frame { i fidx ( Vec i ) locals ( Vec s ) ctrl i pos i end i code_start s pins }

// A predecoded function body: the byte stream decoded ONCE into fixed-width
// records so the execution loop never touches LEB128 or scans for a matching
// `end` again. Layout: 5 x i64 per instruction —
//   [0] opcode   (0xfc/0xfd/0xfe prefixed ops keep the prefix byte as opcode)
//   [1] A        first operand  (local/global idx, const bits, end-target, …)
//   [2] B        second operand (else-target, memarg offset, params, …)
//   [3] C        third operand  (results, packed if-counts, …)
//   [4] BYTE     the instruction's byte offset in the module image, for
//                trap backtraces — the one thing byte positions were
//                still good for
// Branch targets are record indices, resolved at predecode by a patch
// stack (open block/loop/if records get their end/else slots filled in
// when the matching `else`/`end` arrives). `aux` holds br_table label
// vectors: [target0 … targetN default], record A = start index, B = N.
: PFunc { ( Vec i ) code ( Vec i ) aux i count }

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
    : i pn ( vec_len [s] . it pfuncs )
    : ~ i pi 0
    ~ < pi pn { ?? ( vec_get [s] . it pfuncs pi ) { T pp → ( __pf_free pp ) F → {} } = pi + pi 1 }
    ( vec_free [s] . it pfuncs )
    ( nurl_free # s it )
}

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
@ __mem_load * Interp it i ea i n i signed → i {
    ? | < ea 0 > + ea n ( vec_len [u] . it mem ) {
        ( __trap it `memory load out of bounds` ) ^ 0
    } {}
    : ~ i v 0
    : ~ i k 0
    ~ < k n {
        : i byte ?? ( vec_get [u] . it mem + ea k ) { T x → # i x F → 0 }
        = v | v << byte * 8 k
        = k + k 1
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
    : ~ i k 0
    ~ < k n {
        ( vec_set [u] . it mem + ea k # u & >> val * 8 k 255 )
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
// `off` arrives predecoded (and already u32-masked, so a huge offset cannot
// make the effective address wrap negative and slip past the bounds check);
// the alignment hint was dropped at predecode — it carried no semantics here.
@ __exec_mem * Interp it i off i op → v {
    ? == op 63 { ( __push it . it mem_pages ) ^ v } {}  // memory.size
    ? == op 64 { : i d ( __u32 ( __pop it ) ) ( __push it ( __mem_grow it d ) ) ^ v } {}  // memory.grow
    ? & >= op 54 <= op 62 {  // stores: pop value, then addr
        : i val ( __pop it )
        : i ea + & ( __pop it ) 4294967295 off
        ? == op 54 { ( __mem_store it ea 4 val ) } {}  // i32.store
        ? == op 55 { ( __mem_store it ea 8 val ) } {}  // i64.store
        ? == op 56 { ( __mem_store it ea 4 val ) } {}  // f32.store
        ? == op 57 { ( __mem_store it ea 8 val ) } {}  // f64.store
        ? == op 58 { ( __mem_store it ea 1 val ) } {}  // i32.store8
        ? == op 59 { ( __mem_store it ea 2 val ) } {}  // i32.store16
        ? == op 60 { ( __mem_store it ea 1 val ) } {}  // i64.store8
        ? == op 61 { ( __mem_store it ea 2 val ) } {}  // i64.store16
        ? == op 62 { ( __mem_store it ea 4 val ) } {}  // i64.store32
        ^ v
    } {}
    : i ea + & ( __pop it ) 4294967295 off
    ? == op 40 { ( __push it ( __w32 ( __mem_load it ea 4 0 ) ) ) } {}  // i32.load
    ? == op 41 { ( __push it ( __mem_load it ea 8 0 ) ) } {}  // i64.load
    ? == op 42 { ( __push it ( __mem_load it ea 4 0 ) ) } {}  // f32.load (raw 4-byte pattern)
    ? == op 43 { ( __push it ( __mem_load it ea 8 0 ) ) } {}  // f64.load
    ? == op 44 { ( __push it ( __w32 ( __mem_load it ea 1 1 ) ) ) } {}  // i32.load8_s
    ? == op 45 { ( __push it ( __mem_load it ea 1 0 ) ) } {}  // i32.load8_u
    ? == op 46 { ( __push it ( __w32 ( __mem_load it ea 2 1 ) ) ) } {}  // i32.load16_s
    ? == op 47 { ( __push it ( __mem_load it ea 2 0 ) ) } {}  // i32.load16_u
    ? == op 48 { ( __push it ( __mem_load it ea 1 1 ) ) } {}  // i64.load8_s
    ? == op 49 { ( __push it ( __mem_load it ea 1 0 ) ) } {}  // i64.load8_u
    ? == op 50 { ( __push it ( __mem_load it ea 2 1 ) ) } {}  // i64.load16_s
    ? == op 51 { ( __push it ( __mem_load it ea 2 0 ) ) } {}  // i64.load16_u
    ? == op 52 { ( __push it ( __mem_load it ea 4 1 ) ) } {}  // i64.load32_s
    ? == op 53 { ( __push it ( __mem_load it ea 4 0 ) ) } {}  // i64.load32_u
}

// ── control-stack helpers ────────────────────────────────────────

@ __ctrl_push ( Vec s ) ctrl i is_loop i start_pc i end_pc i height i arity → v {
    : *Ctrl e # *Ctrl ( nurl_alloc Z Ctrl )
    = . e is_loop is_loop
    = . e start_pc start_pc
    = . e end_pc end_pc
    = . e height height
    = . e arity arity
    ( vec_push [s] ctrl # s e )
}

@ __ctrl_pop ( Vec s ) ctrl → v {
    : i n ( vec_len [s] ctrl )
    ? <= n 0 { ^ v } {}
    ?? ( vec_get [s] ctrl - n 1 ) { T pp → ? != # i pp 0 { ( nurl_free pp ) } {} F → {} }
    ( vec_pop [s] ctrl )
}

@ __ctrl_at ( Vec s ) ctrl i k → s {
    : i ix - - ( vec_len [s] ctrl ) 1 k
    ? < ix 0 { ^ # s 0 } {}
    ^ ?? ( vec_get [s] ctrl ix ) { T x → x F → # s 0 }
}

// Truncate the value stack to `height`, preserving the top `arity` values (the
// branch payload: a block's results / a loop's parameters).
@ __br_keep * Interp it i height i arity → v {
    : ( Vec i ) kept ( vec_new [i] )
    : ~ i k 0
    ~ < k arity { ( vec_push [i] kept ( __pop it ) ) = k + k 1 }
    ( __vtrunc it height )
    : ~ i j arity
    ~ > j 0 { = j - j 1 ( __push it ?? ( vec_get [i] kept j ) { T x → x F → 0 } ) }
    ( vec_free [i] kept )
}

// Take branch to label depth k: re-enter a loop (carrying its parameters), or
// exit a block past its `end` (carrying its results).
@ __do_branch * Interp it ( Vec s ) ctrl * Wc c i k → v {
    : s tp ( __ctrl_at ctrl k )
    ? == # i tp 0 { ( __trap it `branch label out of range` ) ^ v } {}
    : *Ctrl target # *Ctrl tp
    ( __br_keep it . target height . target arity )
    ? == . target is_loop 1 {
        : ~ i pops k
        ~ > pops 0 { ( __ctrl_pop ctrl ) = pops - pops 1 }
        = . c pos . target start_pc
    } {
        : ~ i pops + k 1
        ~ > pops 0 { ( __ctrl_pop ctrl ) = pops - pops 1 }
        = . c pos + . target end_pc 1
    }
}

// ── the executor ─────────────────────────────────────────────────
// Execute function `fidx`. Arguments are already on the value stack; on return
// the function's results are left on top. Recurses for `call`.

// Dispatch an imported function to the WASI host layer (no frame needed).
@ __call_import * Interp it * Module m i fidx → v {
    : s wp ?? ( vec_get [s] . m imports fidx ) { T x → x F → # s 0 }
    ? != # i wp 0 { : *WImport w # *WImport wp ( __wasi_dispatch it . w module . w field ) } { ( __trap it `bad import index` ) }
}

// Build a frame for defined function `fidx`: locals = params (popped from the
// value stack, in order) ++ declared locals (zeroed). #s 0 on a bad index.
@ __frame_new * Interp it * Module m i fidx → s {
    : s fp ?? ( vec_get [s] . m funcs - fidx . m num_import_funcs ) { T x → x F → # s 0 }
    ? == # i fp 0 { ( __trap it `bad function index` ) ^ # s 0 } {}
    : *WFunc f # *WFunc fp
    : s tp ?? ( vec_get [s] . m types . f typeidx ) { T x → x F → # s 0 }
    ? == # i tp 0 { ( __trap it `bad type index` ) ^ # s 0 } {}
    : *FuncType ft # *FuncType tp
    : i nparams ( vec_len [i] . ft params )
    : i nlocals_decl ( vec_len [i] . f locals )
    : ( Vec i ) locals ( vec_new [i] )
    : ~ i k 0
    ~ < k + nparams nlocals_decl { ( vec_push [i] locals 0 ) = k + k 1 }
    : ~ i p nparams
    ~ > p 0 { = p - p 1 ( vec_set [i] locals p ( __pop it ) ) }
    : s pins ( __pfunc_for it m fidx )
    ? == # i pins 0 { ( __trap it `bad function index` ) ( vec_free [i] locals ) ^ # s 0 } {}
    : *PFunc pfc # *PFunc pins
    : *Frame fr # *Frame ( nurl_alloc Z Frame )
    = . fr fidx fidx
    = . fr locals locals
    = . fr ctrl ( vec_new [s] )
    = . fr pos 0
    = . fr end . pfc count
    = . fr code_start . f code_start
    = . fr pins pins
    ^ # s fr
}

@ __frame_free s pp → v {
    ? == # i pp 0 { ^ v } {}
    : *Frame fr # *Frame pp
    : i cn ( vec_len [s] . fr ctrl )
    : ~ i ci 0
    ~ < ci cn { ?? ( vec_get [s] . fr ctrl ci ) { T cp → ? != # i cp 0 { ( nurl_free cp ) } {} F → {} } = ci + ci 1 }
    ( vec_free [s] . fr ctrl )
    ( vec_free [i] . fr locals )
    ( nurl_free # s fr )
}

// ── predecode ────────────────────────────────────────────────────
// Decode a function body ONCE into PFunc records (layout at the struct).
// Everything position-like in a record is an index into the record array,
// which is what lets the executor drop the byte cursor: `loop` no longer
// re-scans its body for the matching `end` on entry, `if` doesn't run two
// scans per execution, and no operand is LEB-decoded twice.

@ __pf_free s pp → v {
    ? == # i pp 0 { ^ v } {}
    : *PFunc pf # *PFunc pp
    ( vec_free [i] . pf code )
    ( vec_free [i] . pf aux )
    ( nurl_free # s pf )
}

// Emit one 5-slot record; returns its index.
@ __pf_emit ( Vec i ) code i op i a i b i cc i byte → i {
    : i idx / ( vec_len [i] code ) 5
    ( vec_push [i] code op ) ( vec_push [i] code a ) ( vec_push [i] code b )
    ( vec_push [i] code cc ) ( vec_push [i] code byte )
    ^ idx
}

// The patch stack: one i per open block/loop/if — the record index, with
// bit 62 set when the frame is an `if` (so `else` knows whom to patch).
@ __predecode * Module m i code_start i code_end → s {
    : *PFunc pf # *PFunc ( nurl_alloc Z PFunc )
    = . pf code ( vec_new [i] )
    = . pf aux ( vec_new [i] )
    : ( Vec i ) open ( vec_new [i] )
    : *Wc c ( wc_new . m code )
    = . c pos code_start
    = . c len code_end
    ~ < . c pos code_end {
        : i byte . c pos
        : i op ( wc_u8 c )
        ? | == op 2 == op 3 {  // block / loop: A=end (patched), B=params, C=results
            : i bt ( wc_sleb c )
            : i rec ( __pf_emit . pf code op -1 ( __bt_params m bt ) ( __bt_results m bt ) byte )
            ( vec_push [i] open rec )
        } {
            ? == op 4 {  // if: A=end (patched), B=else (-1), C=params<<16|results
                : i bt ( wc_sleb c )
                : i packed | << ( __bt_params m bt ) 16 & ( __bt_results m bt ) 65535
                : i rec ( __pf_emit . pf code 4 -1 -1 packed byte )
                ( vec_push [i] open | rec 4611686018427387904 )
            } {
                ? == op 5 {  // else: patch the open if's B; A here = its end (patched too)
                    : i rec ( __pf_emit . pf code 5 -1 0 0 byte )
                    : i n ( vec_len [i] open )
                    ? > n 0 {
                        : i top ?? ( vec_get [i] open - n 1 ) { T x → x F → 0 }
                        : i orec & top 4611686018427387903
                        ( vec_set [i] . pf code + * orec 5 2 rec )
                    } {}
                } {
                    ? == op 11 {  // end: patch the open frame's A (and an else's A) to here
                        : i rec ( __pf_emit . pf code 11 0 0 0 byte )
                        : i n ( vec_len [i] open )
                        ? > n 0 {
                            : i top ?? ( vec_get [i] open - n 1 ) { T x → x F → 0 }
                            ( vec_pop [i] open )
                            : i orec & top 4611686018427387903
                            ( vec_set [i] . pf code + * orec 5 1 rec )
                            // an if with an else: the else record jumps to this end
                            ? != 0 & top 4611686018427387904 {
                                : i erec ?? ( vec_get [i] . pf code + * orec 5 2 ) { T x → x F → -1 }
                                ? >= erec 0 { ( vec_set [i] . pf code + * erec 5 1 rec ) } {}
                            } {}
                        } {}
                    } {
                        ? | == op 12 == op 13 {  // br / br_if: A=label depth
                            ( __pf_emit . pf code op ( wc_uleb c ) 0 0 byte )
                        } {
                            ? == op 14 {  // br_table: A=aux start, B=label count (default at aux[A+B])
                                : i astart ( vec_len [i] . pf aux )
                                : i n ( wc_uleb c )
                                : ~ i k 0
                                ~ <= k n { ( vec_push [i] . pf aux ( wc_uleb c ) ) = k + k 1 }
                                ( __pf_emit . pf code 14 astart n 0 byte )
                            } {
                                ? == op 16 { ( __pf_emit . pf code 16 ( wc_uleb c ) 0 0 byte ) } {  // call: A=fidx
                                    ? == op 17 {  // call_indirect: A=typeidx (single table; tableidx ignored)
                                        : i ti ( wc_uleb c ) ( wc_uleb c )
                                        ( __pf_emit . pf code 17 ti 0 0 byte )
                                    } {
                                        ? == op 28 {  // select t: value semantics identical to bare select
                                            : i tc ( wc_uleb c ) ( wc_skip c tc )
                                            ( __pf_emit . pf code 27 0 0 0 byte )
                                        } {
                                            ? == op 208 { ( wc_u8 c ) ( __pf_emit . pf code 208 0 0 0 byte ) } {  // ref.null
                                                ? | == op 32 | == op 33 | == op 34 | == op 35 | == op 36 | == op 37 | == op 38 == op 210 {
                                                    // local/global/table get-set/tee / ref.func: A=index
                                                    ( __pf_emit . pf code op ( wc_uleb c ) 0 0 byte )
                                                } {
                                                    ? | == op 65 == op 66 { ( __pf_emit . pf code op ( wc_sleb c ) 0 0 byte ) } {  // i32/i64.const: A=value
                                                        ? == op 67 { ( __pf_emit . pf code 67 ( __read_le c 4 ) 0 0 byte ) } {  // f32.const: A=raw bits
                                                            ? == op 68 { ( __pf_emit . pf code 68 ( __read_le c 8 ) 0 0 byte ) } {  // f64.const: A=raw bits
                                                                ? & >= op 40 <= op 62 {  // loads/stores: A=offset (u32-masked; align dropped)
                                                                    ( wc_uleb c )
                                                                    ( __pf_emit . pf code op & ( wc_uleb c ) 4294967295 0 0 byte )
                                                                } {
                                                                    ? | == op 63 == op 64 { ( wc_u8 c ) ( __pf_emit . pf code op 0 0 0 byte ) } {  // memory.size/grow
                                                                        ? == op 252 {  // bulk memory / table ops / trunc_sat: A=sub, B=first idx operand
                                                                            : i sub ( wc_uleb c )
                                                                            : ~ i bop 0
                                                                            ? == sub 8 { = bop ( wc_uleb c ) ( wc_u8 c ) } {  // memory.init: dataidx
                                                                                ? == sub 9 { = bop ( wc_uleb c ) } {  // data.drop
                                                                                    ? == sub 10 { ( wc_u8 c ) ( wc_u8 c ) } {  // memory.copy
                                                                                        ? == sub 11 { ( wc_u8 c ) } {  // memory.fill
                                                                                            ? == sub 12 { = bop ( wc_uleb c ) ( wc_uleb c ) } {  // table.init: elemidx
                                                                                                ? == sub 13 { = bop ( wc_uleb c ) } {  // elem.drop
                                                                                                    ? == sub 14 { ( wc_uleb c ) ( wc_uleb c ) } {  // table.copy
                                                                                                        ? | | == sub 15 == sub 16 == sub 17 { ( wc_uleb c ) } {} } } } } } } }  // table.grow/size/fill
                                                                            ( __pf_emit . pf code 252 sub bop 0 byte )
                                                                        } {
                                                                            // no-immediate ops (numeric, parametric, sign-ext, ref.is_null, …)
                                                                            // and the unsupported 0xfd/0xfe prefixes: skip their immediates so
                                                                            // record alignment survives, execute-time still traps on them.
                                                                            ? | == op 253 == op 254 { ( __skip_imm c op ) } {}
                                                                            ( __pf_emit . pf code op 0 0 0 byte )
                                                                        } } } } } } } } } } } } } } } } }
    }
    ( vec_free [i] open )
    ( wc_free c )
    = . pf count / ( vec_len [i] . pf code ) 5
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
    : s built ( __predecode m . f code_start . f code_end )
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
            ? >= bpos 0 { = boff - ?? ( vec_get [i] . bpf code + * bpos 5 4 ) { T x → x F → . fr code_start } . fr code_start } {}
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
    : s fr0 ( __frame_new it m fidx )
    ? != # i fr0 0 { ( vec_push [s] frames fr0 ) } {}
    : *Wc c ( wc_new . m code )
    // The frame stack changes only on a call, a return, or falling off the end
    // of a body — but this loop used to re-read the top frame out of `frames`
    // on every *instruction*: a bounds-checked vec_get, an Option unwrap and a
    // dependent load, then two stores copying pos/end into the cursor and one
    // copying pos back. At instruction-level profile that was the single
    // hottest line in the interpreter (14.5 % of all cycles on the vec_get's
    // load alone, ~8 % more on the cursor store) — pure bookkeeping, none of it
    // the guest's work.
    //
    // So the cursor is now the authority on where execution is, and the top
    // frame is cached in `tp` and refreshed only when `reload` says the frame
    // stack moved. `. fr pos` is written back exactly at the transitions where
    // something else will read it: before a call suspends this frame, and
    // before a trap prints a backtrace off it.
    : ~ s tp # s 0
    : ~ s pbase # s 0
    : ~ s abase # s 0
    : ~ i reload 1
    ~ & & > ( vec_len [s] frames ) 0 ! . it exited ! . it trap {
        ? != reload 0 {
            = tp ?? ( vec_get [s] frames - ( vec_len [s] frames ) 1 ) { T x → x F → # s 0 }
            : *Frame nfr # *Frame tp
            : *PFunc npf # *PFunc . nfr pins
            = pbase # s ( vec_data [i] . npf code )
            = abase # s ( vec_data [i] . npf aux )
            = . c pos . nfr pos
            = . c len . nfr end
            = reload 0
        } {}
        : *Frame fr # *Frame tp
        ? >= . c pos . c len {  // fell off the end of the body → return
            ( __frame_free tp ) ( vec_pop [s] frames ) = reload 1
        } {
            ? == . it fuel 0 { ( __trap it `fuel exhausted` ) } {
                ? > . it fuel 0 { = . it fuel - . it fuel 1 } {}
                // One record: five raw word reads off the frozen predecoded
                // array — no bounds check, no Option, no LEB. The record
                // array cannot move (nothing appends after predecode), which
                // is what makes the borrowed vec_data pointer sound.
                : i rbase * . c pos 5
                : i op ( nurl_peek pbase rbase )
                : i ra ( nurl_peek pbase + rbase 1 )
                : i rb ( nurl_peek pbase + rbase 2 )
                : i rc ( nurl_peek pbase + rbase 3 )
                = . c pos + . c pos 1
                ( __pexec_op it m c abase . fr ctrl . fr locals op ra rb rc )
                ? == op 15 { ( __frame_free tp ) ( vec_pop [s] frames ) = reload 1 } {  // return
                    ? >= . it pending_call 0 {  // call / call_indirect
                        : i callee . it pending_call
                        = . it pending_call -1
                        = . fr pos . c pos  // this frame resumes here
                        = reload 1
                        ? < callee . m num_import_funcs { ( __call_import it m callee ) } {
                            ? >= ( vec_len [s] frames ) . it max_depth { ( __trap it `call stack exhausted` ) } {
                                : s nf ( __frame_new it m callee )
                                ? != # i nf 0 { ( vec_push [s] frames nf ) } {}
                            }
                        }
                    } {}
                }
            }
        }
    }
    // The cursor, not the frame, holds the trapping position — sync it back so
    // the backtrace's `+offset` is the instruction that actually trapped.
    // Only when `reload` is still 0: that is exactly the case where the cursor
    // belongs to the frame still on top. If the stack moved (a pop freed `tp`,
    // or `call stack exhausted` trapped after the caller's pos was already
    // saved) the cursor describes a frame that is gone or already up to date,
    // and `tp` may be dangling — so re-read the top rather than trusting it.
    ? . it trap {
        ? & == reload 0 > ( vec_len [s] frames ) 0 {
            : s ttp ?? ( vec_get [s] frames - ( vec_len [s] frames ) 1 ) { T x → x F → # s 0 }
            ? != # i ttp 0 { : *Frame ftr # *Frame ttp = . ftr pos . c pos } {}
        } {}
        ( __trap_backtrace it m frames )
    } {}
    : i fn ( vec_len [s] frames )
    : ~ i fi 0
    ~ < fi fn { ?? ( vec_get [s] frames fi ) { T pp → ( __frame_free pp ) F → {} } = fi + fi 1 }
    ( vec_free [s] frames )
    ( wc_free c )
}

// Execute one predecoded record. `op` plus operands ra/rb/rc were read off
// the PFunc array by the driver; `c` is the program counter in record units
// (pos = next record, len = record count); `abase` is the raw base of the
// PFunc aux array (br_table label vectors). Mutates the value stack, locals,
// control stack and pc.
@ __pexec_op * Interp it * Module m * Wc c s abase ( Vec s ) ctrl ( Vec i ) locals i op i ra i rb i rc → v {
    // ── control flow ──
    ? == op 0 { ( __trap it `unreachable` ) ^ v } {}  // unreachable
    ? == op 1 { ^ v } {}  // nop
    ? | == op 2 == op 3 {  // block / loop: ra=end, rb=params, rc=results
        // control-frame height = the stack base under the block's parameters;
        // a branch carries a loop's params back to the top, a block's results out.
        : i height - ( __vsh it ) rb
        ? == op 3 { ( __ctrl_push ctrl 1 . c pos ra height rb ) }
        { ( __ctrl_push ctrl 0 0 ra height rc ) }
        ^ v
    } {}
    ? == op 4 {  // if: ra=end, rb=else (-1 none), rc=params<<16|results
        : i cond ( __pop it )
        ( __ctrl_push ctrl 0 0 ra - ( __vsh it ) >> rc 16 & rc 65535 )
        ? == cond 0 { = . c pos ? >= rb 0 + rb 1 ra } {}
        ^ v
    } {}
    ? == op 5 {  // else: reached at end of the then-arm → skip to end
        : s tp ( __ctrl_at ctrl 0 )
        ? != # i tp 0 { : *Ctrl e # *Ctrl tp = . c pos . e end_pc } {}
        ^ v
    } {}
    ? == op 11 { ( __ctrl_pop ctrl ) ^ v } {}  // end
    ? == op 12 { ( __do_branch it ctrl c ra ) ^ v } {}  // br
    ? == op 13 { : i cond ( __pop it ) ? != cond 0 { ( __do_branch it ctrl c ra ) } {} ^ v } {}  // br_if
    ? == op 14 {  // br_table: ra=aux start, rb=label count, default at aux[ra+rb]
        : i ui ( __u32 ( __pop it ) )
        : i pick ? < ui rb ui rb
        ( __do_branch it ctrl c ( nurl_peek abase + ra pick ) )
        ^ v
    } {}
    ? == op 15 { ^ v } {}  // return (handled by the driver)
    ? == op 16 { = . it pending_call ra ^ v } {}  // call → driver pushes the frame
    ? == op 17 {  // call_indirect: ra=typeidx (single table)
        : i ei & ( __pop it ) 4294967295
        ? | < ei 0 >= ei ( vec_len [i] . it table ) {
            ( __trap it `call_indirect: index out of range` ) ^ v
        } {}
        : i fi ?? ( vec_get [i] . it table ei ) { T x → x F → -1 }
        ? < fi 0 { ( __trap it `call_indirect: null table element` ) ^ v } {}
        // runtime type check: the callee's type must structurally equal the
        // instruction's expected type
        : s want ?? ( vec_get [s] . m types ra ) { T x → x F → # s 0 }
        : s have ( module_func_type m fi )
        ? | == # i want 0 == # i have 0 {
            ( __trap it `call_indirect: bad type index` ) ^ v } {}
        ? ! ( functype_eq # *FuncType want # *FuncType have ) {
            ( __trap it `call_indirect: signature mismatch` ) ^ v } {}
        = . it pending_call fi
        ^ v
    } {}
    ? == op 26 { ( __pop it ) ^ v } {}  // drop
    ? == op 27 { : i cc ( __pop it ) : i b2 ( __pop it ) : i a2 ( __pop it ) ( __push it ? != cc 0 a2 b2 ) ^ v } {}  // select (typed form folded in at predecode)
    ? == op 37 {  // table.get
        : i ei ( __u32 ( __pop it ) )
        ? >= ei ( vec_len [i] . it table ) { ( __trap it `out of bounds table access` ) ^ v } {}
        ( __push it ?? ( vec_get [i] . it table ei ) { T x → x F → -1 } ) ^ v } {}
    ? == op 38 {  // table.set
        : i val ( __pop it )
        : i ei ( __u32 ( __pop it ) )
        ? >= ei ( vec_len [i] . it table ) { ( __trap it `out of bounds table access` ) ^ v } {}
        ( vec_set [i] . it table ei val ) ^ v } {}
    ? == op 208 { ( __push it -1 ) ^ v } {}  // ref.null ht → −1
    ? == op 209 { ( __push it ? == ( __pop it ) -1 1 0 ) ^ v } {}  // ref.is_null
    ? == op 210 { ( __push it ra ) ^ v } {}  // ref.func (funcref = index)
    // ── locals ──
    ? == op 32 { ( __push it ?? ( vec_get [i] locals ra ) { T x → x F → 0 } ) ^ v } {}
    ? == op 33 { ( vec_set [i] locals ra ( __pop it ) ) ^ v } {}
    ? == op 34 { : i tv ?? ( vec_get [i] . it vs - ( vec_len [i] . it vs ) 1 ) { T x → x F → 0 } ( vec_set [i] locals ra tv ) ^ v } {}  // local.tee
    // ── globals ──
    ? == op 35 { ( __push it ?? ( vec_get [i] . it globals ra ) { T x → x F → 0 } ) ^ v } {}  // global.get
    ? == op 36 { ( vec_set [i] . it globals ra ( __pop it ) ) ^ v } {}  // global.set
    // ── constants (f32/f64 arrive as their raw bit patterns) ──
    ? == op 65 { ( __push it ( __w32 ra ) ) ^ v } {}  // i32.const
    ? | == op 66 | == op 67 == op 68 { ( __push it ra ) ^ v } {}  // i64/f32/f64.const
    // ── linear memory (loads/stores, size/grow) ──
    ? & >= op 40 <= op 64 { ( __exec_mem it ra op ) ^ v } {}
    // ── floats: cmp (91..102), unary/binary (139..166), conversions (167..191) ──
    ? | & >= op 91 <= op 102 | & >= op 139 <= op 166 & >= op 167 <= op 191 { ( __exec_float it op ) ^ v } {}
    // ── sign-extension ops (0xc0..0xc4) and the 0xfc prefix (bulk memory) ──
    ? & >= op 192 <= op 196 { ( __exec_signext it op ) ^ v } {}
    ? == op 252 { ( __exec_fc it ra rb ) ^ v } {}
    // ── the rest: integer numeric ops ──
    ( __exec_num it op )
}

// Numeric/comparison/bitwise ops (both i32 and i64). i32 results are wrapped to
// 32 bits; comparisons push 0/1.
@ __exec_num * Interp it i op → v {
    // i32 unary: eqz
    ? == op 69 { ( __push it ? == ( __pop it ) 0 1 0 ) ^ v } {}
    // i64 unary: eqz
    ? == op 80 { ( __push it ? == ( __pop it ) 0 1 0 ) ^ v } {}
    // i32/i64 unary: clz / ctz / popcnt
    ? == op 103 { ( __push it ( __clz32 ( __pop it ) ) ) ^ v } {}
    ? == op 104 { ( __push it ( __ctz32 ( __pop it ) ) ) ^ v } {}
    ? == op 105 { ( __push it ( __popc32 ( __pop it ) ) ) ^ v } {}
    ? == op 121 { ( __push it ( __clz64 ( __pop it ) ) ) ^ v } {}
    ? == op 122 { ( __push it ( __ctz64 ( __pop it ) ) ) ^ v } {}
    ? == op 123 { ( __push it ( __popc64 ( __pop it ) ) ) ^ v } {}
    // (i32.wrap_i64 / i64.extend_i32_* live in __exec_float's conversion block)
    // binary ops: pop b, a
    : i b ( __pop it )
    : i a ( __pop it )
    // ── i32 comparisons (0x46..0x4f) ──
    ? == op 70 { ( __push it ? == ( __w32 a ) ( __w32 b ) 1 0 ) ^ v } {}
    ? == op 71 { ( __push it ? != ( __w32 a ) ( __w32 b ) 1 0 ) ^ v } {}
    ? == op 72 { ( __push it ? < ( __w32 a ) ( __w32 b ) 1 0 ) ^ v } {}
    ? == op 73 { ( __push it ? < ( __u32 a ) ( __u32 b ) 1 0 ) ^ v } {}  // lt_u
    ? == op 74 { ( __push it ? > ( __w32 a ) ( __w32 b ) 1 0 ) ^ v } {}
    ? == op 75 { ( __push it ? > ( __u32 a ) ( __u32 b ) 1 0 ) ^ v } {}  // gt_u
    ? == op 76 { ( __push it ? <= ( __w32 a ) ( __w32 b ) 1 0 ) ^ v } {}
    ? == op 77 { ( __push it ? <= ( __u32 a ) ( __u32 b ) 1 0 ) ^ v } {}  // le_u
    ? == op 78 { ( __push it ? >= ( __w32 a ) ( __w32 b ) 1 0 ) ^ v } {}
    ? == op 79 { ( __push it ? >= ( __u32 a ) ( __u32 b ) 1 0 ) ^ v } {}  // ge_u
    // ── i32 arithmetic/bitwise (0x6a..0x78) → wrap 32 ──
    ? == op 106 { ( __push it ( __w32 + a b ) ) ^ v } {}
    ? == op 107 { ( __push it ( __w32 - a b ) ) ^ v } {}
    ? == op 108 { ( __push it ( __w32 * a b ) ) ^ v } {}
    ? == op 109 { ( __push it ( __w32 ( __div_s it ( __w32 a ) ( __w32 b ) -2147483648 ) ) ) ^ v } {}
    ? == op 110 { ( __push it ( __w32 ( __div_u it ( __u32 a ) ( __u32 b ) ) ) ) ^ v } {}  // div_u
    ? == op 111 { ( __push it ( __w32 ( __rem_s it ( __w32 a ) ( __w32 b ) ) ) ) ^ v } {}
    ? == op 112 { ( __push it ( __w32 ( __rem_u it ( __u32 a ) ( __u32 b ) ) ) ) ^ v } {}  // rem_u
    ? == op 113 { ( __push it ( __w32 & a b ) ) ^ v } {}
    ? == op 114 { ( __push it ( __w32 | a b ) ) ^ v } {}
    ? == op 115 { ( __push it ( __w32 ^^ a b ) ) ^ v } {}
    ? == op 116 { ( __push it ( __w32 << a & b 31 ) ) ^ v } {}
    ? == op 117 { ( __push it ( __w32 >> ( __w32 a ) & b 31 ) ) ^ v } {}  // shr_s
    ? == op 118 { ( __push it ( __w32 >> ( __u32 a ) & b 31 ) ) ^ v } {}  // shr_u
    ? == op 119 { ( __push it ( __rotl32 a b ) ) ^ v } {}  // rotl
    ? == op 120 { ( __push it ( __rotr32 a b ) ) ^ v } {}  // rotr
    // ── i64 comparisons (0x51..0x5a) ──
    ? == op 81 { ( __push it ? == a b 1 0 ) ^ v } {}
    ? == op 82 { ( __push it ? != a b 1 0 ) ^ v } {}
    ? == op 83 { ( __push it ? < a b 1 0 ) ^ v } {}
    ? == op 84 { ( __push it ? ( __ultb a b ) 1 0 ) ^ v } {}  // lt_u
    ? == op 85 { ( __push it ? > a b 1 0 ) ^ v } {}
    ? == op 86 { ( __push it ? ( __ultb b a ) 1 0 ) ^ v } {}  // gt_u
    ? == op 87 { ( __push it ? <= a b 1 0 ) ^ v } {}
    ? == op 88 { ( __push it ? ! ( __ultb b a ) 1 0 ) ^ v } {}  // le_u
    ? == op 89 { ( __push it ? >= a b 1 0 ) ^ v } {}
    ? == op 90 { ( __push it ? ! ( __ultb a b ) 1 0 ) ^ v } {}  // ge_u
    // ── i64 arithmetic/bitwise (0x7c..0x8a) ──
    ? == op 124 { ( __push it + a b ) ^ v } {}
    ? == op 125 { ( __push it - a b ) ^ v } {}
    ? == op 126 { ( __push it * a b ) ^ v } {}
    ? == op 127 { ( __push it ( __div_s it a b -9223372036854775808 ) ) ^ v } {}
    ? == op 128 { ? == b 0 { ( __trap it `integer divide by zero` ) } { ( __push it ( __udiv64 a b ) ) } ^ v } {}  // div_u
    ? == op 129 { ( __push it ( __rem_s it a b ) ) ^ v } {}
    ? == op 130 { ? == b 0 { ( __trap it `integer divide by zero` ) } { ( __push it ( __urem64 a b ) ) } ^ v } {}  // rem_u
    ? == op 131 { ( __push it & a b ) ^ v } {}
    ? == op 132 { ( __push it | a b ) ^ v } {}
    ? == op 133 { ( __push it ^^ a b ) ^ v } {}
    ? == op 134 { ( __push it << a & b 63 ) ^ v } {}
    ? == op 135 { ( __push it >> a & b 63 ) ^ v } {}  // shr_s
    ? == op 136 { ( __push it ( __lshr64 a & b 63 ) ) ^ v } {}  // shr_u
    ? == op 137 { ( __push it ( __rotl64 a b ) ) ^ v } {}  // rotl
    ? == op 138 { ( __push it ( __rotr64 a b ) ) ^ v } {}  // rotr
    // unsupported opcode → trap
    ( __trap it `unsupported opcode` )
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
        : String s ( bytes_to_str buf )
        ? == fd 2 { ( nurl_eprint ( string_data s ) ) } { ( nurl_print ( string_data s ) ) }
        ( string_free s )
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

@ __exec_signext * Interp it i op → v {
    : i x ( __pop it )
    ? == op 192 { ( __push it ( __w32 ( __sext x 8 ) ) ) ^ v } {}  // i32.extend8_s
    ? == op 193 { ( __push it ( __w32 ( __sext x 16 ) ) ) ^ v } {}  // i32.extend16_s
    ? == op 194 { ( __push it ( __sext x 8 ) ) ^ v } {}  // i64.extend8_s
    ? == op 195 { ( __push it ( __sext x 16 ) ) ^ v } {}  // i64.extend16_s
    ? == op 196 { ( __push it ( __sext x 32 ) ) ^ v } {}  // i64.extend32_s
}

@ __mem_copy * Interp it i dst i src i n → v {
    ? <= n 0 { ^ v } {}
    ? > dst src {
        : ~ i k - n 1
        ~ >= k 0 { ( __mem_store it + dst k 1 ( __mem_load it + src k 1 0 ) ) = k - k 1 }
    } {
        : ~ i k 0
        ~ < k n { ( __mem_store it + dst k 1 ( __mem_load it + src k 1 0 ) ) = k + k 1 }
    }
}

@ __mem_fill * Interp it i dst i val i n → v {
    : ~ i k 0
    ~ < k n { ( __mem_store it + dst k 1 val ) = k + k 1 }
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
