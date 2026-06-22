// enum_float_payload.nu — regression for a codegen hole where a FLOAT
// (`f` / `f32`) value carried as an enum payload emitted invalid IR.
//
// Bug: an enum's payload slot is uniformly pointer-typed. Construction
// (gen_agg_lit) coerced i1 / integer / string / struct payloads into the
// `ptr` slot, but had NO branch for `double` / `float`, so a float payload
// emitted `insertvalue %E …, double X, 1` into a `ptr` field — clang
// rejected (`operand and field disagree in type: 'double' instead of
// 'ptr'`). The match/unbox side had the symmetric gap (a `double` payload
// fell through to the `bitcast ptr … to i8*` catch-all). ANY sum type with
// a float payload — a numeric AST, a real-valued JSON, a geometry variant —
// was uncompilable, even though the grammar permits it
// (`enum_variant = IDENT type*`, and `type` includes `f`).
//
// Fix: gen_agg_lit bitcasts the float to a same-width int (f32 widens
// i32→i64) and `inttoptr`s it into the slot; the match arm inverts it via
// `emit_enum_float_extract` (ptrtoint → bitcast, f32 truncs first). Verified
// across payload slots 0/1/2, a mixed float+pointer recursive enum, and a
// genuine `f32` value. (An IMPLICIT double-literal → `f32` narrowing still
// needs an explicit `# f32` cast, exactly as struct construction requires —
// out of scope here.)

: | E {
    Num f
    Pair f f
    Triple f f f
    Boxed * E
    F32 f32
}

@ ck b ok s label → v {
    ( nurl_print label ) ( nurl_print ? ok ` ok\n` ` FAIL\n` )
}

@ main → i {
    // slot 0 (double)
    : E a @ E { Num 3.5 }
    ?? a {
        Num c → { ( ck == c 3.5 `num_slot0` ) }
        Pair x y → {}
        Triple x y z → {}
        Boxed p → {}
        F32 v → {}
    }

    // slots 0 + 1 (double)
    : E b @ E { Pair 1.25 6.5 }
    ?? b {
        Num c → {}
        Pair x y → { ( ck & == x 1.25 == y 6.5 `pair_slots01` ) }
        Triple x y z → {}
        Boxed p → {}
        F32 v → {}
    }

    // slot 2 (double)
    : E t @ E { Triple 1.0 2.0 9.75 }
    ?? t {
        Num c → {}
        Pair x y → {}
        Triple x y z → { ( ck & & == x 1.0 == y 2.0 == z 9.75 `triple_slots012` ) }
        Boxed p → {}
        F32 v → {}
    }

    // mixed float + pointer recursive enum: Boxed holds a *E whose Num is float
    : *E inner ( box_e @ E { Num 4.25 } )
    : E w @ E { Boxed inner }
    ?? w {
        Num c → {}
        Pair x y → {}
        Triple x y z → {}
        Boxed p → {
            : E ie . p 0
            ?? ie {
                Num c2 → { ( ck == c2 4.25 `boxed_float_child` ) }
                Pair x y → {}
                Triple x y z → {}
                Boxed q → {}
                F32 v → {}
            }
        }
        F32 v → {}
    }

    // genuine f32 value round-trip (explicit cast)
    : f32 fv # f32 2.5
    : E g @ E { F32 fv }
    ?? g {
        Num c → {}
        Pair x y → {}
        Triple x y z → {}
        Boxed p → {}
        F32 v → { ( ck == # f v 2.5 `f32_roundtrip` ) }
    }

    ( nurl_free # s inner )
    ^ 0
}

@ box_e E e → *E {
    : *E p ( my_alloc )
    = . p 0 e
    ^ p
}

@ my_alloc → *E { ^ # *E ( nurl_alloc Z E ) }
