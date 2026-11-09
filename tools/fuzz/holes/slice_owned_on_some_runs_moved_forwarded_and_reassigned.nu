// slice_owned_on_some_runs_moved_forwarded_and_reassigned: agora #540's adversarial pass. A slice owned on some runs (from a function that hands back its own slice or a parameter) moved into another binding, handed back through a forwarder and through a binding, reassigned in a loop with lent and fresh values, called recursively, and holding strings.
// Each owner gets the flag the value came with; a function handing a flagged binding back answers per call.
// main ad960922: leaks (the values owned on some runs were taken for lends).
// map: §7.6 | A2 | runs-clean | - | agora #540: owner flags follow a slice owned on some runs through moves, returns and loops
$ `stdlib/core/string.nu`

@ pick b c [i p → [i {
    ? c { ^ p } {}
    ^ [i | 1 2]
}

// A forwarder: hands back pick's answer.
@ fwd b c [i p → [i { ^ ( pick c p ) }

// Hands back a binding bound from pick: its flag is the answer.
@ via b c [i p → [i {
    : [i q ( pick c p )
    ^ q
}

// Recursion: its own answer, per call.
@ rec i n [i p → [i {
    ? == n 0 { ^ ( pick == 0 % n 2 p ) } {}
    ^ ( rec - n 1 p )
}

@ picks b c [String p → [String {
    ? c { ^ p } {}
    ^ [String | ( string_from `own` )]
}

@ sum [i s → i {
    : ~ i t 0
    ~ x s { = t + t x }
    ^ t
}

@ main → i {
    : [i a [i | 5 6]
    : ~ i acc 0
    // Moved into an owner, from both kinds of run.
    : [i q1 ( pick T a )
    : [i q2 ( pick F a )
    : ~ [i d [i | 9]
    = d q1
    = acc + acc ( sum d )
    = d q2
    = acc + acc ( sum d )
    : [i f1 ( fwd T a ) : [i f2 ( fwd F a )
    : [i v1 ( via T a ) : [i v2 ( via F a )
    : [i r1 ( rec 3 a ) : [i r2 ( rec 4 a )
    = acc + acc + ( sum f1 ) + ( sum f2 ) + ( sum v1 ) + ( sum v2 ) + ( sum r1 ) ( sum r2 )
    // Reassigned in a loop: lent, fresh, a call's answer.
    : ~ [i e [i | 7]
    : ~ i k 0
    ~ < k 6 {
        ? == % k 3 0 { = e a } { ? == % k 3 1 { = e [i | 8 8] } { = e ( pick == % k 2 0 a ) } }
        = acc + acc ( sum e )
        = k + k 1
    }
    : [String ws [String | ( string_from `w` )]
    : [String s1 ( picks T ws )
    : [String s2 ( picks F ws )
    ~ w s1 { = acc + acc ( string_len w ) }
    ~ w s2 { = acc + acc ( string_len w ) }
    ~ x a { = acc + acc x }
    ( nurl_println ( nurl_str_int acc ) )
    ^ 0
}
