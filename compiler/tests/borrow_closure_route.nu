// borrow_closure_route.nu — a closure that runs at a call (one handed to
// it, or the closure value called) is a route to every binding it
// captured. When its body passes a capture to something that may move that
// capture's buffer or drop its elements, no other argument of the same call
// may reach the capture: the binding itself, a view or a borrow of it, or
// another closure that captured it. Inside the callee the two are unrelated
// names, and the change through the closure leaves the other dangling
// (h274–h277, docs/MEMORY.md §2.11).
//
// CONTROLS — none of these may be flagged:
//   * a closure that only reads its capture, beside the capture itself;
//   * a growing closure beside a closure that captured something else;
//   * a growing closure beside a Vec it did not capture;
//   * two closures that only read the same capture;
//   * a closure that captured a growing closure and runs it, with no view
//     of what grows live — at the run, or among its captures.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ with_vec ( Vec i ) w ( @ v ) g → v { ( g ) }

@ apply2 ( @ v ) a ( @ v ) b → v { ( a ) ( b ) }

@ apply_to ( @ v ( @ v ) ) a ( @ v ) b → v { ( a b ) }

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    : ( Vec i ) u ( vec_new [i] )
    : ( @ v ) grow_v \ → v { ( vec_push [i] v 1 ) }
    : ( @ v ) read_v \ → v { ( nurl_println_int ( vec_len [i] v ) ) }
    : ( @ v ) read_v2 \ → v { ( nurl_println_int ( vec_len [i] v ) ) }
    : ( @ v ) grow_u \ → v { ( vec_push [i] u 1 ) }
    : ( @ v ( @ v ) ) run_v \ ( @ v ) g → v { ( nurl_println_int ( vec_len [i] v ) ) ( g ) }
    : ( @ v ) outer \ → v { ( grow_v ) }
    // controls
    ( with_vec v read_v )
    ( apply2 grow_u read_v )
    ( with_vec u grow_v )
    ( apply2 read_v read_v2 )
    ( outer )
    ( with_vec u outer )
    // rejected: a view read after a closure ran that runs one growing it
    : ( Slice i ) sv ( slice_from_vec [i] v )
    ( outer )
    ( nurl_println_int ( slice_len [i] sv ) )
    // rejected: a closure that grows a Vec and captured a view of it
    : ( Slice i ) sw ( slice_from_vec [i] u )
    : ( @ v ) both \ → v { ( vec_push [i] u 2 ) ( nurl_println_int ( slice_len [i] sw ) ) }
    ( both )
    // rejected: the Vec beside a closure that grows it
    ( with_vec v grow_v )
    // rejected: a closure that captured it beside one that grows it
    ( apply_to run_v grow_v )
    // rejected: the closure called captured what its argument grows
    ( run_v grow_v )
    ^ 0
}
