// should_fail_shift_range.nu — a CONSTANT shift amount outside the
// value type's bit range is LLVM poison at every opt level (spec §6.1)
// and is statically known — reject it. Found by the structural fuzzer:
// `>> <i32 payload> 34` in a match guard "worked" at -O0, aborted at
// -O1 (poison fed an allocation size) and segfaulted at -O2 (wild
// jump), because branching on poison is full UB once optimised.

$ `stdlib/core/string.nu`

@ main → i {
    : i32 x # i32 123456
    ( nurl_print ( nurl_str_int # i >> x 34 ) )
    ^ 0
}
