// A closure over three numbers: its environment is the numbers nested in pairs.
@ main → i {
    : i a 1
    : i b 2
    : i c 3
    : ( @ i i ) f \ i x → i { ^ + + + x a b c }
    ^ ( f 4 )
}
