// match_payload_n.nu — regression for the 3-payload match-destructuring
// limit (CRITIC A6 / docs/LIMITATIONS → Enums).
//
// Bug: an enum's type + construction already supported N payload slots
// (`%E = { i64, ptr, ptr, ptr, ptr }`, with all insertvalues emitted), but
// the MATCH side capped binding at 3 — the parser stored only pv0/pv1/pv2
// and the emitter had three hand-unrolled slot blocks. A 4th+ payload was
// silently dropped (`use of undefined identifier 'd'`), forcing a post-match
// `.` extraction workaround.
//
// Fix: the parser now collects overflow payload names/literals (pv_over /
// lit_over, space-joined parallel lists), and the emitter binds slots 1..N-1
// through one `emit_enum_payload_bind` helper driven by a loop (slot 0 keeps
// its opt/res-aware reconstruction inline). Literal constraints on slots 3+
// loop through `emit_lit_check` the same way. Verified for 4- and 5-payload
// variants across mixed payload types (int / float / string / pointer), a
// literal constraint on slot 3, and a guard reading a slot-3 binding.

$ `stdlib/std/float.nu`

: Pt { i px  i py }

: | E {
    Quad i i i i
    Five i f s i i
    WithPtr i i i *Pt
    Leaf
}

@ ck b ok s label → v {
    ( nurl_print label ) ( nurl_print ? ok ` ok\n` ` FAIL\n` )
}

@ main → i {
    // 4 int payloads, slot 3 bound
    : E q @ E { Quad 10 20 30 40 }
    ?? q {
        Quad a b c d → { ( ck & & & == a 10 == b 20 == c 30 == d 40 `quad_4bind` ) }
        Five p w x y z → {}  WithPtr a b c r → {}  Leaf → {}
    }

    // 5 payloads, mixed int / float / string across slots 0..4
    : E f @ E { Five 7 2.5 `hi` 99 123 }
    ?? f {
        Quad a b c d → {}
        Five p w x y z → {
            ( ck & & & & == p 7 == # i w 2 != 0 ( nurl_str_eq x `hi` ) == y 99 == z 123 `five_mixed` )
        }
        WithPtr a b c r → {}  Leaf → {}
    }

    // pointer payload at slot 3
    : *Pt pp # *Pt ( nurl_alloc Z Pt )
    = . pp px 8
    : E w @ E { WithPtr 1 2 3 pp }
    ?? w {
        Quad a b c d → {}  Five p ww x y z → {}
        WithPtr a b c r → { ( ck & & == a 1 == c 3 == . r px 8 `withptr_slot3` ) }
        Leaf → {}
    }
    ( nurl_free # s pp )

    // literal constraint on slot 3 (4th payload)
    ?? q {
        Quad a b c 40 → { ( ck T `quad_slot3_lit` ) }
        Quad a b c d → { ( ck F `quad_slot3_lit` ) }
        Five p ww x y z → {}  WithPtr a b c r → {}  Leaf → {}
    }

    // guard that reads a slot-3 binding (guard runs AFTER payload binding)
    ?? q {
        Quad a b c d ? == d 40 → { ( ck T `quad_guard_slot3` ) }
        Quad a b c d → { ( ck F `quad_guard_slot3` ) }
        Five p ww x y z → {}  WithPtr a b c r → {}  Leaf → {}
    }

    ^ 0
}
