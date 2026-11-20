// should_fail_engine_end_line.nu — where a loan ended, as the ownership
// engine's message names it, is a line on a path that reaches the read.
// The end records sit beside the state: an arm that leaves no path open
// undoes its own, and a `break` or a `continue` carries its records to
// where it goes (after the loop, the next round's head), not to what
// follows the `?` it is an arm of. engine_end_line.sh checks the line each
// read names, in nurlc --engine and in tools/ncore/check.py.
$ `stdlib/core/vec.nu`

// One arm ends `top` and goes on, the other ends it and leaves the loop:
// the read after the `?` is reached from the first arm only (line 19).
@ break_arm ( Vec ( Vec i ) ) top0 i n → i {
    : ~ ( Vec ( Vec i ) ) top ( vec_clone [( Vec i )] top0 )
    : ( Vec i ) inner ( vec_at [( Vec i )] top 0 )
    : ~ i s 0
    : ~ i k 0
    ~ < k n {
        ? == k 1 {
            ( vec_free [( Vec i )] top ) = top ( vec_new [( Vec i )] )
        } {
            ( vec_free [( Vec i )] top ) = top ( vec_new [( Vec i )] )
            break
        }
        = s + s ( vec_len [i] inner )
        = k + k 1
    }
    ^ s
}

// The same with `continue`, `inner` bound anew each round: the read is
// reached from the first arm only (line 40).
@ continue_arm ( Vec ( Vec i ) ) top0 i n → i {
    : ~ ( Vec ( Vec i ) ) top ( vec_clone [( Vec i )] top0 )
    : ~ i s 0
    : ~ i k 0
    ~ < k n {
        = k + k 1
        : ( Vec i ) inner ( vec_at [( Vec i )] top 0 )
        ? == k 1 {
            ( vec_free [( Vec i )] top ) = top ( vec_new [( Vec i )] )
        } {
            ( vec_free [( Vec i )] top ) = top ( vec_new [( Vec i )] )
            continue
        }
        = s + s ( vec_len [i] inner )
    }
    ^ s
}

// What a `break` carries is what holds after the loop (line 57).
@ after_break ( Vec ( Vec i ) ) top0 i n → i {
    : ~ ( Vec ( Vec i ) ) top ( vec_clone [( Vec i )] top0 )
    : ( Vec i ) inner ( vec_at [( Vec i )] top 0 )
    : ~ i k 0
    ~ < k n {
        ? == k 1 {
            ( vec_free [( Vec i )] top ) = top ( vec_new [( Vec i )] )
            break
        } {}
        = k + k 1
    }
    ^ ( vec_len [i] inner )
}

// What a `continue` carries holds at the head of the next round (line 75).
@ round_after_continue ( Vec ( Vec i ) ) top0 i n → i {
    : ~ ( Vec ( Vec i ) ) top ( vec_clone [( Vec i )] top0 )
    : ( Vec i ) inner ( vec_at [( Vec i )] top 0 )
    : ~ i s 0
    : ~ i k 0
    ~ < k n {
        = s + s ( vec_len [i] inner )
        = k + k 1
        ? == k 1 {
            ( vec_free [( Vec i )] top ) = top ( vec_new [( Vec i )] )
            continue
        } {}
    }
    ^ s
}

// A `~ x xs` loop as the first (line 89).
@ foreach_break_arm ( Vec ( Vec i ) ) top0 ( Vec i ) xs → i {
    : ~ ( Vec ( Vec i ) ) top ( vec_clone [( Vec i )] top0 )
    : ( Vec i ) inner ( vec_at [( Vec i )] top 0 )
    : ~ i s 0
    ~ x xs {
        ? == x 1 {
            ( vec_free [( Vec i )] top ) = top ( vec_new [( Vec i )] )
        } {
            ( vec_free [( Vec i )] top ) = top ( vec_new [( Vec i )] )
            break
        }
        = s + s ( vec_len [i] inner )
    }
    ^ s
}

// An arm that returns reaches nothing after the `?` (line 104).
@ return_arm ( Vec ( Vec i ) ) top0 b c → i {
    : ~ ( Vec ( Vec i ) ) top ( vec_clone [( Vec i )] top0 )
    : ( Vec i ) inner ( vec_at [( Vec i )] top 0 )
    ? c {
        ( vec_free [( Vec i )] top ) = top ( vec_new [( Vec i )] )
    } {
        ( vec_free [( Vec i )] top ) = top ( vec_new [( Vec i )] )
        ^ 0
    }
    ^ ( vec_len [i] inner )
}

@ main → i { ^ 0 }
