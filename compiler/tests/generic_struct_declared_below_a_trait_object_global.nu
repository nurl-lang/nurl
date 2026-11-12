// A generic struct declared right below a global whose type names a trait
// object (`: ~ ( @ i %Show ) g 0`) has its fields above both (agora #716):
// the template pre-scan reads the global's type whole, and the `%` of
// `%Show` is a trait object's, not a trait or impl header whose block the
// scan steps over — the template's body, there.
% Show [T] { @ show T s → i }

: Num { i v }

% Show Num { @ show Num s → i { ^ . s v } }

@ peek %Show s → i { ^ ( show s ) }

@ main → i {
    : ( W i ) w @ ( W i ) { 5 }
    : Num n @ Num { 30 }
    : %Show d ( dyn Show n )
    ( nurl_println_int + . w x ( peek d ) )
    ^ 0
}

: ~ ( @ i % Show ) g 0 : W [A] { A x }
