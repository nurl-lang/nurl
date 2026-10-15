// diag_raw_struct_literal.nu — `raw : S { … }` seals a struct whose fields
// carry an invariant (here: `addr` is device memory holding `n` elements),
// so a literal of it, like one of a struct with a raw-pointer field, is
// raw memory: safe code cannot make one up.
raw : DevBuf { i addr i n }

@ dev_len DevBuf b → i { ^ . b n }

@ main → i {
    : DevBuf b @ DevBuf { 123456 10 }
    ^ ( dev_len b )
}
