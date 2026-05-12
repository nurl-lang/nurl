// test_immutable_assign_error.nu
// = x expr kun x on immutable → compile error

@ main → i {
  : i x 10
  = x + x 1
  ^ x
}