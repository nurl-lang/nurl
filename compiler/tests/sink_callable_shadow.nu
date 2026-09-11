$ `stdlib/core/string.nu`

: Detail { String text i code }
: | Owned { Live Detail OwnedEmpty }

@ take sink Owned x → i { ?? x { Live d → ^ . d code OwnedEmpty → ^ 0 } }

@ inspect Owned x → i { ?? x { Live d → ^ . d code OwnedEmpty → ^ 0 } }

@ twice ( @ i Owned ) take Owned x → i { ^ + ( take x ) ( take x ) }

@ main → i {
    : Owned x @ Owned { Live @ Detail { ( string_from `still live` ) 7 } }
    ( nurl_println_int ( twice \ Owned v → i { ^ ( inspect v ) } x ) )
    ( nurl_println_int ( inspect x ) )
    ^ 0
}
