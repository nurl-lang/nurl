// closure_hands_back_an_enum_of_an_owned_clone_of_its_capture_runs_clean: a closure hands back an enum value whose payload is an owned clone of a String it captured: it holds no view at all.
// Closed: h220's check of an owner of views a closure hands back skips the arguments of a call whose result can hold no view (string_clone, string_from): a copy carries nothing of what its argument points into (__sx_names_capture).
// main 4f15689: accepted; ran clean.
// map: §7.5 | A2 | runs-clean | h220 | a closure hands back an enum of an owned clone of the String it captured
$ `stdlib/core/string.nu`

: | Tok { Word s Bad String }

@ main → i {
    : String line ( string_from `hello world, long enough for a heap buffer` )
    : ( @ Tok ) f \ → Tok { ^ @ Tok { Bad ( string_clone line ) } }
    : Tok t ( f )
    ?? t { Word w → ( nurl_println w ) Bad b → ( nurl_println ( string_data b ) ) }
    ^ 0
}
