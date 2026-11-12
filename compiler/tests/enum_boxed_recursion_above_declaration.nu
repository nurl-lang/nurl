// enum_boxed_recursion_above_declaration.nu — a struct that reaches itself
// through an enum's payload, declared below the functions that use it
// (agora #772): an enum's struct payload is boxed, so the type has a finite
// size — accepted, built, read and released (the leak gate runs this file).

@ depth A a → i { ^ ?? . a e { Ea inner → + 1 ( depth inner ) En k → k } }

@ mk i k → A { ^ ? > k 0 @ A { @ E { Ea ( mk - k 1 ) } k } @ A { @ E { En 0 } 0 } }

@ main → i {
    : A a ( mk 3 )
    ( nurl_println_int ( depth a ) )
    ^ - ( depth a ) 3
}

: A { E e i n }

: | E { Ea A En i }
