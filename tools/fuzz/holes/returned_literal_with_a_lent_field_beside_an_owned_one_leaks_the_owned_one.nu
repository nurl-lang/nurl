// returned_literal_with_a_lent_field_beside_an_owned_one_leaks_the_owned_one: agora #635, #545 — `^ @ P2 { . h a ( fresh ) }`, a returned literal with a field lent out of a parameter beside a field of its own: one lent field made the whole literal lent, so the caller did not release it and the literal's own field was owned by nobody — in a struct, a variant, an option and a literal nested in one.
// Closed: a returned literal has one owner. Where it holds a value of its own, each lent field is copied and the caller owns it whole; a field written before the first owned one reads a constant decided at the literal's end (`@.__nurl_rlown.N`, folded by the module writer), so a literal lent throughout copies nothing and stays lent.
// main (before this PR): LeakSanitizer, each owned field.
// map: §7.6 | A2 | runs-clean | - | agora #635: a returned literal with a lent field beside an owned one was lent whole, and its own field leaked
$ `stdlib/core/string.nu`

: P2 { String a String b }
: In { String a i n }
: Out { In inner String extra }
: | E { V String String W i }

@ fresh → String { ^ ( string_from `a long enough string to be on the heap, fresh` ) }

@ lent_first P2 h → P2 { ^ @ P2 { . h a ( fresh ) } }

@ own_first P2 h → P2 { ^ @ P2 { ( fresh ) . h b } }

@ all_lent P2 h → P2 { ^ @ P2 { . h a . h b } }

@ variant P2 h → E { ^ @ E { V . h a ( fresh ) } }

@ nested P2 h → Out { ^ @ Out { @ In { . h a 1 } ( fresh ) } }

@ opt P2 h → ?P2 { ^ @ ?P2 { T @ P2 { . h a ( fresh ) } } }

@ show P2 g → v { ( nurl_println ( string_data . g a ) ) ( nurl_println ( string_data . g b ) ) }

@ main → i {
    : P2 h @ P2 { ( string_from `a long enough string to be on the heap, one` ) ( string_from `a long enough string to be on the heap, two!` ) }
    : P2 g1 ( lent_first h )
    ( show g1 )
    : P2 g2 ( own_first h )
    ( show g2 )
    : P2 g3 ( all_lent h )
    ( show g3 )
    ( lent_first h )
    : E e1 ( variant h )
    ?? e1 { V x y → { ( nurl_println ( string_data x ) ) ( nurl_println ( string_data y ) ) } W n → {} }
    : Out o1 ( nested h )
    ( nurl_println ( string_data . . o1 inner a ) )
    ( nurl_println ( string_data . o1 extra ) )
    : ?P2 p1 ( opt h )
    ?? p1 { T x → { ( show x ) } F → {} }
    ( show h )
    ^ 0
}
