// let_block_outward_ok.nu — a value block bound with `:` whose tail call
// lends one of the block's own locals (`: String r { : W w ( mkw ) ( gets w )
// }`): the block's locals live only to the end of the enclosing scope, so
// the value is copied in place and the binding owns it — it may then be
// assigned to an outer binding, in a loop or an arm, or returned (agora
// #193). Lent from a binding made before the block, nothing is copied.

$ `stdlib/core/string.nu`

: W { String s i n }

% Drop W { @ drop W w → v { ( nurl_print `drop ` ) ( nurl_println_int . w n ) } }

@ gets W w → String { ^ . w s }

@ mkw i n → W { ^ @ W { ( string_from `a string lent out of a block's local` ) n } }

@ make i n → String {
    : String r {
        : W w ( mkw n )
        ( gets w )
    }
    ^ r
}

@ run W p → i {
    : ~ String out ( string_from `start` )
    : ~ i k 0
    ~ < k 2 {
        : String r {
            : W w ( mkw + k 1 )
            ( gets w )
        }
        = out r
        ( nurl_println ( string_data out ) )
        = k + k 1
    }
    : b c T
    ? c {
        : r {
            : W w ( mkw 3 )
            ( gets w )
        }
        = out r
    } {}
    ( nurl_println ( string_data out ) )
    : String q ( make 4 )
    ( nurl_println ( string_data q ) )
    : String v {
        : i z 0
        ( gets p )
    }
    ( nurl_println ( string_data v ) )
    ^ + ( string_len out ) ( string_len v )
}

@ main → i {
    : W p @ W { ( string_from `a parameter's string` ) 9 }
    ( nurl_println_int ( run p ) )
    ^ 0
}
