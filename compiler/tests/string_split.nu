// Test: stdlib/core/string.nu — string_split semantics
//
// Covers: simple split, multi-byte separator, leading / trailing /
// consecutive separators, empty input, separator longer than string,
// empty separator (single-element Vec with full copy).

$ `stdlib/core/string.nu`

@ show_parts ( Vec String ) parts → v {
    ( nurl_print `[` )
    : i n ( vec_len [String] parts )
    : ~ i i 0
    ~ < i n {
        : ?String got ( vec_get [String] parts i )
        ?? got {
            T s → {
                ( nurl_print `"` )
                ( nurl_print ( string_data s ) )
                ( nurl_print `"` )
                ? < i - n 1 { ( nurl_print `,` ) } {}
            }
            F → {}
        }
        = i + i 1
    }
    ( nurl_print `]\n` )
}

@ free_parts ( Vec String ) parts → v {
    : ( @ v String ) drop \ String e → v { ( string_free e ) }
    ( vec_free_with [String] parts drop )
}

@ run String src s sep → v {
    ( nurl_print `split "` )
    ( nurl_print ( string_data src ) )
    ( nurl_print `" by "` )
    ( nurl_print sep )
    ( nurl_print `" → ` )
    : ( Vec String ) parts ( string_split src sep )
    ( show_parts parts )
    ( free_parts parts )
}

@ main → i {
    // simple
    ( run ( string_from `a,b,c` ) `,` )
    // single token
    ( run ( string_from `hello` ) `,` )
    // empty input
    ( run ( string_from `` ) `,` )
    // leading separator
    ( run ( string_from `,a,b` ) `,` )
    // trailing separator
    ( run ( string_from `a,b,` ) `,` )
    // consecutive separators
    ( run ( string_from `a,,b` ) `,` )
    // multi-byte separator
    ( run ( string_from `aXYbXYcXY` ) `XY` )
    // separator longer than string
    ( run ( string_from `ab` ) `abcd` )
    // empty separator → single-element Vec with copy
    ( run ( string_from `abc` ) `` )
    // separator only
    ( run ( string_from `,,,` ) `,` )
    ( nurl_print `done\n` )
    ^ 0
}
