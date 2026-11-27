// A destructor struct of one number field: padded with a number, its field the pair's first.
: C { i n }

% Drop C { @ drop C self → v { : i m . self n ( nurl_println_int m ) } }

@ main → i {
    : C c @ C { 3 }
    : i k + . c n 1
    ^ k
}
