// drop_view_holder_moved_on_every_path: agora #252 — a W moved to a `sink` unconditionally before its source is reallocated: dropped by the callee while the view was good (drop_view_holder_moved_on_every_path).
// Kept: a holder moved on every path is gone before its source ends, and nothing is refused (agora #252).
// main: accepted; ran clean.
// map: §7.6 | A2 | runs-clean | - | agora #252: a W moved to a `sink` unconditionally before its source is reallocated: dropped by the callee while the view was good
$ `stdlib/core/string.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ eat sink W w → i { ^ 0 }

@ main → i {
    : ~ String s ( string_from `a long string that the loop below grows until its buffer moves` )
    : W w @ W { ( string_data s ) }
    : i n ( eat w )
    ~ < ( string_len s ) 4000 { ( string_push_str s `more and more and more text` ) }
    ^ 0
}
