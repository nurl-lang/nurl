// OPEN in 0.72.0 — a raw string handed to a `sink s` parameter the callee only reads is never released.
// main gives up `m` (and the temporary) when it passes them to `take`; `take` only reads its `sink s x`,
// and a callee releases a `sink s` only by handing it to string_adopt. Both strings leak.
// LSan: detected memory leaks — 5 bytes ("abcd", `m`) and 3 bytes ("xy", the temporary).
$ `stdlib/core/string.nu`

@ take sink s x → i { ^ ( strlen x ) }

@ main → i {
    : s m ( nurl_str_cat `ab` `cd` )
    : i n ( take m )
    ( nurl_println_int + n ( take ( nurl_str_cat `x` `y` ) ) )
    ^ 0
}
