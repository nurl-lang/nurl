/*
 * NURL unikernel — unikernel/boot/font8x16.h
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * The console font. See font8x16.c for the font's own licence, which
 * is not this one.
 */

#ifndef NURL_BOOT_FONT8X16_H
#define NURL_BOOT_FONT8X16_H

#define FONT8X16_FIRST 32       /* space          */
#define FONT8X16_LAST  126      /* tilde          */
#define FONT8X16_COUNT (FONT8X16_LAST - FONT8X16_FIRST + 1)

/* Row-major, one byte per pixel row, MSB leftmost, 16 rows a glyph. */
extern const unsigned char font8x16[FONT8X16_COUNT][16];

#endif /* NURL_BOOT_FONT8X16_H */
