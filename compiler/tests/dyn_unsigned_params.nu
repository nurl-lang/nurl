// dyn_unsigned_params.nu — a trait-object method with unsigned parameters
// (agora #512). A dyn call assembles its arguments after the receiver into
// their own list, and that list kept the internal spelling, signedness
// and all (A1): checked against the method's lowered fn-ptr type, a `u64`
// argument for the method's own `u64` parameter was refused ("has type
// 'u64' but the invoked function type declares 'i'"), and had it passed,
// `call i64 %f(i8* %d, u64 %x)` would not have assembled. The list is
// lowered as every other call's argstr is: u64, u32, u16 and u8 values,
// literals and an `i` all reach the impl, through one `%Op` or another.

% Op [T] {
    @ apply T self u64 x → u64
    @ mixed T self u64 a u32 b u16 c u x i y → u64
}

: Adder { u64 c }

: Mul { u64 m }

% Op Adder {
    @ apply Adder o u64 x → u64 { ^ + x . o c }
    @ mixed Adder o u64 a u32 b u16 c u x i y → u64 { ^ + + + + a # u64 b # u64 c # u64 x # u64 y }
}

% Op Mul {
    @ apply Mul o u64 x → u64 { ^ * x . o m }
    @ mixed Mul o u64 a u32 b u16 c u x i y → u64 { ^ * . o m + + + + a # u64 b # u64 c # u64 x # u64 y }
}

@ run %Op o u64 v → u64 { ^ ( apply o v ) }

@ main → i {
    : %Op a ( dyn Op @ Adder { 3 } )
    : %Op m ( dyn Op @ Mul { 7 } )
    : u64 v 5
    ( nurl_println_int # i ( apply a v ) )  // 8
    ( nurl_println_int # i ( apply m v ) )  // 35
    ( nurl_println_int # i ( apply a 7 ) )  // 10
    ( nurl_println_int # i ( run m ^^ v 1 ) )  // 28
    // The full 64 bits survive: 2^63 + 1 times 7 wraps to 2^63 + 7.
    : u64 big + 9223372036854775807 2
    ( nurl_println_int # i >> ( apply m big ) 1 )  // 4611686018427387907
    : u32 b # u32 4000000000
    : u16 c # u16 60000
    : u x # u 200
    ( nurl_println_int # i ( mixed a v b c x -1 ) )  // 4000060204
    ( nurl_println_int # i ( mixed m 1 b c x 2 ) )  // 28000421421
    ^ 0
}
