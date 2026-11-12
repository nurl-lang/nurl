// mutable_value_block_vec_tail_sunk_runs_clean: as mutable_value_block_tail_grown_then_sunk_runs_clean, a `( Vec String )` tail bound `: ~` inside the block
// Closed: as that probe (agora #668 item 1).
// main 9052104: AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #668: as that probe, a Vec
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ eat sink ( Vec String ) x → i { ^ ( vec_len [String] x ) }

@ main → i {
    : ~ ( Vec String ) w { : ~ ( Vec String ) u ( vec_new [String] ) ( vec_push [String] u ( string_from `an element string long enough for a heap buffer` ) ) u }
    ( nurl_println_int ( eat w ) )
    ^ 0
}
