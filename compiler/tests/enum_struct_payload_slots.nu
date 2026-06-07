// enum_struct_payload_slots.nu — regression for a codegen hole where a
// multi-field STRUCT value carried as an enum payload in a NON-slot-0
// position (`: | E { Nil  V  i Pt }`) emitted invalid IR.
//
// Bug: enum construction (gen_agg_lit) heap-boxes a `%`-named struct
// payload for EVERY payload slot, but the match/unbox side only
// reconstructed it for slot 0 (`pv0`). Slots 1 and 2 (`pv1`/`pv2`) fell
// through to the catch-all `bitcast ptr … to i8*`, so the arm bound a
// `ptr`/`i8*` where the struct type was expected — clang rejected the
// store (`'%rNN' defined with type 'ptr' but expected '%Pt'`). A struct
// payload only round-tripped when it happened to be the FIRST payload.
//
// Fix: slots 1/2 now mirror slot 0's reconstruction — a single-pointer
// handle (f0 is a pointer) is rebuilt via `insertvalue`; a multi-field
// struct / enum / anon aggregate is loaded back through its heap-box
// pointer.
//
// main returns the number of failed checks (0 = all pass).

: Pt { i x i y }
: Trip { i a i b i c }

// Struct payload in each non-trivial slot position.
: | S1 { NilA WrapA i Pt }  // struct in slot 1 (after an int)
: | S2 { NilB WrapB i i Pt }  // struct in slot 2 (after two ints)
: | S0 { NilC WrapC Pt }  // struct in slot 0 (regression guard)
: | TwoS { NilD WrapD Pt Pt }  // structs in slots 0 AND 1
: | Mix { NilE WrapE Pt i Trip }  // struct, int, bigger struct across all 3

@ chk i got i want s tag → i {
    ? == got want {
        ( nurl_print tag ) ( nurl_print ` ok\n` ) ^ 0
    } {
        ( nurl_print tag ) ( nurl_print ` FAIL\n` ) ^ 1
    }
}

@ main → i {
    : ~ i f 0

    // Slot 1: int + struct.
    : Pt p1 @ Pt { 10 20 }
    : S1 e1 @ S1 { WrapA 5 p1 }
    = f + f ?? e1 { WrapA n q → ( chk + n + . q x . q y 35 `slot1_struct` ) NilA → 1 }

    // Slot 2: int + int + struct.
    : Pt p2 @ Pt { 100 200 }
    : S2 e2 @ S2 { WrapB 1 2 p2 }
    = f + f ?? e2 { WrapB a b q → ( chk + a + b + . q x . q y 303 `slot2_struct` ) NilB → 1 }

    // Slot 0 only (the path that already worked — guard against regression).
    : Pt p0 @ Pt { 3 4 }
    : S0 e0 @ S0 { WrapC p0 }
    = f + f ?? e0 { WrapC q → ( chk + . q x . q y 7 `slot0_struct` ) NilC → 1 }

    // Two struct payloads, slots 0 and 1.
    : Pt pa @ Pt { 3 4 }
    : Pt pb @ Pt { 5 6 }
    : TwoS et @ TwoS { WrapD pa pb }
    = f + f ?? et {
        WrapD a b → ( chk + . a x + . a y + . b x . b y 18 `slot0_and_slot1_struct` )
        NilD → 1
    }

    // All three slots populated: struct (2-field), int, struct (3-field).
    : Pt mp @ Pt { 7 8 }
    : Trip mt @ Trip { 1 2 3 }
    : Mix em @ Mix { WrapE mp 9 mt }
    ?? em {
        WrapE q n t → {
            = f + f ( chk + . q x . q y 15 `mix_slot0_struct` )
            = f + f ( chk n 9 `mix_slot1_int` )
            = f + f ( chk + . t a + . t b . t c 6 `mix_slot2_struct` )
        }
        NilE → {}
    }

    ^ f
}
