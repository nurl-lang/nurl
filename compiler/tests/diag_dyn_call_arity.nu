// diag_dyn_call_arity.nu — a dyn trait-object method call missing an
// argument. The indirect call through the vtable carries its own
// signature, so `( speak s )` against `speak T self i volume`
// ASSEMBLED and the thunk read an unset register — silently.
% Speaker [T] {
    @ speak T self i volume → i
}

: Dog { i pitch }

% Speaker Dog { @ speak Dog d i volume → i { ^ + . d pitch volume } }

@ announce %Speaker s → i {
    ^ ( speak s )
}

@ main → i {
    : Dog d @ Dog { 10 }
    : %Speaker sd ( dyn Speaker d )
    ^ ( announce sd )
}
