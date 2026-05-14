// test_no_capture.nu
// Closure that doesn't capture anything

@ main → i {
    : i local_value 42

    // This closure doesn't capture - uses only parameters and constants
    : ( @ i i ) add_ten \ i x → i { + x 10 }

    // Test calling it (this won't work yet due to call site issues)
    ^ 0
}
