### Fixed

- **A function handing back an option field of its parameter says it lent
  it** (Agora #459; probes *field_of_a_parameter_handed_back_on_some_runs).
  `@ pick H h i k → ?String`, returning `. h o` when `k` is 0 and a fresh
  value otherwise, told its caller the field was its own on both runs. The
  caller then released what `h` still held, and reading `h`'s field read
  freed memory. A field handed back as is is now answered "lent" for
  options and results too, as it already was for a String or a Vec field.
