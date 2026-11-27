// A destructor value made in one arm, whose frame a return from that arm leaves.
$ `stdlib/core/string.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ pick i k → i {
    : String s ( string_from `a holder made in one arm only` )
    ? == k 0 {
        : W w @ W { ( string_data s ) }
        ^ 1
    } {}
    ^ 0
}

@ main → i { ^ ( pick 0 ) }
