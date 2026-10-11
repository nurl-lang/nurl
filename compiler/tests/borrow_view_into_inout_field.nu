// A view of a local string stored into a field of an `inout` struct — the
// caller's — outlives the string: an error. So does one stored into a field
// of a local struct that outlives the string (a loop body's string, read
// after the loop).
$ `stdlib/core/string.nu`

: Rec { s name i n }

@ setl inout Rec r → v { : s x ( nurl_str_cat `ef` `gh` ) = . r name x }

@ main → i {
    : ~ Rec r @ Rec { `init` 1 }
    ( setl r )
    : ~ i k 0
    ~ < k 2 { : s y ( nurl_str_cat `ef` `gh` ) = . r name y = k + k 1 }
    ( nurl_println . r name )
    ^ 0
}
