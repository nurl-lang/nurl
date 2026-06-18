// should_fail_member_on_scalar.nu — `.` field/element access on a scalar
// (non-aggregate) used to emit `extractvalue i64 …`. Rejected at the source.
@ main → i { : i n 5  : i z . n x  ^ 0 }
