// should_fail_duplicate_impl.nu — two impls of the same trait for the same
// type must be a clean COMPILE FAIL (coherence), not an LLVM function
// redefinition. `i` and `i64` are the same type (both lower to LLVM i64),
// so impls for both collide and are reported as a duplicate impl.
% Show i { @ show i a → i { ^ 0 } }

% Show i64 { @ show i64 a → i { ^ 0 } }

@ main → i { ^ 0 }
