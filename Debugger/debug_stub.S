/** @file debug_stub.S
 *  @brief ARM Breakpoint Debugger support routines
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
 *					User R0, R1, ..., R15, CPSR
 *	  px			get the value of one register (x)      hex data or ENN
 *	  Px=rrrr		set the value of one register (x) to   OK or ENN
 *					32-bit hex value rrrr.
 *					x = ['0','F'] for R0-R15,
 *                  '18' for FPSCR (dummy), '19' for User CPSR
 *
 *    mAA..AA,LLLL  Read LLLL bytes at address AA..AA      hex data or ENN
 *    MAA..AA,LLLL:bb..bb
 *                  Write LLLL bytes at address AA.AA      OK or ENN
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
 *    zt,AA..AA,k	Remove a Breakpoint of type t at addr  OK or ENN
 *                  AA..AA of kind k
 *    Zt,AA..AA,k	Insert a Breakpoint of type t at addr  OK or ENN
 *                  AA..AA of kind k
 *                  t 0: memory breakpoint
 *                    1: hardware breakpoint
 *                    2: write watchpoint
 *                    3: read watchpoint
 *                    4: access watchpoint
 *                  k: 2 (16-bit Thumb), 3 (32-bit Thumb2)
 *                       or 4 (32-bit ARM) for t=[0,1]
 *                     Num. bytes to watch for t=[2,4]
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
 /* Modified GDB Server Remote Protocol definition from GDB's sparc-stub.c Comment Header included above
  * Additional commands from GDB Reference Appendix D.2
  *
  * Note: ARMDEBUG can only implement Memory Breakpoints t=0. Hardware breakpoints requires a JTAG debugger.
  *       Currently, watchpoints are not implemented as they require hardware support as well (need verification).
  *
  * GDB requires command parameters to be specified as Big Endian values.
  * However, the read/write register command expect the register contents to be specified in target byte order.
  * The default target byte order is Little Endian for the AT91SAM7xxx processor in the NXT.
  * If Big Endian target byte order is required, the __BIG_ENDIAN__ preprocessor label should be defined.
  */

/* FIXME: The Hex value arguments passed by GDB does not have fixed lengths! Although the standard says
 *        there should be x digits, it does not follow this requirement. e.g., register index.
 */


#define __ASSEMBLY__
#include "debug_stub.h"
#include "debug_internals.h"
#include "debug_macros.h"

/* Macro definitions */

/* _check_msgseparator
 *      Look for separator ','
 *  On entry:
 *    bufferptr: points to the parameter buffer [can't be R0]
 *  On exit:
 *    R0: destroyed
 *    bufferptr: points to the next character location in the parameter buffer
 *    Flags: Updated
 */

    .macro  _check_msgseparator bufferptr
    ldrb    r0, [\bufferptr], #1                /* get separator */
    cmp     r0, #MSGBUF_SEPCHAR
    .endm

/* _check_msgargument
 *      Look for argument ':'
 *  On entry:
 *    bufferptr: points to the parameter buffer [can't be R0]
 *  On exit:
 *    R0: destroyed
 *    bufferptr: points to the next character location in the parameter buffer
 *    Flags: Updated
 */

    .macro  _check_msgargument bufferptr
    ldrb    r0, [\bufferptr], #1                /* get separator */
    cmp     r0, #MSGBUF_ARGCHAR
    .endm

/* _check_msgassignment
 *      Look for assignment '='
 *  On entry:
 *    bufferptr: points to the parameter buffer [can't be R0]
 *  On exit:
 *    R0: destroyed
 *    bufferptr: points to the next character location in the parameter buffer
 *    Flags: Updated
 */

    .macro  _check_msgassignment bufferptr
    ldrb    r0, [\bufferptr], #1                /* get separator */
    cmp     r0, #MSGBUF_SETCHAR
    .endm

.bss
.align 4
debug_InMsgBuf:
	.space	MSGBUF_SIZE,0
debug_OutMsgBuf:
	.space	MSGBUF_SIZE,0

debug_state:
    .byte   0x0									/* dbg_state_t variable */
debug_mode:
    .byte   0x0                                 /* Boolean variable */
debug_bkpt_type:
    .byte   0x0                                 /* bkpt_type_t variable */
debug_curr_breakpoint:
    .byte   0x0

.data
.align 4
debug_RetransmitFlag:
	.byte	'-',0

debug_AckOnlyFlag:
	.byte	'+',0

debug_ValidResponsePrefix:
	.byte	'+','$',0

debug_ErrorResponsePrefix:
	.byte	'+','$','E',0

debug_SignalResponsePrefix:
	.byte	'+','$','S',0

debug_OkResponse:
	.byte	'+','$','O','K',0

/* The CmdIndexTable and CmdJumpTable must be kept in sync */
debug_cmdIndexTable:
	.byte	'g','G','p','P','m','M','c','s','k','z','Z','?','q','Q',0

/* Command Handlers
 * On entry:
 *		R0: Input Message Parameter Buffer address pointer (points to contents after '$' and '<cmdchar>')
 */
.align 4
debug_cmdJumpTable:
	.word	_dbg__cmd_GetAllRegs				/* 'g' */
	.word	_dbg__cmd_SetAllRegs	   			/* 'G' */
	.word	_dbg__cmd_GetOneReg				    /* 'p' */
	.word	_dbg__cmd_SetOneReg				    /* 'P' */
	.word	_dbg__cmd_ReadMem					/* 'm' */
	.word	_dbg__cmd_WriteMem					/* 'M' */
	.word	_dbg__cmd_Continue					/* 'c' */
	.word	_dbg__nop							/* 's' */
	.word	_dbg__nop							/* 'k' */
	.word	_dbg__cmd_RemoveBreakpoint			/* 'z' */
	.word	_dbg__cmd_InsertBreakpoint			/* 'Z' */
	.word	_dbg__cmd_Status					/* '?' */
	.word	_dbg__cmd_Query						/* 'q' */
	.word	_dbg__nop							/* 'Q' */
	.word	0

/* Rm Shifted Shift Type Jump Table
 * On entry:
 *      R0: Register Rm
 *      R1: Shift/Rotate Amount
 * On exit:
 *      R0: RmShifted result
 *
 */
debug_regShiftJumpTable:
    .word   _reg_lsl                            /* 00 */
    .word   _reg_lsr                            /* 01 */
    .word   _reg_asr                            /* 02 */
    .word   _reg_ror                            /* 03 */
    .word   _reg_rrx                            /* 04 */

/* Data Processing Instruction Jump Table
 * On entry:
 *      R0: Register Rn (Operand 1) value
 *      R1: Operand 2 value
 *      R2: Default Next Instruction Address
 * On exit:
 *      R0: Calculated result
 *      R1, R2, R3: Destroyed
 *
 */
debug_dataInstrJumpTable:
    .word   _opcode_and                         /* 00 */
    .word   _opcode_eor                         /* 01 */
    .word   _opcode_sub                         /* 02 */
    .word   _opcode_rsb                         /* 03 */
    .word   _opcode_add                         /* 04 */
    .word   _opcode_adc                         /* 05 */
    .word   _opcode_sbc                         /* 06 */
    .word   _opcode_rsc                         /* 07 */
    .word   _opcode_tst                         /* 08 */
    .word   _opcode_teq                         /* 09 */
    .word   _opcode_cmp                         /* 0A */
    .word   _opcode_cmn                         /* 0B */
    .word   _opcode_orr                         /* 0C */
    .word   _opcode_mov                         /* 0D */
    .word   _opcode_bic                         /* 0E */
    .word   _opcode_mvn                         /* 0F */


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
	.word	0x012fff10, 0x0ffffff0, _arm_bx_blx_handler		/* BX or BLX. Note v4t does not have BLX instr */
	.word	0x0410f000, 0x0410f000, _arm_ldr_pc_handler		/* LDR with Rd = PC */
/*	.word	0x06000010, 0x0e000010, _arm_undef_handler	*/	/* Undefined instr: shouldn't occur, as it would've been trapped already. See _dbg_following_instruction_addr */
	.word	0x08108000, 0x0e108000, _arm_ldm_pc_handler		/* LDM {pc} */
	.word	0x0a000000, 0x0e000000, _arm_b_bl_blx_handler	/* B, BL or BLX. Note v4t does not have BLX instr */
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
	.word	_thumb_long_bl_blx_handler			/* Long BL or BLX (4 bytes) Note: b11 (H) indicates 1st or 2nd instr */
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
	.extern dbg__sendAckOrNak			/* Send Ack or Nak to indicate success/failure of message receipt */
	.extern dbg__runloopTasks           /* Platform specific Run Loop processing */


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
 *		Previous Mode R15
 *		Previous Mode R14
 *		Previous Mode R13
 *			...
 *		User Mode R02
 *		User Mode R01
 *		User Mode R00
 *		Previous Mode CPSR (UNDEF SPSR)
 *		UNDEF Next Instr Addr 		__debugger_stack_bottom__
 *  [Low Memory Address]
 *
 *	Each Breakpoint State will initially be zeroed.
 *
 */
 /* FIXME: The Debugger Stack Frame is probably not 100% consistent with the order that
    GDB expects in the g/G messages. CSPR is probably located above R15 */

#ifndef __NXOS__
/****************************************************************************
 *
 * GDB Debugger Invocation Routine for NXT Firmware
 *
 ****************************************************************************/
    .code 16
    .align 2
    .global cCommHandleDebug
    .thumb_func
/* cCommHandleDebug
 * Switch Mode to Debugger.
 *      Used by NXT Firmware only
 *
 * UWORD cCommHandleDebug(UBYTE *pInBuf, UBYTE CmdBit, UWORD MsgLength);
 *
 * This routine is called from cCommInterprete either in normal operation mode (SVC)
 * or else when we're in debug mode (ABORT) which uses the cCommCtrl() routine to handle
 * I/O with the Host.
 *
 * On entry, the message is copied from the NXT buffer into our own buffers.
 *
 * If this is accessed from normal operation mode, we need to switch mode to
 * ABORT mode to handle the incoming message using a Manual Breakpoint instruction.
 * When DEBUG is exited, the execution resumes from the instruction following the Breakpoint.
 */
cCommHandleDebug:
/* Arg Registers are not preserved since this is invoked explicitly */
        push  {lr}                      /* store arg registers */
        bl    dbg__copyNxtDebugMsg  	/* setup Debugger Message Buffers, validate input, CPSR returned in R0 */
        _dbg_getmode r0             	/* Get Debug Mode */
        cmp   r0, #(TRUE & BYTE0)		/* Confine it to Byte size */

        /* If Debug Mode is TRUE, this means that we're already running the Debugger */
		beq	  _cCommHandleDebug_cont
        /* Else, we're in normal operation mode (SVC), or other mode (??!) and need to force a switch to Debug mode */
        dbg__bkpt_thumb
_cCommHandleDebug_cont:
        mov   r0, #0                   /* FIXME: Return Status */
        pop	  {r1}					   /* Can't Pop LR directly */
        bx    r1					   /* Safe code: actually we should be able to Pop PC since the caller is Thumb Mode */

        .ltorg
#endif

/****************************************************************************
 *
 * GDB Debugger Init and Breakpoint Handler Routines
 *
 ****************************************************************************/
    .code 32
    .align 4
 	.global dbg__bkpt_init
/* dbg__bkpt_init
 * 		GDB set_debug_traps() routine
 */
dbg__bkpt_init:
    push    {lr}
	bl		_dbg__clear_breakpoints
	mov		r2, #0
	ldr		r1, =debug_curr_breakpoint
	strb	r2, [r1]
	ldr		r0, =debug_InMsgBuf
	strb	r2, [r0]
	ldr		r1, =debug_OutMsgBuf
	strb	r2, [r1]
	bl		dbg__comm_init				/* Pass R0: Rx Buffer, R1: Tx Buffer to comm submodule */

/* FIXME: Initialize other stuff here */
	_dbg_setstate DBG_INIT
    _dbg_setmode FALSE                  /* Debug Mode = False */
    pop     {lr}
    bx      lr                          /* Must return via BX; may have been called from Thumb mode (NXT Firmware) */


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
	_dbg_set_bkpt_type DBG_NORMAL_BKPT_THUMB
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
	_dbg_set_bkpt_type DBG_NORMAL_BKPT_ARM
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
	_dbg_set_bkpt_type DBG_AUTO_BKPT
	b	_dbg__switch2undefmode

/* _dbg__switch2undefmode
 *      Common internal routine to return execution to user program
 */
_dbg__switch2undefmode_withAck:
	bl		__dbg__procAckOnly				/* send Ack to keep GDB server happy */
	bl      dbg__runloopTasks               /* Service run loop tasks */
_dbg__switch2undefmode:
    bl  	_dbg__flush_icache
    msr     cpsr_c, #(MODE_UND | CPSR_FIQ | CPSR_IRQ)         /* Configure Undef Mode */
    _dbg_setmode FALSE                  	/* Debug Mode = False */
    ldr     lr, =resume_execution
    mov     pc, lr                          /* Exit via UNDEF mode */

_process_manual_breakpoint_thumb:
	_dbg_set_bkpt_type DBG_MANUAL_BKPT_THUMB
	b	dbg__bkpt_waitCMD

_process_manual_breakpoint_arm:
	_dbg_set_bkpt_type DBG_MANUAL_BKPT_ARM
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
	/* We enter this code section when a Breakpoint Triggers */
    _dbg_setmode TRUE                       /* Debug Mode = True */
	_dbg_getstate r0
	cmp		r0, #DBG_CONFIGURED
	blo		dbg__bkpt_waitCMD_cont			/* Not configured yet, don't send Breakpoint Signal Response */
	bl		_dbg__cmd_Status				/* Send signal response to the GDB server */

dbg__bkpt_waitCMD_cont:
	bl      dbg__runloopTasks               /* Execute housekeeping tasks while in ABRT mode */
	bl		dbg__getDebugMsg				/* Read new message from Debugger, buflen in R0, 0 if none, -1 if error, msgbuf pointer in R1 */
	cmp		r0, #0
	beq     dbg__bkpt_waitCMD_cont          /* No message yet, do housekeeping tasks */
	bgt		_proc_command					/* valid message, process it */
	bl		__dbg__procChecksumError		/* Message invalid, checksum error? */
	b		dbg__bkpt_waitCMD_cont

_proc_command:
/* Message now has Ctrl-C or $<packet info>\0 */
    mov     r4, r1							/* Use R4 as buffer pointer */
	ldrb	r0, [r4], #1					/* Look for Ctrl-C or '$' */
	teq		r0, #MSGBUF_CTRLC
	bne		_dbg_check_gdb_command
	/* Ctrl-C detected, do nothing (wait for next command from GDB) */
	bl		__dbg__procAckOnly				/* send Ack */
	b		dbg__bkpt_waitCMD_cont

_dbg_check_gdb_command:
	teq		r0, #MSGBUF_STARTCHAR
	movne	r0, #MSG_ERRFORMAT				/* Message Format invalid (not '$') */
	bne		_dbg__cmdError					/* Shouldn't happen */
	ldrb	r0, [r4], #1					/* Look for command char */
	bl		_dbg__cmdChar2Index				/* Index in R0 */
	mov		r1, #CMDINDEX_OUTOFRANGE
	teq		r0, r1
	bne		_dbg__cmdExists					/* Found valid command, execute it */
_dbg_unknown_command:
	bl		_dbg__nop						/* Command character not recognized, send empty response to GDB server */
	b 		dbg__bkpt_waitCMD_cont

#if 0
	moveq	r0, #MSG_UNKNOWNCMD				/* Out of range, Command character not recognized */
	beq		_dbg__cmdError					/* Send response to GDB server */
#endif

_dbg__cmdExists:
	mov		r3, r0							/* put Command Handler Index in R3 */
	mov		r0, r4							/* R0 now contains Input Message Buffer Parameter Pointer (previously in R4) */
	_dbg_jumpTableHandler	debug_cmdJumpTable, r2, r3		/* Call Command Handler Routine, use R2 as jump address pointer */
	b 		dbg__bkpt_waitCMD_cont

_dbg__cmdError:
	_dbg_outputMsgStatusErr
	bl		dbg__putDebugMsg				/* Send error response to the GDB server */
	b 		dbg__bkpt_waitCMD_cont


/* __dbg__procAckOnly
 *		Send Ack to GDB due to Continue or Step
 *		On entry:
 *			None
 *		On exit:
 *			r0-r3: destroyed
 */
__dbg__procAckOnly:
	stmfd	sp!, {lr}
    _dbg_outputAckOnlyFlag
	b		_cont_sendAckOrNak				/* Acknowledge Continue or Step command from GDB server */

/* __dbg__procChecksumError
 *		Request Retransmission from GDB due to Checksum error
 *		On entry:
 *			None
 *		On exit:
 *			r0-r3: destroyed
 */
__dbg__procChecksumError:
	stmfd	sp!, {lr}
    _dbg_outputRetransmitFlag
	/* b		_cont_sendAckOrNak	*/		/* Acknowledge Continue or Step command from GDB server */

_cont_sendAckOrNak:
	bl		dbg__sendAckOrNak				/* send Ack or Nak to GDB server */
	cmp		r0, #0
	beq		_cont_sendAckOrNak_exit			/* Sending of Ack or Nak succeeded */
	bl      dbg__runloopTasks               /* Service run loop tasks */
	b 		_cont_sendAckOrNak				/* Retry Ack or Nak transmission */
_cont_sendAckOrNak_exit:
    ldmfd   sp!, {pc}

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
	moveq	r0, #CMDINDEX_OUTOFRANGE	    /* End of Index Table, Not found */
	beq		_exit_cmdIndexTable
	teq		r1, r2
	addne	r0, #1							/* Increment Index */
	bne		1b								/* No match, skip to next command char */
_exit_cmdIndexTable:
	bx		lr

/* __dbg__cmdParamLen
 *   Determines the length of the parameter buffer for a given command
 *   On entry:
 *      R0: parameter buffer pointer (contents after '$' and '<cmdchar>')
 *   On exit:
 *      R0: Address of parameter buffer (preserved)
 *      R1: length
 */
__dbg__cmdParamLen:
    stmfd   sp!, {r0,r2,lr}     /* R2: scratch register */
    mov     r1, #0
1:  ldrb    r2, [r0], #1
    teq     r2, #0
    addne   r1, r1, #1
    bne     1b
    ldmfd   sp!, {r0,r2,pc}

/* __dbg__procCmdOk
 *      Common subroutine exit stub to return Command Ok Status for Command Handlers
 *      DO NOT CALL THIS STUB DIRECTLY! It Assumes that the return address is in the stack.
 *
 */
__dbg__procCmdOk:
    _dbg_outputMsgStatusOk
    b       __dbg__sendDebugMsgExit

/* __dbg__procUnimplementedError
 *      Common subroutine exit stub to handle Unimplemented GDB Command Error
 *      DO NOT CALL THIS STUB DIRECTLY! It Assumes that the return address is in the stack.
 *		Note: GDB Remote Protocol specifies returning blank message ('+$')
 *
 */
__dbg__procUnimplementedError:
    _dbg_outputMsgValidResponse
    b       __dbg__sendDebugMsgExit

/* __dbg__procCmdParamError
 *		Common subroutine exit stub to handle Command Parameter Error for Command Handlers
 *		DO NOT CALL THIS STUB DIRECTLY! It Assumes that the return address is in the stack.
 *
 */
__dbg__procCmdParamError:
    mov r1, #MSG_UNKNOWNPARAM
    b   __dbg__procErrorMsg

/* __dbg__procCmdReturnInputLengthError
 *      Common subroutine exit stub to handle Command Input Length Error for Command Handlers
 *      DO NOT CALL THIS STUB DIRECTLY! It Assumes that the return address is in the stack.
 *
 */
__dbg__procCmdReturnInputLengthError:
    mov r1, #MSG_ERRINLENGTH
    b   __dbg__procErrorMsg

/* __dbg__procCmdReturnOutputLengthError
 *      Common subroutine exit stub to handle Command Return Output Error for Command Handlers
 *      DO NOT CALL THIS STUB DIRECTLY! It Assumes that the return address is in the stack.
 *
 */
__dbg__procCmdReturnOutputLengthError:
    mov r1, #MSG_ERROUTLENGTH
    b   __dbg__procErrorMsg

/* __dbg__procBreakpointAddrError
 *      Common subroutine exit stub to handle Breakpoint Address Error for Breakpoint Insert/Remove Handlers
 *      DO NOT CALL THIS STUB DIRECTLY! It Assumes that the return address is in the stack.
 *
 */
__dbg__procBreakpointAddrError:
    mov r1, #MSG_UNKNOWNBRKPT
    b   __dbg__procErrorMsg


__dbg__procErrorMsg:
    __dbg_outputErrMsg
    /* b       __dbg__sendDebugMsgExit */

__dbg__sendDebugMsgExit:
    bl      dbg__putDebugMsg                /* Send error response to the GDB server */
    ldmfd   sp!, {pc}

/* _dbg__cmd_Status
 *		Status Command Handler
 *		On entry:
 *			r0: parameter buffer (contents after '$' and '<cmdchar>')
 *      On exit:
 *          r0, r1, r2, r3: destroyed
 */
_dbg__cmd_Status:
	stmfd	sp!, {lr}
	_dbg_outputMsgStatusSig 0x0				/* FIXME: Dummy Signal number */
	b	__dbg__sendDebugMsgExit

/* _dbg__cmd_Query
 *		Query Command Handler
 *		On entry:
 *			r0: parameter buffer (contents after '$' and '<cmdchar>')
 *				[varied, see GDB General Packets query docs]
 *				http://sourceware.org/gdb/current/onlinedocs/gdb/General-Query-Packets.html
 *      On exit:
 *          r0, r1, r2, r3: destroyed
 */
_dbg__cmd_Query:
	stmfd	sp!, {lr}
	_dbg_setstate	DBG_CONFIGURED			/* We have exchanged query messages with the GDB server */
	b      __dbg__procUnimplementedError	/* FIXME: return an empty message to GDB (no modifiable settings) */


/* _dbg__cmd_GetOneReg
 *		Get One Register Value Command Handler
 *		Valid command parameter x is from '0' to 'F' for User Mode Registers R0-R15,
 *			'18' for FPSCR (dummy), and '19' for CPSR
 *		On entry:
 *			r0: parameter buffer pointer (contents after '$' and '<cmdchar>')
 *              x
 *      On exit:
 *          r0, r1, r2, r3: destroyed
 *
 */
_dbg__cmd_GetOneReg:
	stmfd	sp!, {lr}
	bl      __dbg__cmdParamLen
	cmp		r1, #CMD_REG_GETONE_MINPARAMLEN	/* Check for correct length */
	blo		__dbg__procCmdParamError		/* Unexpected input, report error */
 	cmp		r1, #CMD_REG_GETONE_MAXPARAMLEN	/* Check for correct length */
	bhi		__dbg__procCmdParamError		/* Unexpected input, report error */
    bl      ascii2hex_varlen_be             /* convert ASCII reg enum to Hex (in R0), R1 has address of next buffer char */

_dbg__proc_getRegister:
	mov		r3, r0							/* Keep register index safe */
	_dbg_outputMsgValidResponse				/* R0: address of output message buffer data pointer (after response prefix) */
	mov		r1, r3							/* Move register index value to R1 */
	bl		_dbg_outputOneRegValue			/* update output buffer */
	_asciiz r0, r1
	bl		dbg__putDebugMsg				/* Send response to the GDB server */
	ldmfd	sp!, {pc}

/* _dbg_outputOneRegValue
 *		Given Register Enum (0-F: R0-R15, 0x19: CPSR, OtherVal: dummy), output hex char to buffer
 *		On entry:
 *          r0: output message buffer pointer
 *			r1: register enum (0-F, 0x19)
 *		On exit:
 *			r0: updated (points to next character slot at end of Output Buffer)
 *			r1: original output message buffer pointer
 *			r2: destroyed
 */
_dbg_outputOneRegValue:
	stmfd	sp!, {lr}
	cmp		r1, #REG_PC
	addls	r2, r1, #DBGSTACK_USERREG_INDEX	/* Convert register enum to Debug Stack index */
	bls		_retrieve_RegVal

	cmp		r1, #REG_CPSR
	moveq	r2, #DBGSTACK_USERCPSR_INDEX	/* convert register enum to Debug Stack index */
	beq		_retrieve_RegVal

	cmp		r1, #REG_FPSCR
	bne		_exit_dbg_outputOneRegValue		/* No match, skip */

_output_dummy_fpscr:
	/* Output Dummy FPSCR value */
	mov		r1, #0
	b		_output2buffer					/* Output all zeros for FPSCR */

_retrieve_RegVal:
	_getdbgregisterfromindex r2, r1			/* Retrieve Register contents into R1 */

_output2buffer:

#ifdef __BIG_ENDIAN__
	bl		word2ascii_be				    /* Convert and put hex chars into Output Message Buffer */
#else
    bl      word2ascii_le                   /* Convert and put hex chars into Output Message Buffer */
#endif

_exit_dbg_outputOneRegValue:
	ldmfd	sp!, {pc}

/* _dbg__cmd_GetAllRegs
 *		Get All Register Values Command Handler
 *		Output Buffer returns register values in the order: User R0, R1, R2, ..., R15, CPSR
 *		On entry:
 *			r0: parameter buffer pointer (contents after '$' and '<cmdchar>')
 *              <NULL> (no parameters)
 *      On exit:
 *          r0, r1, r2, r3: destroyed
 */
_dbg__cmd_GetAllRegs:
	stmfd	sp!, {lr}
    bl      __dbg__cmdParamLen
    teq     r1, #CMD_REG_GETALL_PARAMLEN    /* Check for correct length */
	bne		__dbg__procCmdParamError		/* Unexpected input, report error */

    _dbg_outputMsgValidResponse             /* R0: address of output message buffer data pointer (after response prefix) */

	/* We must return R0-R15, then CPSR */
	mov		r3, #REG_R0						/* Output User Register Values first */
1:  mov		r1, r3
	bl		_dbg_outputOneRegValue			/* update output buffer */
	add		r3, r3, #1						/* increment index */
	cmp		r3, #REG_PC
	bls		1b								/* process all the registers */
_get_cpsr:
	mov		r1, #REG_CPSR					/* Output User CPSR Value last */
	bl		_dbg_outputOneRegValue			/* update output buffer */

    _asciiz r0, r1
	bl		dbg__putDebugMsg				/* Send response to the GDB server */
	ldmfd	sp!, {pc}

/* _dbg_setOneRegValue
 *		Given Register Enum (0-F: R0-R15, 0x19: CPSR, OtherVal: dummy), output hex char to buffer
 *		On entry:
 *          r0: parameter buffer pointer
 *			r1: register enum (0-F, 0x19)
 *		On exit:
 *          r0: (Updated) Address of parameter in buffer
 *          r1, r2, r3: destroyed
 */
_dbg_setOneRegValue:
    stmfd   sp!, {lr}
	cmp		r1, #REG_PC
	addls	r2, r1, #DBGSTACK_USERREG_INDEX	/* Convert register enum to Debug Stack index */
	bls		_store_RegVal

	cmp		r1, #REG_CPSR
	moveq	r2, #DBGSTACK_USERCPSR_INDEX	/* convert register enum to Debug Stack index */
	beq		_store_RegVal

	cmp		r1, #REG_FPSCR
	bne		_exit_dbg_setOneRegValue		/* No match, skip */
	/* FIXME: If we get SetAllRegs with FP reg values, this will not skip pass the FP regs! */

_set_dummy_fpscr:
	/* Set dummy FPSCR value (ignored) */
	add		r1, r0, #CMD_REG_REGPARAMLEN	/* Just increment the pointer */
	b		_done_store_RegVal

_store_RegVal:
#ifdef __BIG_ENDIAN__
    bl      ascii2word_be
#else
    bl      ascii2word_le
#endif
    /* R0: value, R1: pointer to next char in buffer */
    _setdbgregisterfromindex r2, r0, r3     /* Set Register contents in R0, using index in R2, and scratch register R3 */
_done_store_RegVal:
	mov		r0, r1							/* Copy buffer pointer to next parameter to R0 for return value */
_exit_dbg_setOneRegValue:
    ldmfd   sp!, {pc}


/* _dbg__cmd_SetOneReg
 *      Set One Register Value Command Handler
 *		Valid command parameter x is from '0' to 'F' for User Mode Registers R0-R15,
 *			'18' for FPSCR (dummy), and '19' for CPSR
 *      On entry:
 *          r0: parameter buffer pointer (contents after '$' and '<cmdchar>')
 *              x=rrrr
 *      On exit:
 *          r0, r1, r2, r3, r4: destroyed
 *
 */
_dbg__cmd_SetOneReg:
    stmfd   sp!, {lr}
    bl      __dbg__cmdParamLen
    cmp     r1, #CMD_REG_SETONE_MINPARAMLEN    /* Check for correct length */
    blo     __dbg__procCmdParamError        /* Unexpected input, report error */
    cmp     r1, #CMD_REG_SETONE_MAXPARAMLEN    /* Check for correct length */
    bhi     __dbg__procCmdParamError        /* Unexpected input, report error */

    bl      ascii2hex_varlen_be             /* convert ASCII reg enum to Hex (in R0), R1 has address of next buffer char */
	mov		r4, r0							/* Keep enum in R4 */
    _check_msgassignment r1					/* R1 points to next char in buffer */
    bne     __dbg__procCmdParamError        /* Can't find '=' */

_dbg__proc_setRegister:
	mov		r0, r1							/* move parameter buffer pointer to R0 */
    mov     r1, r4                          /* and retrieve enum to R1 to call _dbg_setOneRegValue */
    bl      _dbg_setOneRegValue
    b       __dbg__procCmdOk

/* _dbg__cmd_SetAllReg
 *      Set All Register Values Command Handler
 *      On entry:
 *          r0: parameter buffer pointer (contents after '$' and '<cmdchar>')
 *              rrrrRRRRrrrr... (17 registers)
 *      On exit:
 *          r0, r1, r2, r3, r4: destroyed
 *
 */
_dbg__cmd_SetAllRegs:
	/* Assumes that the registers are in the sequence R0, R1, ... R15, CPSR */
    stmfd   sp!, {lr}
    bl      __dbg__cmdParamLen              /* R0: pointer to parameters in buffer */
    teq     r1, #CMD_REG_SETALL_PARAMLEN    /* Check for correct length */
    bne     __dbg__procCmdParamError        /* Unexpected input, report error */
    mov     r4, #REG_R0					    /* R4: register enum, starting with enum for R0 */
1:	mov		r1, r4							/* Copy enum to R1; R0 already points to current parameter */
	bl		_dbg_setOneRegValue				/* R0: next parameter address pointer */
    add     r4, r4, #1                      /* increment index */
    cmp		r4, #REG_PC
    bls		1b

_set_cpsr:
#if 0
	/* GDB was not happy when this was added */
	/* Read dummy FPSCR value (ignored) */
#ifdef __BIG_ENDIAN__
    bl      ascii2word_be
#else
    bl      ascii2word_le
#endif
	mov		r0, r1							/* Copy buffer pointer to next parameter to R0 for return value */
#endif

    mov     r1, #REG_CPSR				    /* Use CPSR enum */
	bl		_dbg_setOneRegValue				/* R0: next parameter address pointer */
    ldrb    r0, [r0]
    teq     r0, #0                          /* Look for ASCIIZ character to terminate loop */
    beq     __dbg__procCmdOk
	bne		__dbg__procCmdParamError		/* Unexpected input, report error */

/* _dbg__nop
 *		NOP Command Handler (placeholder)
 *		On entry:
 *			r0: parameter buffer (contents after '$' and '<cmdchar>')
 *      On exit:
 *          r0, r1, r2, r3: destroyed
 */
_dbg__nop:
	stmfd	sp!, {lr}
	b      __dbg__procUnimplementedError

/* _dbg__cmd_ReadMem
 *      Read Memory Contents Command Handler
 *      Output Buffer returns memory contents
 *      On entry:
 *          r0: parameter buffer pointer (contents after '$' and '<cmdchar>')
 *              AA..AA,LLLL
 *      On exit:
 *          r0, r1, r2, r3, r4: destroyed
 */
_dbg__cmd_ReadMem:
    stmfd   sp!, {lr}
    bl      __dbg__cmdParamLen
#if 0
    teq     r1, #CMD_MEM_READ_PARAMLEN      /* Check for correct length */
    bne     __dbg__procCmdParamError        /* Unexpected input, report error */
    bl      ascii2word_be                   /* convert ASCII address location to Hex (in R0), R1 has address of next buffer char */
#endif
    bl      ascii2hex_varlen_be             /* convert ASCII address to Hex (in R0), R1 has address of next buffer char */
    mov     r3, r0                          /* Keep Address location in R3 */
    _check_msgseparator r1
    bne     __dbg__procCmdParamError        /* Can't find ',' */
    mov     r0, r1                          /* move buffer pointer to R0 for subsequent processing */
    bl      ascii2hex_varlen_be             /* convert ASCII length to Hex (in R0), R1 has address of next buffer char */
    cmp     r0, #CMD_MEM_MAXREADBYTES       /* Don't overflow our buffer (2 x CMD_MEM_MAXREADBYTES) */
    bhi     __dbg__procCmdReturnOutputLengthError /* Requested Length greater than buffer size, return error */
    mov     r4, r0                          /* Keep numbytes in R4 */
    /* FIXME: Should validate the address? */

    _dbg_outputMsgValidResponse             /* R0: address of output message buffer data pointer (after response prefix) */
1:  ldrb    r1, [r3], #1
    bl      byte2ascii                       /* update output buffer */
    subs    r4, r4, #1
    bne     1b

    _asciiz r0, r1
    bl      dbg__putDebugMsg                /* Send response to the GDB server */
    ldmfd   sp!, {pc}


/* _dbg__cmd_WriteMem
 *      Write Memory Contents Command Handler
 *      On entry:
 *          r0: parameter buffer pointer (contents after '$' and '<cmdchar>')
 *              AA..AA,LLLL::bb..bb
 *      On exit:
 *          r0, r1, r2, r3, r4: destroyed
 */
_dbg__cmd_WriteMem:
    stmfd   sp!, {lr}
    bl      __dbg__cmdParamLen
#if 0
    cmp     r1, #CMD_MEM_WRITE_MINPARAMLEN  /* Check for correct (minimum) length */
    blo     __dbg__procCmdParamError        /* Unexpected input, report error */
    sub     r4, r1, #CMD_MEM_WRITE_MINPARAMLEN  /* R4: Number of ASCII Hex chars for byte writes */
    bl      ascii2word_be                   /* convert ASCII address location to Hex (in R0), R1 has address of next buffer char */
#endif
    bl      ascii2hex_varlen_be             /* convert ASCII address to Hex (in R0), R1 has address of next buffer char */
    mov     r3, r0                          /* Keep Address location in R3 */
    _check_msgseparator r1
    bne     __dbg__procCmdParamError        /* Can't find ',' */
    mov     r0, r1                          /* move buffer pointer to R0 for subsequent processing */
    bl      ascii2hex_varlen_be             /* convert ASCII length to Hex (in R0), R1 has address of next buffer char */
    cmp     r0, r4, asr #1                  /* is Number of bytes to write == (number of ASCII Hex Chars / 2)? */
    bne     __dbg__procCmdParamError        /* Number of bytes does not match argument length */
    cmp     r0, #CMD_MEM_MAXWRITEBYTES      /* Don't overflow our buffer (2 x CMD_MEM_MAXWRITEBYTES) */
    bhi     __dbg__procCmdReturnInputLengthError /* Requested Length greater than buffer size, return error */
    mov     r4, r0                          /* Keep numbytes in R4 */
    /* FIXME: Should validate the address? */
    _check_msgargument r1
    bne     __dbg__procCmdParamError        /* Can't find ':' */

1:  mov     r0, r1
    bl      ascii2byte                      /* convert ASCII Hex value into byte value */
    strb    r0, [r3], #1                    /* Store into memory location */
    subs    r4, r4, #1
    bne     1b
    b       __dbg__procCmdOk

/* _dbg__cmd_Continue
 *      Continue User Program Execution Command Handler
 *      Setup breakpoints before resuming execution of program.
 *
 *      If Address is specified, update the next instruction address to specified address
 *
 *      If this is a Normal Breakpoint, then we need to install an Autobreakpoint at next instruction address
 *          and resume from current (Breakpoint) exception address
 *      Else (it is a Manual Breakpoint or Address Specified)
 *          We need to resume from the next instruction address
 *      On entry:
 *          r0: parameter buffer pointer (contents after '$' and '<cmdchar>')
 *              Optional: AA..AA
 *      On exit:
 *          r0-r7: destroyed
 *			Note: This routine does not return to caller. Instead it switches
 *				  operating mode to UNDEF and returns to previously active program
 */
_dbg__cmd_Continue:
    /* Don't put anything on the stack, we won't return to the Debugger Run Loop */
    bl      __dbg__cmdParamLen
    cmp     r1, #CMD_CONTINUE_MINPARAMLEN  /* Check for correct parameter length */
    beq     _dbg__cont_check_breakpoint_type          /* Continue from current PC */

_dbg__cont_fromAddr:
    bl      ascii2hex_varlen_be             /* convert ASCII address to Hex (in R0), R1 has address of next buffer char */
    /* Continue from Specified Address */
    mov     r2, #DBGSTACK_NEXTINSTR_INDEX   /* The Next Instruction Pointer for Resume is in index 0 of the Debug Stack */
    _setdbgregisterfromindex r2, r0, r1     /* Set Register contents in R0, using index in R2, and scratch register R1 */
    b       _dbg__cont_is_manual_bkpt_or_address_specified

_dbg__cont_check_breakpoint_type:
    _dbg_get_bkpt_type   r0
    teq r0, #DBG_MANUAL_BKPT_ARM
    beq _dbg__cont_is_manual_bkpt_or_address_specified
    teq r0, #DBG_MANUAL_BKPT_THUMB
    beq _dbg__cont_is_manual_bkpt_or_address_specified

_dbg__cont_is_normal_breakpoint:
/* FIXME: _dbg_following_instruction_addr doesn't actually work currently.
   This breaks normal breakpoints which need to determine the next instruction to execute
   (for placing the autobreakpoint) prior to returning.
*/
    mov		r2, #DBGSTACK_USERPC_INDEX      /* Retrieve Aborted Instruction PC from the Debug Stack */
    _getdbgregisterfromindex r2, r0         /* Retrieve Register contents into R0 */
    mov		r2, #DBGSTACK_NEXTINSTR_INDEX   /* The Next Instruction Pointer for Resume is in index 0 of the Debug Stack */
    _setdbgregisterfromindex r2, r0, r1     /* Set Register contents in R0, using index in R2, and scratch register R1 */
    bl  	_dbg_following_instruction_addr /* following instruction address returned in r1 */
    bl  	_dbg__install_singlestep        /* Setup Single Step, next instruction address returned in r1 */
    _dbg_getcurrbkpt_index r0               /* load current breakpoint index in memory */
    bl  	_dbg__activate_autobreakpoint   /* pass next instruction address in r1 */
	b		_dbg__switch2undefmode_withAck

_dbg__cont_is_manual_bkpt_or_address_specified:
    bl      _dbg__activate_breakpoints      /* Restore exisiting breakpoints */
    b       _dbg__switch2undefmode_withAck

/* _dbg__cmd_Step
 *      Step User Program Execution Command Handler
 *      Setup breakpoints before resuming execution of program.
 *
  *      If Address is specified, update the next instruction address to specified address
 *
 *      If this is a Normal Breakpoint, then we need to install a Step Breakpoint at next instruction address
 *          and resume from current (Breakpoint) exception address
 *      Else (it is a Manual Breakpoint or Address specified)
 *          We need to install a Step Breakpoint at the following instruction address (after the next instruction address)
 *          and resume from the next instruction address
 *      On entry:
 *          r0: parameter buffer pointer (contents after '$' and '<cmdchar>')
 *              Optional: AA..AA
 *      On exit:
 *          r0-r7: destroyed
 *          Note: This routine does not return to caller. Instead it switches
 *                operating mode to UNDEF and returns to previously active program
 */
_dbg__cmd_Step:
    /* Don't put anything on the stack, we won't return to the Debugger Run Loop */
    bl      __dbg__cmdParamLen
    cmp     r1, #CMD_STEP_MINPARAMLEN       /* Check for correct parameter length */
    beq     _dbg__step_check_breakpoint_type          /* Step from current PC */

_dbg__step_fromAddr:
    bl      ascii2hex_varlen_be             /* convert ASCII address to Hex (in R0), R1 has address of next buffer char */
    /* Step from Specified Address */
    mov     r2, #DBGSTACK_NEXTINSTR_INDEX   /* The Next Instruction Pointer for Resume is in index 0 of the Debug Stack */
    _setdbgregisterfromindex r2, r0, r1     /* Set Register contents in R0, using index in R2, and scratch register R1 */
    b       _dbg__step_is_manual_bkpt_or_address_specified

_dbg__step_check_breakpoint_type:
    _dbg_get_bkpt_type   r0
    teq 	r0, #DBG_MANUAL_BKPT_ARM
    beq 	_dbg__step_is_manual_bkpt
    teq 	r0, #DBG_MANUAL_BKPT_THUMB
    beq 	_dbg__step_is_manual_bkpt

_dbg__step_is_normal_breakpoint:
/* FIXME: _dbg_following_instruction_addr doesn't actually work currently.
   This breaks normal breakpoints which need to determine the next instruction to execute
   (for placing the autobreakpoint) prior to returning.
*/
    mov     r2, #DBGSTACK_USERPC_INDEX      /* Retrieve Aborted Instruction PC from the Debug Stack */
    _getdbgregisterfromindex r2, r0         /* Retrieve Register contents into R0 */
    mov     r2, #DBGSTACK_NEXTINSTR_INDEX   /* The Next Instruction Pointer for Resume is in index 0 of the Debug Stack */
    _setdbgregisterfromindex r2, r0, r1     /* Set Register contents in R0, using index in R2, and scratch register R1 */
    b       _dbg__step_is_manual_bkpt_or_address_specified

_dbg__step_is_manual_bkpt:
    mov     r2, #DBGSTACK_NEXTINSTR_INDEX   /* The Next Instruction Pointer for Resume is in index 0 of the Debug Stack */
    _getdbgregisterfromindex r2, r0         /* Retrieve Register contents into R1 */
    /* b       _dbg__step_is_manual_bkpt_or_address_specified */

_dbg__step_is_manual_bkpt_or_address_specified:
    bl  	_dbg_following_instruction_addr /* following instruction address returned in r1 */
    bl  	_dbg__install_singlestep        /* Setup Single Step, next instruction address returned in r1 */
	bl		_dbg__activate_singlestep
    b       _dbg__switch2undefmode_withAck


/* _dbg__proc_brkpt_params
 *      Process Breakpoint Parameters
 *      On entry:
 *          r0: parameter buffer pointer (contents after '$' and '<cmdchar>')
 *              t,AA..AA,k
 *      On exit:
 *          r0: non-zero = breakpoint address; 0 = parameter error
 *          r1: destroyed
 *          r2: destroyed
 *          r3: destroyed
 */
_dbg__proc_brkpt_params:
    /* FIXME: Add support for watchpoints */
    stmfd   sp!, {lr}
    mov     r3, r0                          /* Keep parameter buffer address in R3 */
    ldrb    r0, [r3], #1                    /* get breakpoint type t */
    bl      char2hex
    cmp     r0, #CMD_BKPT_TYPE_BREAK_MEMORY
    bne     _dbg__proc_brkpt_params_error   /* We only support memory breakpoints for now */
    _check_msgseparator r3
    bne     _dbg__proc_brkpt_params_error   /* Something wrong with the parameters */
    mov     r0, r3                          /* Check Address */
    bl      ascii2hex_varlen_be             /* convert ASCII address to Hex (in R0), R1 has address of next buffer char */
    mov     r3, r0                          /* Keep breakpoint address in R3 */
    _check_msgseparator r1
    bne     _dbg__proc_brkpt_params_error   /* Something wrong with the parameters */
    ldrb    r0, [r1], #1                    /* get breakpoint kind k */
    bl      char2hex
    cmp     r0, #CMD_BKPT_KIND_THUMB
    orreq   r3, r3, #1                      /* Mark Thumb breakpoints */
    beq     _exit_dbg__proc_brkpt_params
    cmp     r0, #CMD_BKPT_KIND_ARM
    beq     _exit_dbg__proc_brkpt_params    /* ARM breakpoint */

_dbg__proc_brkpt_params_error:
    mov     r3, #0                          /* Unrecognized breakpoint type */
_exit_dbg__proc_brkpt_params:
    mov     r0, r3                          /* return breakpoint address */
    ldmfd   sp!, {pc}

/* _dbg__cmd_InsertBreakpoint
 *		Add Breakpoint
 *      On entry:
 *          r0: parameter buffer pointer (contents after '$' and '<cmdchar>')
 *              t,AA..AA,k
 *      On exit:
 *          r0, r1, r2, r3: destroyed
 */
_dbg__cmd_InsertBreakpoint:
    stmfd   sp!, {lr}
    bl      __dbg__cmdParamLen
    teq     r1, #CMD_BKPT_INSERT_MINPARAMLEN   /* Check for correct length */
    blo     __dbg__procCmdParamError        /* Unexpected input, report error */
    bl      _dbg__proc_brkpt_params         /* R0: Breakpoint Address */
    teq     r0, #0
    beq     __dbg__procBreakpointAddrError  /* Thumb2 instructions, or unknown kind */
    mov     r3, r0                          /* Keep breakpoint address in R3 */
    mov     r0, #0                          /* Empty Breakpoint entry */
    bl      _dbg_find_breakpoint_slot       /* Look for an available breakpoint slot, return index in R0 */
    cmp     r0, #CMD_BKPT_NOTFOUND
    beq     __dbg__procBreakpointAddrError  /* No empty slot! */
    mov     r1, r3                          /* Move breakpoint address to R1 */
	bl     _dbg__install_one_breakpoint		/*	r0: index, r1: instruction address */
    b       __dbg__procCmdOk

/* _dbg__cmd_RemoveBreakpoint
 *		Remove Breakpoint
 *		On entry:
 *          r0: parameter buffer pointer (contents after '$' and '<cmdchar>')
 *              t,AA..AA,k
 *      On exit:
 *          r0, r1, r2, r3: destroyed
 */
_dbg__cmd_RemoveBreakpoint:
    stmfd   sp!, {lr}
    bl      __dbg__cmdParamLen
    teq     r1, #CMD_BKPT_REMOVE_MINPARAMLEN  /* Check for correct length */
    blo     __dbg__procCmdParamError       /* Unexpected input, report error */
    bl      _dbg__proc_brkpt_params        /* R0: Breakpoint Address */
    teq     r0, #0
    beq     __dbg__procBreakpointAddrError /* Thumb2 instructions, or unknown kind */
    bl      _dbg_find_breakpoint_slot      /* Look for matching breakpoint slot, return index in R0 */
    cmp     r0, #CMD_BKPT_NOTFOUND
    beq     __dbg__procBreakpointAddrError /* Specified Breakpoint not found! */
	_index2bkptindex_addr	r0, r1		   /* Calculate Breakpoint Entry Address */
	mov     r0, r1                         /* Move it to R0 for subroutine call */
	bl	    _dbg__clear_one_breakpoint     /* R0: address of breakpoint to clear */
    b       __dbg__procCmdOk




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

/* _dbg_following_instruction_addr
 *		Determine the address of the following instruction to execute.
 *      On entry:
 *          R0: Address of the instruction to be (re)executed
 *		On exit:
 *          R0: Destroyed
 *			R1: Following Instruction Address (31 bits, b0 = THUMB flag)
 *          R2-R7: Destroyed
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
_dbg_following_instruction_addr:
    stmfd   sp!, {lr}
/* We assume that any BKPT instructions in the code will be Manual Breakpoints,
 * i.e., the Debugger does not leave stray Single Step / Auto / Normal breakpoints in memory
 */
    mov     r6, r0                                      /* Keep instruction address in R6 */
    mov     r2, #DBGSTACK_USERCPSR_INDEX                /* Retrieve User CPSR */
    _getdbgregisterfromindex r2, r1                     /* Retrieve Register contents into R1 */
    and     r4, r1, #CPSR_THUMB                         /* store Thumb Mode status in R4 */
    mov     r5, r1, lsr #28                             /* store CPSR condition flags in R5[3:0] */

_dbg_get_aborted_instr:
1:  teq     r4, #0                                      /* Check if it is ARM or Thumb instruction */
    ldrneh  r0, [r6]                                    /* Load Thumb instruction opcode using Addr in R6 into R0 */
    ldrne   r2, =(BKPT16_INSTR | BKPT16_MANUAL_BKPT)    /* check for Thumb Manual Breakpoint Instruction */
    ldreq   r0, [r6]                                    /* Load ARM instruction opcode using Addr in R6 into R0 */
    ldreq   r2, =(BKPT32_INSTR | BKPT32_MANUAL_BKPT)    /* check for ARM Manual Breakpoint Instruction */
    teq     r0, r2                                      /* Is instruction opcode (R0) == Manual Breakpoint opcode (R2)? */
    bne     2f                                          /* Not Manual breakpoint */
    teq     r4, #0                                      /* Check if it is ARM or Thumb Manual Breakpoint */
    addne   r6, r6, #2                                  /* Is Manual Breakpoint, Skip to next Thumb instruction */
    addeq   r6, r6, #4                                  /* Is Manual Breakpoint, Skip to next ARM instruction */
    b       1b                                          /* To protect against a sequence of Manual Breakpoint Instructions */

/* Here, R0 contains the instruction opcode which will be (re)executed when program resumes.
 * We need to dissect it to see if it is a branch instruction.
 * For ARM instructions, we also need to evaluate the current (breakpointed) instruction to see if it'll execute.
 * If not, then the following instruction is at the address following the address of the opcode in R0 (Default Following Instruction Address).
 */
2:
    teq     r4, #0                                      /* Check if it is ARM or Thumb instruction */
    beq     _following_instr_is_arm
_following_instr_is_thumb:
    add     r6, r6, #2                                  /* Store following Thumb instruction address to R1 */
    orr     r6, r6, #BKPT_STATE_THUMB_FLAG              /* Set b0 to indicate Thumb instruction */
    /* R0: Candidate Instruction Opcode
     * R5[3:0]: CPSR condition codes
     * R6: Default Following Instruction Address (PC+2)
     */
    bl      _eval_thumb_instruction						/* following address is either ARM or Thumb */
    /* We must set this the Thumb bit only within the instruction handler since BX would switch modes */
    b       _exit_dbg_following_instruction_addr

_following_instr_is_arm:
    add     r6, r6, #4                                  /* Store following ARM instruction address to R1 */
    /* R0: Candidate Instruction Opcode
     * R5[3:0]: CPSR condition codes
     * R6: Default Following Instruction Address (PC+4)
     */
    bl      _eval_arm_instruction

_exit_dbg_following_instruction_addr:
    mov     r1, r0                                      /* Return Actual Following Instruction Address in R1 (B0 set to indicate Thumb mode) */
    ldmfd   sp!, {pc}


/* _eval_arm_instruction
 *      Evaluate ARM instruction to determine following instruction address
 *      On entry:
 *          R0: instruction to be executed
 *          R5[3:0]: CPSR condition codes
 *          R6: Default Following Instruction Address (PC+4)
 *      On exit:
 *          R0: following instruction address (B0 set to indicate Thumb mode)
 *          R1-R7: destroyed
 */
_eval_arm_instruction:
    stmfd   sp!, {lr}
    mov     r4, r0                      /* Keep Instruction Opcode in R4 */
    bl      _dbg_check_arm_condcode
    teq     r0, #FALSE
    moveq   r0, r6                      /* False (don't execute), so use Default Following Instruction Address */
    bne     _exit_eval_arm_instruction

_will_execute_arm_instr:
    mov     r0, r4                      /* Copy instruction opcode to R0 as Code Handler parameter */
    mov     r1, #0                      /* initialize ARM Decode Entry Table index register */
1:
    _dbg_armDecodeEntry r2, r3, r4, r1  /* instrreg (R2), instrmask (R3), codehandler (R4), indexreg (R1) */
    teq     r2, #0                      /* Check for Null Entry (End of Table marker) */
    moveq   r0, r6                      /* End of Table, no match found, so use Default Following Instruction Address */
    beq     _exit_eval_arm_instruction
    and     r7, r0, r3                  /* Use R7 to check masked instruction opcode (from R0) to see if it matches template (in R2) */
    teq     r7, r2
    addne   r1, r1, #1                  /* No match, so keep looking */
    bne     1b

_call_arm_code_handler:
    mov     r1, r6                      /* Copy Default Following Instruction Address to R1 as Code Handler Parameter */
    mov     lr, pc
    bx      r4                          /* Call Code Handler with R0: Instruction Opcode, R1: Default Following Instruction Address */
_exit_eval_arm_instruction:
    /* Returned Following Address Instruction in R0 (B0 set to indicate Thumb mode)  */
    ldmfd   sp!, {pc}

/* _eval_thumb_instruction
 *      Evaluate Thumb instruction to determine following instruction address
 *      On entry:
 *          R0: instruction to be executed
 *          R5[3:0]: CPSR condition codes
 *          R6: Default Following Instruction Address (PC+2)
 *      On exit:
 *          R0: following instruction address (B0 set to indicate Thumb mode)
 *          R1-R7: destroyed
 */
_eval_thumb_instruction:
    stmfd   sp!, {lr}
#if 0
    mov     r4, r0                      /* Keep Instruction Opcode in R4 */
	/* Only B<cond> instructions are conditionally executed, deal with it in that Code Handler */
    bl      _dbg_check_thumb_condcode
    teq     r0, #FALSE
    moveq   r0, r6                      /* False (don't execute), so use Default Following Instruction Address */
    bne     _exit_eval_thumb_instruction

_will_execute_thumb_instr:
    mov     r0, r4                      /* Copy instruction opcode to R0 as Code Handler parameter */
#endif
    mov     r1, #0                      /* initialize Thumb Decode Entry Table index register */
1:
    _dbg_thumbDecodeEntry r2, r3, r4, r1  /* instrreg (R2), instrmask (R3), codehandler (R4), indexreg (R1) */
    teq     r2, #0                      /* Check for Null Entry (End of Table marker) */
    moveq   r0, r6                      /* End of Table, no match found, so use Default Following Instruction Address */
    beq     _exit_eval_thumb_instruction

    and     r7, r0, r3                  /* Use R5 to check masked instruction opcode (from R0) to see if it matches template (in R2) */
    teq     r7, r2
    addne   r1, r1, #1                  /* No match, so keep looking */
    bne     1b

_call_thumb_code_handler:
    mov     r1, r6                      /* Copy Default Following Instruction Address to R1 as Code Handler Parameter */
    mov     lr, pc
    bx      r4                          /* Call Code Handler with R0: Instruction Opcode, R1: Default Following Instruction Address */
_exit_eval_thumb_instruction:
    /* Returned Following Address Instruction in R0 */
    ldmfd   sp!, {pc}


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
 *          R1-R3: Destroyed
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


/* _arm_rmshifted_val
 *      Calculate value of Shifted Rm (operand)
 *      On entry:
 *          R0[11:0]: Shifted Rm operand
 *      On exit:
 *          R0: value of Shifted Rm
 *          R1, R2, R3: destroyed
 */
_arm_rmshifted_val:
    stmfd   sp!, {lr}
    ldr     r3, =(NIBBLE2|BYTE0)
    and     r3, r0, r3                      /* 12 bit Shifted Register operand, copied to R3 */
    and     r2, r3, #NIBBLE0                /* Register Rn Enum in R2 */
    _regenum2index  r2, r2                  /* Convert Enum into Index in R2 */
    _getdbgregisterfromindex r2, r0         /* Retrieve Register Rn contents from Index (R2) into R0 */

    tst     r3, #0x10                       /* B4: Immediate (0) or Register (1) shift count */
    /* check bitshift op */
    and     r3, r3, #0x60                   /* shift type */
    mov     r3, r3, lsr #5                  /* convert into shift type jumptable index */
    bne     _arm_get_reg_shift              /* Flags set previously via TST r3 (B4) */
_arm_calc_const_shift:
    movs    r1, r3, lsr #7                  /* Immediate shift count, 5 bit unsigned value in R1 */
    bne     _arm_calc_shifted_rm_val        /* Non-zero shift count, process normally */
    /* Must check for RRX == ROR #0 */
    teq     r3, #0x3                        /* ROR == 0x3 */
    addeq   r3, r3, #1
    b       _arm_calc_shifted_rm_val

_arm_get_reg_shift:
    mov     r2, r3, lsr #8                  /* Register-based shift count, 4 bit register enum in R2 */
    _regenum2index  r2, r2                  /* Convert Enum into Index in R2 */
    _getdbgregisterfromindex r2, r1         /* Retrieve Register value (shift count) from Index (R2) into R1 */

_arm_calc_shifted_rm_val:
    _dbg_jumpTableHandler   debug_regShiftJumpTable, r2, r3     /* Calculate RmShifted value from R0: Rn Register val, R1: Shift/Rotate val */
    ldmfd   sp!, {pc}

/* Rm Shifted Shift Type Jump Table Routines
 * On entry:
 *      R0: Register Rm
 *      R1: Shift/Rotate Amount
 * On exit:
 *      R0: RmShifted result
 *      R1, R2: destroyed
 *
 */
_reg_lsl:
    lsl     r0, r0, r1
    bx      lr

_reg_lsr:
    lsr     r0, r0, r1
    bx      lr

_reg_asr:
    asr     r0, r0, r1
    bx      lr

_reg_ror:
    ror     r0, r0, r1
    bx      lr

_reg_rrx:
    moveq   r2, #DBGSTACK_USERCPSR_INDEX    /* convert register enum to Debug Stack index */
    _getdbgregisterfromindex r2, r1         /* Retrieve CPSR contents from Index (R2) into R1 */
    ands    r1, r1, #CPSR_CFLAG            /* Keep C Flag */
    movne   r1, #0x80000000                 /* Set B31 if C Flag set */
    lsr     r0, r0, #1                      /* Rm >> 1 */
    orr     r0, r0, r1                      /* Put C flag into B31 */
    bx      lr


/* _arm_data_instr_handler
 *      ARM Data Processing Instruction with Rd == R15
 *      On entry:
 *          R0: instruction to be executed
 *          R1: Default Following Instruction Address (PC+4)
 *          R5[3:0]: CPSR condition codes
 *      On exit:
 *          R0: following instruction address
 *          R1, R2, R3, R4, R5, R6: Destroyed
 */
_arm_data_instr_handler:
    stmfd   sp!, {lr}
    mov     r6, r1                          /* save Following Instruction Address in R6 */
    ldr     r1, =0x0FBF0000
    and     r4, r0, r1                      /* Keep instruction Opcode in R4 */
    ldr     r1, =0x010F0000
    cmp     r4, r1                          /* Check for MSR / MRS instruction */

_arm_is_msr_mrs_instr:
    moveq   r0, r6                          /* Copy default next instruciton address to R0 */
    beq     _exit_arm_data_instr_handler    /* Return default next instruction address */

    /* Not MSR / MRS, so process normally */
_arm_normal_data_instr:
    and     r4, r0, #0x01E00000             /* Mask Instruction Opcode into R4 */
    and     r5, r0, #0x000F0000             /* Store Rn (Operand 1) Register Enum into R5[19:16] */
    lsr     r5, r5, #16                     /* Shift into R5[3:0] */

_arm_check_operand2_type:
    tst     r0, #0x02000000                 /* Check for Immediate (1) or Register (0) Operand 2 */
    beq     _arm_op2_is_reg

_arm_op2_is_imm:
    and     r1, r0, #BYTE0                  /* 8 bit unsigned constant in R1 */
    and     r2, r0, #NIBBLE2                /* (rotate count / 2) in R2[11:8] */
    lsr     r2, r2, #7                      /* actual rotate count in R2[4:0] */
    ror     r1, r1, r2                      /* Rotated constant in R1 */
    b       _arm_get_operand1_val

_arm_op2_is_reg:
    ldr     r1, =(NIBBLE2|BYTE0)
    and     r0, r0, r1                      /* 12 bit register operand in R1 */
    bl      _arm_rmshifted_val              /* R0 contains the Rm shifted val */
    mov     r1, r0                          /* move to R1 for later processing */

_arm_get_operand1_val:
    _regenum2index  r5, r1                  /* Convert Enum into Index in R1 */
    _getdbgregisterfromindex r1, r0         /* Retrieve Register contents from Index (R1) into R4 */
    teq     r5, #REG_PC                     /* Check if it is PC relative */
    addeq   r0, r0, #8                      /* adjust for PC relative (+8) */

_arm_calc_data_instr_val:
    mov     r2, r6                          /* Retrieve Following Instruction Address in R6 to R2 */
    /* Calculate data instruction value from R0: Rn Register (Op1) val, R1: Operand 2 val, R2: Default Next Instr Addr */
    _dbg_jumpTableHandler   debug_dataInstrJumpTable, r3, r4    /* Next Instruction Address in R0 */
_exit_arm_data_instr_handler:
    ldmfd   sp!, {pc}


/* Data Processing Instruction Jump Table Routines
 * On entry:
 *      R0: Register Rn (Operand 1) value
 *      R1: Operand 2 value
 *      R2: Default Next Instruction Address (PC+4)
 * On exit:
 *      R0: Calculated result
 *      R1, R2, R3: Destroyed
 *
 */
_opcode_and:
    and r0, r0, r1
    bx  lr

_opcode_eor:
    eor r0, r0, r1
    bx  lr

_opcode_sub:
    sub r0, r0, r1
    bx  lr

_opcode_rsb:
    rsb r0, r0, r1
    bx  lr

_opcode_add:
    add r0, r0, r1
    bx  lr

_opcode_adc:
    /* Op1 + Op2 + C */
    moveq   r2, #DBGSTACK_USERCPSR_INDEX    /* convert register enum to Debug Stack index */
    _getdbgregisterfromindex r2, r3         /* Retrieve CPSR contents from Index (R2) into R3 */
    ands    r3, r3, #CPSR_CFLAG             /* Keep C Flag, NE if C set */
    add     r0, r0, r1
    addne   r0, r0, #1                      /* Add C if set */
    bx      lr

_opcode_sbc:
    /* Op1 - Op2 + C - 1 */
    moveq   r2, #DBGSTACK_USERCPSR_INDEX    /* convert register enum to Debug Stack index */
    _getdbgregisterfromindex r2, r3         /* Retrieve CPSR contents from Index (R2) into R3 */
    ands    r3, r3, #CPSR_CFLAG             /* Keep C Flag, NE if C set */
    sub     r0, r0, r1
    subeq   r0, r0, #1                      /* If C clear, subtract 1, else (C - 1) = 0 */
    bx      lr

_opcode_rsc:
    /* Op2 - Op1 + C - 1 */
    moveq   r2, #DBGSTACK_USERCPSR_INDEX    /* convert register enum to Debug Stack index */
    _getdbgregisterfromindex r2, r3         /* Retrieve CPSR contents from Index (R2) into R3 */
    ands    r3, r3, #CPSR_CFLAG             /* Keep C Flag, NE if C set */
    rsb     r0, r0, r1
    subeq   r0, r0, #1                      /* If C clear, subtract 1, else (C - 1) = 0 */
    bx  lr

_opcode_tst:
_opcode_teq:
_opcode_cmp:
_opcode_cmn:
    mov r0, r2          /* Next Instruction Address is not modified */
    bx  lr

_opcode_orr:
    orr r0, r0, r1
    bx  lr

_opcode_mov:
    mov r0, r1          /* Operand 1 is ignored */
    bx  lr

_opcode_bic:
    bic r0, r0, r1
    bx  lr

_opcode_mvn:
    mvn r0, r1          /* Operand 1 is ignored */
    bx  lr


/* _arm_bx_blx_handler
 *      BX or BLX Rm Handler. Note v4t does not have BLX instr
 *      On entry:
 *          R0: instruction to be executed
 *          R1: Default Following Instruction Address (PC+4)
 *          R5[3:0]: CPSR condition codes
 *      On exit:
 *          R0: following instruction address (B0 set to indicate Thumb mode)
 *          R1, R2: destroyed
 */
_arm_bx_blx_handler:
    stmfd   sp!, {lr}
    and     r0, r0, #NIBBLE0                /* Register Rn Enum in R0 */
    _regenum2index  r0, r1                  /* Convert Enum into Index in R1 */
    _getdbgregisterfromindex r1, r0         /* Retrieve Register contents from Index (R1) into R0 */
	/* Here, the register value would have B0 set to indicate switch to Thumb mode  */
#if 0
    bic     r0, #0x01                       /* Clear R0[0] since it is used to indicates Thumb mode */
#endif
    ldmfd   sp!, {pc}

/* _arm_ldr_pc_handler
 *      LDR with Rd = PC
 *      On entry:
 *          R0: instruction to be executed
 *          R1: Default Following Instruction Address (PC+4)
 *          R5[3:0]: CPSR condition codes
 *      On exit:
 *          R0: following instruction address
 *          R1, R2, R3, R4, R5: destroyed
 */

_arm_ldr_pc_handler:
    stmfd   sp!, {lr}
    mov     r5, r0                          /* Keep a copy of the instruction in R5 */
    and     r0, r0, #NIBBLE4                /* Register Rn Enum in R0[19:16] */
    lsr     r0, r0, #16                     /* Move Rn Enum to R0[3:0] */
    _regenum2index  r0, r1                  /* Convert Enum into Index in R1 */
    _getdbgregisterfromindex r1, r4         /* Retrieve Register contents from Index (R1) into R4 */
    teq     r0, #REG_PC                     /* Check if it is PC relative */
    addeq   r4, r4, #8                      /* adjust for PC relative (+8) */
    tst     r5, #0x01000000                 /* Pre (1) or Post (0) Indexed */
    beq     _exit_arm_ldr_pc_handler        /* If Post-Indexed, just return value of Rn */
    /* Pre-Indexed */
    ldr     r0, =(NIBBLE2|BYTE0)
    and     r0, r5, r0                      /* 12 bit Immediate value or Shifted Reg operand */
    tst     r5, #0x02000000                 /* Immediate (0) or Register (1) */
    beq     _calc_ldr_pc_offset             /* Immediate value is already in R0 */

_get_shiftedreg_val:
    bl      _arm_rmshifted_val              /* Convert Rm shifted operand into value in R0 */

_calc_ldr_pc_offset:
    tst     r5, #0x00800000                 /* Add (1) or Subtract (0) */
    addne   r4, r4, r0                      /* If Add, R2 = Rn + value */
    subeq   r4, r4, r0                      /* If Sub, R2 = Rn - value */

_exit_arm_ldr_pc_handler:
    mov     r0, r4                          /* Return next instruction address in R0 */
    ldmfd   sp!, {pc}


/* _arm_ldm_pc_handler
 *      LDM {pc}
 *      On entry:
 *          R0: instruction to be executed
 *          R1: Default Following Instruction Address (PC+4)
 *          R5[3:0]: CPSR condition codes
 *      On exit:
 *          R0: following instruction address
 *          R1, R2, R3: destroyed
 *
 *      FIXME: The algorithm from eCos arm_stub.c does not deal with the Pre/Post-Indexed addressing (P) bit.
 */
_arm_ldm_pc_handler:
    stmfd   sp!, {lr}
    and     r3, r0, #0x000F0000             /* Store Rn (Operand 1) Register Enum into R3[19:16] */
    lsr     r3, r3, #16                     /* Shift into R3[3:0] */

_arm_get_Rn_val:
    _regenum2index  r3, r2                  /* Convert Enum into Index in R2 */
    _getdbgregisterfromindex r2, r1         /* Retrieve Register contents from Index (R2) into R1 */
    teq     r3, #REG_PC                     /* Check if it is PC relative */
    addeq   r1, r1, #8                      /* adjust Rn (R1) for PC relative (+8) */

_arm_get_regcount:
    mov     r2, #0                          /* Initialize reg_count (R2) to 0 */
    mov     r3, r0, lsl #16					/* Keep HLFWORD0 containing vector bits in R3[31:16] */
	/* This shortens the checking to a max of 16 iterations, since the PC bit should be set */
1:  movs    r3, r3, lsl #1                  /* count number of '1' bits */
    addcs   r2, r2, #1                      /* increment reg_count (R2) if C Flag set */
    bne     1b                              /* continue until vector is empty */

_arm_check_updown_offset:
    tst     r0, #0x00800000                 /* Check Up (1) or Down (0) */
    addne   r1, r1, r2, lsl #2              /* Ascending: Rn (R1) += reg_count (R2) x 4 */
    subeq   r1, r1, #4                      /* Descending: Rn (R1) -= 4 */
    ldr     r0, [r1]                        /* Retrieve stack content for new PC value */
    ldmfd   sp!, {pc}



/* _arm_b_bl_blx_handler
 *      B, BL or BLX <offset>. Note v4t does not have BLX instr
 *      On entry:
 *          R0: instruction to be executed
 *          R1: Default Following Instruction Address (PC+4)
 *          R5[3:0]: CPSR condition codes
 *      On exit:
 *          R0: following instruction address
 *          R1, R2, R3: destroyed
 */

_arm_b_bl_blx_handler:
    stmfd   sp!, {lr}
#ifndef __ARM6OR7__
	/* armv5t or later, has BLX support */
	mov		r3, r0							/* Copy instruction to R3 */
#endif

_arm_b_bl_blx_get_offset:
    and     r0, r0, #(BYTE2|BYTE1|BYTE0)    /* Encoded Branch offset in R0[23:0] */
    lsl		r0, r0, #(32-24)				/* Shift to R0[31:8] */
    asr		r0, r0, #(32-25)				/* Actual Signed offset = Encode Offset x 2 in R0[25:0] */
	add		r1, r1, #4						/* R1: (PC+4) + 4 */
    add     r0, r0, r1                      /* Calculate Branch Target Address R0: (PC+8) + signed offset */

#ifndef __ARM6OR7__
	/* armv5t or later, has BLX support */
	and		r2, r3, #0xFE000000				/* Mask out Condition Code and Opcode */
	teq		r2, #0xFA000000					/* Look for BLX */
	bne		_exit_arm_b_bl_blx_handler		/* No, it is a B/BL instruction */
	tst		r3, #0x01000000					/* H bit for Thumb Halfword Address */
	orrne	r0, r0, #0x02					/* Set Halfword Address R0[1] */
    orr   	r0, r0, #0x01           		/* Set R0[0] since it is used to indicates Thumb mode */
#endif

_exit_arm_b_bl_blx_handler:
    ldmfd   sp!, {pc}

/* _arm_coproc_swi_handler
 *      SVC (SWI) or Coprocessor instruction
 *      On entry:
 *          R0: instruction to be executed
 *          R1: Default Following Instruction Address (PC+4)
 *          R5[3:0]: CPSR condition codes
 *      On exit:
 *          R0: following instruction address
 *          R1, R2: destroyed
 */

_arm_coproc_swi_handler:
    and     r2, r0, #0x0F000000
    teq     r2, #0x0F000000                 /* SVC (SWI) instruction */

_arm_swi_instr:
    ldreq   r0, =SVC_VECTOR                 /* Return SVC Vector Address */
    beq     _exit_arm_coproc_swi_handler

_arm_coproc_instr:
    mov     r0, r1                          /* Use default Following Instruction Address */
_exit_arm_coproc_swi_handler:
	bx	    lr


/* _thumb_bx_blx_handler
 *      BX or BLX Handler. Note: b7 (H1) is not matched in the mask (should be 0); armv4t does not support BLX.
 *      On entry:
 *          R0: instruction to be executed
 *          R1: Default Following Instruction Address (PC+2)
 *          R5[3:0]: CPSR condition codes
 *      On exit:
 *          R0: following instruction address (B0 set to indicate Thumb mode)
 *          R1: destroyed
 */
_thumb_bx_blx_handler:
    stmfd   sp!, {lr}
    and     r0, r0, #0x78                	/* Register Rn Enum in R0[6:3] (Hi-Reg indicated by B6) */
    mov		r0, r0, lsr #3					/* Shift Rn Enum to R0[3:0] */
    _regenum2index  r0, r1                  /* Convert Enum into Index in R1 */
    _getdbgregisterfromindex r1, r0         /* Retrieve Register contents from Index (R1) into R0 */
	/* Here, the register value would have R0[0] set to indicate switch to Thumb mode  */
    ldmfd   sp!, {pc}

/* _thumb_poppc_handler
 *     PUSH/POP, specifically POP {Rlist,PC}
 *      On entry:
 *          R0: instruction to be executed
 *          R1: Default Following Instruction Address (PC+2)
 *          R5[3:0]: CPSR condition codes
 *      On exit:
 *          R0: following instruction address (B0 set to indicate Thumb mode)
 *          R1: destroyed
 */
_thumb_poppc_handler:
    stmfd   sp!, {lr}

_thumb_get_SP_val:
	mov		r2, #DBGSTACK_USERSP_INDEX		/* Set Register Index (R2) to SP Index */
    _getdbgregisterfromindex r2, r1         /* Retrieve SP contents from Index (R2) into R1 */

_thumb_get_regcount:
    mov     r2, #0                          /* Initialize reg_count (R2) to 0 */
    mov     r3, r0, lsl #24					/* Keep BYTE0 containing vector bits in R3[31:24] */
	/* This shortens the checking to a max of 8 iterations */
1:  movs    r3, r3, lsl #1                  /* count number of '1' bits */
    addcs   r2, r2, #1                      /* increment reg_count (R2) if C Flag set */
	add		r1, r1, #4						/* Walk the stack to locate the PUSHed LR (POP PC) value */
    bne     1b                              /* continue until vector is empty */
	ldr		r0, [r1]						/* Retrieve new PC value */
#if 0
	/* PC Value should have B0 set */
    orr     r0, r0, #0x01           		/* Force R0[0] since it is used to indicates Thumb mode */
#endif
    ldmfd   sp!, {pc}


/* _thumb_bcond_swi_handler
 *      B<cond> or SWI (SVC)
 *      On entry:
 *          R0: instruction to be executed
 *          R1: Default Following Instruction Address (PC+2)
 * 			R5[3:0]: CPSR condition codes
 *      On exit:
 *          R0: following instruction address (B0 set to indicate Thumb mode)
 *          R1-R6: destroyed
 */
_thumb_bcond_swi_handler:
	mov		r4, r0					        /* Keep instruction in R4 */
    and     r2, r0, #0x0F00					/* Keep Condition Code R2[11:8] */
    teq     r2, #0x0F00 	                /* SVC (SWI) instruction */
_thumb_swi_instr:
    ldreq   r0, =SVC_VECTOR                 /* Return SVC Vector Address */
    beq     _exit_thumb_bcond_swi_handler	/* Switch to ARM mode for SVC */
_thum_bcond_unused_instr:
    teq		r2, #0x0E00
    moveq   r0, r6                          /* False (don't execute), so use Default Following Instruction Address */
    beq     _exit_thumb_bcond_instr

_thumb_bcond_instr:
	mov     r6, r1                          /* Store Default Following Instruction Address in R6 */
	lsl		r0, r2, #(32-12)		        /* Shift condition code in R2[11:8] to R0[31:28] to match ARM cond-code format */
	bl		_dbg_check_arm_condcode	        /* Use ARM condition code checking routine to test (R4, R6 unchanged) */
    teq     r0, #FALSE
    moveq   r0, r6                          /* False (don't execute), so use Default Following Instruction Address */
    beq     _exit_thumb_bcond_instr

_thumb_calc_bcond_offset:
    lsl		r0, r4, #(32-8)					/* Shift 8-bit offset in R4[7:0] to R0[31:24] */
    asr		r0, r0, #(32-9)					/* Convert into 9-bit signed offset in R0[8:0] */
    add		r0, r6, r0						/* PC+2 + signed offset */
    add		r0, r0, #2						/* PC+4 + signed offset */
_exit_thumb_bcond_instr:
    orr     r0, r0, #0x01                   /* Set R0[0] since it is used to indicates Thumb mode */
_exit_thumb_bcond_swi_handler:
	bx	lr

/* _thumb_b_handler
 *      B
 *      On entry:
 *          R0: instruction to be executed
 *          R1: Default Following Instruction Address (PC+2)
 *          R5[3:0]: CPSR condition codes
 *      On exit:
 *          R0: following instruction address (B0 set to indicate Thumb mode)
 *          R1: destroyed
 *		Note: The signed offset is 12-bits (encoded value x 2)
 */
_thumb_b_handler:
    stmfd   sp!, {lr}
    lsl		r0, r0, #(32-11)		/* Shift 11-bit offset in R0[10:0] to R0[31:21] */
    asr		r0, r0, #(32-12)		/* Convert into 12-bit signed offset in R0[11:0] */
    add		r0, r1, r0				/* PC+2 + signed offset */
    add		r0, r0, #2				/* PC+4 + signed offset */
    orr     r0, r0, #0x01           /* Set R0[0] since it is used to indicates Thumb mode */
    ldmfd   sp!, {pc}


/* _thumb_long_bl_blx_handler
 *      Long BL or BLX (4 bytes) Note: b11 (H) indicates 1st or 2nd instr; armv4t does not support BLX.
 *      On entry:
 *          R0: instruction to be executed
 *          R1: Default Following Instruction Address (PC+2)
 *          R5[3:0]: CPSR condition codes
 *      On exit:
 *          R0: following instruction address (B0 set to indicate Thumb mode)
 *          R1, R2, R3: destroyed
 *		Note: The BL instruction (0xFxxx) should be in pairs (Dual 16-bit instructions).
 *		The first instruction should have (H=0) to indicate the upper 11 bits of the encoded offset
 *		The second instruction should have (H=1) to indicate the lower 11 bits of the encoded offset
 *		The signed offset is 23 bits (encoded value x 2)
 *
 *		Note2: The BLX instruction (0xExxx) encodes the first instruciton using BL (0xFxxx) with H=0,
 *		while the second instruction has a different opcode value (0xExxx), with H=1.
 *		BLX is only used to switch to an ARM target.
 */
_thumb_long_bl_blx_handler:
    stmfd   sp!, {lr}
	tst		r0, #0x0800					/* Check H bit */
	bne		_return_default_thumb_following_instr	/* H=1 as first instruction shouldn't happen */

_thumb_is_1st_bl_blx_instruction:
    lsl		r0, r0, #(32-11)			/* Shift 11-bit offset in R0[10:0] to R0[31:21] */
    asr		r0, r0, #(32-23)			/* Convert into 12-bit signed offset in R0[22:12] */
    ldrh	r3, [r1]					/* Get second instruction in pair into R3 */
	tst		r3, #0x0800					/* Check H bit */
	beq		_exit_thumb_long_bl_blx_handler	/* H=0 as second instruction shouldn't happen */

    lsl		r2, r3, #(32-11)			/* Shift 11-bit offset in R3[10:0] to R2[31:21] */
    lsr		r2, r2, #(32-12)			/* Convert into 12-bit unsigned offset in R2[11:0] */
	orr		r0, r0, r2					/* Combine offsets */
    add		r0, r1, r0					/* PC+2 + signed offset */
    add		r0, r0, #2					/* PC+4 + signed offset */

_thumb_is_2nd_bl_blx_instruction:
    and		r3, r3, #0x0F000			/* Keep instruction opcode in R3 */

    cmp		r3, #0x0F000				/* Look for BL */
    orreq   r0, r0, #0x01           	/* Match, set R0[0] since it is used to indicates Thumb mode */
	beq		_exit_thumb_long_bl_blx_handler

#ifndef __ARM6OR7__
	/* v5t or higher architecture */
	cmp		r3, #0x0E000				/* Look for BLX */
	biceq	r0, r0, #0x03				/* Match, Force ARM address */
    beq		_exit_thumb_long_bl_blx_handler
#endif

_return_default_thumb_following_instr:
	mov	r0, r1							/* Return default Following Instruction Address */

_exit_thumb_long_bl_blx_handler:
    ldmfd   sp!, {pc}


/****************************************************************************
 *
 * Breakpoint Manipulation Routines
 *
 ****************************************************************************/
/* _dbg_find_breakpoint_slot
 *      Find the matching Breakpoint Slot.
 *      This is both used to find empty slots (pass R0=0x0000) or
 *      occupied slots (pass R0=<brkpt addr>)
 *
 *  On Entry:
 *      R0: Breakpoint Address
 *  On Exit:
 *      R0: Matching Index (-1: not found)
 *
 *  NOTE: This routine performs exact match, i.e., breakpoint address MUST be configured
 *        for ARM or Thumb (bit 0 clear/set) as appropriate
 */

_dbg_find_breakpoint_slot:
    stmfd   sp!, {r1,r2,r3, lr}
    mov     r1, #1                      /* Only consider Breakpoints 1-7 */
    ldr     r3, =__breakpoints_num__
1:
    _index2bkptindex_addr   r1, r2      /* Calculate Breakpoint Entry Address */
    ldr     r2, [r2]                    /* Get actual breakpoint entry (instruction address) */
    cmp     r0, r2
    beq     _found_breakpoint_slot
    add     r1, r1, #1                  /* no match, check next */
    cmp     r1, r3
    blo     1b                          /* continue checking only if we don't exceed __breakpoints_num__ */

_notfound_breakpoint_slot:
    mov     r1, #CMD_BKPT_NOTFOUND
_found_breakpoint_slot:
    mov     r0, r1                      /* Return value in R0 */
    ldmfd   sp!, {r1,r2,r3, pc}

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

