// option_literal_match_moves_a_drop_value_once.nu — agora #654: a value with
// its own `% Drop`, moved into an option literal that `??` matches, is
// dropped exactly once — after the arm that binds it, by the unwind when the
// arm panics under `recover`, and by the statement when the arm binds `_`.

$ `stdlib/std/panic.nu`

: R { i v }

% Drop R { @ drop R r → v { ( nurl_println_int . r v ) } }

@ boom i k → i { ? > k 0 { ( nurl_panic `boom` ) } {} ^ k }

@ main → i {
    : R x @ R { 1 }
    ?? @ ?R { T x } { T q → { ( nurl_println_int + . q v 10 ) } F → {} }
    : R y @ R { 2 }
    : !v PanicInfo pr ( recover \ → v {
        : R z @ R { 3 }
        ?? @ ?R { T z } { T q → { ( nurl_println_int + . q v ( boom 1 ) ) } F → {} }
    } )
    : R w @ R { 4 }
    ?? @ ?R { T w } { T _ → { ( nurl_println `wild` ) } F → {} }
    ^ ?? pr { T _ → 1 F _ → 0 }
}
