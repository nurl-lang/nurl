// Regression: compiler-generated recursive Drop for boxed-payload enum
// trees. `Node` is an enum whose `NElem` variant carries a multi-field
// struct (`Elem`) — heap-boxed by gen_agg_lit. `Elem` owns a tag String
// and two Vecs (attributes, and child Nodes — a recursive tree). With
// the auto-Drop, an owned `Node` tree freed ONLY by going out of scope
// must reclaim every box, String and Vec exactly once: no leak, no
// double-free. Build with ./build.sh; for the memory proof run under
// ASan/LSan (compiler/tests/run_san_tests.sh with LSAN_DETECT_LEAKS=1).
//
// This is the shape `stdlib/ext/xml.nu` would use as a natural enum
// (XText / XElem) now that the box leak is fixed at the root.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Attr { String name String value }
: Elem { String tag ( Vec Attr ) attrs ( Vec Node ) kids }
: | Node { NText String  NElem Elem }

// A struct wrapper so a freshly-built node can be handed around and its
// inner Node pushed into a parent's `kids` as a field-extract (a
// temporary, never an auto-dropped `:` binding) — exactly how a parser
// threads parsed children.
: NBox { Node n }

@ mk_text s t → Node {
    ^ @ Node { NText ( string_from t ) }
}

@ mk_elem s tag → NBox {
    ^ @ NBox { @ Node { NElem @ Elem { ( string_from tag ) ( vec_new [Attr] ) ( vec_new [Node] ) } } }
}

@ set_attr Node n s k s val → v {
    ?? n {
        NElem e → ( vec_push [Attr] . e attrs @ Attr { ( string_from k ) ( string_from val ) } )
        NText _ → {}
    }
}

@ kid_count Node n → i {
    ?? n { NElem e → ( vec_len [Node] . e kids ) NText _ → 0 }
}

@ tag_eq Node n s want → b {
    ?? n {
        NElem e → == 1 ( nurl_str_eq ( string_data . e tag ) want )
        NText _ → F
    }
}

// Build:  <root id="1"><greet>hi</greet>text<sub class="c">deep</sub></root>
@ build → Node {
    : NBox rootb ( mk_elem `root` )
    ?? . rootb n {
        NElem e → {
            ( set_attr . rootb n `id` `1` )
            // nested element child (built via wrapper, pushed as field-extract)
            : NBox greetb ( mk_elem `greet` )
            ?? . greetb n {
                NElem ge → ( vec_push [Node] . ge kids ( mk_text `hi` ) )
                NText _ → {}
            }
            ( vec_push [Node] . e kids . greetb n )
            // a bare text child
            ( vec_push [Node] . e kids ( mk_text `text-between` ) )
            // another nested element with an attribute + text
            : NBox subb ( mk_elem `sub` )
            ( set_attr . subb n `class` `c` )
            ?? . subb n {
                NElem se → ( vec_push [Node] . se kids ( mk_text `deep-content` ) )
                NText _ → {}
            }
            ( vec_push [Node] . e kids . subb n )
        }
        NText _ → {}
    }
    ^ . rootb n
}

@ main → i {
    : ~ i fails 0

    : Node tree ( build )
    ? ! ( tag_eq tree `root` ) { ( nurl_print `  FAIL root tag\n` ) = fails + fails 1 } {}
    ? != ( kid_count tree ) 3 { ( nurl_print `  FAIL kid count\n` ) = fails + fails 1 } {}

    // Walk into the first child (the <greet> element) and check its text.
    ?? tree {
        NElem e → {
            ?? ( vec_get [Node] . e kids 0 ) {
                T k0 → {
                    ? ! ( tag_eq k0 `greet` ) { ( nurl_print `  FAIL child0 tag\n` ) = fails + fails 1 } {}
                    ? != ( kid_count k0 ) 1 { ( nurl_print `  FAIL greet kids\n` ) = fails + fails 1 } {}
                }
                F → { ( nurl_print `  FAIL no child0\n` ) = fails + fails 1 }
            }
        }
        NText _ → { ( nurl_print `  FAIL tree not elem\n` ) = fails + fails 1 }
    }

    // `tree` is an owned local: at scope exit the compiler-generated
    // drop__Node reclaims the whole tree (boxes + Strings + Vecs)
    // recursively, exactly once. No manual free anywhere.

    ? == fails 0 { ( nurl_print `enum_tree_drop: PASS\n` ) } {
        ( nurl_print `enum_tree_drop: ` ) ( nurl_print ( nurl_str_int fails ) ) ( nurl_print ` FAILURES\n` )
    }
    ^ fails
}
