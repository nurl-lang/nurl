// block_tail_call_returned_ok.nu — `^` of a block whose tail is a call
// hands back that call's result as `^ ( g x )` does (agora #187): what g
// lends of the block's own locals is copied — they are dropped on the way
// out — through nested blocks and in a closure, a raw view of one is the
// caller's own copy, and a lend of a parameter stays a lend.

$ `stdlib/core/string.nu`

: W { String s }

@ gets W w → String { ^ . w s }

@ mkw i n → W { ^ @ W { ( string_from ? == n 0 `a string from a local` `a string from a nested block` ) } }

@ local → String {
    ^ {
        : W w ( mkw 0 )
        ( gets w )
    }
}

@ nested → String {
    ^ {
        : W w ( mkw 1 )
        {
            : i z 1
            ( gets w )
        }
    }
}

@ param W w → String {
    ^ {
        : i z 0
        ( gets w )
    }
}

@ raw → s {
    ^ {
        : String x ( string_from `a raw view of a local` )
        ( string_data x )
    }
}

@ main → i {
    : String a ( local )
    ( nurl_println ( string_data a ) )
    : String b ( nested )
    ( nurl_println ( string_data b ) )
    : W w @ W { ( string_from `a string the caller owns` ) }
    : String c ( param w )
    ( nurl_println ( string_data c ) )
    : s r ( raw )
    ( nurl_println r )
    : ( @ String ) f \ → String {
        ^ {
            : W cw @ W { ( string_from `a string from a closure's block` ) }
            ( gets cw )
        }
    }
    : String d ( f )
    ( nurl_println ( string_data d ) )
    ^ 0
}
