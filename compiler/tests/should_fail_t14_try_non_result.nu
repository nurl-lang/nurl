// t14_try_non_result.nu — \ used on non-Result type → compile error
// Expected: no exe, stderr contains:
//   try operator \ used on non-Result type: i

@ add i a i b → i {
  ^ + a b
}

@ broken → ! i s {
  : i val \ ( add 1 2 )
  ^ @ ! i s { T val }
}

@ main → i {
  : ! i s res ( broken )
  ^ 0
}
