### Fixed

- **A value lent out of a Slice field depends on what the Slice views**
  (Agora #566). `: S e ( slice_at [S] . h z 0 )`, where `. h z` views a
  Vec, borrowed nothing, so clearing that Vec, or a sibling field `. h a`
  that `. h z` views, and then reading `e` read freed memory (heap use
  after free). Now `e` borrows what the field views, as it already did
  through a whole Slice binding.
- **Clearing a payload lent out of one `Rc` share ends borrows taken
  through another share of the same Rc** (Agora #566). `: ( Vec S ) va
  ( rc_get . h a )` followed by `( vec_clear [S] va )` left standing a
  String borrowed through `. h z`, another share of the same Rc, and a
  later read of it read freed memory. The same happened with a join or a
  value block of such payloads. Clearing through the share directly was
  already refused.
