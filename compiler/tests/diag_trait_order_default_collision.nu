// The first impl's deferred default collides with a later explicit method.
% First i {}

% Second i { @ value i self → i { ^ self } }

% First [T] { @ value T self → i { ^ 1 } }

% Second [T] { @ value T self → i }

@ main → i { ^ 0 }
