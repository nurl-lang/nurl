// test_closure_mutate_immut.nu
// Closure yrittää muuttaa kaapattua immutable-muuttujaa → compile error

@ main → i {
  : i x 10
  : (@ v) bad \ → v { = x + x 1 }
  ( bad )
  ^ 0
}