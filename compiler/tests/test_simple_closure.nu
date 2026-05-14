// test_simple_closure.nu
// Very simple closure test

@ main → i {
    : ( @ i i ) square \ i x → i { * x x }
    ^ 0
}
