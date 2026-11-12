// trait_object_bound_right_after_a_lending_call: `: %Tr d ( dyn Tr g )` right after a call that lends its result (`: String b ( first v )`, first handing back a `vec_at` element) — in a function body, in a loop body, in a closure body, and given to `=`. A `( dyn … )` box is allocated where it is made, so the binding always owns it.
// Closed (agora #687): the binding judged the box by the last call's channels (`__last_value_borrow__`, the call's ownership bit) — "lent" after a lending call, so it registered no drop and the box and the String in it leaked; a `dyn` let first in a closure body read a register of the enclosing function (clang refused the IR). The box is now known by its own register (g_dyn_box_reg), and a closure body starts with no last call of its own.
// main (before this PR): LeakSanitizer reported each box (8 bytes) and the String it held.
// map: §7.6 | A2 | runs-clean | - | a trait object bound right after a lending call took the call's "lent" for its own and was never dropped — leak
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

% Taker [T] { @ take T self i k → i }

: G { String s }

% Taker G { @ take G g i k → i { ^ + k ( string_len . g s ) } }

@ first ( Vec String ) v → String { ^ ( vec_at [String] v 0 ) }

@ main → i {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `abc` ) )
    : G g @ G { ( string_from `a string long enough to own a heap buffer` ) }
    : String b ( first v )
    : ~ % Taker d ( dyn Taker g )
    : ~ i acc ( take d 0 )
    : String b2 ( first v )
    = d ( dyn Taker @ G { ( string_from `another string long enough to own a buffer` ) } )
    = acc + acc ( take d 0 )
    : ~ i k 0
    ~ < k 3 {
        : String c ( first v )
        : %Taker e ( dyn Taker @ G { ( string_from `a third string, also on the heap` ) } )
        = acc + acc ( take e 0 )
        = k + k 1
    }
    : ( @ i i ) w \ i k → i {
        : %Taker e ( dyn Taker @ G { ( string_from `a fourth one, in the closure body` ) } )
        : String c ( first v )
        : %Taker f ( dyn Taker @ G { ( string_from `a fifth one, after the lending call` ) } )
        ^ + + ( take e k ) ( take f k ) ( string_len c )
    }
    = acc + acc ( w 0 )
    ? == acc 0 { ^ 1 } {}
    ^ 0
}
