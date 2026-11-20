// mem_dup_of_an_owned_slice_is_a_copy_runs_clean: `( mem_dup a )` of a `[i` bound, handed to a call and returned (`@ dupi [i t → [i { ^ ( mem_dup t ) }` of a temporary and of a binding), of a call's temporary fresh or lent per run, of a join, and of a `[s`: each a copy the receiver owns
// Closed (agora #938): mem_dup of an owned slice copies its buffer (`__nurl_clone_sl`), as a literal's owned slice field does: a value of its own where the elements hold no view, holding what they view where they do (`__nurl_slice_copy` / `__nurl_slice_copy_v`); an operand fresh on some runs (a call's, a join's, by its bit) is taken on those runs, not copied. It handed back the slice itself before - no copy.
// main 3ad3d7c8: AddressSanitizer: double-free (`( ln ( dupi ( mk ) ) )`: the caller released the temporary and the "copy", the same buffer).
// map: §7.6 | A2 | runs-clean | - | agora #938: mem_dup of an owned slice is a copy, bound, an argument, returned, of a temporary fresh or lent, of a join, of a slice of views
$ `stdlib/core/string.nu`

@ mk → [i { ^ [i | 1 2 3] }
@ mks → [s { ^ [s | `a` `b`] }
@ ln [i t → i { : ~ i k 0 ~ x t { = k + k x } ^ k }
@ dupi [i t → [i { ^ ( mem_dup t ) }
@ dups [s t → [s { ^ ( mem_dup t ) }
@ pick b c [i a → [i { ? c { ^ a } {} ^ ( mk ) }

@ main → i {
    : [i a ( mk )
    : [i b ( mem_dup a )
    ( nurl_println_int + ( ln a ) ( ln b ) )
    ( nurl_println_int ( ln ( mem_dup a ) ) )
    ( nurl_println_int ( ln ( dupi ( mk ) ) ) )
    : [i c ( dupi a )
    ( nurl_println_int ( ln c ) )
    : [i x ( mem_dup ( mk ) )
    : [i y ( mem_dup ( pick T a ) )
    : [i z ( mem_dup ( pick F a ) )
    : [i w ( mem_dup ? > ( ln a ) 3 ( mk ) a )
    ( nurl_println_int + + + ( ln x ) ( ln y ) ( ln z ) ( ln w ) )
    : [s v ( mks )
    : [s s ( dups v )
    ~ e s { ( nurl_println e ) }
    : [s u ( mem_dup ( mks ) )
    ~ e u { ( nurl_println e ) }
    ^ 0
}
