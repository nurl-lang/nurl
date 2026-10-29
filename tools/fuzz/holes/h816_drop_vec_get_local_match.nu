// H816: agora #187 — the same element handed out of a returned `??` over the call (drop_vec_get_local_match).
// Closed: A value that cannot be copied, handed back from a call that may lend it out of an argument this frame owns (a local, a `sink` parameter), is refused at module end on the callee's final summary — there is nothing to copy (__park_nc_local_lend / resolve_nc_local_lends; agora #187).
// main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ pick b c → D {
    : ( Vec D ) v ( vec_new [D] )
    ( vec_push [D] v @ D { ( string_from `element string long enough for a heap buffer` ) } )
    ^ ?? ( vec_get [D] v 0 ) { T d → d F → @ D { ( string_from `fresh string long enough for a heap buffer` ) } }
}

@ main → i {
    : D a ( pick T )
    ( nurl_println_int ( string_len . a s ) )
    ^ 0
}
