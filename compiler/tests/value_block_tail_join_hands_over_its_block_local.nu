// A value block whose tail is a join hands over the block-local an arm
// selects, on that arm's path (agora #807): assigned in a loop (spelled
// like the target, and otherwise), bound and sunk, both arms, a `??`, a
// join that is an inner block's tail, a `% Drop` struct. Each value is
// released once.
$ `stdlib/core/string.nu`

: D { i n }

% Drop D { @ drop D d → v { ( nurl_println_int . d n ) } }

@ eat sink String x → i { ^ ( string_len x ) }

@ main → i {
    : ~ String s ( string_from `outer` )
    : ~ i k 0
    ~ < k 2 {
        = s { : String s ( string_from `own s` ) ? > k 0 { s } { ( string_from `else` ) } }
        = k + k 1
    }
    ( nurl_println ( string_data s ) )
    = k 0
    ~ < k 2 {
        : String t { : String u ( string_from `bound u` ) : String w ( string_from `bound w` ) ? == k 1 { u } { w } }
        ( nurl_println_int ( eat t ) )
        = k + k 1
    }
    : ?i o @ ?i { T 3 }
    = s { : String u ( string_from `matched u` ) ?? o { T x → u F → ( string_from `none` ) } }
    ( nurl_println ( string_data s ) )
    = s { : String u ( string_from `nested u` ) { : i z 1 ? > z 0 { u } { ( string_from `else` ) } } }
    ( nurl_println ( string_data s ) )
    : ~ D d @ D { 0 }
    = k 1
    ~ < k 3 {
        = d { : D u @ D { k } ? > k 1 { u } { @ D { + k 10 } } }
        = k + k 1
    }
    ( nurl_println_int . d n )
    ^ 0
}
