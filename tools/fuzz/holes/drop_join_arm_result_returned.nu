// drop_join_arm_result_returned: agora #198 — `^ ? c ( getr h ) ( okd )` with a `% Drop` payload lent out of the local `h`: it cannot be copied (drop_join_arm_result_returned).
// Closed: A returned join lends a local through an arm's call, a try over one or its scrutinee: copied there; one that cannot be copied is refused (agora #198).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | h893 | agora #198: `^ ? c ( getr h ) ( okd )` with a `% Drop` payload lent out of the local `h`: it cannot be copied
$ `stdlib/core/string.nu`

: | E { Bad }

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

: H { D d }

@ getr H h → !D E { ^ @ !D E { T . h d } }

@ mkh → H { ^ @ H { @ D { ( string_from `a string long enough for a heap buffer` ) } } }

@ okd → !D E { ^ @ !D E { T @ D { ( string_from `fresh` ) } } }

@ pick b c → !D E {
    : H h ( mkh )
    ^ ? c ( getr h ) ( okd )
}

@ main → i {
    ?? ( pick T ) { T x → ( nurl_println_int ( string_len . x s ) ) F _ → ( nurl_println `bad` ) }
    ^ 0
}
