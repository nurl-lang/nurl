// diag_objsafe_sink_receiver.nu — a trait method that consumes its
// receiver. A '%Trait' object cannot hand ownership through a vtable.
% Eater [T] { @ eat sink T self → i }

: Dog { i age }

% Eater Dog { @ eat sink Dog d → i { ^ 1 } }

@ use %Eater e → i { ^ 0 }

@ main → i { ^ 0 }
