// diag_volatile_load_untyped.nu — volatile_load handed a plain integer.
// The width to read comes from the pointer's type, so an untyped
// address cannot say how much to load.
@ main → i {
    : i p 4096
    : i v ( volatile_load p )
    ^ v
}
