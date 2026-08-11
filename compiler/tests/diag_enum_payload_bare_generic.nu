// diag_enum_payload_bare_generic.nu — a generic template's bare name
// as an enum variant's payload type ('JArr Vec' for
// 'JArr ( Vec Json )'). The payload registered as '%Vec' and every
// match arm binding it allocated an unsized type — invalid IR only the
// LLVM verifier saw. Payload types now run the same known-type check
// as fields, params, and returns.

: Pair [A B] {
    A first
    B second
}

: | Node {
    Leaf i
    Branch Pair
}

@ main → i {
    ^ 0
}
