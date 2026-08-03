// should_fail_assign_undefined.nu — assignment to a name with no
// binding, parameter, or global in scope must be an error. It used to
// fall through SILENTLY: the RHS was evaluated and the store vanished
// (no diagnostic, no IR) — found by the structural fuzzer's minimizer,
// whose deletions kept "compiling" through the hole.

$ `stdlib/core/string.nu`

@ main → i {
    : ~ i k 0
    ~ < k 3 {
        = nosuchname # u64 4908083960683138595
        = k + k 1
    }
    ^ 0
}
