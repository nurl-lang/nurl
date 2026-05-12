// test_debug_closure.nu
// Simple debug test for parameter parsing

@ main → i {
  // Test: \ i x → i { ^ x }
  : (@ i i) f \ i x → i { ^ x }
  ^ 0
}