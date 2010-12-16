
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

#define MODE_SVC 0x13 			/* Supervisor mode. */

.text
.code 32
.align 0

	.extern dbg__thumb_bkpt_handler
	.extern dbg__arm_bkpt_handler
	.extern default_undef_handler

	.global undef_handler

undef_handler:
/* Remote GDB Debugger relies on BKPT instruction being trapped here
   In ARMv4t, it is an Illegal (Undefined) Instruction.
   On triggering, lr (R14) contains the previous mode's pc (R15).
   Based on example in Hohl, "ARM Assembly Language: Fundamentals and Techniques"
   Chapter 11, Example 11.1.
   Note: The handler is not AAPCS compliant (8 byte-alignment and stack, etc.)
 */
 /* We assume that the UNDEF stack has been setup previously
    On entry, LR_undef points to one instruction past the UNDEF instruction
  */
  		ldr	sp, =__debugger_stack__
 		stmfd sp, {r0-r15}^				/* Save workspace, user mode's pc via 'S' flag */
 		sub	sp, sp, #(4*16)				/* Need to manually update SP(undef) */
 		mrs	r1, spsr					/* Copy SPSR to r0 */
 		tst	r1, #CPSR_THUMB				/* Check for Thumb Mode */
		beq	_is_arm						/* Clear, so it's ARM mode */
_is_thumb:
 		sub	r0, lr, #2					/* LR points to instruction after UNDEF instruction */
 		stmfd	sp!, {r0,r1}			/* Save UNDEF instruction addr and previous mode's CPSR to stack */
		ldrh r0, [r0]					/* load UNDEF instruction into r0 */
		ldr	r1, =BKPT16_ENUM_MASK		/* Thumb BKPT enum mask */
		bic	r2, r0, r1					/* leave only opcode */
		ldr	r1, =BKPT16_INSTR			/* check for Thumb Breakpoint Instruction */
		teq	r2, r1
		bne	default_undef_handler
		ldr	r1, =BKPT16_ENUM_MASK		/* get Thumb BKPT Enum Mask */
		and	r0, r1, r0					/* Keep index value */
		msr	cpsr_c, #(MODE_SVC)			/* Configure Supervisor Mode */
		ldr	lr, =dbg__thumb_bkpt_handler	/* handle BKPT, BKPT index in r0 */
		mov	pc, lr						/* Invoke Debugger State (Supervisor Mode) */
_is_arm:
 		sub	r0, lr, #4					/* LR points to instruction after UNDEF instruction */
 		stmfd	sp!, {r0,r1}			/* Save UNDEF instruction addr and previous mode's CPSR to stack */
		ldr	r0, [r0]					/* load UNDEF instruction into r0 */
		ldr	r1, =BKPT32_ENUM_MASK		/* ARM BKPT enum mask */
		bic	r2, r0, r1					/* leave only opcode */
		ldr	r1, =BKPT32_INSTR			/* check for ARM Breakpoint Instruction */
		teq	r2, r1
		bne	default_undef_handler
		ldr	r1, =BKPT32_ENUM_MASK		/* get ARM BKPT Enum Mask */
		and	r0, r1, r0					/* Keep index value */
		msr	cpsr_c, #(MODE_SVC)			/* Configure Supervisor Mode */
		ldr	lr, =dbg__arm_bkpt_handler		/* handle BKPT, BKPT index in r0 */
		mov	pc, lr						/* Invoke Debugger State (Supervisor Mode) */


