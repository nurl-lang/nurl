### Fixed

- **A helper that puts its `Rc` parameter into a local is followed by every spelling of the put** (AGORA-793). A caller holds a view of an `Rc` payload through one handle and passes another handle on the same value to a helper. The helper puts the parameter into a local and replaces or grows the payload through that local. The caller's view then read freed memory when the put was one of these:
  - a helper of its own pushing `( rc_clone h )` or `@ W { h }` into another argument;
  - storing it into a field of an `inout` struct;
  - pushing it into `x0` of `: … x0 ( vec_at xss 0 )` and replacing the payload through `xss`;
  - pushing it into a container reached through a call, `. ( box_get bx ) hs`;
  - putting a `??` payload of an option parameter into a local.

  Each of these now counts as the helper changing that parameter, so the caller's view ends at the call, as it already did for a direct push. Take the view again after the call. A helper that only reads through the local is not affected.
