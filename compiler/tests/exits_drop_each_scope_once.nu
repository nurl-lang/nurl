// Early exits end every scope they leave, innermost first, and each
// destructor runs exactly once (agora #871). A `break` out of `~ T` from
// two scopes deep, a `continue` from inside a scope, and a `^` across
// nested scopes and a loop: as the calculus has an exit (formal/A2,
// `ExitAt`, `Step.blockExit`: the frames left end from the inside out,
// their drops and destructors run as at each scope's own end).
$ `stdlib/core/string.nu`

: R { i n }

% Drop R { @ drop R x → v { ( puts ( nurl_str_cat `drop ` ( nurl_str_int . x n ) ) ) } }

// break out of while T from two scopes deep
@ brk → i {
    : R a @ R { 1 }
    : ~ i k 0
    ~ T {
        : R b @ R { + 10 k }
        = k + k 1
        ? > k 1 {
            : R c @ R { 100 }
            break
        } {}
    }
    ( puts `after brk loop` )
    ^ k
}

// continue from inside a scope, each round's value dropped once
@ cont → i {
    : ~ i k 0
    ~ < k 3 {
        = k + k 1
        : R b @ R { + 20 k }
        ? == k 2 { : R c @ R { 200 } continue } {}
        ( puts `round end` )
    }
    ^ k
}

// early ^ across nested scopes and a loop
@ ret → i {
    : R a @ R { 3 }
    : ~ i k 0
    ~ T {
        : R b @ R { + 30 k }
        = k + k 1
        ? == k 2 { : R c @ R { 300 } ^ k } {}
    }
    ^ 0
}

@ main → i {
    : i x ( brk )
    ( puts `--` )
    : i y ( cont )
    ( puts `--` )
    : i z ( ret )
    ( puts `--` )
    ^ + + x y z
}
