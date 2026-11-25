// coreir.nu — nurlc's core IR (`nurlc --emit-core`) read into records.
//
// The text is docs/dev/CORE_IR.md §2: tab-separated header lines and one
// statement a line.
//
//   fn    <name> <return type> <parameters> <line> <file> <flags> <template>
//   v     <id> <kind> <depth> <flags> <line> <value block> <name> <type>
//   <statements>
//   endfn
//   ty    <type> <class> <drops> <base> A <n> <type>… F <n> (<field> <type>)… V <n> (<variant> <n> <type>…)…
//   virt  <virtual callee> <impl function>…
//   sum   <function> <parameters> (<key>=<words>)…
//
// One reader for every tool that reads the IR (the certificate's
// translator, tolean.nu, first). It keeps what the text says and decides
// nothing: a function's variables in the order of their `v` lines, its
// statements as lines and as words, each `ty`, `sum` and `virt` line as a
// record. Where a name has more than one record (a `sum` or a `ty` line
// printed twice), the lookups answer the last one, and a variable's id
// its last `v` line.
//
// Lines are split as Python's `str.splitlines` splits ASCII text, and a
// statement's words at ASCII whitespace, so a reader written against the
// Python prototypes (tools/ncore) sees the same lines and words.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/hashmap.nu`

// A variable of a function (a `v` line).
: CoreVar {
    i id
    i kind
    i depth
    i flags
    i line
    i vblock
    String name
    String ty
}

// A function (`fn` … `endfn`).
: CoreFn {
    String name
    String ret
    i np
    i line
    String file
    i flags
    String template
    ( Vec CoreVar ) vars
    // a variable's id → its record in `vars` (the last `v` line), -1 none
    ( Vec i ) vidx
    // the statement lines, without the whitespace around them
    ( Vec String ) body
    // every statement's words, line after line: line k's are
    // words[wstart[k] .. wstart[k + 1])
    ( Vec String ) words
    ( Vec i ) wstart
}

// A type (`ty`): its columns, its fields and its variants.
: CoreTy {
    String name
    String cls
    String drops
    String base
    ( Vec String ) targs
    ( Vec String ) fnames
    ( Vec String ) ftys
    ( Vec String ) vnames
    // variant k's payload types are vtys[vstart[k] .. vstart[k + 1])
    ( Vec i ) vstart
    ( Vec String ) vtys
}

// What the walk's summary holds for a function (`sum`): key=value pairs,
// in the line's order.
: CoreSum {
    String name
    i np
    ( Vec String ) keys
    ( Vec String ) vals
}

// The impl functions a `dyn` method call may run (`virt`).
: CoreVirt {
    String callee
    ( Vec String ) impls
}

: CoreIR {
    ( Vec CoreFn ) fns
    ( Vec CoreTy ) tys
    ( Vec CoreSum ) sums
    ( Vec CoreVirt ) virts
    ( HashMap String i ) ty_of
    ( HashMap String i ) sum_of
}

// ── Characters and words ─────────────────────────────────────────────

// ASCII whitespace as Python's str.split / str.strip take it.
@ core_is_ws i c → b { ^ | | == c 32 & >= c 9 <= c 13 & >= c 28 <= c 31 }

// A line break as Python's str.splitlines takes it (\n, \r, \v, \f, \x1c–\x1e).
@ __cr_is_nl i c → b { ^ | | | == c 10 == c 13 | == c 11 == c 12 & >= c 28 <= c 30 }

// The whitespace-separated words of t[a, z), pushed onto `out`.
@ core_split_words ( Slice u ) t i a i z ( Vec String ) out → v {
    : ~ i k a
    ~ < k z {
        ~ & < k z ( core_is_ws ( slice_byte t k ) ) { = k + k 1 }
        ? < k z {
            : ~ i e k
            ~ & < e z ! ( core_is_ws ( slice_byte t e ) ) { = e + e 1 }
            : String w ( string_new )
            ( string_push_window w t k - e k )
            ( vec_push [String] out w )
            = k e
        } {}
    }
}

// The tab-separated columns of t[a, z) (an empty one kept).
@ __cr_split_tabs ( Slice u ) t i a i z → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : ~ i k a
    : ~ b more T
    ~ more {
        : ~ i e k
        ~ & < e z != ( slice_byte t e ) 9 { = e + e 1 }
        : String w ( string_new )
        ( string_push_window w t k - e k )
        ( vec_push [String] out w )
        ? < e z { = k + e 1 } { = more F }
    }
    ^ out
}

// The decimal number `s` reads as (an optional `-`, then digits), 0 when
// there is none.
@ core_int s text → i {
    : ( Slice u ) t ( slice_of_str text )
    : i n ( slice_len [u] t )
    : ~ i k 0
    : ~ b neg F
    ? & > n 0 == ( slice_byte t 0 ) 45 { = neg T = k 1 } {}
    : ~ i v 0
    ~ & < k n & >= ( slice_byte t k ) 48 <= ( slice_byte t k ) 57 {
        = v + * v 10 - ( slice_byte t k ) 48
        = k + k 1
    }
    ^ ? neg - 0 v v
}

@ __cr_col ( Vec String ) f i k → s {
    ? < k ( vec_len [String] f ) { ^ ( string_data ( vec_at [String] f k ) ) } {}
    ^ ``
}

@ __cr_is ( Vec String ) f i k s want → b { ^ != 0 ( nurl_str_eq ( __cr_col f k ) want ) }

@ __cr_hash String x → i { ^ ( hash_string ( string_data x ) ) }

@ __cr_eq String a String b → b { ^ ( eq_string ( string_data a ) ( string_data b ) ) }

// ── The reader ───────────────────────────────────────────────────────

@ __cr_ty ( Vec String ) f → CoreTy {
    : ( Vec String ) targs ( vec_new [String] )
    : ( Vec String ) fnames ( vec_new [String] )
    : ( Vec String ) ftys ( vec_new [String] )
    : ( Vec String ) vnames ( vec_new [String] )
    : ( Vec i ) vstart ( vec_new [i] )
    : ( Vec String ) vtys ( vec_new [String] )
    : i n ( vec_len [String] f )
    // ty <type> <class> <drops> <base> A <n> … F <n> … V <n> …
    : ~ i k 5
    ? ( __cr_is f k `A` ) {
        : i na ( core_int ( __cr_col f + k 1 ) )
        = k + k 2
        : ~ i j 0
        ~ & < j na < k n {
            ( vec_push [String] targs ( string_from ( __cr_col f k ) ) )
            = k + k 1
            = j + j 1
        }
    } {}
    ? ( __cr_is f k `F` ) {
        : i nf ( core_int ( __cr_col f + k 1 ) )
        = k + k 2
        : ~ i j 0
        ~ & < j nf < + k 1 n {
            ( vec_push [String] fnames ( string_from ( __cr_col f k ) ) )
            ( vec_push [String] ftys ( string_from ( __cr_col f + k 1 ) ) )
            = k + k 2
            = j + j 1
        }
    } {}
    ? ( __cr_is f k `V` ) {
        : i nv ( core_int ( __cr_col f + k 1 ) )
        = k + k 2
        : ~ i j 0
        ~ & < j nv < + k 1 n {
            ( vec_push [String] vnames ( string_from ( __cr_col f k ) ) )
            ( vec_push [i] vstart ( vec_len [String] vtys ) )
            : i np ( core_int ( __cr_col f + k 1 ) )
            = k + k 2
            : ~ i q 0
            ~ & < q np < k n {
                ( vec_push [String] vtys ( string_from ( __cr_col f k ) ) )
                = k + k 1
                = q + q 1
            }
            = j + j 1
        }
    } {}
    ( vec_push [i] vstart ( vec_len [String] vtys ) )
    ^ @ CoreTy { ( string_from ( __cr_col f 1 ) ) ( string_from ( __cr_col f 2 ) ) ( string_from ( __cr_col f 3 ) )
        ( string_from ( __cr_col f 4 ) ) targs fnames ftys vnames vstart vtys }
}

@ __cr_sum ( Vec String ) f → CoreSum {
    : ( Vec String ) keys ( vec_new [String] )
    : ( Vec String ) vals ( vec_new [String] )
    : i n ( vec_len [String] f )
    : ~ i k 3
    ~ < k n {
        : String kv ( vec_at [String] f k )
        ?? ( string_index_of kv `=` ) {
            T e → {
                ( vec_push [String] keys ( string_substr kv 0 e ) )
                ( vec_push [String] vals ( string_substr kv + e 1 - - ( string_len kv ) e 1 ) )
            }
            F → {}
        }
        = k + k 1
    }
    ^ @ CoreSum { ( string_from ( __cr_col f 1 ) ) ( core_int ( __cr_col f 2 ) ) keys vals }
}

@ __cr_new_fn ( Vec String ) f → CoreFn {
    ^ @ CoreFn { ( string_from ( __cr_col f 1 ) ) ( string_from ( __cr_col f 2 ) ) ( core_int ( __cr_col f 3 ) )
        ( core_int ( __cr_col f 4 ) ) ( string_from ( __cr_col f 5 ) ) ( core_int ( __cr_col f 6 ) )
        ( string_from ( __cr_col f 7 ) ) ( vec_new [CoreVar] ) ( vec_new [i] ) ( vec_new [String] ) ( vec_new [String] )
        ( vec_new [i] ) }
}

// A function's record finished: its id index and the words' end.
@ __cr_seal inout CoreFn fn → v {
    : i nv ( vec_len [CoreVar] . fn vars )
    : ~ i top -1
    : ~ i k 0
    ~ < k nv {
        : i id . ( vec_at [CoreVar] . fn vars k ) id
        ? > id top { = top id } {}
        = k + k 1
    }
    : ~ i j 0
    ~ <= j top { ( vec_push [i] . fn vidx -1 ) = j + j 1 }
    = k 0
    ~ < k nv {
        : i id . ( vec_at [CoreVar] . fn vars k ) id
        ? >= id 0 { ( vec_put [i] . fn vidx id k ) } {}
        = k + k 1
    }
    ( vec_push [i] . fn wstart ( vec_len [String] . fn words ) )
}

// The core IR in `text`.
@ core_read s text → CoreIR {
    : ( Vec CoreFn ) fns ( vec_new [CoreFn] )
    : ( Vec CoreTy ) tys ( vec_new [CoreTy] )
    : ( Vec CoreSum ) sums ( vec_new [CoreSum] )
    : ( Vec CoreVirt ) virts ( vec_new [CoreVirt] )
    : ( HashMap String i ) ty_of ( map_new [String i] )
    : ( HashMap String i ) sum_of ( map_new [String i] )
    : ( Slice u ) t ( slice_of_str text )
    : i n ( slice_len [u] t )
    : ~ CoreFn cur ( __cr_new_fn ( vec_new [String] ) )
    : ~ b in_fn F
    : ~ i a 0
    ~ < a n {
        : ~ i z a
        ~ & < z n ! ( __cr_is_nl ( slice_byte t z ) ) { = z + z 1 }
        // (`\r\n` is one break)
        : i nxt ? & & < + z 1 n == ( slice_byte t z ) 13 == ( slice_byte t + z 1 ) 10 + z 2 + z 1
        // the line without the whitespace around it
        : ~ i sa a
        ~ & < sa z ( core_is_ws ( slice_byte t sa ) ) { = sa + sa 1 }
        : ~ i sz z
        ~ & > sz sa ( core_is_ws ( slice_byte t - sz 1 ) ) { = sz - sz 1 }
        ? < sa sz {
            : ( Vec String ) f ( __cr_split_tabs t a z )
            : s f0 ( __cr_col f 0 )
            ? != 0 ( nurl_str_eq f0 `fn` ) {
                = cur ( __cr_new_fn f )
                = in_fn T
            } {
                ? & in_fn != 0 ( nurl_str_eq f0 `v` ) {
                    : i nf ( vec_len [String] f )
                    : String vname ? >= nf 9 ( string_from ( __cr_col f 7 ) ) ( string_new )
                    : CoreVar cv @ CoreVar { ( core_int ( __cr_col f 1 ) ) ( core_int ( __cr_col f 2 ) ) ( core_int ( __cr_col f 3 ) )
                        ( core_int ( __cr_col f 4 ) ) ( core_int ( __cr_col f 5 ) ) ( core_int ( __cr_col f 6 ) ) vname
                        ( string_from ( __cr_col f - nf 1 ) ) }
                    ( vec_push [CoreVar] . cur vars cv )
                } {
                    ? & ! in_fn != 0 ( nurl_str_eq f0 `sum` ) {
                        : CoreSum sm ( __cr_sum f )
                        : ?i _o ( map_set [String i] sum_of ( string_clone . sm name ) ( vec_len [CoreSum] sums ) \ String x → i { ^ ( __cr_hash x ) } \ String p String q → b { ^ ( __cr_eq p q ) } )
                        ( vec_push [CoreSum] sums sm )
                    } {
                        ? & ! in_fn != 0 ( nurl_str_eq f0 `ty` ) {
                            : CoreTy ct ( __cr_ty f )
                            : ?i _o ( map_set [String i] ty_of ( string_clone . ct name ) ( vec_len [CoreTy] tys ) \ String x → i { ^ ( __cr_hash x ) } \ String p String q → b { ^ ( __cr_eq p q ) } )
                            ( vec_push [CoreTy] tys ct )
                        } {
                            ? & ! in_fn != 0 ( nurl_str_eq f0 `virt` ) {
                                : ( Vec String ) impls ( vec_new [String] )
                                : ~ i k 2
                                ~ < k ( vec_len [String] f ) { ( vec_push [String] impls ( string_from ( __cr_col f k ) ) ) = k + k 1 }
                                ( vec_push [CoreVirt] virts @ CoreVirt { ( string_from ( __cr_col f 1 ) ) impls } )
                            } {
                                ? & in_fn != 0 ( nurl_str_eq f0 `endfn` ) {
                                    ( __cr_seal cur )
                                    ( vec_push [CoreFn] fns cur )
                                    = cur ( __cr_new_fn ( vec_new [String] ) )
                                    = in_fn F
                                } {
                                    ? in_fn {
                                        : String line ( string_new )
                                        ( string_push_window line t sa - sz sa )
                                        ( vec_push [String] . cur body line )
                                        ( vec_push [i] . cur wstart ( vec_len [String] . cur words ) )
                                        ( core_split_words t sa sz . cur words )
                                    } {}
                                }
                            }
                        }
                    }
                }
            }
        } {}
        = a nxt
    }
    ^ @ CoreIR { fns tys sums virts ty_of sum_of }
}

// ── Lookups ──────────────────────────────────────────────────────────

// The record of type `name`, or -1.
@ core_ty_index CoreIR ir s name → i {
    ^ ?? ( map_get_with [String i s] . ir ty_of name \ s x → i { ^ ( hash_string x ) } \ String p s q → b { ^ ( eq_string ( string_data p ) q ) } ) {
        T k → k
        F → -1
    }
}

// The summary of function `name`, or -1.
@ core_sum_index CoreIR ir s name → i {
    ^ ?? ( map_get_with [String i s] . ir sum_of name \ s x → i { ^ ( hash_string x ) } \ String p s q → b { ^ ( eq_string ( string_data p ) q ) } ) {
        T k → k
        F → -1
    }
}

// The value of `key` in a summary (the last pair with that key), or -1.
@ core_sum_key CoreSum sm s key → i {
    : ~ i k - ( vec_len [String] . sm keys ) 1
    ~ >= k 0 {
        ? != 0 ( nurl_str_eq ( string_data ( vec_at [String] . sm keys k ) ) key ) { ^ k } {}
        = k - k 1
    }
    ^ -1
}

// The number of words of statement k.
@ core_nwords CoreFn fn i k → i { ^ - ( vec_at [i] . fn wstart + k 1 ) ( vec_at [i] . fn wstart k ) }

// Word j of statement k ("" past its last).
@ core_word CoreFn fn i k i j → s {
    ? | < j 0 >= j ( core_nwords fn k ) { ^ `` } {}
    ^ ( string_data ( vec_at [String] . fn words + ( vec_at [i] . fn wstart k ) j ) )
}

// The record in `vars` of variable `id`, or -1.
@ core_var CoreFn fn i id → i {
    ? | < id 0 >= id ( vec_len [i] . fn vidx ) { ^ -1 } {}
    ^ ( vec_at [i] . fn vidx id )
}
