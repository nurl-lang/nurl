// diag_dyn_no_impl.nu — 'dyn' over a type with no impl of the trait.
% Speaker [T] { @ speak T self → i }

: Dog { i pitch }
: Cat { i lives }

% Speaker Dog { @ speak Dog d → i { ^ . d pitch } }

@ main → i {
    : Cat c @ Cat { 9 }
    : %Speaker s ( dyn Speaker c )
    ^ 0
}
