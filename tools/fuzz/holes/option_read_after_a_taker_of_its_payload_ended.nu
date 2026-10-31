// option_read_after_a_taker_of_its_payload_ended: agora #175 — an option whose payload a block's binding took, read after the block (option_read_after_a_taker_of_its_payload_ended).
// Closed: taking an option's payload moves the option (mem_arm_hown, bck_note_payload_taken; agora #175).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | h669 | agora #175: an option whose payload a block's binding took, read after the block
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ main → i {
    : ?String o @ ?String { T ( mk ) }
    {
        : String t ?? o { T s → s F → ( mk ) }
        ( nurl_println ( string_data t ) )
    }
    ?? o { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ^ 0
}
