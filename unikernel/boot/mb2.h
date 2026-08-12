/*
 * NURL unikernel — unikernel/boot/mb2.h
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * What `multiboot2.c` learned at handover, for the two files that
 * need it afterwards: `platform_x86.c` (did this boot fail, and on
 * what) and `console.c` (is there a screen, and what shape is it).
 */

#ifndef NURL_BOOT_MB2_H
#define NURL_BOOT_MB2_H

/* The screen the bootloader handed over. `fb_type` is Multiboot2's:
 * 0 = indexed colour, 1 = direct RGB, 2 = EGA text. The console
 * drives 1 and 2; 0 needs a palette nobody has asked for yet. */
struct mb2_fb {
    unsigned long long addr;
    unsigned int       pitch;      /* bytes per row, NOT pixels        */
    unsigned int       width;      /* pixels, or columns when EGA text */
    unsigned int       height;     /* pixels, or rows when EGA text    */
    unsigned char      bpp;
    unsigned char      fb_type;
};

/* Non-zero when the machine came up through `_mb2_start` — i.e. a
 * bootloader on real hardware rather than a hypervisor's PVH jump. */
int mb2_booted(void);

/* The sentence describing why the handover was unusable, or NULL when
 * it was fine. Recorded rather than printed because the conversion
 * runs before there is anywhere to print. */
const char *mb2_failure(void);

/* The framebuffer, or NULL if the bootloader supplied none. */
const struct mb2_fb *mb2_framebuffer(void);

#endif /* NURL_BOOT_MB2_H */
