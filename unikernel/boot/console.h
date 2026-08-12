/*
 * NURL unikernel — unikernel/boot/console.h
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * The screen. See console.c for why a serial port is not enough on real
 * hardware.
 */

#ifndef NURL_BOOT_CONSOLE_H
#define NURL_BOOT_CONSOLE_H

#include "mb2.h"

/* Arm the console from what the bootloader handed over. `info` may be
 * NULL, which on a Multiboot2 boot means a BIOS that stayed in text
 * mode; the console then uses the fixed 80x25 at 0xB8000. Safe to call
 * with a shape it cannot drive — it leaves itself off instead. */
void console_init(const struct mb2_fb *info);

/* One character, or nothing at all when there is no console. */
void console_putc(char c);

/* Whether anything is being drawn. */
int console_active(void);

/* Which console, in words, for the guest to print. */
const char *console_kind_name(void);

#endif /* NURL_BOOT_CONSOLE_H */
