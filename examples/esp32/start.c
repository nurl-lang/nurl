/* start.c — minimal freestanding startup shim for the NURL ESP32-C3 demo.
 *
 * nurlc's emitted `main` calls `nurl_init(argc, argv)` before running the
 * NURL body (`_nurl_main`). On bare metal there is no libc and no argv, so
 * we provide an empty `nurl_init` and a `_start` reset entry that just sets
 * up a stack pointer and jumps to `main`.
 *
 * This is enough to LINK a real RV32 ELF from the NURL-generated object and
 * inspect/disassemble the machine code. It is NOT a flashable image: a real
 * ESP32-C3 boot needs the 2nd-stage bootloader header, the IO_MUX/clock
 * bring-up and a flash partition layout (all provided by ESP-IDF). See
 * README.md.
 */

/* nurlc emits:  i32 main(i32 argc, i8** argv)  ->  calls nurl_init then _nurl_main */
void nurl_init(int argc, char **argv) { (void)argc; (void)argv; }

int main(int argc, char **argv);

/* Top of DRAM on the ESP32-C3 (see esp32c3.ld). */
extern char _stack_top;

__attribute__((naked, section(".text.start")))
void _start(void) {
    __asm__ volatile(
        "la   sp, _stack_top\n"   /* set up the stack            */
        "li   a0, 0\n"            /* argc = 0                    */
        "li   a1, 0\n"            /* argv = NULL                 */
        "call main\n"             /* run the NURL program        */
        "1: j 1b\n"               /* spin forever on return      */
    );
}
