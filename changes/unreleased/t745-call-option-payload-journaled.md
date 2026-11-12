### Fixed

- **Under `recover`, a panic in an arm of `?? ( f … )` drops the payload
  the arm binds** (Agora #745). A `% Drop` payload of a call's fresh
  option or result was registered for its drop at the arm's end and in no
  journal entry, so a panic in the arm leaked it. It is journaled with its
  drop flag now. A payload the arm is only lent is still dropped once, by
  its owner.
