// diag_raw_on_impl_method.nu — a trait method can be called through a
// `dyn` value, where no caller can be checked, so `raw` is refused there.
: S { i v }

% Get { @ get S s → i }

% Get S { raw @ get S s → i { ^ . s v } }

@ main → i { ^ 0 }
