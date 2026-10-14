// diag_raw_on_const.nu — `raw` seals a plain struct or marks a function;
// on a constant it means nothing, and says so.
raw : i LIMIT 5

@ main → i { ^ LIMIT }
