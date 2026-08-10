// diag_dyn_not_generic.nu — a '%Trait' object over a trait that is not
// generic over Self.
% Speaker { @ speak i self → i }

: Dog { i pitch }

% Speaker Dog { @ speak Dog d → i { ^ . d pitch } }

@ announce %Speaker s → i { ^ ( speak s ) }

@ main → i { ^ 0 }
