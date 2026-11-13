### Fixed

- **A result copied or taken out of a local survives a panicking
  destructor** (Agora #814, #677 D). `^ . h name` of a local struct, a
  payload taken out of a local enum, or a copy of either, lived in a
  register while the locals were dropped; a local's destructor that
  panicked unwound past it and the value leaked under `recover`. It is
  journaled for that window with its own bit, as a returned literal is.
