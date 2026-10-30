// block_assigned_outward_ok.nu — a value block whose tail call lends one
// of the block's own locals, assigned to a binding of an outer scope (`=
// out { : W w ( mkw ) ( gets w ) }` in a loop or an arm): the block's
// locals live to the end of the enclosing scope, which ends first, so the
// value is copied in place and the binding owns it (agora #190). In the
// binding's own scope, or lent from a parameter, nothing is copied.

$ `stdlib/core/string.nu`

: W { String s i n }

% Drop W { @ drop W w → v { ( nurl_print `drop ` ) ( nurl_println_int . w n ) } }

@ gets W w → String { ^ . w s }

@ mkw i n → W { ^ @ W { ( string_from `a string lent out of a block's local` ) n } }

@ run W p → i {
    : ~ String out ( string_from `start` )
    : ~ i k 0
    ~ < k 2 {
        = out {
            : W w ( mkw + k 1 )
            ( gets w )
        }
        ( nurl_println ( string_data out ) )
        = k + k 1
    }
    : b c T
    ? c {
        = out {
            : W w ( mkw 3 )
            ( gets w )
        }
    } {}
    ( nurl_println ( string_data out ) )
    = out {
        : i z 0
        ( gets p )
    }
    ( nurl_println ( string_data out ) )
    ^ ( string_len out )
}

@ main → i {
    : W p @ W { ( string_from `a parameter's string` ) 9 }
    ( nurl_println_int ( run p ) )
    ^ 0
}
