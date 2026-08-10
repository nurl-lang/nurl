// diag_method_no_impl.nu — calling a trait method with a receiver
// whose type has no impl. The name is impl-backed (so the unknown-
// callee check lets it through), dispatch missed, and the fall-through
// emitted `call @speak(%Cat …)` against an undefined symbol — an error
// only clang reported, far from the call.
% Speaker [T] {
    @ speak T self → i
}

: Dog { i pitch }
: Cat { i lives }

% Speaker Dog { @ speak Dog d → i { ^ . d pitch } }

@ main → i {
    : Cat c @ Cat { 9 }
    ^ ( speak c )
}
