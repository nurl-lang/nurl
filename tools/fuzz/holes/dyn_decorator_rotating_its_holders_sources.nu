// dyn_decorator_rotating_its_holders_sources: a dyn decorator forwarding to the object it wraps with its sources rotated.
// Closed: a `dyn` decorator forwarding to the object it wraps: the other impls answer what a copy of each argument holds, `h>%k`.
// main 836c0e9: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.7 | A2 | rejected | - | Family G review: a dyn decorator forwarding to the object it wraps with its sources rotated
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

% Ext [T] { @ ext T self ( Vec s ) d ( Vec s ) a ( Vec s ) c ( Vec s ) e → v }

: Cp { i k }
: Rot { % Ext inner }

% Ext Rot { @ ext Rot r ( Vec s ) d ( Vec s ) a ( Vec s ) c ( Vec s ) e → v { ( ext . r inner d c e a ) } }

% Ext Cp { @ ext Cp k ( Vec s ) d ( Vec s ) a ( Vec s ) c ( Vec s ) e → v { ( vec_extend [s] d a ) } }

@ main → i {
    : %Ext x ( dyn Ext @ Rot { ( dyn Ext @ Rot { ( dyn Ext @ Cp { 1 } ) } ) } )
    : ~ ( Vec s ) ws ( vec_new [s] )
    : ( Vec s ) l1 ( vec_new [s] )
    ( vec_push [s] l1 `literal one` )
    : ( Vec s ) l2 ( vec_new [s] )
    ( vec_push [s] l2 `literal two` )
    : ~ ( Vec s ) t ( vec_new [s] )
    {
        : String b ( string_from `a string freed at the end of its block` )
        ( vec_push [s] t ( string_data b ) )
        ( ext x ws l1 l2 t )
    }
    ( nurl_println ( vec_at [s] ws - ( vec_len [s] ws ) 1 ) )
    ^ 0
}
