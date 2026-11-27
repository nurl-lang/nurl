// A struct of three numbers: its literal nested in pairs, each field read through them.
: Tri { i a i b i c }

@ main → i {
    : Tri t @ Tri { 1 2 3 }
    ^ + + . t a . t b . t c
}
