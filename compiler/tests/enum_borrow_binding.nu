// Regression: borrow-provenance for auto-Drop enum trees. An accessor
// that RETURNS A BORROW into the tree (e.g. `first_kid` → vec_get of a
// child) assigned to a `:`-binding must NOT auto-drop that binding —
// doing so would double-free the tree that still owns the node. The
// compiler marks the accessor `ret_borrow` (its result aliases a
// parameter) and skips the binding's drop. Conversely an OWNED result
// (a fresh `@`-construction returned) must still drop exactly once.
//
// Build with ./build.sh; the memory proof (no leak, no double-free) is
// under ASan/LSan. Prints PASS; returns the failure count.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Elem { String tag ( Vec Node ) kids }
: | Node { NText String NElem Elem }
: NBox { Node n }

@ mk_text s t → Node { ^ @ Node { NText ( string_from t ) } }

@ mk_elem s tag → NBox { ^ @ NBox { @ Node { NElem @ Elem { ( string_from tag ) ( vec_new [Node] ) } } } }

// Returns a BORROW: the first child Node aliases `parent`'s kids Vec.
// Implicit (no `^`) nested-match block return through vec_get — exactly
// the shape that used to double-free.
@ first_kid Node parent → Node {
    ?? parent {
        NElem e → ?? ( vec_get [Node] . e kids 0 ) { T y → y F → parent }
        NText _ → parent
    }
}

// Returns an OWNED value (fresh) — the caller's `:`-binding MUST drop it.
@ make_owned s t → Node { ^ ( mk_text t ) }

@ kid_count Node n → i {
    ?? n { NElem e → ( vec_len [Node] . e kids ) NText _ → 0 }
}

@ build → Node {
    : NBox rb ( mk_elem `root` )
    ?? . rb n {
        NElem e → {
            ( vec_push [Node] . e kids ( mk_text `first-child` ) )
            ( vec_push [Node] . e kids ( mk_text `second-child` ) )
        }
        NText _ → {}
    }
    ^ . rb n
}

@ main → i {
    : ~ i fails 0

    : Node tree ( build )
    ? != ( kid_count tree ) 2 { ( nurl_print `  FAIL kid count\n` ) = fails + fails 1 } {}

    // BORROW binding off an accessor — must NOT be auto-dropped (the tree
    // owns the node). Before the fix this double-freed at scope exit.
    : Node child ( first_kid tree )
    ?? child { NText _ → {} NElem _ → { ( nurl_print `  FAIL child not text\n` ) = fails + fails 1 } }

    // OWNED binding off a fresh constructor — must drop exactly once
    // (leak-free; verified by LSan).
    : Node owned ( make_owned `owned-node` )
    ?? owned { NText _ → {} NElem _ → { ( nurl_print `  FAIL owned not text\n` ) = fails + fails 1 } }

    // `tree` drops here (frees the whole tree once). `child` is a borrow
    // into it (no drop). `owned` is owned (drops once). No double-free.

    ? == fails 0 { ( nurl_print `enum_borrow_binding: PASS\n` ) } {
        ( nurl_print `enum_borrow_binding: ` ) ( nurl_print ( nurl_str_int fails ) ) ( nurl_print ` FAILURES\n` )
    }
    ^ fails
}
