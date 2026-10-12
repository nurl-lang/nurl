// An `inout` struct parameter on a foreign function: the C function
// writes a struct through the pointer, and it lands in a local of the
// caller — no buffer allocated and freed around the call.
: Timespec { i sec i nsec }

& `c` @ clock_gettime i32 clock_id inout Timespec tp → i32

unsafe @ main → i {
    : ~ Timespec ts @ Timespec { 0 0 }
    : i32 rc ( clock_gettime # i32 0 ts )
    ( nurl_println_int # i rc )
    // CLOCK_REALTIME (0): some time after 2001, with a sub-second part.
    ( nurl_println_int # i > . ts sec 1000000000 )
    ( nurl_println_int # i & >= . ts nsec 0 < . ts nsec 1000000000 )
    ^ 0
}
