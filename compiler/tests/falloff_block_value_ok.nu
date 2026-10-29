// falloff_block_value_ok.nu — a bare `{ … }` block that is its function's
// fall-off value is a value block, as `^ { … }` is (agora #188): what it
// hands back is not dropped at its `}` — its own String, a `% Drop` value,
// a call's lend of its local (copied), through a nested block, in a
// closure — and a block whose tail `?` lends its own local hands back a
// copy on that path.

$ `stdlib/core/string.nu`

: D { String s i n }

% Drop D { @ drop D d → v { ( nurl_print `drop ` ) ( nurl_println_int . d n ) } }

: W { String s }

@ gets W w → String { ^ . w s }

@ fresh → String {
    : i z 1
    {
        : String w ( string_from `a block's own string` )
        w
    }
}

@ lent → String {
    : i z 1
    {
        : W w @ W { ( string_from `a string lent out of a block's local` ) }
        ( gets w )
    }
}

@ nested → String {
    : i z 1
    {
        : i y 2
        {
            : String w ( string_from `a string from a nested block` )
            w
        }
    }
}

@ dropv → D {
    : i z 1
    {
        : D d @ D { ( string_from `a % Drop value` ) 1 }
        d
    }
}

@ joined b c → String {
    ^ {
        : String w ( string_from `a block's local through a join` )
        ? c w ( string_from `a fresh string through a join` )
    }
}

@ main → i {
    ( nurl_println ( string_data ( fresh ) ) )
    ( nurl_println ( string_data ( lent ) ) )
    ( nurl_println ( string_data ( nested ) ) )
    {
        : D d ( dropv )
        ( nurl_println_int ( string_len . d s ) )
    }
    ( nurl_println ( string_data ( joined T ) ) )
    ( nurl_println ( string_data ( joined F ) ) )
    : ( @ String ) f \ → String {
        : i z 1
        {
            : String w ( string_from `a closure's block` )
            w
        }
    }
    ( nurl_println ( string_data ( f ) ) )
    ^ 0
}
