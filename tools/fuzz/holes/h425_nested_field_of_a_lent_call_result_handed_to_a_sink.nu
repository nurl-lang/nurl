// H425: as h424, a nested field (`. . ( box_get b ) q name`) handed to a
// generic `sink`.
// Closed: as h424 (agora #150).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: Q { String name String tag }
: R { Q q i n }

@ mkq → Q { ^ @ Q { ( mk ) ( mk ) } }

@ take_any [T] sink T x → v {}

@ main → i {
    : ( Box R ) b ( box_new [R] @ R { ( mkq ) 1 } )
    ( take_any [String] . . ( box_get [R] b ) q name )
    ( box_free [R] b )
    ^ 0
}
