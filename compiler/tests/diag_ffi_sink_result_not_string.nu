// A 'sink' FFI result says the C function hands over a string it
// allocated, which the caller then owns. Only a raw string can be handed
// over that way.
& `c` @ getpid → sink i

@ main → i { ^ 0 }
