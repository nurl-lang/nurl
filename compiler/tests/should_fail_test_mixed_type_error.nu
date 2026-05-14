// test_mixed_type_error.nu
// b & i → compile error, tyypit eivät sovi yhteen

@ main → i {
    : b flag T
    : i mask 255
    : result & flag mask
    ^ 0
}
