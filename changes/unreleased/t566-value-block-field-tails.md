### Fixed

- **A value block whose tail is a field read lends like the field read** (Agora #566, items 3 and 4). `( vec_clear [S] ( idv { . h z } ) )` ended no borrow of `. h z` through the identity function, and `^ { . ( vec_at [S] . h a 0 ) name }` handed the caller a String the parameter's element still held, which the caller then freed (a heap-use-after-free). Both now behave as the bare `. h z` and `. ( vec_at … ) name` spellings do.
