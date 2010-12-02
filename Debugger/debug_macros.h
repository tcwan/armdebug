/** @file debug_macros.h
 *  @brief internal macros used by debug_stub routines
 *
 */

/* Copyright (C) 2007-2010 the NxOS developers
 *
 * Module Developed by: TC Wan <tcwan@cs.usm.my>
 *
 * See AUTHORS for a full list of the developers.
 *
 * See COPYING for redistribution license
 *
 */

#ifndef __DEBUG_MACROS_H__
#define __DEBUG_MACROS_H__

#include "_c_arm_macros.h"


/** @addtogroup debug_macros */
/*@{*/

/* _dbg_jumpTableHandler
 *      Call Jump Table Routine based on Index
 *	On entry:
 *	  jumptableaddr is the address (constant) of the Jump Table
 *	  jumpreg is the register used to perform the indirect jump
 *	  indexreg contains jump table index value
 */
	.macro  _dbg_jumpTableHandler   jumptableaddr, jumpreg, indexreg

	ldr	 \jumpreg, =\jumptableaddr
	ldr	 \jumpreg, [\jumpreg, \indexreg, lsl #2]
	mov	 lr, pc
	bx	  \jumpreg	/* Call Command Handler Routine */
	.endm


/* _dbg_stpcpy
 *	_dbg_stpcpy macro
 *	On entry:
 *	  deststrptr: Destination string [Cannot be R0]
 *	  sourcestrptr: Source string [Cannot be R0]
 *	On exit:
 *	  deststrptr: Pointer to NULL character in destination string
 *	  R0: destroyed
 */
	.macro  _dbg_stpcpy	 deststrptr, sourcestrptr
1:	ldrb	r0, [\sourcestrptr], #1
	strb	r0, [\deststrptr], #1
	teq	 r0, #0
	bne	 1b
	sub	 \deststrptr, \deststrptr, #1	/* Adjust Destination string pointer to point at NULL character */
	.endm

/* _dbg_outputMsgValidResponse
 *	Return Message with valid response ('+$')
 *	On exit:
 *	  R0: destroyed
 *	  R1: points to NULL character after the prefix
 *	  R2: destroyed
 */
	.macro  _dbg_outputMsgValidResponse
	ldr	 r1, =debug_OutMsgBuf
	ldr	 r2, =debug_ValidResponsePrefix
	_dbg_stpcpy	 r1, r2
	.endm


/* _dbg_outputMsgStatusOk
 *	Return Message with Ok ('+OK') status
 *	On exit:
 *	  R0: destroyed
 *	  R1: destroyed
 *	  R2: destroyed
 */
	.macro  _dbg_outputMsgStatusOk
	ldr	 r1, =debug_OutMsgBuf
	ldr	 r2, =debug_OkResponse
	_dbg_stpcpy	 r1, r2
	.endm

/* _dbg_outputMsgStatusErr
 *	Return Message with Error ('-ENN') status
 *	On entry:
 *	  R0: register containing error value (byte)
 *	On exit:
 *	  R0: destroyed
 *	  R1: destroyed
 *	  R2: destroyed
 *	  R3: destroyed
 */
	.macro  _dbg_outputMsgStatusErr
	mov	 r3, r0
	ldr	 r1, =debug_OutMsgBuf
	ldr	 r2, =debug_ErrorResponsePrefix
	_dbg_stpcpy	 r1, r2
	mov	 r0, r3
	bl	  byte2ascii	  /* R1 points to NULL character after the prefix */
	.endm

/* _dbg_outputMsgStatusSig
 *	Return Message with Signal ('+SNN') status
 *	On entry:
 *	  R0: register containing error value (byte)
 *	On exit:
 *	  R0: destroyed
 *	  R1: destroyed
 *	  R2: destroyed
 *	  R3: destroyed
 */
	.macro  _dbg_outputMsgStatusSig
	mov	 r3, r0
	ldr	 r1, =debug_OutMsgBuf
	ldr	 r2, =debug_SignalResponsePrefix
	_dbg_stpcpy	 r1, r2
	mov	 r0, r3
	bl	  byte2ascii	  /* R1 points to NULL character after the prefix */
	.endm

/* _index2dbgstackaddr
 *	Convert debugger stack index to Debugger Stack register address
 *
 *	On entry:
 *	  indexreg contains debugger stack index value (0-max entries)
 *	On exit:
 *	  indexreg: Breakpoint index (preserved)
 *	  addrreg: Debugger Stack Register Address
 */
	.macro  _index2dbgstackaddr  indexreg, addrreg
	ldr	 \addrreg, =__debugger_stack_bottom__
	add	 \addrreg, \addrreg, \indexreg, lsl #2	   /* Calculate Debugger Stack Register Address */
	.endm

/* _index2bkptindex_addr
 *	Convert Breakpoint index to breakpoing entry address
 *
 *	On entry:
 *	  indexreg contains breakpoint index value
 *	On exit:
 *	  indexreg: Breakpoint index (preserved)
 *	  addrreg: Breakpoint Entry Address
 */
	.macro _index2bkptindex_addr indexreg, addrreg
	ldr	 \addrreg, =__breakpoints_start__
	add	 \addrreg, \addrreg, \indexreg, lsl #3	   /* Calculate Breakpoint Entry Address */
	.endm

/* _dbg_getstate
 *	Get Debugger State
 *	On exit:
 *	  reg: Debugger State enum
 */
	.macro _dbg_getstate	reg
	ldr	 \reg, =debug_state
	ldr	 \reg, [\reg]
	.endm

/* _dbg_setstate
 *	Set Debugger State to given value
 *	On exit:
 *	  r0, r1: destroyed
 */
	.macro _dbg_setstate	state
	ldr	 r0, =\state
	ldr	 r1, =debug_state
	str	 r0, [r1]
	.endm

/* _dbg_getcurrbkpt_index
 *	Get current breakpoint index
 *	On exit:
 *	  reg: Breakpoint index
 */
	.macro _dbg_getcurrbkpt_index   reg
	ldr	 \reg, =debug_curr_breakpoint
	ldr	 \reg, [\reg]
	.endm

/* _dbg_setcurrbkpt_index
 *	Set current breakpoint index
 *	On exit:
 *	  r1: destroyed
 */
	.macro _dbg_setcurrbkpt_index  reg
	ldr	 r1, =debug_curr_breakpoint
	str	 \reg, [r1]
	.endm

/* _dbg_getabortedinstr_addr
 *	Get aborted instruction address
 *	On exit:
 *	  reg: aborted instruction address
 */
        .macro _dbg_getabortedinstr_addr  reg
	ldr	 \reg, =__debugger_stack_bottom__
	ldr	 \reg, [\reg]
	.endm

/* _dbg_setabortedinstr_addr
 *	Set aborted instruction address
 *	On exit:
 *	  r1: destroyed
 */
        .macro _dbg_setabortedinstr_addr  reg
        ldr   r1, =__debugger_stack_bottom__
        str   \reg, [r1]
        .endm


 /*@}*/

#endif /* __DEBUG_MACROS_H__ */
