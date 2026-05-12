// t15_result_type_mismatch.nu — \ propagates ! i s in fn returning ! i MathErr → compile error
// Expected: no exe, stderr contains:
//   try propagation type mismatch

: | MathErr { DivZero }

@ string_err i x → ! i s {
  ^ @ ! i s { T x }
}

@ mismatched → ! i MathErr {
  : i val \ ( string_err 5 )
  ^ @ ! i MathErr { T val }
}

@ main → i {
  : ! i MathErr res ( mismatched )
  ^ 0
}
