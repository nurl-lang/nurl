// diag_import_missing.nu — a '$' import naming a file that does not
// exist. Used to die inside the runtime's nurl_read_file as a bare
// "nurlc: cannot open '<path>'" — no file, line, or 'error:' tag, so
// neither an editor nor an agent could anchor it, and which of a
// file's imports was broken was left to guesswork. Now anchored at the
// '$' directive with the resolution order spelled out.

$ `stdlib/core/vek.nu`

@ main → i {
    ^ 0
}
