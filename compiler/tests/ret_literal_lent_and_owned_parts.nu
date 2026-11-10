// A returned literal with a field lent from a parameter beside a field of
// its own — `^ @ Row { . p name ( string_from … ) }`: a result has one
// owner, so the lent field is copied and the caller owns the literal
// whole. A literal lent throughout stays lent, nothing copied. Lent with
// the rest, the literal's own field was released by nobody: it leaked — a
// String, a Vec, a slice, in a struct, a variant, an option, a result and
// a literal nested in one (agora #635, #545).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P2 { String a String b }
: HH { [i a [i b }
: H3 { String a [i b String c }
: In { String a i n }
: Mid { In inner i n }
: Out { Mid mid String extra }
: Q2 { ?String a String b }
: PV { ( Vec String ) a String b }
: Bx { In x String b }
: | E { V String String W i }
: | EB { VB In String WB i }
: | ES { VS [i [i WS i }

@ fresh → String { ^ ( string_from `a long enough string to be on the heap, fresh` ) }

// The lent field first, the owned one first, a local moved in.
@ lent_first P2 h → P2 { ^ @ P2 { . h a ( fresh ) } }
@ own_first P2 h → P2 { ^ @ P2 { ( fresh ) . h b } }
@ all_lent P2 h → P2 { ^ @ P2 { . h a . h b } }

@ local_last P2 h → P2 {
    : String loc ( string_from `a long enough string to be on the heap, loc` )
    ^ @ P2 { . h b loc }
}

@ local_first P2 h → P2 {
    : String loc ( string_from `a long enough string to be on the heap, loc` )
    ^ @ P2 { loc . h b }
}

// Slices, and three fields.
@ slices HH h → HH { ^ @ HH { . h a [i | 9 9] } }
@ three H3 h → H3 { ^ @ H3 { . h a . h b ( fresh ) } }

// A variant: payloads in the word, and boxed.
@ variant P2 h → E { ^ @ E { V . h a ( fresh ) } }
@ variant_boxed Bx h → EB { ^ @ EB { VB . h x ( fresh ) } }
@ variant_slices HH h → ES { ^ @ ES { VS . h a [i | 9 9] } }

// Nested: the lent part and the owned one on different levels.
@ nested P2 h → Out { ^ @ Out { @ Mid { @ In { . h a 1 } 2 } ( fresh ) } }
@ nested_lent P2 h → Out { ^ @ Out { @ Mid { @ In { . h a 1 } 2 } . h b } }
@ nested_own P2 h → Out { ^ @ Out { @ Mid { @ In { ( fresh ) 1 } 2 } . h b } }

// In an option, a result, and an option field.
@ opt HH h → ?HH { ^ @ ?HH { T @ HH { . h a [i | 9 9] } } }
@ res HH h → !HH String { ^ @ !HH String { T @ HH { . h a [i | 9 9] } } }
@ opt_field P2 h → Q2 { ^ @ Q2 { @ ?String { T . h a } ( fresh ) } }
@ opt_field_none P2 h → Q2 { ^ @ Q2 { @ ?String { F . h a } . h b } }
@ opt_field_lent P2 h → Q2 { ^ @ Q2 { @ ?String { T . h a } . h b } }

// A Vec field, and one return lent, the other mixed.
@ vec_field PV h → PV { ^ @ PV { . h a ( string_concat . h b . h b ) } }

@ either PV h i k → PV {
    ? > k 0 { ^ @ PV { . h a . h b } } {}
    ^ @ PV { . h a ( fresh ) }
}

// A join of two literals; a closure's.
@ join b c P2 h → P2 { ^ ? c @ P2 { . h a ( fresh ) } @ P2 { . h a . h b } }

@ in_closure P2 h → i {
    : ( @ P2 ) mk \ → P2 { ^ @ P2 { . h a ( fresh ) } }
    : P2 g ( mk )
    ( nurl_println ( string_data . g a ) )
    ^ ( string_len . g b )
}

// The result passed straight on, assigned over, discarded.
@ twice P2 h → P2 { ^ ( lent_first ( lent_first h ) ) }

@ show P2 g → v { ( nurl_println ( string_data . g a ) ) ( nurl_println ( string_data . g b ) ) }

@ show_q Q2 q → v {
    ?? . q a { T x → { ( nurl_println ( string_data x ) ) } F → { ( nurl_println `none` ) } }
    ( nurl_println ( string_data . q b ) )
}

@ main → i {
    : P2 h @ P2 { ( string_from `a long enough string to be on the heap, one` ) ( string_from `a long enough string to be on the heap, two!` ) }
    : P2 g1 ( lent_first h )
    ( show g1 )
    : P2 g2 ( own_first h )
    ( show g2 )
    : P2 g3 ( all_lent h )
    ( show g3 )
    : P2 g4 ( local_last h )
    ( show g4 )
    : P2 g5 ( local_first h )
    ( show g5 )
    ( lent_first h )
    : ~ P2 k ( lent_first h )
    = k ( lent_first k )
    = k ( own_first h )
    ( show k )
    : P2 t ( twice h )
    ( show t )
    ( show ( join T h ) )
    ( show ( join F h ) )
    ( nurl_println ( nurl_str_int ( in_closure h ) ) )

    : HH hs @ HH { [i | 1 2 3] [i | 4 5] }
    : HH s1 ( slices hs )
    ( nurl_println ( nurl_str_int + . . s1 a length . . s1 b length ) )
    : H3 h3 @ H3 { ( string_from `a long enough string to be on the heap, h3` ) [i | 1 2] ( string_from `a long enough string to be on the heap, h3!` ) }
    : H3 s3 ( three h3 )
    ( nurl_println ( string_data . s3 a ) )
    ( nurl_println ( string_data . s3 c ) )
    ( nurl_println ( nurl_str_int . . s3 b length ) )

    : E e1 ( variant h )
    ?? e1 { V x y → { ( nurl_println ( string_data x ) ) ( nurl_println ( string_data y ) ) } W n → {} }
    : Bx bx @ Bx { @ In { ( string_from `a long enough string to be on the heap, in` ) 3 } ( string_from `a long enough string to be on the heap, bx` ) }
    : EB e2 ( variant_boxed bx )
    ?? e2 { VB x y → { ( nurl_println ( string_data . x a ) ) ( nurl_println ( string_data y ) ) } WB n → {} }
    : ES e3 ( variant_slices hs )
    ?? e3 { VS x y → { ( nurl_println ( nurl_str_int + . x length . y length ) ) } WS n → {} }
    ( nurl_println ( string_data . . bx x a ) )

    : Out o1 ( nested h )
    ( nurl_println ( string_data . . . o1 mid inner a ) )
    ( nurl_println ( string_data . o1 extra ) )
    : Out o2 ( nested_lent h )
    ( nurl_println ( string_data . . . o2 mid inner a ) )
    ( nurl_println ( string_data . o2 extra ) )
    : Out o3 ( nested_own h )
    ( nurl_println ( string_data . . . o3 mid inner a ) )
    ( nurl_println ( string_data . o3 extra ) )

    : ?HH p1 ( opt hs )
    ?? p1 { T x → { ( nurl_println ( nurl_str_int + . . x a length . . x b length ) ) } F → {} }
    : !HH String p2 ( res hs )
    ?? p2 { T x → { ( nurl_println ( nurl_str_int + . . x a length . . x b length ) ) } F e → {} }
    ( show_q ( opt_field h ) )
    ( show_q ( opt_field_none h ) )
    ( show_q ( opt_field_lent h ) )
    : Q2 q1 ( opt_field h )
    ( show_q q1 )

    : ~ ( Vec String ) w ( vec_new [String] )
    ( vec_push [String] w ( string_from `a long enough string to be on the heap, v1` ) )
    : PV pv @ PV { w ( string_from `a long enough string to be on the heap, pv` ) }
    : PV v1 ( vec_field pv )
    ( nurl_println ( nurl_str_int ( vec_len [String] . v1 a ) ) )
    ( nurl_println ( string_data . v1 b ) )
    : PV v2 ( either pv 1 )
    ( nurl_println ( string_data . v2 b ) )
    : PV v3 ( either pv 0 )
    ( nurl_println ( string_data . v3 b ) )

    ( show h )
    ( nurl_println ( nurl_str_int + . . hs a length . . hs b length ) )
    ( nurl_println ( string_data . h3 a ) )
    ( nurl_println ( string_data . pv b ) )
    ^ 0
}
