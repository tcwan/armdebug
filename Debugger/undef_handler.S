
/* Copyright (C) 2007-2010 the NxOS developers
 *
 * Module Developed by: TC Wan <tcwan@cs.usm.my>
 *
 * See AUTHORS for a full list of the developers.
 *
 * Redistribution of this file is permitted under
 * the terms of the GNU Public License (GPL) version 2.
 */
#define __ASSEMBLY__
#include "debug_stub.h"

#define MODE_USR 0x10			/* User mode */
#define MODE_FIQ 0x11			/* FIQ mode */
#define MODE_IRQ 0x12			/* IRQ mode */
#define MODE_SVC 0x13 			/* Supervisor mode */
#define MODE_ABT 0x17			/* Abort mode */
#define MODE_UND 0x1B			/* Undefined mode */
#define MODE_SYS 0x1F			/* System mode */

.text
.code 32
.align 0

	.extern dbg__thumb_bkpt_handler
	.extern dbg__arm_bkpt_handler
	.extern default_undef_handler

	.global undef_handler

undef_handler:
/* Remote GDB Debugger relies on BKPT instruction being trapped here
 * In ARMv4t, it is an Illegal (Undefined) Instruction.
 * On triggering, lr (R14) contains the previous mode's pc (R15).
 * Based on example in Hohl, "ARM Assembly Language: Fundamentals and Techniques"
 * Chapter 11, Example 11.1.
 * Note: The handler is not AAPCS compliant (8 byte-alignment and stack, etc.)
 */
 /* We assume that the UNDEF stack holds only one stack frame and we will overwrite it.
  * On entry, LR_undef points to one instruction past the UNDEF instruction.
  *
  * For the purpose of Debugging, the stack frame should present the PC (R15) as the address
  * of the instruction that triggered the Breakpoint. Hence we need to adjust R15
  * to point to the address of the UNDEF instruction. This is what the JTAG debugger
  * does. (In the ARM hardware, the PC would point to UNDEF+2 instruction address
  * since it has a three stage pipeline).
  *
  * We will also store UNDEF LR (next instruction pointer) and UNDEF SPSR to the stack.
  */
  		ldr	sp, =__debugger_stack__
 		stmfd sp, {r0-r15}^				/* Save workspace, previous mode's pc via 'S' flag, R13-R15: placeholders */
 		mrs	r1, spsr					/* Copy SPSR to r1 */
 		tst	r1, #CPSR_THUMB				/* Check for Thumb Mode */
 		subne	r4, lr, #2				/* Is Thumb instruction, adjust PC for UNDEF instruction address */
 		subeq	r4, lr, #4				/* Is ARM instruction, adjust PC for UNDEF instruction address */
 		str		r4, [sp, #-4]			/* Save PC to stack (R15 slot) */

 		and r0, r1, #CPSR_MODE			/* Get previous mode */
 		teq	r0, #MODE_USR
 		beq	_skip_banked_registers		/* Can't switch back if we're in User mode! */
/* FIXME: We don't handle FIQ properly! */

_store_prev_mode_banked_regs:
 		orr	r0, #(CPSR_FIQ | CPSR_IRQ)	/* Disable Interrupts */
 		msr	cpsr_c, r0					/* Switch to previous mode */
 		mov	r3, lr						/* Previous Mode's LR (R14) */
 		mov	r2, sp						/* Previous Mode's SP (R13) */
		msr	cpsr_c, #(MODE_UND | CPSR_FIQ | CPSR_IRQ)	/* Revert to Undef Mode */
 		stmfd	sp, {r2,r3,r4}			/* Save previous mode SP, LR, PC to stack (R13-R15 slots). Need to store PC again as we're not updating SP(undef) */

_skip_banked_registers:
 		sub	sp, sp, #(4*16)				/* Need to manually update SP(undef) */
 		mov r0, lr						/* Move LR to r0 to enable use of stmfd */
 		stmfd	sp!, {r0,r1}			/* Save User's Next Instr Pointer (in UNDEF LR) and previous mode's CPSR to stack */
 		tst	r1, #CPSR_THUMB				/* Check for Thumb Mode */
		beq	_is_arm						/* Clear, so it's ARM mode */
_is_thumb:
		ldrh r0, [r4]					/* load UNDEF instruction into r0 */
		ldr	r1, =BKPT16_ENUM_MASK		/* Thumb BKPT enum mask */
		bic	r2, r0, r1					/* leave only opcode */
		ldr	r1, =BKPT16_INSTR			/* check for Thumb Breakpoint Instruction */
		teq	r2, r1
		bne	default_undef_handler
		ldr	r1, =BKPT16_ENUM_MASK		/* get Thumb BKPT Enum Mask */
		b	_exit_undef_handler
_is_arm:
		ldr	r0, [r4]					/* load UNDEF instruction into r0 */
		ldr	r1, =BKPT32_ENUM_MASK		/* ARM BKPT enum mask */
		bic	r2, r0, r1					/* leave only opcode */
		ldr	r1, =BKPT32_INSTR			/* check for ARM Breakpoint Instruction */
		teq	r2, r1
		bne	default_undef_handler
		ldr	r1, =BKPT32_ENUM_MASK		/* get ARM BKPT Enum Mask */
_exit_undef_handler:
		and	r0, r1, r0					/* Keep index value */
		msr	cpsr_c, #(MODE_ABT)			/* Configure Abort Mode */
		ldr	lr, =dbg__arm_bkpt_handler		/* handle BKPT, BKPT index in r0 */
		mov	pc, lr						/* Invoke Debugger State (Supervisor Mode) */


