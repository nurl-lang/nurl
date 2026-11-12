// import_second_alias.nu — agora #694: one module imported under two
// aliases is compiled once, under the first; `n::name` reads as `m::name`.
// The second import line was skipped without a word, and `: n::Point q …`
// failed as "use of undefined identifier 'q'".

$ `compiler/tests/alias_rewrite_types_mod.nu` m
$ `compiler/tests/alias_rewrite_types_mod.nu` n

@ main → i {
    : m::Point p ( m::make_point 1 2 )
    : n::Point q ( n::make_point 3 4 )
    // One type, however it is spelled.
    : m::Point r q
    ( nurl_println_int + . p x . r x )
    ^ - n::PI_FIXED m::PI_FIXED
}
