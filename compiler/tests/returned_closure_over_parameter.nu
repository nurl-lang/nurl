// returned_closure_over_parameter.nu — a closure a function returns over a
// parameter it does not take over is a view of the caller's argument, in
// every spelling (agora #141): written in the `^`, bound first, copied,
// joined, given a new value, or over a view, a slice or a closure of the
// frame. The caller keeps each argument alive while the closure runs, so
// all of them run; releasing the argument first is rejected (h384–h388).
// The sanitizer corpus holds each to no use after free and no leak.

$ `stdlib/core/string.nu`
$ `stdlib/core/slice.nu`

: P { String name }

@ lit String s → ( @ v ) { ^ \ → v { ( nurl_println ( string_data s ) ) } }

@ bound String s → ( @ v ) {
    : ( @ v ) c \ → v { ( nurl_println ( string_data s ) ) }
    ^ c
}

@ copied String s → ( @ v ) {
    : ( @ v ) c \ → v { ( nurl_println ( string_data s ) ) }
    : ( @ v ) d c
    ^ d
}

@ joined String s → ( @ v ) {
    : ( @ v ) c \ → v { ( nurl_println ( string_data s ) ) }
    ^ ? > ( string_len s ) 3 c c
}

@ joined_lits String s → ( @ v ) { ^ ? > ( string_len s ) 3 \ → v { ( nurl_println ( string_data s ) ) } \ → v { ( nurl_println `short` ) } }

@ reassigned String s → ( @ v ) {
    : ~ ( @ v ) c \ → v { ( nurl_println `none` ) }
    = c \ → v { ( nurl_println ( string_data s ) ) }
    ^ c
}

@ nested String s → ( @ v ) {
    : ( @ v ) inner \ → v { ( nurl_println ( string_data s ) ) }
    ^ \ → v { ( inner ) }
}

@ over_view String s → ( @ v ) {
    : s v ( string_data s )
    ^ \ → v { ( nurl_println v ) }
}

@ over_slice String s → ( @ v ) {
    : ( Slice u ) w ( slice_of_str ( string_data s ) )
    ^ \ → v { ( nurl_println_int ( slice_len [u] w ) ) }
}

@ over_field P p → ( @ v ) {
    : s v ( string_data . p name )
    ^ \ → v { ( nurl_println v ) }
}

@ main → i {
    : String t ( string_from `a string long enough to own a heap buffer here` )
    : ( @ v ) a ( lit t )
    : ( @ v ) b ( bound t )
    : ( @ v ) c ( copied t )
    : ( @ v ) d ( joined t )
    : ( @ v ) e ( joined_lits t )
    : ( @ v ) f ( reassigned t )
    : ( @ v ) g ( nested t )
    : ( @ v ) h ( over_view t )
    : ( @ v ) k ( over_slice t )
    : P pp @ P { ( string_from `a field string long enough to own a heap buffer` ) }
    : ( @ v ) m ( over_field pp )
    ( a ) ( b ) ( c ) ( d ) ( e ) ( f ) ( g ) ( h ) ( k ) ( m )
    ^ 0
}
