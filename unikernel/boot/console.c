/*
 * NURL unikernel — unikernel/boot/console.c
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * The screen, on a machine that has one.
 *
 * Under a hypervisor the guest's console is a serial port, because the
 * hypervisor is holding the other end of it. On real hardware nobody
 * is: a laptop booted off a USB stick has no 8250 at 0x3F8 to speak
 * into, and a guest that prints only there is indistinguishable from a
 * guest that never started. So the same output also goes to whatever
 * the bootloader left on the screen.
 *
 * Two shapes arrive, and which one depends on the firmware rather than
 * on anything this image chose:
 *
 *   EGA text — a legacy BIOS boot. 80x25 cells of (character,
 *   attribute) at 0xB8000, the format PCs have had since 1981. The
 *   firmware owns the font.
 *
 *   Direct RGB — a UEFI boot. A pixel buffer and nothing else: no text
 *   memory, no font in ROM, no firmware call available once the
 *   bootloader has exited boot services. Glyphs have to come from the
 *   image, which is what boot/font8x16.c is for.
 *
 * Only white on black is drawn, which is why no pixel-format masks are
 * needed even though the bootloader reports them: white is all bits
 * set and black is none, in every RGB layout there is.
 *
 * This console is armed ONLY on a Multiboot2 boot. A PVH guest keeps
 * exactly the output path its gates are written against — 0xB8000 on a
 * microvm is ordinary RAM nobody looks at, and scribbling into it to
 * no effect is not an improvement worth a regression risk.
 */

#include "console.h"
#include "font8x16.h"

typedef unsigned long long u64;
typedef unsigned int       u32;
typedef unsigned char      u8;

#define FB_W 8                 /* the font's cell, in pixels */
#define FB_H 16

static enum { CON_NONE, CON_TEXT, CON_FB } kind;

static volatile u8 *fb;        /* the screen                          */
static u32 pitch;              /* bytes per row — NOT width * bytes   */
static u32 bytes_pp;
static u32 cols, rows;         /* in CHARACTERS, both modes           */
static u32 cx, cy;

/* Text mode: light grey on black, the attribute a PC comes up with. */
#define TEXT_ATTR 0x07

/* ── the hardware cursor ─────────────────────────────────────────
 * Text mode only. Without this the block sits at the top left while
 * output scrolls past underneath it, which reads as a hung machine at
 * exactly the moment someone is looking for signs of life. */
static inline void outb(unsigned short port, u8 v) {
    __asm__ __volatile__("outb %0, %1" :: "a"(v), "Nd"(port));
}

static void cursor_to(u32 x, u32 y) {
    u32 off = y * cols + x;
    outb(0x3D4, 0x0F); outb(0x3D5, (u8)(off & 0xFF));
    outb(0x3D4, 0x0E); outb(0x3D5, (u8)((off >> 8) & 0xFF));
}

/* ── one glyph ───────────────────────────────────────────────────── */

static void draw_cell(u32 x, u32 y, char c) {
    if (kind == CON_TEXT) {
        volatile u8 *p = fb + (y * cols + x) * 2;
        p[0] = (u8)c;
        p[1] = TEXT_ATTR;
        return;
    }

    /* Anything the font does not cover becomes '?', which is a
     * character the reader can see and reason about. Indexing past the
     * table with it would be a fault in the code that exists to report
     * faults. */
    unsigned idx = (unsigned char)c;
    if (idx < FONT8X16_FIRST || idx > FONT8X16_LAST) idx = '?';
    const u8 *g = font8x16[idx - FONT8X16_FIRST];

    for (u32 row = 0; row < FB_H; row++) {
        volatile u8 *p = fb + (u64)(y * FB_H + row) * pitch
                            + (u64)(x * FB_W) * bytes_pp;
        u8 bits = g[row];
        for (u32 col = 0; col < FB_W; col++) {
            u8 v = (bits & (0x80u >> col)) ? 0xFF : 0x00;
            for (u32 b = 0; b < bytes_pp; b++) p[col * bytes_pp + b] = v;
        }
    }
}

static void clear_row(u32 y) {
    for (u32 x = 0; x < cols; x++) draw_cell(x, y, ' ');
}

/* Copy every row up by one and blank the last. A framebuffer scroll is
 * a few megabytes of memmove per line, which is slow enough to notice
 * and still the right answer: the alternative is a ring buffer and a
 * redraw, i.e. the same bytes moved plus bookkeeping. */
static void scroll(void) {
    if (kind == CON_TEXT) {
        volatile u8 *p = fb;
        u64 line = (u64)cols * 2;
        for (u64 i = 0; i < line * (rows - 1); i++) p[i] = p[i + line];
    } else {
        volatile u8 *p = fb;
        u64 line = (u64)pitch * FB_H;
        for (u64 i = 0; i < line * (rows - 1); i++) p[i] = p[i + line];
    }
    clear_row(rows - 1);
}

/* ── the interface ───────────────────────────────────────────────── */

void console_init(const struct mb2_fb *info) {
    if (!info) {
        /* A Multiboot2 boot with no framebuffer tag is a BIOS boot
         * that stayed in text mode. That mode is at a fixed address
         * with a fixed size; it is the one place on a PC where
         * assuming is better founded than asking. */
        fb    = (volatile u8 *)0xB8000UL;
        cols  = 80;
        rows  = 25;
        kind  = CON_TEXT;
    } else if (info->fb_type == 2) {
        fb    = (volatile u8 *)(unsigned long)info->addr;
        cols  = info->width;
        rows  = info->height;
        kind  = CON_TEXT;
    } else if (info->fb_type == 1 && info->bpp >= 8) {
        /* boot.S identity-maps the low 4 GiB and no more. A screen
         * above that line is one this console cannot reach, and
         * touching it would page-fault inside the code that prints
         * page faults. Refusing leaves the serial port, which is
         * output, rather than a triple fault, which is not. */
        if (info->addr + (u64)info->pitch * info->height > 0x100000000ULL) {
            kind = CON_NONE;
            return;
        }
        fb       = (volatile u8 *)(unsigned long)info->addr;
        pitch    = info->pitch;
        bytes_pp = (u32)info->bpp / 8;
        cols     = info->width  / FB_W;
        rows     = info->height / FB_H;
        kind     = CON_FB;
    } else {
        kind = CON_NONE;        /* indexed colour: needs a palette   */
        return;
    }

    if (!cols || !rows) { kind = CON_NONE; return; }

    cx = cy = 0;
    for (u32 y = 0; y < rows; y++) clear_row(y);
    if (kind == CON_TEXT) cursor_to(0, 0);
}

void console_putc(char c) {
    if (kind == CON_NONE) return;

    /* The font covers ASCII and this project writes UTF-8. A character
     * outside the font is drawn as one '?' — but a naive byte-at-a-time
     * console draws one per BYTE, so an em dash comes out as "???" and
     * every line of prose looks corrupted rather than approximated.
     * Continuation bytes (10xxxxxx) are therefore swallowed: the lead
     * byte already stood in for the whole character. */
    if ((unsigned char)c >= 0x80) {
        if (((unsigned char)c & 0xC0) == 0x80) return;   /* continuation */
        c = '?';
    }

    if (c == '\r') { cx = 0; goto done; }
    if (c == '\n') { cx = 0; cy++; goto wrap; }

    draw_cell(cx, cy, c);
    if (++cx < cols) goto done;
    cx = 0;
    cy++;

wrap:
    if (cy >= rows) { scroll(); cy = rows - 1; }
done:
    if (kind == CON_TEXT) cursor_to(cx, cy);
}

int console_active(void) { return kind != CON_NONE; }

/* For the guest to print. "Which console am I on" is the first
 * question when output appears in one place and not another, and the
 * machine is the only thing that can answer it. */
const char *console_kind_name(void) {
    switch (kind) {
    case CON_TEXT: return "VGA text (0xB8000)";
    case CON_FB:   return "linear framebuffer, 8x16 font";
    default:       return "serial only — nothing is reaching a screen";
    }
}
