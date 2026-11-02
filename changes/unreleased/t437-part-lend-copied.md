### Fixed

- **An owner given a part of its own value keeps that part alive**
  (Agora #437, claude-formal's HOLD on #419; probes
  enum_owner_given_a_part_*). Take `= o ( kid o )`, where `kid` hands
  back `( vec_at v 0 )` out of `o`'s own payload. #419's identity test
  found the result's key different from the old value's, took it for
  another owner's value, and released the old value with the part inside
  it (heap-use-after-free). Where the callee may hand back a part of a
  parameter rather than whole parameters, a result that is not the old
  value is now copied. The old value then goes by its flag, and `o` owns
  its copy. A type that cannot be copied is refused there.
