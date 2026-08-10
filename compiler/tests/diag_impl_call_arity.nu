// diag_impl_call_arity.nu — a static impl-method call missing an
// argument. `( speak d )` against `speak Dog d i volume` assembled
// (opaque-pointer calls carry their own signature) and the callee read
// an unset register for volume, silently.
% Speaker [T] {
    @ speak T self i volume → i
}

: Dog { i pitch }

% Speaker Dog { @ speak Dog d i volume → i { ^ + . d pitch volume } }

@ main → i {
    : Dog d @ Dog { 10 }
    ^ ( speak d )
}
