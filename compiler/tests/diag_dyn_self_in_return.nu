// diag_dyn_self_in_return.nu — a trait method naming Self past the
// receiver. The vtable has one entry per method and no way to say which
// concrete type comes back, so the trait is not object-safe.
% Maker [T] { @ make T self → T }

: Dog { i pitch }

% Maker Dog { @ make Dog d → Dog { ^ d } }

@ use %Maker m → i { ^ 0 }

@ main → i { ^ 0 }
