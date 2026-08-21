/*
 * NURL unikernel — unikernel/boot/cmdenv.c
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * The kernel command line IS the environment. Plan B7 promised
 * "getenv + CLI args from kernel cmdline (key=value pairs plus a
 * passthrough for argv)"; the argv half has always worked and the
 * getenv half was left an empty list — a NURL program in the guest
 * could never read `wallclock=`, `dns=` or an operator's own key,
 * even though the host states them right there.
 *
 * Every `key=value` token becomes one environ entry, except
 * `args="…"` (that token is argv's, and its contents are program
 * arguments, not configuration). A value may be quoted to carry
 * spaces — GRUB re-quotes the whole line, so quotes appear around
 * values that never had them under QEMU; they are dropped, which
 * makes the two spellings read identically.
 *
 * Shared by all three platform files the way boot/fdt.c is: the same
 * cmdline grammar exists on every board, and three copies of a token
 * scanner is how the AArch64 walker got its hard-coded depth.
 */

int nl_env_from_cmdline(const char *cl, char *buf, unsigned long bufsz,
                        char **envv, int envmax);

int nl_env_from_cmdline(const char *cl, char *buf, unsigned long bufsz,
                        char **envv, int envmax)
{
    int n = 0;
    unsigned long w = 0;
    const char *p = cl;

    if (cl) {
        while (*p && n < envmax) {
            while (*p == ' ') p++;
            if (!*p) break;

            unsigned long tok = w;      /* where this entry starts */
            int has_eq = 0, in_quote = 0, full = 0;

            while (*p) {
                char c = *p;
                if (c == ' ' && !in_quote) break;
                if (c == '"') { in_quote = !in_quote; p++; continue; }
                if (c == '=') has_eq = 1;
                if (w + 2 >= bufsz) { full = 1; break; }
                buf[w++] = c;
                p++;
            }
            if (full) { w = tok; break; }
            buf[w] = 0;

            /* args= is argv's token, and a bare word ("quiet") is not
             * an assignment — neither becomes environment. */
            int is_args = buf[tok + 0] == 'a' && buf[tok + 1] == 'r' &&
                          buf[tok + 2] == 'g' && buf[tok + 3] == 's' &&
                          buf[tok + 4] == '=';
            if (has_eq && !is_args) {
                w++;                    /* keep the NUL */
                envv[n++] = &buf[tok];
            } else {
                w = tok;                /* rewind: not an entry */
            }
        }
    }
    envv[n] = 0;
    return n;
}
