// map: §7.6 | A2 | rejected | - | agora #846: `: s d { : String t … : s x ( string_data t ) x }  ^ d`: a view of a value block's local handed back after the block
$ `stdlib/core/string.nu`

@ f → s {
    : s d { : String t ( string_from `a block-local string long enough for a heap buffer` ) : s x ( string_data t ) x }
    ^ d
}

@ main → i { : s r ( f ) ( nurl_println r ) ^ 0 }
