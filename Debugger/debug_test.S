/** @file debug_test.S
 *  @brief Test Routines to trigger ARM and Thumb Manual Breakpoints
 *
 */

/* Copyright (C) 2007-2011 the NxOS developers
 *
 * Module Developed by: TC Wan <tcwan@cs.usm.my>
 *
 * See AUTHORS for a full list of the developers.
 *
 * See COPYING for redistribution license
 *
 */
#define __ASSEMBLY__
#include "debug_stub.h"

.text
.align 4
.code 32

/**********************************************
 * dbg__test_arm_bkpt Test Routine
 *
 */
	.global dbg__test_arm_bkpt
dbg__test_arm_bkpt:
	stmfd sp!,{lr}
	dbg__bkpt_arm                  /* Trigger ARM Manual Breakpoint */
    ldmfd sp!,{pc}

/**********************************************
 * dbg__test_thumb_bkpt Test Routine
 *
 */
	.global dbg__test_thumb_bkpt
dbg__test_thumb_bkpt:
	stmfd sp!,{lr}
/*	ldr r0, =_thumb_entry
	orr	r0, r0, #1					@ Set Thumb mode
	mov	lr, pc
	bx	r0
*/
    bl  _thumb_entry
	ldmfd sp!,{pc}

.code 16
.thumb_func
_thumb_entry:
	dbg__bkpt_thumb
	bx	lr

.end
