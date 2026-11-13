// struct_holding_boxed_enum_is_dropped.nu — agora #787: a struct holding an
// enum whose payload is a boxed plain struct (`: | Shade { Light Mix Pt }`)
// is dropped, its enum's box and its String with it: made, moved, pushed
// into a Vec, read in a loop, sunk, replaced and cleared, each released once.
// It was dropped by nobody, and `( vec_push [W] v b )` was refused as a copy
// of a borrowed W.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Pt { i x i y }
: | Shade { Light Mix Pt }
: W { Shade s String t }

@ mk i k → W { ^ @ W { @ Shade { Mix @ Pt { k 0 } } ( string_from `a heap string, long enough for its own buffer` ) } }

@ sx W w → i { ^ ?? . w s { Mix q → . q x Light → 0 } }

@ eat sink W w → i { ^ ( sx w ) }

@ main → i {
    : W a ( mk 1 )
    : W b a
    : ~ ( Vec W ) v ( vec_new [W] )
    ( vec_push [W] v ( mk 2 ) )
    ( vec_push [W] v b )
    : ~ i t 0
    ~ e v { = t + t ( sx e ) }
    = t + t ( eat ( mk 3 ) )
    : ~ W c ( mk 4 )
    = c ( mk 5 )
    = t + t ( sx c )
    ( vec_clear [W] v )
    ( nurl_println_int t )
    ^ - t 11
}
