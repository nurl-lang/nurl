### Fixed

- **A field a `sink` took cannot be used until it has a value again**
  (Agora #280; probes vec_field_taken_by_a_sink_then_pushed,
  string_field_taken_by_a_sink_then_pushed,
  struct_with_a_taken_field_handed_on_whole,
  struct_with_a_taken_field_returned_whole and
  inout_field_taken_by_a_sink_then_used_by_the_caller; tests
  diag_moved_field and diag_moved_field_inout). `(
  take . h buf )`, where take's parameter is a `sink`, takes the field's
  value and leaves the field empty where it lives. A later `( vec_push [u]
  . h buf … )` or `string_push_str` then dereferenced the null handle, and
  `bytes_extend_str` spun. All of that was in safe code. A binding in the
  same place was already refused as a use of a moved value. Now a field
  is too:
  - reading or binding it, handing its struct on whole to a call, a store
    or a `^`, and leaving the function while its struct is an `inout`
    parameter (the caller would get it back with the field empty), is
    refused, whether it was taken definitely or on some paths;
  - a store to the field (`= . h buf …`), or a new value for the struct,
    makes it usable again;
  - the struct's other fields stay usable.
  Nothing is added at run time.
