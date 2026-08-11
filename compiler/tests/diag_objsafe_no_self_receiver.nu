// diag_objsafe_no_self_receiver.nu — a trait method whose first
// parameter is not Self, so dynamic dispatch has nothing to dispatch on.
% Maker [T] { @ make i n → i }

: Dog { i age }

% Maker Dog { @ make i n → i { ^ n } }

@ use %Maker m → i { ^ 0 }

@ main → i { ^ 0 }
