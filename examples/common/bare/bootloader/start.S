/* IDF-free minimal 2nd-stage bootloader -- reset entry.
 *
 * The mask ROM jumps here after loading our image into SRAM.  Establish a clean
 * register window + stack (the ROM left a deep window on ITS stack), clear .bss,
 * then enter boot_main.  We leave VECBASE on the ROM vectors (a fault in the
 * bootloader is rare; if it happens the ROM handler resets -- and esptool download
 * mode always recovers).  Window/PS handling mirrors the app's start.S. */
	.section .text, "ax"
	.align	4
	.global	_start
	.type	_start, @function
_start:
	/* SP = top of the bootloader stack, 16-aligned */
	movi	a1, _stack_top
	movi	a0, -16
	and	a1, a1, a0
	/* PS: WOE=1, CALLINC=1, UM=1, INTLEVEL=0 (window-overflow detection on) */
	movi	a0, 0x00050020
	wsr.ps	a0
	rsync
	/* discard the ROM's deep window: WINDOWSTART = 1 << WINDOWBASE (only the
	   current frame live), so a later spill does not chase the ROM's stale frames */
	rsr.windowbase	a3
	ssl	a3
	movi	a2, 1
	sll	a2, a2
	wsr.windowstart	a2
	rsync
	movi	a0, 0
	/* clear .bss [_bss_start, _bss_end) */
	movi	a2, _bss_start
	movi	a3, _bss_end
	movi	a4, 0
.Lbss:
	bgeu	a2, a3, .Lbss_done
	s32i	a4, a2, 0
	addi	a2, a2, 4
	j	.Lbss
.Lbss_done:
	/* enter boot_main as the OUTERMOST window frame (jump, not call, so its own
	   ENTRY is the true top of the spill chain with a0=0 terminating it) */
	movi	a8, boot_main
	movi	a0, 0
	jx	a8
.Lhang:
	j	.Lhang
	.size	_start, . - _start
