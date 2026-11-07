// packages/nurllama/src/experts.nu — a Mixture of Experts' routed experts
// streamed from where they are stored, on demand (Agora #521).
//
// A model whose routed experts do not fit the device keeps `slots` of them
// there — a device cache, least recently used out first — and loads the
// ones a layer's router picks out of their file when they are not in it: a
// GGUF stack's range, a safetensors tensor, an EXL3 tensor group (whole or
// in tensor-parallel shares). The bytes come out of the file's mapping, so
// the host's page cache is the second level: RAM holds the experts it has
// room for, the disk the rest. A slot holds an expert exactly as the
// all-resident stack holds it, and the same kernels run over the slots —
// only the expert table changes, expert → slot — so the logits are the
// all-resident run's.
//
// This file is the bookkeeping: which (layer, expert) each slot holds, the
// LRU order, and the pass a slot is pinned in — a slot that launches
// recorded but not yet run read from is not given to another expert before
// they run. model.nu ("routed experts streamed") loads and computes.
//
//   ( xc_none )                     → LmExp     no cache: experts resident
//   ( xc_tables c slots nkeys )                 size the slot / key tables
//   ( xc_find c key )               → i         its slot (used now), or -1
//   ( xc_victim c )                 → i         a slot to load into, or -1
//   ( xc_bind c slot key )                      the slot now holds key
//   ( xc_next_pass c )                          what was recorded has run

$ `stdlib/core/vec.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `kernels.nu`

// Where the experts come from: a GGUF's stacks (each expert a range of
// one, in the GGUF's type, or as f32 when that type has no device kernel),
// a checkpoint's tensors (as f32), or a checkpoint's EXL3 tensor groups.
: i XC_GGUF 0

: i XC_ST 1

: i XC_EXL3 2

: LmExp {
    b on  // the routed experts go through the cache
    i src  // XC_GGUF, XC_ST or XC_EXL3
    // every layer's projection has one type the batched expert matvec
    // reads (f32, q8_0): a layer runs as five launches over the slots
    // (`poolw`); otherwise one matvec per (position, expert) (`slotw`)
    b batched
    i slots
    // per projection (gate, up, down): a block of slots · stride bytes —
    // the stack's layout, or the trellises — and, batched, its weight
    ( Vec GkBuf ) pool
    ( Vec LkW ) poolw
    ( Vec i ) stride
    // XC_EXL3: per projection, slots · sstride halves (suh | svh)
    ( Vec GkBuf ) spool
    ( Vec i ) sstride
    ( Vec LkW ) slotw  // slot · 3 + projection → the weight in that slot
    GkBuf stage  // q8_0: one expert before its repack into a slot
    GkBuf aux  // XC_EXL3: the scratch its matvecs rotate through
    ( Vec i ) key  // per slot: L · n_expert + e, -1 = empty
    ( Vec i ) last  // per slot: the tick it was last used
    ( Vec i ) pin  // per slot: the pass that may not lose it
    ( Vec i ) at  // per L · n_expert + e: its slot, -1 = not on the device
    i tick
    i pass
    // what it did (NURLLAMA_PROF / NURLLAMA_VERBOSE)
    i loads
    i hits
    i load_ns
    i load_bytes
}

@ xc_none → LmExp {
    ^ @ LmExp { F XC_GGUF F 0 ( vec_new [GkBuf] ) ( vec_new [LkW] ) ( vec_new [i] ) ( vec_new [GkBuf] ) ( vec_new [i] ) ( vec_new [LkW] )
        ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) 0 1 0 0 0 0 }
}

// `slots` empty slots, and no key (of nkeys) on the device.
@ xc_tables inout LmExp c i slots i nkeys → v {
    = . c slots slots
    : ~ i s 0
    ~ < s slots {
        ( vec_push [LkW] . c slotw ( lk_w_none ) )
        ( vec_push [LkW] . c slotw ( lk_w_none ) )
        ( vec_push [LkW] . c slotw ( lk_w_none ) )
        ( vec_push [i] . c key -1 )
        ( vec_push [i] . c last 0 )
        ( vec_push [i] . c pin 0 )
        = s + s 1
    }
    : ~ i k 0
    ~ < k nkeys {
        ( vec_push [i] . c at -1 )
        = k + k 1
    }
}

// Slot `s` is used now, by the pass being recorded.
@ __xc_use inout LmExp c i s → v {
    = . c tick + . c tick 1
    : b _a ( vec_set [i] . c last s . c tick )
    : b _b ( vec_set [i] . c pin s . c pass )
}

// The slot holding `key` (marked used), or -1.
@ xc_find inout LmExp c i key → i {
    : i s ?? ( vec_get [i] . c at key ) { T x → x F → -1 }
    ? >= s 0 {
        ( __xc_use c s )
        = . c hits + . c hits 1
    } {}
    ^ s
}

// A slot to load into: an empty one, else the least recently used one the
// pass being recorded has not used; -1 when it has used them all (run what
// is recorded, xc_next_pass, ask again).
@ xc_victim LmExp c → i {
    : ~ i best -1
    : ~ i bl 0
    : ~ i s 0
    ~ < s . c slots {
        : i k ( vec_at [i] . c key s )
        ? < k 0 { ^ s } {}
        ? != ( vec_at [i] . c pin s ) . c pass {
            : i l ( vec_at [i] . c last s )
            ? | < best 0 < l bl {
                = best s
                = bl l
            } {}
        } {}
        = s + s 1
    }
    ^ best
}

// Slot `s` now holds `key` — whatever it held is gone — marked used.
@ xc_bind inout LmExp c i s i key → v {
    : i old ( vec_at [i] . c key s )
    ? >= old 0 { : b _a ( vec_set [i] . c at old -1 ) } {}
    : b _b ( vec_set [i] . c key s key )
    : b _c ( vec_set [i] . c at key s )
    = . c loads + . c loads 1
    ( __xc_use c s )
}

// Every launch recorded so far has run: no slot is pinned any more.
@ xc_next_pass inout LmExp c → v { = . c pass + . c pass 1 }
