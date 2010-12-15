/** @file debug_stub.S
 *  @brief ARM Breakpoint Debugger support routines
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

 /* GDB sparc-stub.c comments header included below to document GDB Server Remote protocol */
 /* This header has been modified to include additional commands not documented in the header stub */

 /****************************************************************************

		THIS SOFTWARE IS NOT COPYRIGHTED

   HP offers the following for use in the public domain.  HP makes no
   warranty with regard to the software or it's performance and the
   user accepts the software "AS IS" with all faults.

   HP DISCLAIMS ANY WARRANTIES, EXPRESS OR IMPLIED, WITH REGARD
   TO THIS SOFTWARE INCLUDING BUT NOT LIMITED TO THE WARRANTIES
   OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.

****************************************************************************/

/****************************************************************************
 *  Header: remcom.c,v 1.34 91/03/09 12:29:49 glenne Exp $
 *
 *  Module name: remcom.c $
 *  Revision: 1.34 $
 *  Date: 91/03/09 12:29:49 $
 *  Contributor:     Lake Stevens Instrument Division$
 *
 *  Description:     low level support for gdb debugger. $
 *
 *  Considerations:  only works on target hardware $
 *
 *  Written by:      Glenn Engel $
 *  ModuleState:     Experimental $
 *
 *  NOTES:           See Below $
 *
 *  Modified for SPARC by Stu Grossman, Cygnus Support.
 *
 *  This code has been extensively tested on the Fujitsu SPARClite demo board.
 *
 *  To enable debugger support, two things need to happen.  One, a
 *  call to set_debug_traps() is necessary in order to allow any breakpoints
 *  or error conditions to be properly intercepted and reported to gdb.
 *  Two, a breakpoint needs to be generated to begin communication.  This
 *  is most easily accomplished by a call to breakpoint().  Breakpoint()
 *  simulates a breakpoint by executing a trap #1.
 *
 *************
 *
 *    The following gdb commands are supported:
 *
 * command          function                               Return value
 *
 *    g             return the value of the CPU registers  hex data or ENN
 *    GrrrrRRRR..   set the value of the CPU registers     OK or ENN
 *					where register values are given as
 *					32-bit hex values in the sequence:
 *					User CPSR, R0, R1, ..., R15
 *	  px			get the value of one register (x)      hex data or ENN
 *	  Px=rrrr		set the value of one register (x) to   OK or ENN
 *					32-bit hex value rrrr.
 *					x = ['0','F'] for R0-R15, '!' for User CPSR
 *
 *    mAA..AA,LLLL  Read LLLL bytes at address AA..AA      hex data or ENN
 *    MAA..AA,LLLL: Write LLLL bytes at address AA.AA      OK or ENN
 *
 *    c             Resume at current address              SNN   ( signal NN)
 *    cAA..AA       Continue at address AA..AA             SNN
 *
 *    s             Step one instruction                   SNN
 *    sAA..AA       Step one instruction from AA..AA       SNN
 *
 *    k             kill
 *
 *    ?             What was the last sigval ?             SNN   (signal NN)
 *
 * All commands and responses are sent with a packet which includes a
 * checksum.  A packet consists of
 *
 * $<packet info>#<checksum>.
 *
 * where
 * <packet info> :: <characters representing the command or response>
 * <checksum>    :: < two hex digits computed as modulo 256 sum of <packetinfo>>
 *
 * When a packet is received, it is first acknowledged with either '+' or '-'.
 * '+' indicates a successful transfer.  '-' indicates a failed transfer.
 *
 * Example:
 *
 * Host:                  Reply:
 * $m0,10#2a               +$00010203040506070809101112131415#42
 *
 ****************************************************************************/
 /* Modified GDB Server Remote Protocol definition from GDB's sparc-stub.c Comment Header included above */


/* FIXME: What about setting/clearing Breakpoints? */

#define __ASSEMBLY__
#include "debug_stub.h"
#include "debug_macros.h"

.bss
.align 4
debug_state:
	.word	0x0
debug_curr_breakpoint:
	.word	0x0
debug_InMsgBuf:
	.space	MSGBUF_SIZE,0
debug_OutMsgBuf:
	.space	MSGBUF_SIZE,0

.data
.align 4
debug_ValidResponsePrefix:
	.byte	'+','$',0

debug_ErrorResponsePrefix:
	.byte	'-','$','E',0

debug_SignalResponsePrefix:
	.byte	'+','$','S',0

debug_OkResponse:
	.byte	'+','$','O','K',0

/* The CmdIndexTable and CmdJumpTable must be kept in sync */
debug_cmdIndexTable:
	.byte	'g','G','p','P','m','M','c','s','k','?',0

/* Command Handlers
 * On entry:
 *		R0: Input Message Parameter Buffer address pointer (points to contents after '$' and '<cmdchar>')
 */
debug_cmdJumpTable:
	.word	_dbg__procGetRegs					/* 'g' */
	.word	_dbg__procSetRegs					/* 'G' */
	.word	_dbg__procGetOneReg					/* 'p' */
	.word	_dbg__procSetOneReg					/* 'P' */
	.word	_dbg__nop							/* 'm' */
	.word	_dbg__nop							/* 'M' */
	.word	_dbg__nop							/* 'c' */
	.word	_dbg__nop							/* 's' */
	.word	_dbg__nop							/* 'k' */
	.word	_dbg__nop							/* '?' */
	.word	0

/*
 * To determine the next instruction to execute, we need to check current (breakpointed) instruction
 * and determine whether it will be executed or not. This necessitates a mini instruction decoder
 * that can check the type of instruction, as well as if it'll affect the PC.
 * The instruction decoder used here is table based. Each entry in the table consists of:
 *		Instruction Identifier (IID), Instruction Bitmask (IBM), Instruction Handler Address (IHA)
 * Null entries are placed at the end of the table.
 *
 * This allows for a flexible approach to handling instructions that we're interested in, at the expense
 * of memory usage.
 *
 * For ARM, the IID & IBM are both 4 bytes, whereas the Thumb IID & IBM are 2 bytes.
 * The IHA is always 4 bytes.
 */

/* ARM Instruction Decode Table
 *	.word IID, IBM, IHA (12 bytes)
 */

debug_armDecodeTable:
	.word	0x0000f000, 0x0c00f000, _arm_data_instr_handler	/* Data Processing instr with Rd = R15 */
	.word	0x012fff10, 0x0ffffff0, _arm_bx_blx_handler		/* BX or BLX */
	.word	0x0410f000, 0x0410f000, _arm_ldr_pc_handler		/* LDR with Rd = PC */
/*	.word	0x06000010, 0x0e000010, _arm_undef_handler	*/	/* Undefined instr: shouldn't occur, as it would've been trapped already. See _dbg_next_instruction_addr */
	.word	0x08108000, 0x0e108000, _arm_ldm_pc_handler		/* LDM {pc} */
	.word	0x0a000000, 0x0e000000, _arm_b_bl_handler		/* B or BL. Note v4t does not have BLX instr */
	.word	0x0c000000, 0x0c000000, _arm_coproc_swi_handler	/* Coprocessor instr or SWI */
	.word	0x0,0x0,0x0										/* Null Entry */

/* Thumb Instruction Decode Table
 * 	.hword IID, IBM
 * 	.word IHA (8 bytes)
 */

debug_thumbDecodeTable:
	.hword	0x4700, 0xff07
	.word	_thumb_bx_blx_handler				/* BX or BLX. Note: b7 (H1) is not matched in the mask */
	.hword	0xbd00, 0xff00
	.word	_thumb_poppc_handler				/* PUSH/POP, specifically POP {Rlist,PC} */
	.hword	0xd000, 0xf000
	.word	_thumb_bcond_swi_handler			/* B<cond> or SWI */
	.hword	0xe000, 0xf800
	.word	_thumb_b_handler					/* B */
	.hword	0xf000, 0xf000
	.word	_thumb_long_b_handler				/* Long BL or BLX (4 bytes) Note: b11 (H) indicates 1st or 2nd instr */
	.hword	0x0,0x0
	.word	0x0									/* Null Entry */

/* ARM Condition Code Mapping Table
 * Converts Instruction encoding to SPSR Flags.
 * b31 b30 b29 b28
 *  N   Z   C   V
 * Indexed according to Instruction Encoding order (pg 30, Table 6, ATMEL ARM7TDMI Data Sheet)
 * Condition Code stored in MSN(set), LSN(clr) order
 * Note1: 0x00 = AL. NV is deprecated, treat as AL
 * Note2: 0xFF indicates that the condition checks needs to be handled separately (complex checks)
 *
 *		EQ: Z set
 *		NE: Z clr
 *		HS/CS: C set
 *		LO/CC: C clr
 *		MI: N set
 *		PL: N clr
 *		VS: V set
 *		VC: V clr
 *		HI: C set AND Z clr
 *		LS: C clr AND Z set
 */


debug_armCondCodeTable:
			/* EQ,   NE, HS/CS, LO/CC,   MI,   PL,   VS,   VC,   HI,   LS,   GE,   LT,   GT,   LE,   AL,   NV */
	.byte	 0x40, 0x04,  0x20,  0x02, 0x80, 0x08, 0x10, 0x01, 0x24, 0x42, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00

/* ARM Complex Condition Code Mapping Table
 * Converts Instruction encoding to SPSR Flags.
 * b31 b30 b29 b28
 *  N   Z   C   V
 * Indexed according to Instruction Encoding order (pg 30, Table 6, ATMEL ARM7TDMI Data Sheet)
 * for GE, LT, GT and LE instructions only
 * Condition Code stored in the following order:
 *	 b7  b6  b5  b4   b3     b2   b1    b0
 *	  -   -   - ANDOR  -  Z set  AND  N==V		(bit set = 1)
 *	  -   -   - ANDOR  -  Z clr   OR  N!=V		(bit clr = 0)
 *
 *		GE: N == V
 *		LT: N != V
 *		GT: Z clr AND (N == V)
 *		LE: Z set OR (N != V)
 */

#define COMPLEX_CONDCODE_START	   0x0A
#define COMPLEX_CONDCODE_NEQV_MASK 0x01
#define COMPLEX_CONDCODE_AND_MASK  0x02
#define COMPLEX_CONDCODE_ZSET_MASK 0x04
#define COMPLEX_CONDCODE_ANDOR_MASK 0x10

#define COMPLEX_CONDCODE_NFLAG		0x08
#define COMPLEX_CONDCODE_ZFLAG		0x04
#define COMPLEX_CONDCODE_CFLAG		0x02
#define COMPLEX_CONDCODE_VFLAG		0x01


debug_armComplexCCTable:
			/* GE,   LT,   GT,   LE */
	.byte	 0x01, 0x00, 0x15, 0x12

.code 32
.text
.align 	4
	.extern __breakpoints_num__
	.extern dbg__hasDebugMsg			/* Check for message from the communications link */
	.extern dbg__getDebugMsg			/* Read a message from the communications link */
	.extern	dbg__putDebugMsg			/* Write a message to the communications link */


/* The Debugger Interface can handle a total of (n-1) Breakpoint States and 1 Single Stepping State,
 * where n is a power of 2. The value of n is given by __breakpoints_num__ defined in the linker file.
 *
 * In addition, a Debugger Stack contains the User Mode Register Stack Frame + SPSR + Bkpt Instr Addr.
 * These are currently stored in the .stack area in RAM, so there is no fixed address
 * location that is used for this purpose.
 *
 * The Breakpoint feature assumes that the program is executed in RAM. It is not possible
 * to set dynamic breakpoints for programs executed from Flash in the AT91SAM7S which lacks
 * instruction breakpointing support in hardware without using JTAG. The only type of breakpoints
 * that can be supported in Flash based programs are Static (predefined) breakpoints inserted into
 * the code.
 *
 * Each Breakpoint State i is a struct comprising the Breakpoint Address + Memory Contents
 * stored in 8 bytes as:
 *    [High Memory Address]
 *		ADDR [i*8+4]: Memory Contents		(32 bits)
 *		ADDR [i*8]:   Breakpoint Address	(31 bits, b0 = THUMB flag [not implemented yet])
 *	  [Low Memory Address]
 *
 * A Non-zero Breakpoint Address means that the breakpoint is active, whereas the memory contents
 * contains the instruction which resided at that address initially (now replaced by a BKPT <index>
 * instruction).
 * Note: Currently it is not possible to resume execution of a program with breakpoints enabled
 * after a RESET, since the RESET will clear all contents of the stack, destroying the instruction
 * contained in a given breakpoint.
 * Fortunately the NXT will also need to reload the program into RAM so this is not expected to be
 * an issue.
 *
 * The Memory Map for the Debugger State is as follows:
 *
 *	[High Memory Address]			__breakpoints_end__
 *		Breakpoint 07 State
 *		Breakpoint 06 State
 *			...
 *		Breakpoint 02 State
 *		Breakpoint 01 State
 *		Single Step   State			__debugger_stack__ / __breakpoints_start__
 *		User Mode R15
 *		User Mode R14
 *			...
 *		User Mode R02
 *		User Mode R01
 *		User Mode R00
 *		User Mode CPSR (UNDEF SPSR)
 *		Bkpt Instr Addr 			__debugger_stack_bottom__
 *  [Low Memory Address]
 *
 *	Each Breakpoint State will initially be zeroed.
 *
 */

/****************************************************************************
 *
 * GDB Debugger Init and Breakpoint Handler Routines
 *
 ****************************************************************************/

 	.global dbg__bkpt_init
/* dbg__bkpt_init
 * 		GDB set_debug_traps() routine
 */
dbg__bkpt_init:
	stmfd	sp!, {lr}
	bl		_dbg__clear_breakpoints
	mov		r0, #0
	ldr		r1, =debug_curr_breakpoint
	str		r0, [r1]
	ldr		r1, =debug_InMsgBuf
	strb	r0, [r1]
	ldr		r1, =debug_OutMsgBuf
	strb	r0, [r1]

/* FIXME: Initialize other stuff here */
	_dbg_setstate DBG_INIT
	ldmfd	sp!, {pc}


/* _dbg__flush_icache
 *		Flush the Instruction cache
 *		Defined by GDB Stub, but not needed for ARMv4T architecture
 */
_dbg__flush_icache:
		/* nop */
		bx	lr


	.global	dbg__thumb_bkpt_handler
/* dbg__thumb_bkpt_handler
 * 		GDB handle_exception() routine (Thumb Mode)
 */
dbg__thumb_bkpt_handler:
/* On entry, r0 contains breakpoint index value */
	mov	r4, #BKPT16_AUTO_BKPT
	and	r4, r0, #BKPT16_AUTO_BKPT	/* keep AUTO flag value in r4 */
	bic	r0, r0, #BKPT16_AUTO_BKPT	/* mask out AUTO flag */
	_dbg_setcurrbkpt_index r0		/* keep current breakpoint index in memory */
	ldr	r1, =BKPT16_MANUAL_BKPT
	teq	r0, r1
	beq	_process_manual_breakpoint_thumb
	ldr	r1, =__breakpoints_num__
	cmp	r0, r1					/* Sanity check that index is in range */
	bhs	dbg__bkpt_offset_outofrange
/* Valid index value found */
	teq	r4, #0					/* Check if AUTO flag set */
	bne	_process_auto_breakpoint
/* else */
	_dbg_setstate DBG_NORMAL_BKPT_THUMB
	b	_process_normal_breakpoint

	.global	dbg__arm_bkpt_handler
/* dbg__arm_bkpt_handler
 * 		GDB handle_exception() routine (ARM Mode)
 */
dbg__arm_bkpt_handler:
/* On entry, r0 contains breakpoint index value */
	mov	r4, #BKPT32_AUTO_BKPT
	and	r4, r0, #BKPT32_AUTO_BKPT	/* keep AUTO flag value in r4 */
	bic	r0, r0, #BKPT32_AUTO_BKPT	/* mask out AUTO flag */
	_dbg_setcurrbkpt_index r0		/* keep current breakpoint index in memory */
	ldr	r1, =BKPT32_MANUAL_BKPT
	teq	r0, r1
	beq	_process_manual_breakpoint_arm
	ldr	r1, =__breakpoints_num__
	cmp	r0, r1					/* Sanity check that index is in range */
	bhs	dbg__bkpt_offset_outofrange
/* Valid index value found */
	teq	r4, #0					/* Check if AUTO flag set */
	bne	_process_auto_breakpoint
/* else */
	_dbg_setstate DBG_NORMAL_BKPT_ARM
/*	b	_process_normal_breakpoint */

_process_normal_breakpoint:
	bl	_dbg__restore_breakpoints
	bl	_dbg__restore_singlestep
	bl	_dbg__clear_singlestep
	bl	_dbg__flush_icache
	b	dbg__bkpt_waitCMD

_process_auto_breakpoint:
/* Load Auto BKPT for Breakpoint index given in r0 */
	_index2bkptindex_addr	r0, r1	/* Calculate Breakpoint Entry Address */
	ldm	r1, {r1, r2}				/* r1: Breakpoint Address, r2: Breakpoint Instruction */
	teq	r1, #0						/* Check that Breakpoint is active */
	beq	dbg__bkpt_inactive
	bl	_dbg__activate_one_breakpoint
	bl	_dbg__restore_singlestep
	bl	_dbg__clear_singlestep
	b	__dbg__resume_execution

_process_manual_breakpoint_thumb:
	_dbg_setstate DBG_MANUAL_BKPT_THUMB
	b	dbg__bkpt_waitCMD

_process_manual_breakpoint_arm:
	_dbg_setstate DBG_MANUAL_BKPT_ARM
/*	b	dbg__bkpt_waitCMD */

dbg__bkpt_inactive:
/*	b	dbg__bkpt_waitCMD */

dbg__bkpt_offset_outofrange:
/*	b	dbg__bkpt_waitCMD */

	.global	dbg__bkpt_waitCMD
/* dbg__bkpt_waitCMD
 *		GDB Stub Remote Command Handler
 */

/****************************************************************************
 *
 * GDB Server Command Processing Routines
 *
 ****************************************************************************/
dbg__bkpt_waitCMD:
1:	bl		dbg__hasDebugMsg				/* Check for messages */
	beq		1b								/* Busy wait */
	bl		dbg__getDebugMsg				/* Read new message from Debugger, message buffer addr in R0, NULL if error */
	teq		r0, #0
	moveq	r0, #MSG_ERRCHKSUM				/* Message invalid, checksum error? */
	beq		_dbg__cmdError					/* Send response to GDB server */
/* Message now has $<packet info>\0 */
	mov		r4, r0							/* Use R4 as Message Buffer pointer */
	ldrb	r0, [r4], #1					/* Look for '$' */
	teq		r0, #MSGBUF_STARTCHAR
	movne	r0, #MSG_ERRFORMAT				/* Message Format invalid (not '$') */
	bne		_dbg__cmdError					/* Shouldn't happen */
	ldrb	r0, [r4], #1					/* Look for command char */
	bl		_dbg__cmdChar2Index				/* Index in R0 */
	ldr		r1, =MSGBUF_CMDINDEX_OUTOFRANGE_VAL
	teq		r0, r1
	moveq	r0, #MSG_UNKNOWNCMD				/* Out of range, Command character not recognized */
	beq		_dbg__cmdError					/* Send response to GDB server */

_dbg__cmdExists:
	mov		r3, r0							/* put Command Handler Index in R3 */
	mov		r0, r4							/* R0 now contains Input Message Buffer Parameter Pointer (previously in R4) */
	_dbg_jumpTableHandler	debug_cmdJumpTable, r2, r3		/* Call Command Handler Routine, use R2 as jump address pointer */
	b dbg__bkpt_waitCMD

_dbg__cmdError:
	_dbg_outputMsgStatusErr
	bl		dbg__putDebugMsg				/* Send error response to the GDB server */
	b 		dbg__bkpt_waitCMD


/* _dbg__cmdChar2Index
 *		Convert Command Character to Jump Table Index
 *		On entry:
 *			r0: command character
 *		On exit:
 *			r0: jump table index (-1 for command not found)
 *			R1: destroyed
 *			R2: destroyed
 *			R3: destroyed
 */
_dbg__cmdChar2Index:
	mov		r1, r0							/* Copy command character to r1 */
	mov		r0, #0							/* Clear return value */
	ldr		r3, =debug_cmdIndexTable		/* Convert command to index using r3 as Index Lookup Address Pointer */
1:	ldrb	r2, [r3, r0]					/* Get table entry */
	teq		r2, #0
	moveq	r0, #MSGBUF_CMDINDEX_OUTOFRANGE_VAL	/* End of Index Table, Not found */
	beq		_exit_cmdIndexTable
	teq		r1, r2
	addne	r0, #1							/* Increment Index */
	bne		1b								/* No match, skip to next command char */
_exit_cmdIndexTable:
	bx		lr

/* __dbg__procCmdParamError
 *		Common subroutine exit stub to handle Command Parameter Error for Command Handlers
 *		DO NOT CALL THIS STUB DIRECTLY! It Assumes that the return address is in the stack.
 *
 */

__dbg__procCmdParamError:
	mov		r0, #MSG_UNKNOWNPARAM
	_dbg_outputMsgStatusErr
	bl		dbg__putDebugMsg				/* Send error response to the GDB server */
	ldmfd	sp!, {pc}



/* _dbg__procGetOneReg
 *		Get One Register Value Command Handler
 *		Valid register parameter is from '0' to 'F' for User Mode Registers R0-R15
 *		CPSR register parameer is '!'
 *		On entry:
 *			r0: parameter buffer pointer (contents after '$' and '<cmdchar>')
 *
 */
_dbg__procGetOneReg:
	stmfd	sp!, {lr}
	ldrb	r2, [r0, #1]					/* char after parameter value (Should be NULL character) */
	ldrb	r0, [r0]						/* Retrieve register index parameter to R0 */
	teq		r2, #0							/* Check for NULL */
	bne		__dbg__procCmdParamError		/* Unexpected input, report error */
	teq		r0, #MSGBUF_CPSRREG				/* Check for CPSR register indicator */
	moveq	r0, #DBGSTACK_USERCPSR_OFFSET	/* Put offset from User Registers (-1) into index, so that after adjustment it points to CPSR slot */
	beq		_dbg__procRegister				/* Handle User CPSR */
	bl		char2hex						/* Convert to Hex value (assume input is valid) */
	cmp		r0, #NIBBLE0					/* sanity check, (though it is not foolproof as input char in 0x0-0xF (ctrl-chars) will pass through) */
	bhi		__dbg__procCmdParamError		/* Non-hex char, report error */

_dbg__procRegister:
	mov		r3, r0							/* Keep register index safe */
	_dbg_outputMsgValidResponse				/* Setup R1 with address of output message buffer data pointer (after response prefix) */
	mov		r0, r3							/* Restore register index value */
	bl		_dbg_outputOneRegValue			/* update output buffer */
	bl		dbg__putDebugMsg				/* Send response to the GDB server */
	ldmfd	sp!, {pc}

/* _dbg_outputOneRegValue
 *		Given Register Index (-1: CPSR, 0-F: R0-R15), output hex char to buffer
 *		On entry:
 *			r0: register index (-1, 0-F)
 *			r1: output message buffer pointer
 *		On exit:
 *			r0: output message buffer pointer
 *			r1: updated (points to NULL character at end of Output Buffer)
 *			r2: destroyed
 */
_dbg_outputOneRegValue:
	stmfd	sp!, {lr}
	add		r2, r0, #DBGSTACK_USERREG_INDEX	/* Convert register index to Debug Stack index */
	_getdbgregisterfromindex r2, r0			/* Retrieve Register contents into R0 */
	ldr		r0, [r0]
	bl		word2ascii						/* Convert and put hex chars into Output Message Buffer */
	ldmfd	sp!, {pc}

/* _dbg__procGetRegs
 *		Get All Register Values Command Handler
 *		Output Buffer returns register values in the order: User CPSR, R0, R1, R2, ..., R15
 *		On entry:
 *			r0: parameter buffer pointer (contents after '$' and '<cmdchar>')
 */
_dbg__procGetRegs:
	stmfd	sp!, {lr}
	ldrb	r0, [r0]						/* Retrieve register index parameter to R0 */
	teq		r0, #0							/* Check for NULL */
	bne		__dbg__procCmdParamError		/* Unexpected input, report error */

	_dbg_outputMsgValidResponse				/* Setup R1 with address of output message buffer data pointer (after response prefix) */
	mov		r3, #DBGSTACK_USERCPSR_OFFSET	/* Output User CPSR Value first */
1:  mov		r0, r3
	bl		_dbg_outputOneRegValue			/* update output buffer */
	add		r3, r3, #1						/* increment index */
	cmp		r3, #0xF
	ble		1b								/* process all the registers */

	bl		dbg__putDebugMsg				/* Send response to the GDB server */
	ldmfd	sp!, {pc}


_dbg__procSetOneReg:
_dbg__procSetRegs:
	bx		lr

/* _dbg__nop
 *		NOP Command Handler (placeholder)
 *		On entry:
 *			r0: parameter buffer (contents after '$' and '<cmdchar>')
 */
_dbg__nop:
	stmfd	sp!, {lr}
	mov		r0, #MSG_ERRIMPL				/* Stub, not implemented yet */
	_dbg_outputMsgStatusErr
	bl		dbg__putDebugMsg				/* Send error response to the GDB server */
	ldmfd	sp!, {pc}


/* dbg__cmd_install_breakpoint
 *		Configure Breakpoint
 *		On entry:
 *			r0: index of breakpoint to install
 *			r1: instruction address to install
 */
dbg__cmd_install_breakpoint:
	bl _dbg__install_one_breakpoint		/*	r0: index, r1: instruction address */
	b dbg__bkpt_waitCMD

/* dbg__cmd_clear_breakpoint
 *		Clear Breakpoint
 *		On entry:
 *			r0: index of breakpoint to clear
 */
dbg__cmd_clear_breakpoint:
	_index2bkptindex_addr	r0, r0		/* Calculate Breakpoint Entry Address */
	bl	_dbg__clear_one_breakpoint
	b dbg__bkpt_waitCMD


/* dbg__cmd_run
 *		Continue execution of program
 */
dbg__cmd_run:
	bl	_dbg__activate_breakpoints
	b	__dbg__resume_execution

/* dbg__cmd_step
 *		Single Step execution of program
 */
dbg__cmd_step:
	bl	_dbg_next_instruction_addr					/* next instruction address returned in r1 */
	bl	_dbg__install_singlestep					/* Setup Single Step */
	bl	_dbg__activate_singlestep
	b	__dbg__resume_execution

/* dbg__cmd_cont
 *		Continue execution of program.
 *		If this is a Normal Breakpoint, then we need to install an Autobreakpoint at next instruction address
 *			and resume from current (Breakpoint) exception address
 *		Else (it is a Manual Breakpoint)
 *			We need to resume from the next instruction address
 */
dbg__cmd_cont:
/* FIXME: What happens if we call this when we did not stop at a Breakpoint previously? */
	_dbg_getstate	r0
	ldr	r1, =DBG_MANUAL_BKPT_ARM
	teq	r0, r1
	beq	__dbg_is_manual_breakpoint

	bl	_dbg_next_instruction_addr					/* next instruction address returned in r1 */
	bl	_dbg__install_singlestep					/* Setup Single Step, next instruction address returned in r1 */
	_dbg_getcurrbkpt_index r0							/* load current breakpoint index in memory */
	bl	_dbg__activate_autobreakpoint				/* pass next instruction address in r1 */
	b	__dbg__resume_execution

__dbg_is_manual_breakpoint:
	bl	_dbg_next_instruction_addr					/* Skip Manual Breakpoint Instruction(s) */
	bl	_dbg__activate_breakpoints
	b	__dbg__resume_execution

/****************************************************************************
// Selected Routines from the eCos arm_stub.c related to next instruction address
// determination in ARM processors.

//========================================================================
//
//      arm_stub.c
//
//      Helper functions for stub, generic to all ARM processors
//
//========================================================================
// ####ECOSGPLCOPYRIGHTBEGIN####
// -------------------------------------------
// This file is part of eCos, the Embedded Configurable Operating System.
// Copyright (C) 1998, 1999, 2000, 2001, 2002, 2003 Free Software Foundation, Inc.
//
// eCos is free software; you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free
// Software Foundation; either version 2 or (at your option) any later
// version.
//
// eCos is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// You should have received a copy of the GNU General Public License
// along with eCos; if not, write to the Free Software Foundation, Inc.,
// 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
//
// As a special exception, if other files instantiate templates or use
// macros or inline functions from this file, or you compile this file
// and link it with other works to produce a work based on this file,
// this file does not by itself cause the resulting work to be covered by
// the GNU General Public License. However the source code for this file
// must still be made available in accordance with section (3) of the GNU
// General Public License v2.
//
// This exception does not invalidate any other reasons why a work based
// on this file might be covered by the GNU General Public License.
// -------------------------------------------
// ####ECOSGPLCOPYRIGHTEND####
//========================================================================
//#####DESCRIPTIONBEGIN####
//
// Author(s):     Red Hat, gthomas
// Contributors:  Red Hat, gthomas, jskov
// Date:          1998-11-26
// Purpose:
// Description:   Helper functions for stub, generic to all ARM processors
// Usage:
//
//####DESCRIPTIONEND####
//
//========================================================================


static int
ins_will_execute(unsigned long ins)
{
    unsigned long psr = get_register(PS);  // condition codes
    int res = 0;
    switch ((ins & 0xF0000000) >> 28) {
    case 0x0: // EQ
        res = (psr & PS_Z) != 0;
        break;
    case 0x1: // NE
        res = (psr & PS_Z) == 0;
        break;
    case 0x2: // CS
        res = (psr & PS_C) != 0;
        break;
    case 0x3: // CC
        res = (psr & PS_C) == 0;
        break;
    case 0x4: // MI
        res = (psr & PS_N) != 0;
        break;
    case 0x5: // PL
        res = (psr & PS_N) == 0;
        break;
    case 0x6: // VS
        res = (psr & PS_V) != 0;
        break;
    case 0x7: // VC
        res = (psr & PS_V) == 0;
        break;
    case 0x8: // HI
        res = ((psr & PS_C) != 0) && ((psr & PS_Z) == 0);
        break;
    case 0x9: // LS
        res = ((psr & PS_C) == 0) || ((psr & PS_Z) != 0);
        break;
    case 0xA: // GE
        res = ((psr & (PS_N|PS_V)) == (PS_N|PS_V)) ||
            ((psr & (PS_N|PS_V)) == 0);
        break;
    case 0xB: // LT
        res = ((psr & (PS_N|PS_V)) == PS_N) ||
            ((psr & (PS_N|PS_V)) == PS_V);
        break;
    case 0xC: // GT
        res = ((psr & (PS_N|PS_V)) == (PS_N|PS_V)) ||
            ((psr & (PS_N|PS_V)) == 0);
        res = ((psr & PS_Z) == 0) && res;
        break;
    case 0xD: // LE
        res = ((psr & (PS_N|PS_V)) == PS_N) ||
            ((psr & (PS_N|PS_V)) == PS_V);
        res = ((psr & PS_Z) == PS_Z) || res;
        break;
    case 0xE: // AL
        res = TRUE;
        break;
    case 0xF: // NV
        if (((ins & 0x0E000000) >> 24) == 0xA)
	    res = TRUE;
	else
	    res = FALSE;
        break;
    }
    return res;
}

static unsigned long
RmShifted(int shift)
{
    unsigned long Rm = get_register(shift & 0x00F);
    int shift_count;
    if ((shift & 0x010) == 0) {
        shift_count = (shift & 0xF80) >> 7;
    } else {
        shift_count = get_register((shift & 0xF00) >> 8);
    }
    switch ((shift & 0x060) >> 5) {
    case 0x0: // Logical left
        Rm <<= shift_count;
        break;
    case 0x1: // Logical right
        Rm >>= shift_count;
        break;
    case 0x2: // Arithmetic right
        Rm = (unsigned long)((long)Rm >> shift_count);
        break;
    case 0x3: // Rotate right
        if (shift_count == 0) {
            // Special case, RORx
            Rm >>= 1;
            if (get_register(PS) & PS_C) Rm |= 0x80000000;
        } else {
            Rm = (Rm >> shift_count) | (Rm << (32-shift_count));
        }
        break;
    }
    return Rm;
}

// Decide the next instruction to be executed for a given instruction
static unsigned long *
target_ins(unsigned long *pc, unsigned long ins)
{
    unsigned long new_pc, offset, op2;
    unsigned long Rn;
    int i, reg_count, c;

    switch ((ins & 0x0C000000) >> 26) {
    case 0x0:
        // BX or BLX
        if ((ins & 0x0FFFFFD0) == 0x012FFF10) {
            new_pc = (unsigned long)get_register(ins & 0x0000000F);
            return ((unsigned long *)new_pc);
        }
        // Data processing
        new_pc = (unsigned long)(pc+1);
        if ((ins & 0x0000F000) == 0x0000F000) {
            // Destination register is PC
            if ((ins & 0x0FBF0000) != 0x010F0000) {
                Rn = (unsigned long)get_register((ins & 0x000F0000) >> 16);
                if ((ins & 0x000F0000) == 0x000F0000) Rn += 8;  // PC prefetch!
                if ((ins & 0x02000000) == 0) {
                    op2 = RmShifted(ins & 0x00000FFF);
                } else {
                    op2 = ins & 0x000000FF;
                    i = (ins & 0x00000F00) >> 8;  // Rotate count
                    op2 = (op2 >> (i*2)) | (op2 << (32-(i*2)));
                }
                switch ((ins & 0x01E00000) >> 21) {
                case 0x0: // AND
                    new_pc = Rn & op2;
                    break;
                case 0x1: // EOR
                    new_pc = Rn ^ op2;
                    break;
                case 0x2: // SUB
                    new_pc = Rn - op2;
                    break;
                case 0x3: // RSB
                    new_pc = op2 - Rn;
                    break;
                case 0x4: // ADD
                    new_pc = Rn + op2;
                    break;
                case 0x5: // ADC
                    c = (get_register(PS) & PS_C) != 0;
                    new_pc = Rn + op2 + c;
                    break;
                case 0x6: // SBC
                    c = (get_register(PS) & PS_C) != 0;
                    new_pc = Rn - op2 + c - 1;
                    break;
                case 0x7: // RSC
                    c = (get_register(PS) & PS_C) != 0;
                    new_pc = op2 - Rn +c - 1;
                    break;
                case 0x8: // TST
                case 0x9: // TEQ
                case 0xA: // CMP
                case 0xB: // CMN
                    break; // PC doesn't change
                case 0xC: // ORR
                    new_pc = Rn | op2;
                    break;
                case 0xD: // MOV
                    new_pc = op2;
                    break;
                case 0xE: // BIC
                    new_pc = Rn & ~op2;
                    break;
                case 0xF: // MVN
                    new_pc = ~op2;
                    break;
                }
            }
        }
        return ((unsigned long *)new_pc);
    case 0x1:
        if ((ins & 0x02000010) == 0x02000010) {
            // Undefined!
            return (pc+1);
        } else {
            if ((ins & 0x00100000) == 0) {
                // STR
                return (pc+1);
            } else {
                // LDR
                if ((ins & 0x0000F000) != 0x0000F000) {
                    // Rd not PC
                    return (pc+1);
                } else {
                    Rn = (unsigned long)get_register((ins & 0x000F0000) >> 16);
                    if ((ins & 0x000F0000) == 0x000F0000) Rn += 8;  // PC prefetch!
                    if (ins & 0x01000000) {
                        // Add/subtract offset before
                        if ((ins & 0x02000000) == 0) {
                            // Immediate offset
                            if (ins & 0x00800000) {
                                // Add offset
                                Rn += (ins & 0x00000FFF);
                            } else {
                                // Subtract offset
                                Rn -= (ins & 0x00000FFF);
                            }
                        } else {
                            // Offset is in a register
                            if (ins & 0x00800000) {
                                // Add offset
                                Rn += RmShifted(ins & 0x00000FFF);
                            } else {
                                // Subtract offset
                                Rn -= RmShifted(ins & 0x00000FFF);
                            }
                        }
                    }
                    return ((unsigned long *)*(unsigned long *)Rn);
                }
            }
        }
        return (pc+1);
    case 0x2:  // Branch, LDM/STM
        if ((ins & 0x02000000) == 0) {
            // LDM/STM
            if ((ins & 0x00100000) == 0) {
                // STM
                return (pc+1);
            } else {
                // LDM
                if ((ins & 0x00008000) == 0) {
                    // PC not in list
                    return (pc+1);
                } else {
                    Rn = (unsigned long)get_register((ins & 0x000F0000) >> 16);
                    if ((ins & 0x000F0000) == 0x000F0000) Rn += 8;  // PC prefetch!
                    offset = ins & 0x0000FFFF;
                    reg_count = 0;
                    for (i = 0;  i < 15;  i++) {
                        if (offset & (1<<i)) reg_count++;
                    }
                    if (ins & 0x00800000) {
                        // Add offset
                        Rn += reg_count*4;
                    } else {
                        // Subtract offset
                        Rn -= 4;
                    }
                    return ((unsigned long *)*(unsigned long *)Rn);
                }
            }
        } else {
            // Branch
            if (ins_will_execute(ins)) {
                offset = (ins & 0x00FFFFFF) << 2;
                if (ins & 0x00800000) offset |= 0xFC000000;  // sign extend
                new_pc = (unsigned long)(pc+2) + offset;
		// If its BLX, make new_pc a thumb address.
		if ((ins & 0xFE000000) == 0xFA000000) {
		    if ((ins & 0x01000000) == 0x01000000)
			new_pc |= 2;
		    new_pc = MAKE_THUMB_ADDR(new_pc);
		}
                return ((unsigned long *)new_pc);
            } else {
                // Falls through
                return (pc+1);
            }
        }
    case 0x3:  // Coprocessor & SWI
        if (((ins & 0x03000000) == 0x03000000) && ins_will_execute(ins)) {
           // SWI
           return (unsigned long *)(CYGNUM_HAL_VECTOR_SOFTWARE_INTERRUPT * 4);
        } else {
           return (pc+1);
        }
    default:
        // Never reached - but fixes compiler warning.
        return 0;
    }
}

// FIXME: target_ins also needs to check for CPSR/THUMB being set and
//        set the thumb bit accordingly.

static unsigned long
target_thumb_ins(unsigned long pc, unsigned short ins)
{
    unsigned long new_pc = MAKE_THUMB_ADDR(pc+2); // default is fall-through
                                        // to next thumb instruction
    unsigned long offset, arm_ins, sp;
    int i;

    switch ((ins & 0xf000) >> 12) {
    case 0x4:
        // Check for BX or BLX
        if ((ins & 0xff07) == 0x4700)
            new_pc = (unsigned long)get_register((ins & 0x00078) >> 3);
        break;
    case 0xb:
        // push/pop
        // Look for "pop {...,pc}"
        if ((ins & 0xf00) == 0xd00) {
            // find PC
            sp = (unsigned long)get_register(SP);

            for (offset = i = 0; i < 8; i++)
              if (ins & (1 << i))
                  offset += 4;

            new_pc = *(cyg_uint32 *)(sp + offset);

            if (!v5T_semantics())
                new_pc = MAKE_THUMB_ADDR(new_pc);
        }
        break;
    case 0xd:
        // Bcc | SWI
        // Use ARM function to check condition
        arm_ins = ((unsigned long)(ins & 0x0f00)) << 20;
        if ((arm_ins & 0xF0000000) == 0xF0000000) {
            // SWI
            new_pc = CYGNUM_HAL_VECTOR_SOFTWARE_INTERRUPT * 4;
        } else if (ins_will_execute(arm_ins)) {
            offset = (ins & 0x00FF) << 1;
            if (ins & 0x0080) offset |= 0xFFFFFE00;  // sign extend
            new_pc = MAKE_THUMB_ADDR((unsigned long)(pc+4) + offset);
        }
        break;
    case 0xe:
        // check for B
        if ((ins & 0x0800) == 0) {
            offset = (ins & 0x07FF) << 1;
            if (ins & 0x0400) offset |= 0xFFFFF800;  // sign extend
            new_pc = MAKE_THUMB_ADDR((unsigned long)(pc+4) + offset);
        }
        break;
    case 0xf:
        // BL/BLX (4byte instruction!)
        // First instruction (bit 11 == 0) holds top-part of offset
        if ((ins & 0x0800) == 0) {
	    offset = (ins & 0x07FF) << 12;
	    if (ins & 0x0400) offset |= 0xFF800000;  // sign extend
	    // Get second instruction
	    // Second instruction (bit 11 == 1) holds bottom-part of offset
	    ins = *(unsigned short*)(pc+2);
	    // Check for BL/BLX
	    if ((ins & 0xE800) == 0xE800) {
		offset |= (ins & 0x07ff) << 1;
		new_pc = (unsigned long)(pc+4) + offset;
		// If its BLX, force a full word alignment
		// Otherwise, its a thumb address.
		if (!(ins & 0x1000))
		    new_pc &= ~3;
		else
		    new_pc = MAKE_THUMB_ADDR(new_pc);
	    }
	}
        break;
    }

    return new_pc;
}

void __single_step (void)
{
    unsigned long pc = get_register(PC);
    unsigned long cpsr = get_register(PS);

    // Calculate address of next instruction to be executed
    if (cpsr & CPSR_THUMB_ENABLE) {
        // thumb
        ss_saved_pc = target_thumb_ins(pc, *(unsigned short*)pc);
    } else {
        // ARM
        unsigned long curins = *(unsigned long*)pc;
        if (ins_will_execute(curins)) {
            // Decode instruction to decide what the next PC will be
            ss_saved_pc = (unsigned long) target_ins((unsigned long*)pc,
                                                     curins);
        } else {
            // The current instruction will not execute (the conditions
            // don't hold)
            ss_saved_pc = pc+4;
        }
    }

    // Set breakpoint according to type
    if (IS_THUMB_ADDR(ss_saved_pc)) {
        // Thumb instruction
        unsigned long t_pc = UNMAKE_THUMB_ADDR(ss_saved_pc);
        ss_saved_thumb_instr = *(unsigned short*)t_pc;
        *(unsigned short*)t_pc = HAL_BREAKINST_THUMB;
    } else {
        // ARM instruction
        ss_saved_instr = *(unsigned long*)ss_saved_pc;
        *(unsigned long*)ss_saved_pc = HAL_BREAKINST_ARM;
    }
}

 ****************************************************************************/


/* _dbg_next_instruction_addr
 *		Determine the address of the next instruction to execute.
 *		On exit:
 *			R1: Instruction Address (31 bits, b0 = THUMB flag)
 *
 *	Here we make use of the Debugger Stack which contains the address of the aborted instruction that will be reexecuted
 *	when we resume the program.
 *
 *	If it is a Manual Breakpoint inserted into the code, then we will need to update the aborted instruction
 *	address to skip the current aborted instruction and resume execution at the next instruction address,
 *  and the next instruction address to be returned to the calling routine is the following instruction
 *  address instead.
 *
 *	We need to check the aborted instruction type, to see if it is a branch instruction, before we can determine
 *	the next instruction address (for inserting a Breakpoint).
 */
_dbg_next_instruction_addr:
/* We assume that any BKPT instructions in the code will be Manual Breakpoints,
 * i.e., the Debugger does not leave stray Single Step / Auto / Normal breakpoints in memory
 */

	mov		r2, #DBGSTACK_USERCPSR_INDEX				/* Retrieve User CPSR */
	_getdbgregisterfromindex r2, r0						/* Retrieve Register contents into R0 */
 	and		r4, r0, #CPSR_THUMB							/* store Thumb Mode status in R4 */
 	mov		r5, r0, lsr #28								/* store CPSR condition flags in R5[3:0] */

	_dbg_getabortedinstr_addr	r2						/* Retrieve aborted instruction address */
1:	teq		r4, #0										/* Check if it is ARM or Thumb instruction */
	ldrneh	r0, [r2]
	ldrne	r1, =(BKPT16_INSTR | BKPT16_MANUAL_BKPT)	/* check for Thumb Manual Breakpoint Instruction */
	ldreq	r0, [r2]
	ldreq	r1, =(BKPT32_INSTR | BKPT32_MANUAL_BKPT)	/* check for ARM Manual Breakpoint Instruction */
	teq		r0, r1
	bne		2f											/* Not Manual breakpoint */
	teq		r4, #0										/* Check if it is ARM or Thumb instruction */
	addne	r2, r2, #2									/* Is Manual Breakpoint, Skip to next Thumb instruction */
	addeq	r2, r2, #4									/* Is Manual Breakpoint, Skip to next ARM instruction */
	_dbg_setabortedinstr_addr	r2						/* Update aborted instruction address */
	b		1b											/* To protect against a sequence of Manual Breakpoint Instructions */

/* Here, r0 contains the instruction which will be reexecuted when program resumes. We need to dissect it to see if
 * it is a branch instruction.
 * For ARM instructions, we also need to evaluate the current (breakpointed) instruction to see if it'll execute.
 * If not, then the next instruction is the instruction following the current instruction.
 */
2:
	/* Use R6 to store candidate next instruction address */
	teq		r4, #0										/* Check if it is ARM or Thumb instruction */
	beq		_next_instr_is_arm
_next_instr_is_thumb:
	add		r6, r2, #2									/* set next Thumb instruction address */
	/*_is_thumb_branch_instr	r0		*/					/* check if the current instruction is a branch instruction */
_next_instr_is_arm:
	add		r6, r2, #4									/* Is ARM, set next ARM instruction address */
@@@@@@@@@
	bx	lr

/* __dbg__resume_execution
 *		cleanup, resume execution of program.
 *		Restore User Mode Regsiters from Debugger Stack, and resume execution from aborted instruction
 */
__dbg__resume_execution:
@@@@@@
	bl	_dbg__flush_icache
	b __dbg__resume_execution

/****************************************************************************
 *
 * Instruction Decode Routines
 *
 ****************************************************************************/

/* _dbg_check_arm_condcode
 *		Check ARM conditional execution code
 *		On entry:
 *			R0: instruction to be executed
 *			R5[3:0]: CPSR condition codes
 *		On exit:
 *			R0: will_execute (boolean)
 */

_dbg_check_arm_condcode:
	stmfd	sp!, {r6,lr}							/* Use R6 as temporary will_execute variable */
	mov		r6, #TRUE
	mov		r0, r0, lsr #28							/* convert condition code to index (0-F) */
	ldr		r2, =debug_armCondCodeTable
	ldrb	r1, [r2, r0]							/* Get condition code mask */
/*
 * The following check is unnecessary as it is covered by the set/clear checking algorithm
 	teq		r1, #0
	beq		_dbg_check_arm_condcode_exit
*/
	teq		r1, #0xFF
	bne		_dbg_check_bits_set


/*
 * Complex Checks:
 *
 * will_execute = TRUE [default condition]
 * If (N == V) bit set
 *		will_execute = (N == V)
 * else
 *		will_execute = (N != V)
 *
 * If (ANDOR bit) set
 *		z_cond = ((Z XOR Z set) == 0)
 *		If (AND bit set)
 *			will_execute = will_execute && z_cond
 *		else
 *			will_execute = will_execute || z_cond
 */
_dbg_cond_complex_check:
	sub		r1, r0, #COMPLEX_CONDCODE_START			/* Convert complex condition code to new index (0-3) */
	ldr		r2, =debug_armComplexCCTable
	ldrb	r1, [r2, r1]							/* Get complex condition code bitmap */

	/* Use r2 to store N, r3 to store V */
	tst		r5, #COMPLEX_CONDCODE_NFLAG
	moveq	r2, #FALSE
	movne	r2, #TRUE								/* r2 = N flag */
	tst		r5, #COMPLEX_CONDCODE_VFLAG
	moveq	r3, #FALSE
	movne	r3, #TRUE								/* r3 = V flag */
	eor		r2, r2, r3								/* r2 = (N xor V): 0 if equal, 0xFF if not equal */
	tst		r1, #COMPLEX_CONDCODE_NEQV_MASK
	mvnne	r6, r1									/* If (N == V) bit set, will_execute (r6) = TRUE if (N == V) [r2 == 0] -> invert r2 */
	moveq	r6, r1									/* else (N == V) bit clr, will_execute (r6) = TRUE if (N != V) [r2 == 0xFF] */

	tst		r1, #COMPLEX_CONDCODE_ANDOR_MASK
	beq		_dbg_check_arm_condcode_exit			/* No additional checks needed, exit */

	/* Use r2 to store Z, r3 to store Z set */
	and		r2, r5, #COMPLEX_CONDCODE_ZFLAG			/* r2 = Z flag */
	and		r3, r1, #COMPLEX_CONDCODE_ZSET_MASK		/* r3 = Z set */
	eors	r2, r2, r3								/* r2 = (Z xor Z set): 0 if matched, non-zero if not matched */
	moveq	r2, #TRUE
	movne	r2, #FALSE								/* r2 (z_cond): TRUE if matched, FALSE if not matched */

	tst		r1, #COMPLEX_CONDCODE_AND_MASK
	andne	r6, r6, r2								/* If AND bit set, will_execute = will_execute && z_cond */
	orreq	r6, r6, r2								/* else, will_execute = will_execute || z_cond */
	b		_dbg_check_arm_condcode_exit


/*
 * Simple Checks:
 *
 * will_execute = TRUE [default condition, equivalent to 0x00 (AL) ]
 * If (SetBitMask is Non-Zero)
 *		will_execute = ((cond_code & SetBitMask) == SetBitMask)
 * If will_execute && (ClearBitMask is Non-Zero)
 *		will_execute = will_execute && ((cond_code | ~ClearBitMask) == ~ClearBitMask)
 */

_dbg_check_bits_set:
	movs	r0, r1, lsr #4							/* R0: bits set */
	beq		_dbg_check_bits_clear
	and		r2, r5, r0								/* Check bits set IF bitmask non-zero */
	teq		r2, r0									/* ((cond_code & SetBitMask) == SetBitMask)? */
	movne	r6, #FALSE								/* No, so will_execute = FALSE */
	bne		_dbg_check_arm_condcode_exit

_dbg_check_bits_clear:
	ands	r1, r1, #NIBBLE0						/* R1: bits clear */
	beq		_dbg_check_arm_condcode_exit
	mvn		r1, r1									/* Invert Bitmask */
	orr		r2, r5, r1								/* Check bits clear IF bitmask non-zero */
	teq		r2, r1									/* ((cond_code | ~ClearBitMask) == ~ClearBitMask)? */
	movne	r6, #FALSE								/* No, so will_execute = FALSE */
	bne		_dbg_check_arm_condcode_exit


_dbg_check_arm_condcode_exit:
	mov		r0, r6									/* Update return value */
	ldmfd	sp!, {r6, pc}


_arm_data_instr_handler:	/* Data Processing instr with Rd = R15 */
_arm_bx_blx_handler:		/* BX or BLX */
_arm_ldr_pc_handler:		/* LDR with Rd = PC */
_arm_ldm_pc_handler:		/* LDM {pc} */
_arm_b_bl_handler:		/* B or BL. Note v4t does not have BLX instr */
_arm_coproc_swi_handler:	/* Coprocessor instr or SWI */
	bx	lr

_thumb_bx_blx_handler:				/* BX or BLX. Note: b7 (H1) is not matched in the mask */
_thumb_poppc_handler:				/* PUSH/POP, specifically POP {Rlist,PC} */
_thumb_bcond_swi_handler:			/* B<cond> or SWI */
_thumb_b_handler:					/* B */
_thumb_long_b_handler:				/* Long BL or BLX (4 bytes) Note: b11 (H) indicates 1st or 2nd instr */
	bx	lr


/****************************************************************************
 *
 * Breakpoint Manipulation Routines
 *
 ****************************************************************************/

/* _dbg__clear_singlestep
 *		Clear the Single Step Breakpoint
 */
_dbg__clear_singlestep:
	ldr		r0, =__breakpoints_start__	/* Single Step Breakpoint is at the beginning of the Breakpoint State Struct */
/*	b		_dbg__clear_one_breakpoint */

/* _dbg__clear_one_breakpoint
 *		On entry, R0 contains the Breakpoint State slot address to be cleared
 *
 */
_dbg__clear_one_breakpoint:
	mov		r1, #0
	mov		r2, #0
	stmea	r0!, {r1, r2}		/* clear Breakpoint state */
	bx		lr

/* _dbg__clear_breakpoints
 *		Routine iterates through the array of breakpoints (incl single step breakpoint) and clears the breakpoint
 */
_dbg__clear_breakpoints:
	stmfd	sp!, {lr}
	ldr		r0, =__breakpoints_start__	/* Single Step Breakpoint is at the beginning of the Breakpoint State Struct */
	ldr		r3, =__breakpoints_end__		/* start from top of the table */
3:	bl		_dbg__clear_one_breakpoint
	cmp		r0, r3
	blo		3b
	ldmfd	sp!, {pc}

/* _dbg__install_singlestep
 *		Install the Single Step Breakpoint
 *		On entry:
 *			R1: Instruction Address (31 bits, b0 = THUMB flag)
 */
_dbg__install_singlestep:
	mov		r0, #0
/*	b		_dbg__install_one_breakpoint */

/* _dbg__install_one_breakpoint
 *		Install breakpoint entry into Breakpoint State Table
 *		On entry:
 *			R0: Breakpoint index (assumed valid)
 *			R1: Instruction Address (31 bits, b0 = THUMB flag)
 *
 *		On exit:
 *			R2: Breakpoint Instruction
 *			R3: Breakpoint Entry address
 */
_dbg__install_one_breakpoint:
/* Check for Thumb bit */
	tst		r1, #BKPT_STATE_THUMB_FLAG	/* 1: Thumb instruction */
/* Assume that the address entry is valid, otherwise we should sanitize it (mask out b1) */
	ldreq	r2, [r1]					/* if 0: load ARM instruction from address location */
	ldrneh	r2, [r1]					/* else load Thumb instruction */
	_index2bkptindex_addr	r0, r3		/* Calculate Breakpoint Entry Address */
	stm		r3, {r1, r2}
	bx		lr


/* _dbg__restore_singlestep
 *		Restores the contents of the single step breakpoint to memory
 */
_dbg__restore_singlestep:
	mov		r0, #0						/* single step breakpoint index */
	_index2bkptindex_addr	r0, r1		/* Calculate Single Step Breakpoint Entry Address */
	ldm		r1, {r1, r2}				/* r1: Breakpoint Address, r2: Breakpoint Instruction */
	teq		r1, #0
	bxeq	lr							/* Exit if not active */
/*	b		_dbg__restore_one_breakpoint */

/* _dbg__restore_one_breakpoint
 *		Restores the contents to memory for one breakpoint
 *		On entry:
 *			R0: Breakpoint index (assumed valid) [not used -- can be used for validating BKPT]
 *			R1: Breakpoint Address (assumed valid)
 *			R2: Breakpoint Instruction (assumed valid)
 */
_dbg__restore_one_breakpoint:
/* Check for Thumb bit */
	tst		r1, #BKPT_STATE_THUMB_FLAG	/* 1: Thumb instruction */
/* Assume that the address entry is valid, otherwise we should sanitize it (mask out b1) */
	streq	r2, [r1]					/* if 0: restore ARM instruction to address location */
	bicne	r1, #BKPT_STATE_THUMB_FLAG	/* else, clear Thumb Flag */
	strneh	r2, [r1]					/* store Thumb instruction */
	bx		lr

/* _dbg__restore_breakpoints
 *		Routine iterates through the array of breakpoints (incl single step breakpoint) and restores the contents to memory
 *		Only Active breakpoints (i.e., Non-zero Address) are processed.
 */
_dbg__restore_breakpoints:
	stmfd	sp!, {lr}
	ldr		r5, =_dbg__restore_one_breakpoint
	b		__dbg__iterate_breakpoint_array

/* _dbg__activate_singlestep
 *		Activate the single step breakpoint to memory
 */
_dbg__activate_singlestep:
	mov		r0, #0						/* single step breakpoint index */
	_index2bkptindex_addr	r0, r1		/* Calculate Single Step Breakpoint Entry Address */
	ldm		r1, {r1, r2}				/* r1: Breakpoint Address, r2: Breakpoint Instruction */
	teq		r1, #0
	bxeq	lr							/* Exit if not active */
/*	b		_dbg__activate_one_breakpoint */

/* _dbg__activate_one_breakpoint
 *		Activate one breakpoint to memory
 *		On entry:
 *			R0: Breakpoint index (assumed valid)
 *			R1: Breakpoint Address (assumed valid)
 *			R2: Breakpoint Instruction (assumed valid)
 */
_dbg__activate_one_breakpoint:
/* Check for Thumb bit */
	tst		r1, #BKPT_STATE_THUMB_FLAG	/* 1: Thumb instruction */
	bne		_nx_is_thumb_bp
_nx_is_arm_bp:
/* Assume that the address entry is valid, otherwise we should sanitize it (mask out b1) */
	ldr		r3, [r1]					/* if 0: load ARM instruction from address location */
	teq		r2, r3							/* check that the two instructions are identical */
	bne		_dbg__breakpoint_invalid_arm
	ldr		r2, =BKPT32_INSTR				/* ARM BKPT instruction */
	and		r2, r2, r0						/* Merge Breakpoint index */
	str		r2, [r1]						/* Store it into memory location */
_dbg__breakpoint_invalid_arm:
	bx		lr
_nx_is_thumb_bp:
	bic		r1, #BKPT_STATE_THUMB_FLAG	/* else, clear Thumb Flag */
	ldrh	r3, [r1]						/* load Thumb instruction from address location */
	teq		r2, r3							/* check that the two instructions are identical */
	bne		_dbg__breakpoint_invalid_thumb
	ldr		r2, =BKPT16_INSTR				/* Thumb BKPT instruction */
	and		r2, r2, r0						/* Merge Breakpoint index */
	strh	r2, [r1]						/* Store it into memory location */
_dbg__breakpoint_invalid_thumb:
	bx		lr

/* _dbg__activate_breakpoints
 *		Routine iterates through the array of breakpoints (incl single step breakpoint) and activates them
 *		Only Active breakpoints (i.e., Non-zero Address) are processed.
 */
_dbg__activate_breakpoints:
	stmfd	sp!, {lr}
	ldr		r5, =_dbg__activate_one_breakpoint
	b		__dbg__iterate_breakpoint_array


/* __dbg__iterate_breakpoint_array
 *		Common routine iterates through the array of breakpoints (incl single step breakpoint)
 *		and executes routine given in R5, passing:
 *			R0: Breakpoint index
 *			R1: Breakpoint Address
 *			R2: Breakpoint Instruction
 *
 *		On Entry:
 *			Assumes that lr has been push to stack (routine can't be called directly)
 *
 *		Only Active breakpoints (i.e., Non-zero Address entries) are processed.
 */
__dbg__iterate_breakpoint_array:
	ldr		r4, =__breakpoints_end__		/* start from top of the table (Assume __breakpoints_end__ > __breakpoints_start__) */
	ldr		r3, =__breakpoints_start__		/* end address check */
	ldr		r0, =__breakpoints_num__		/* Number of Breakpoints (incl Single Step) (Assume Non-Zero) */
4:	sub		r0, r0, #1						/* Decrement breakpoint index in r0 */
	ldmea	r4!, {r1, r2}					/* r1: Breakpoint Address, r2: Breakpoint Instruction */
	teq		r1, #0							/* Is it active? */
	movne	lr, pc
	bxne	r5								/* active entry */
	cmp		r4, r3
	bhi		4b								/* if (pointer > start of Breakpoint Table address), get next slot */
	ldmfd	sp!, {pc}

/* _dbg__activate_autobreakpoint
 *		Activate all other breakpoints except current breakpoint, activate auto breakpoint in next instr slot
 *		On entry:
 *			R0: Current Breakpoint index (assumed valid)
 *			R1: Next Instruction address (for AUTO Breakpoint) [Not used, assume Single Step Breakpoint already has correct info]
 */
_dbg__activate_autobreakpoint:
	stmfd	sp!, {lr}
	mov		r5, r0							/* Keep Current Breakpoint Index in r5 */
	ldr		r4, =__breakpoints_end__		/* start from top of the table */
	ldr		r0, =__breakpoints_num__		/* Number of Breakpoints (incl Single Step) (Assume Non-Zero) */
4:	subs	r0, r0, #1						/* Decrement breakpoint index in r0 */
	ldmea	r4!, {r1, r2}					/* r1: Breakpoint Address, r2: Breakpoint Instruction */
	bls		5f								/* Flag set by subs instruction previously. Reached Single Step, go activate AUTO Breakpoint */
	teq		r0, r5							/* Is it the Current Breakpoint? */
	beq		4b								/* Yes, so skip */
	teq		r1, #0							/* Is it active? */
	blne	_dbg__activate_one_breakpoint	/* active entry */
	b		4b								/* Next iteration */
5:
/* Here, r1: Breakpoint Address, r2: Breakpoint Instruction */
	tst		r1, #BKPT_STATE_THUMB_FLAG		/* Check for Thumb bit -- 1: Thumb instruction */
	orreq	r0, r5, #BKPT32_AUTO_BKPT		/* Is ARM Instruction, merge AUTO flag with Current Breakpoint Index */
	orrne	r0, r5, #BKPT16_AUTO_BKPT		/* Is Thumb Instruction, merge AUTO flag with Current Breakpoint Index */
	bl		_dbg__activate_one_breakpoint	/* Activate AUTO Breakpoint */
	ldmfd	sp!, {pc}

