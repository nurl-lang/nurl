### Fixed

- **`btree_remove` drops the removed key after the tree is final** (Agora
  #658). The stored key was dropped inside the removal, while its node
  still counted the slot and before the ancestors' sizes and the tree's
  length were lowered. A key whose `% Drop` panicked under `recover` left
  a tree that counted an emptied slot, and the tree's own drop then ran
  the destructor again on it (a crash). The key is now handed up and
  dropped last: the panic leaves a tree without the entry — still ordered,
  counted and usable — and the value that was about to be returned is
  released by the unwind. A tree whose keys run no code of the program's
  own when dropped removes exactly as before.
