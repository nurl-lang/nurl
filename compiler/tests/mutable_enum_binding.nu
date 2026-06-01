// Test: bare-variant-name enum bindings (`: Color c Red`, `: ~ Color c Red`,
// `= c Green`). Previously a bare variant name resolves through gen_ident's
// __global path to a loaded i64 tag, and `coerce_store_val` had no
// i64 → %Enum wrap — so the let / assign stored a raw i64 into a %Enum
// slot and LLVM rejected the IR with a type mismatch.
//
// Fix: `coerce_store_val` now detects when the destination is a registered
// enum type (`<name>__variants` side-table set) and emits an
// `insertvalue %Enum undef, i64 val, 0` wrapper before the store.
//
// Covers `: ~ MyEnum` mutable enum binding. Also incidentally the same shape
// in the immutable case (`: NetErr last NetOther`), which was equally
// broken but undocumented.

: | Color { Red Green Blue }

// Mirrors the real NetErr / IoErr-style narrow enum the http stack uses.
: | NetishErr { NetOk NetTimeout NetDns NetOther }

// Wide enum (one variant carries a payload) — exercises the
// `%Foo = type { i64, ptr }` shape: the insertvalue wrapper must
// only touch field 0 and leave the payload slot undef.
: | Status { Idle Busy Err i }

@ name_color Color c → s {
    ?? c {
        Red → `red`
        Green → `green`
        Blue → `blue`
    }
}

@ main → i {
    // ── Immutable narrow ──────────────────────────────────────────
    : Color c1 Red
    ( nurl_print `c1: ` ) ( nurl_print ( name_color c1 ) ) ( nurl_print `\n` )

    // ── Mutable narrow with reassignment ─────────────────────────
    : ~ Color c2 Green
    ( nurl_print `c2/init: ` ) ( nurl_print ( name_color c2 ) ) ( nurl_print `\n` )
    = c2 Blue
    ( nurl_print `c2/blue: ` ) ( nurl_print ( name_color c2 ) ) ( nurl_print `\n` )
    = c2 Red
    ( nurl_print `c2/red: ` ) ( nurl_print ( name_color c2 ) ) ( nurl_print `\n` )

    // ── http_server.nu-style sentinel pattern, now native ─────────
    // Was: `: ~ b had_err F` + sentinel-flag dance.
    // Now: real mutable enum binding for the error state.
    : ~ NetishErr last_err NetOk
    // ... simulate a step that updates the error variant directly ...
    = last_err NetTimeout
    ?? last_err {
        NetOk → ( nurl_print `last_err: ok?!\n` )
        NetTimeout → ( nurl_print `last_err: timeout\n` )
        NetDns → ( nurl_print `last_err: dns\n` )
        NetOther → ( nurl_print `last_err: other\n` )
    }
    = last_err NetDns
    ?? last_err {
        NetOk → ( nurl_print `last_err2: ok\n` )
        NetTimeout → ( nurl_print `last_err2: timeout?!\n` )
        NetDns → ( nurl_print `last_err2: dns\n` )
        NetOther → ( nurl_print `last_err2: other?!\n` )
    }

    // ── Wide enum: tag-only variant via bare name still wraps cleanly ─
    : ~ Status s Idle
    = s Busy
    ?? s {
        Idle → ( nurl_print `s: idle?!\n` )
        Busy → ( nurl_print `s: busy\n` )
        Err _ → ( nurl_print `s: err?!\n` )
    }

    // Wide enum: payload-bearing variant goes through @ Foo { … } as before
    = s @ Status { Err 7 }
    ?? s {
        Idle → ( nurl_print `s2: idle?!\n` )
        Busy → ( nurl_print `s2: busy?!\n` )
        Err n → {
            ( nurl_print `s2: err=` )
            ( nurl_print ( nurl_str_int n ) ) ( nurl_print `\n` )
        }
    }

    ^ 0
}
