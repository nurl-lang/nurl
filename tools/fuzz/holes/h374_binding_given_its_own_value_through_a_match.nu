// H374: as h373, through a `??`: `= x ?? o { T v → v F → x }` with o empty handed x its own value lent, and the assignment freed it first.
// Closed: copied in on the lending paths, as h373 (agora #132).
// v0.79.0: accepted; ASan reported heap-use-after-free.
$ `stdlib/core/string.nu`

@ maybe i c → ?String { ? > c 9 { ^ @ ?String { T ( string_from `chosen` ) } } {} ^ @ ?String { F } }

@ main → i {
    : ~ String x ( string_from `a string long enough to own a heap buffer` )
    = x ?? ( maybe 1 ) { T v → v F → x }
    ( nurl_println ( string_data x ) )
    ^ 0
}
