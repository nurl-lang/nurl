// should_fail_immutable_global.nu
// A top-level binding introduced with `:` (no `~`) is immutable. A
// function reassigning it with `= G …` must be a COMPILE ERROR. Mutable
// module state must be declared `: ~`.
: i G 0

@ main → i {
    = G 5
    ^ G
}
