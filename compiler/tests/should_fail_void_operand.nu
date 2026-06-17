// should_fail_void_operand.nu — a bare type keyword used as a VALUE operand.
//
// `v` (and the other type keywords) have no SSA value in operand position.
// This used to lower to `add void void, 100` — IR nurlc emitted with status 0
// and only clang rejected ("void type only allowed for function results").
// die_if_void now rejects it at the source so the trap is a NURL diagnostic.
@ main → i {
    : i x + v 100
    ( nurl_print ( nurl_str_int x ) )
    ^ 0
}
