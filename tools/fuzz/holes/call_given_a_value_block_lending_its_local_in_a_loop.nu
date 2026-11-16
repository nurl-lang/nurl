// call_given_a_value_block_lending_its_local_in_a_loop: `= b ( id { : String t ( mk k ) t } )` in a loop, b read after it — the unblocked `: String t ( mk k )  = b ( id t )` is refused.
// Closed: a value block's bindings are the enclosing scope's to the walk as they are to codegen — its `vblock` row ends their names at the `}`, not their lives, which end where the enclosing scope does (agora #846).
// main 525613d: accepted; AddressSanitizer: heap-use-after-free.
// map: §1 | A2 | rejected | - | agora #846, #839: a call lending a value block's tail binding, kept past the round
$ `stdlib/core/string.nu`

@ mk i c → String { ^ ( string_from `a heap string long enough for the heap buffer` ) }

@ id String x → String { ^ x }

@ main → i { : ~ String b ( mk 0 ) : ~ i k 0 ~ < k 2 { = b ( id { : String t ( mk k ) t } ) = k + k 1 } ( nurl_println ( string_data b ) ) ^ 0 }
