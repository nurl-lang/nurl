// string_consume_sink_param_only_read: a raw string handed to a `sink s` parameter the callee only reads is never released.
// Closed: in safe code only a declared `sink` takes a raw string over, and its callee releases it; a caller hands over a string it owns, or a copy of anything else (mem_sink_str_arg, __own_sink_str_params).
// main gives up `m` (and the temporary) when it passes them to `take`; `take` only reads its `sink s x`,
// and a callee releases a `sink s` only by handing it to string_adopt. Both strings leak.
// LSan: detected memory leaks — 5 bytes ("abcd", `m`) and 3 bytes ("xy", the temporary).
// map: §2.13 | A2 | runs-clean | h169 | string to sink s param that only reads it; leaks
$ `stdlib/core/string.nu`

@ take sink s x → i { ^ ( strlen x ) }

@ main → i {
    : s m ( nurl_str_cat `ab` `cd` )
    : i n ( take m )
    ( nurl_println_int + n ( take ( nurl_str_cat `x` `y` ) ) )
    ^ 0
}
