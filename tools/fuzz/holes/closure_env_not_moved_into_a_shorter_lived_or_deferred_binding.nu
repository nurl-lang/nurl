// closure_env_not_moved_into_a_shorter_lived_or_deferred_binding: `: g f` in an inner scope with `f` called after it; `: g f` after a `;` defer that calls `f`; `= keep f` in an arm after such a defer; `= a a`.
// Closed: a closure's environment moves to a second binding only where that binding lives at least as long as the first and no `;` defer armed before may still call the first (mem_clo_deferred, the depth test in mem_bind_closure_owner and gen_assign); otherwise the second binding is another name of a closure the first still owns. Moved into the inner scope's `g`, the env was released at that scope's end and `f` was called after it; moved after the defer, it was released by the taker before the defer ran. A binding assigned to itself releases nothing (agora #614).
// main 2498b4e: accepted; AddressSanitizer: heap-use-after-free (each of the four).
// map: §7.4 | A2 | runs-clean | - | agora #614: a closure's env moved into a shorter-lived binding, moved under a pending defer, or released by a self-assignment
$ `stdlib/core/string.nu`

@ mkn i n → ( @ i i ) { ^ \ i x → i { ^ + x n } }

@ inner String tag → i {
    : ( @ i i ) f \ i x → i { ^ + x ( string_len tag ) }
    : ~ i t 0
    {
        : ( @ i i ) g f
        = t ( g 1 )
    }
    : ~ i k 0
    ~ < k 2 {
        : ( @ i i ) h f
        = t + t ( h k )
        = k + k 1
    }
    ^ + t ( f 1 )
}

@ deferred String tag i n → i {
    : ( @ i i ) f \ i x → i { ^ + + x n ( string_len tag ) }
    ; { ( nurl_println_int ( f 1 ) ) }
    : ( @ i i ) g f
    : ~ ( @ i i ) keep ( mkn 1 )
    ? > n 0 { = keep f } {}
    ^ + ( g 2 ) ( keep 2 )
}

@ main → i {
    : String tag ( string_from `a captured tag long enough for a heap buffer` )
    ( nurl_println_int ( inner tag ) )
    ( nurl_println_int ( deferred tag 0 ) )
    ( nurl_println_int ( deferred tag 1 ) )
    : ~ ( @ i i ) a \ i x → i { ^ + x ( string_len tag ) }
    = a a
    ( nurl_println_int ( a 1 ) )
    ^ 0
}
