// borrow_strict_handle_second_name_more.nu — three more ways a heap
// handle acquires a second name, all found by tools/metamorph.
//
// #899 closed the copy, the `?`/`??` join, the assignment and the
// callee-returns-its-argument spellings. The harness enumerates the
// same situation across spellings and asks whether the verdict agrees;
// these three did not, and each is an ASan-confirmed double free
// (SEGV on a write) when compiled with --no-borrowck and run:
//
//   1. a NESTED `?` — the outer join's arm is not a bare identifier, so
//      the outer published no candidates and the inner's were dropped
//      on the floor. One level worked, two did not.
//   2. an AGGREGATE LITERAL field — `@ Holder { a }`. The lint already
//      treated this as released and the code comment already called it
//      a move; only the checker had not been told. Measured: the field
//      and the binding share a data pointer, and a push through one is
//      visible through the other.
//   3. a CLOSURE CAPTURE — a closure that frees what it captured. Moves
//      recorded inside a closure body are deliberately dropped (its
//      statements must not inline into the enclosing function's list),
//      which also dropped this one.
//
// All three are MAYBE-moves, so they need --strict-borrowck. The reason
// is the same one that made the assignment case conditional in #899:
// the handover is certain, but the old name may still be a legal way to
// use the live buffer, and only liveness — which this checker does not
// compute — could say when it stops being one. For the closure there is
// a second reason: the checker knows the capture, not the call count,
// and a closure that frees its capture but is never called leaks rather
// than double-frees.
//
// Three functions, because recovery is per declaration: one error each.

$ `stdlib/core/vec.nu`

: Holder { ( Vec i ) v }

@ nested_ternary i c → i {
    : ( Vec i ) a ( vec_new [i] )
    : ( Vec i ) b ? > c 0 ? > c 0 a ( vec_new [i] ) ( vec_new [i] )
    ( vec_free [i] b )
    ( vec_free [i] a )
    ^ 0
}

@ aggregate_field → i {
    : ( Vec i ) a ( vec_new [i] )
    : Holder h @ Holder { a }
    ( vec_free [i] . h v )
    ( vec_free [i] a )
    ^ 0
}

@ closure_capture → i {
    : ( Vec i ) a ( vec_new [i] )
    : ( @ v ) f \ → v { ( vec_free [i] a ) }
    ( f )
    ( vec_free [i] a )
    ^ 0
}

@ main → i {
    : i r ( nested_ternary 1 )
    : i s ( aggregate_field )
    : i t ( closure_capture )
    ^ + r + s t
}
