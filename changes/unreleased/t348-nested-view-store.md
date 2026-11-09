### Fixed

- **A nested field store of a view makes the holder depend on its source**
  (Agora #348). `= . . h w v ( string_data b )` inside b's block, then a
  read of `. . h w v` after it, read freed memory. The same happened in a
  closure, in a `% Drop` holder's destructor, and with a view of a
  block-local struct's field. These are refused now, as the one-level
  store already was. A nested store of a view whose source outlives the
  holder stays accepted.
  A nested store is now a store into the root binding in every respect.
  A borrowed parameter stored there is copied, which fixes a use after
  free. A view stored by a field store whose value is a block that stores
  into another binding is tied to the right binding.
