// core_ir_shapes: one function per construct the core IR lowers
// (docs/dev/CORE_IR.md). compiler/tests/core_ir.sh prints the IR of this
// file and checks the statements each function becomes; run as a program
// it only has to compile and exit 0.
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: P { ( Vec String ) items i n }

: | Shape { Circle f Rect f f Named String }

@ parse String s → !i String {
    ? == ( string_len s ) 0 { ^ @ !i String { F ( string_from `empty` ) } } {}
    ^ @ !i String { T 1 }
}

@ shape_try String s → !i String {
    : i a \ ( parse s )
    ^ @ !i String { T + a a }
}

@ shape_join b c String a String b2 → String {
    ^ ? c a b2
}

@ shape_match Shape sh → f {
    ^ ?? sh {
        Circle r → * r r
        Rect w h → * w h
        Named nm → 0.0
    }
}

@ shape_loops ( Vec String ) v → i {
    : ~ i n 0
    ~ s v { = n + n ( string_len s ) }
    : ~ i k 0
    ~ < k 3 {
        = k + k 1
        ? == k 2 { break } {}
    }
    ^ + n k
}

@ shape_store → i {
    : ( Vec String ) v ( vec_new [String] )
    : ~ P p @ P { v 1 }
    = . p n 5
    ( vec_push [String] . p items ( string_from `a` ) )
    ^ . p n
}

@ shape_block → i {
    : String t {
        : String inner ( string_from `in` )
        ( string_clone inner )
    }
    ^ ( string_len t )
}

@ shape_short String a → b {
    ^ | == ( string_len a ) 0 == ( string_len a ) 1
}

@ apply ( @ i i ) f i x → i {
    ^ ( f x )
}

@ shape_closure → i {
    : String name ( string_from `n` )
    : ~ i acc 0
    : ( @ i i ) add \ i k → i {
        = acc + acc k
        ^ + k ( string_len name )
    }
    ; { ( nurl_println_int acc ) }
    ^ + ( apply add 3 ) ( add 4 )
}

@ defaults i a i b = 2 i c = 3 → i { ^ + + a b c }

@ shape_named → i {
    ^ + ( defaults 1 ) ( defaults c : 7 a : 1 )
}

// A body that falls off with a tail join's value hands it back with no
// `^`: a function's, and a closure's.
@ shape_fall b c → String {
    ? c ( string_from `left` ) ( string_from `right` )
}

@ shape_fall_closure b c → i {
    : ( @ String b ) pick \ b d → String {
        ? d ( string_from `p` ) ( string_from `qq` )
    }
    : String got ( pick c )
    ^ ( string_len got )
}

@ main → i {
    : Shape sh @ Shape { Named ( string_from `q` ) }
    : i z ?? ( shape_try ( string_from `x` ) ) { T v → v F e → 0 }
    : String w ( shape_join T ( string_from `a` ) ( string_from `b` ) )
    : [i xs [i | 1 2 3]
    : ( Vec String ) vs ( vec_new [String] )
    : i total + + + + + + + z ( shape_loops vs ) # i ( shape_match sh ) ( shape_store ) ( shape_block ) ( shape_closure ) ( shape_named ) . xs length
    : b one ( shape_short w )
    : String fell ( shape_fall T )
    : i falls + ( string_len fell ) ( shape_fall_closure F )
    ^ ? & & one > total 0 == falls 6 0 1
}
