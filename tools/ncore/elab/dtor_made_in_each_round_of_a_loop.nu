// A destructor value made in every round of a loop: its frame ends with the round.
$ `stdlib/core/string.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ main → i {
    : String s ( string_from `a holder made and dropped in every round` )
    : ~ i k 0
    ~ < k 3 {
        : W w @ W { ( string_data s ) }
        = k + k 1
    }
    ^ k
}
