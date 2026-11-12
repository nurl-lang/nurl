// enum_value_above_declaration.nu — agora #772 (with #752): an enum used
// BY VALUE above its declaration — made, matched, replaced, handed to a
// sink, held in a Vec — as a struct may be: its variants,
// payloads and compiler drop are read before any body compiles. Each
// payload is released once (the leak gate and the sanitizer corpus run
// this file); it was refused as "declared LATER".

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk i k → E { ^ ? > k 0 @ E { Txt ( string_from `hello` ) } @ E { Num k } }

@ len E e → i { ^ ?? e { Txt s → ( string_len s ) Num n → n Nothing → 0 } }

@ eat sink E e → i { ^ ?? e { Txt s → ( string_len s ) Num n → n Nothing → 0 } }

@ main → i {
    : E a ( mk 1 )
    : ~ E b ( mk 0 )
    = b ( mk 1 )
    : Shade sh @ Shade { Mix @ Pt { 40 0 } }
    : ~ ( Vec E ) v ( vec_new [E] )
    ( vec_push [E] v ( mk 3 ) )
    ( vec_push [E] v @ E { Num 4 } )
    : ~ i t + + ( len a ) ( len b ) ( eat ( mk 2 ) )
    ~ e v { = t + t ( len e ) }
    ( vec_clear [E] v )
    = t + t ?? sh { Mix q → . q x Light → 0 }
    ( nurl_println_int t )
    ^ - t 64
}

: Pt { i x i y }

: | Shade { Light Mix Pt }

: | E { Txt String Num i Nothing }
