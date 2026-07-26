// Regression: an array *store* through a raw pointer whose index
// expression has an unsigned sized type must lower the index operand
// like every other type on the getelementptr line.
//
// `= . p idx v` with `idx : u64` used to print the NURL type name into
// the IR — `getelementptr i64, i64* %p, u64 %idx` — which nurlc emitted
// with rc 0 and only clang rejected, with a bare "expected type". The
// matching *load* path (`. p idx`) already lowered it, so a program
// could read at an unsigned index but not write at one.
//
// Covered here: the plain raw-pointer store (u64 / u32 / u16 index), the
// same store inside a function that takes the pointer as a parameter,
// and a read-back through both an unsigned and a signed index so the
// two paths are checked against each other.

@ store_at * u64 p u64 idx u64 v → v {
    = . p idx v
}

@ store_via_u32 * i32 p u32 idx i32 v → v {
    = . p idx v
}

@ main → i {
    : *u64 p # *u64 ( malloc * 8 8 )
    : ~ i z 0
    ~ < z 8 {
        = . p z # u64 0
        = z + z 1
    }

    // u64 index, stored in main.
    : u64 i3 3
    = . p i3 # u64 111
    ( nurl_print ( nurl_str_int # i . p 3 ) ) ( nurl_print `\n` )  // 111

    // u64 index, stored through a *u64 parameter.
    ( store_at p # u64 4 # u64 222 )
    ( nurl_print ( nurl_str_int # i . p 4 ) ) ( nurl_print `\n` )  // 222

    // Read back at an unsigned index (the load path) and at a signed
    // index — both must reach the same slot.
    : u64 i4 4
    ( nurl_print ( nurl_str_int # i . p i4 ) ) ( nurl_print `\n` )  // 222
    ( nurl_print ? == . p i4 . p 4 `same\n` `differ\n` )  // same

    // u16 index on a narrower element type.
    : u16 i1 1
    : *i32 q # *i32 ( malloc * 4 4 )
    = . q 0 # i32 0
    = . q i1 # i32 -7
    ( nurl_print ( nurl_str_int # i . q 1 ) ) ( nurl_print `\n` )  // -7

    // u32 index through a parameter.
    ( store_via_u32 q # u32 2 # i32 33 )
    ( nurl_print ( nurl_str_int # i . q 2 ) ) ( nurl_print `\n` )  // 33

    // An unsigned index above the signed 32-bit range must not be
    // sign-smeared into a negative offset: 2^31 elements past the base
    // is unreachable here, so use a wide index that stays in bounds
    // after masking — the point is that the operand type printed is
    // `i64`, not `u64`.
    : u64 wide & 0x1000000000000005 7
    = . p wide # u64 999
    ( nurl_print ( nurl_str_int # i . p 5 ) ) ( nurl_print `\n` )  // 999

    ( free q )
    ( free p )
    ^ 0
}
