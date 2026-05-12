// test_capture.nu
// Test variable capture

@ main → i {
  : i captured_value 42

  // This closure should capture 'captured_value' from outer scope
  : (@ i) getter \ → i { ^ captured_value }

  ^ 0
}