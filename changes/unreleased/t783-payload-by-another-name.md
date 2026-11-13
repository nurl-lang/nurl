### Fixed

- **A `??` payload of a local enum handed back by another route than
  `^ s` is the caller's own** (Agora #783). `: String t s ^ t`, the same
  as a join's value, `^ ( gid [String] s )` and a lender beside a
  parameter were answered as lent out of the enum, which is released on
  the way out — the caller read freed memory. A binding of the payload
  under another name is that payload (taken or copied as `^ s` is), and a
  call lending such a payload lends out of a local (copied on the way
  out).
- **A literal handed back with a nested literal that lends whole beside
  a fresh field owns everything it holds** (Agora #783 item 5):
  `^ @ O2 { @ P1 { . h name } ( string_from … ) }` was answered lent
  whole, and the fresh String leaked. The nested literal is copied, as a
  lent field beside an own one already was (#635), where it holds no view.
