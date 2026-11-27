// A destructor value made in a loop's body, whose frame a break leaves.
$ `stdlib/core/string.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ main → i {
    : String s ( string_from `a holder whose frame a break leaves` )
    : ~ i k 0
    ~ T {
        : W w @ W { ( string_data s ) }
        ? > k 2 { break } {}
        = k + k 1
    }
    ^ k
}
