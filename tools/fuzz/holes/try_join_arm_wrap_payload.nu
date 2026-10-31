// try_join_arm_wrap_payload: agora #198 — `^ @ !String E { T ? c \ ( getr w ) ( string_from … ) }`: a try over a call lending the local `w`, as a join arm in a returned payload (try_join_arm_wrap_payload).
// Closed: A returned join lends a local through an arm's call, a try over one or its scrutinee: copied there; one that cannot be copied is refused (agora #198).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h880 | agora #198: `^ @ !String E { T ? c \ ( getr w ) ( string_from … ) }`: a try over a call lending the local `w`, as a join arm in a returned payload
$ `stdlib/core/string.nu`

: | E { Bad }

: W { String s }

@ getr W w → !String E { ^ @ !String E { T . w s } }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) } }

@ pick b c → !String E {
    : W w ( mkw )
    ^ @ !String E { T ? c \ ( getr w ) ( string_from `fresh` ) }
}

@ main → i {
    ?? ( pick T ) { T x → ( nurl_println_int ( string_len x ) ) F _ → ( nurl_println `bad` ) }
    ^ 0
}
