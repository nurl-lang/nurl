// should_fail_ambiguous_method.nu — two distinct traits providing a method
// of the same name for the same type makes bare-name dispatch ambiguous;
// the compiler must reject it (coherence), naming both traits.
% Show i { @ fmt i a → i { ^ 0 } }

% Debug i { @ fmt i a → i { ^ 1 } }

@ main → i { ^ 0 }
