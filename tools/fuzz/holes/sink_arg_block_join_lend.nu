// sink_arg_block_join_lend: the same join as a block's tail (sink_arg_block_join_lend).
// Closed: A `?` / `??` handed to a `sink` parameter — bare or a block's tail — is copied on the paths where its published ownership (`__last_join_own__`) says an arm lent; one that cannot be copied is rejected (gen_call's sink-argument checks).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h935 | the same join as a block's tail
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { String s }
: H { String s }

@ gets W w → String { ^ . w s }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) } }

@ slen String t → i { ^ ( string_len t ) }

@ keep sink String t → i { ^ ( string_len t ) }

@ main → i {
    : b c T
    : W w ( mkw )
    ( nurl_println_int ( keep { : i k 1 ? c ( gets w ) ( string_from `x` ) } ) )
    ^ 0
}
