// diag_raw_prefix_on_import.nu — `raw` prefixes function and struct
// declarations only; on an import it means nothing and is rejected.

raw

$ `stdlib/core/io.nu`

@ main → i { ^ 0 }
