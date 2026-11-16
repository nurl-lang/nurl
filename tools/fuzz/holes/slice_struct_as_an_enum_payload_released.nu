// slice_struct_as_an_enum_payload_released: `: | EH { A H  B i }` with `H { [String names i n }`: the enum's release frees the payload's slice and its Strings
// main 3358873a: invalid LLVM IR (extractvalue of the payload as a slice). AGORA-869: runs clean, LSan clean; agora #848.
// map: §7.6 | A2 | runs-clean | - | agora #848: a slice struct as an enum payload
$ `stdlib/core/string.nu`
$ `stdlib/core/slice.nu`

: H { [String names i n }
: | EH { A H B i }

@ mk i n → H { ^ @ H { [String | ( string_from `a name long enough for the heap buffer, yes` )] n } }

@ main → i {
    : EH e @ EH { A ( mk 1 ) }
    ?? e { A h → { ( nurl_println_int . h n ) } B k → { ( nurl_println_int k ) } }
    ^ 0
}
