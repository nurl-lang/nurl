// A global whose type is a closure type or names a trait object (`: ~ ( @
// i %Show ) g 0`, `: ~ ( @ i i ) h 0`) hides nothing declared below it
// (agora #727): the pre-passes read a global's type whole, so the `@` of
// its closure type is no function declaration and the `%` of `%Show` no
// trait or impl header. A function, a generic function and a generic
// struct declared below the globals are known above them.
$ `stdlib/core/vec.nu`

% Show [T] { @ show T s → i }

: Num { i v }

% Show Num { @ show Num s → i { ^ . s v } }

@ peek %Show s → i { ^ ( show s ) }

@ main → i {
    : Num n @ Num { 30 }
    : %Show d ( dyn Show n )
    : ( W i ) w @ ( W i ) { 2 }
    ( nurl_println_int + ( later 5 ) ( peek d ) )
    ( nurl_println_int ( twice [i] 21 ) )
    ( nurl_println_int + . w x ( after 1 ) )
    ^ 0
}

: ~ ( @ i % Show ) g 0

@ later i x → i { ^ * x 2 }

: ~ ( @ i i ) h 0

@ twice [T] T x → T { ^ + x x }

: ~ ( @ v ( Vec % Show ) ) k 0 : W [A] { A x }

@ after i x → i { ^ + x 1 }
