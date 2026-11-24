@ twice ( @ i i ) f i x → i { ^ ( f ( f x ) ) }

@ main → i {
    : i a 3
    : i b 4
    : ( @ i i ) f \ i x → i { ^ + * x a b }
    ^ ( twice f 1 )
}
