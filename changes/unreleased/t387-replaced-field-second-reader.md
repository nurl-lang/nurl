### Fixed

- **A second reader of a replaced field is a borrow of the first**
  (Agora #387). With `: String g1 . o name  : String g2 . o name`,
  replacing `. o name` hands the old value to `g1`. `g2` is a view of it.
  Handing `g2` to a `sink`, or reading it after `g1` is consumed or given a
  new value, compiled and read freed memory. It is now refused: "'g2'
  borrows from 'g1', which ended at line N…".
- **No leak when a reader that took a field's old value in a block is
  handed on after it** (found fixing Agora #387). The struct's new value
  was taken out of the field with it and leaked.
