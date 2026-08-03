// enum_payload_canonical.nu — a narrow-int enum payload slot must hold
// the CANONICAL widened value of the DECLARED payload type regardless
// of the constructor expression's own type. `@ E { V 151 }` with an i8
// payload must store the same slot bits as `@ E { V # i8 151 }`
// (-105 sign-extended). Before the fix the bare-i64 form kept the raw
// 151, so a literal constraint (compared against the slot) and the
// pattern binding (trunc+extend of the slot) disagreed about the same
// logical value — found by the structural fuzzer (genprog seed 20).

: | E {
    ByteV i8 i
    HalfU u16
    Nil
}

@ ck b ok s label → v {
    ( nurl_print label ) ( nurl_print ? ok ` ok\n` ` FAIL\n` )
}

@ main → i {
    // bare i64 initializer for an i8 payload → canonical -105
    : E a @ E { ByteV 151 77 }
    : i ra ?? a {
        ByteV -105 x → x
        ByteV bx x → 0
        HalfU h → 1
        Nil → 2
    }
    ( ck == ra 77 `lit_constraint_canonical` )
    // binding reconstructs the same canonical value
    : i rb ?? a {
        ByteV bx x → # i bx
        HalfU h → 1
        Nil → 2
    }
    ( ck == rb -105 `binding_canonical` )
    // signed narrow value into a WIDER unsigned payload: i8 -1 → u16 0xFFFF
    : E c @ E { HalfU # i8 -1 }
    : i rc ?? c {
        ByteV bx x → 0
        HalfU h → # i h
        Nil → 2
    }
    ( ck == rc 65535 `sign_flip_canonical` )
    // typed narrow initializer stays canonical (regression guard)
    : E d @ E { ByteV # i8 151 77 }
    : i rd ?? d {
        ByteV -105 x → x
        ByteV bx x → 0
        HalfU h → 1
        Nil → 2
    }
    ( ck == rd 77 `typed_init_same_slot` )
    ^ 0
}
