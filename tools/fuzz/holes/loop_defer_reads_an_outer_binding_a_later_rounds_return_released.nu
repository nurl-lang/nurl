// loop_defer_reads_an_outer_binding_a_later_rounds_return_released: `: String x …  ~ c { ? d { ^ 7 } {}  ; { … x … } }`.
// Closed: the owners in sight at the head of a loop whose body registers a defer are kept from there on (__dloop_open), and the `^` runs the defer an earlier round armed, which reads `x` before the cleanup releases it (agora #655).
// main ee9d2c5: accepted; it ran clean only because the `^` skipped the armed defer. With the defer run, as the language says, the `^` had released `x` before it (heap-use-after-free).
// map: §5.3 | A2 | runs-clean | - | agora #655: a `^` above a loop body's `;` released an outer binding the defer, armed in an earlier round, reads
$ `stdlib/core/string.nu`

@ f → i {
    : String x ( string_from `x: an outer string long enough for a heap buffer` )
    : ~ i k 0
    ~ < k 2 {
        ? == k 1 { ^ 7 } {}
        ; { ( nurl_println_int ( string_len x ) ) }
        = k + k 1
    }
    ^ k
}

@ main → i {
    ( nurl_println_int ( f ) )
    ^ 0
}
