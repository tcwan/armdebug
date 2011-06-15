/** @file debug_runlooptasks.S
 *  @brief GDB Server platform Run Loop
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

/*
 * This file contains platform specific code.
 * This include ABORT Mode Debugger Run Loop operation,
 * as well as Debugger Interfacing code to the platform code.
 */

/*
 * The Debugger has to implement a Run Loop in ABORT mode
 * since the hardware is still running. Consequently,
 * the communications subsystems such as USB (and Bluetooth?)
 * which is used to communicate with the Host needs to be
 * serviced in order for actual data transmission and reception
 * to take place. Currently we're reusing the platform's
 * communication routines to do the actual tx/rx, so it means
 * that it is not possible to set breakpoints in those modules.
 * In addition, since the platform communication modules may
 * handle other tasks, it is currently possible to enter an
 * indeterminate state where certain communication messages trigger
 * a platform response which cannot be handled by the Debugger Run Loop.
 * The alternative is to implement our own communications routines, but
 * that will take even more code.
 *
 * FIXME: It may become necessary to hack the platform communications
 * routines to detect that we're in the Debugger Run Loop and not the
 * normal run loop to avoid system crashes, but the current goal is to
 * have as minimal changes to the platform code as possible.
 *
 * Since there are two Run Loops for the platform, the way in which
 * they interact is as follows:
 *
 * [Platform Run Loop]  - DBG_INIT/ GDB Cmd/ BKPT ->  [Debugger Run Loop]
 *                    \ <------ GO/ STEP/ CONT ----- /
 *        ...                                                 ...
 *        ...                                         Handle GDB Cmd/Resp
 *        ...                                                 ...
 *   {normal runloop                                  {communications /
 *    processing}                                      watchdog routines}
 * ^-------v                                                      v-------^
 *
 * The Platform will invoke dbg__bkpt_init() after hardware and system initialization,
 * before entering the Platform Run Loop. This configures the Debugger, but does not
 * invoke the Debugger Run Loop unless a Manual Breakpoint is found in the platform code.
 *
 * Subsequently, the Debugger Run Loop will be triggered by Breakpoints, or
 * when the communications subsystem receives a GDB Command.
 *
 * The Debugger Run Loop is actually dbg__bkpt_waitCMD(), this file contains
 * the Run Loop Tasks which needs to be invoked periodically by the Run Loop,
 * to minimize the coupling between the ARMDEBUG modules and the Platform.
 *
 * Note: The Debugger Run Loop does not handle Hardware Shutdown, it is
 * assumed that we wouldn't need to do so in Debug Mode.
 *
 */
#define __ASSEMBLY__

#include "debug_internals.h"
#include "debug_macros.h"

	.code 32
	.align 4
    .global dbg__runloopTasks


#ifdef __NXOS__
/****************************************************************************
 *
 * NxOS Run Loop
 *
 ****************************************************************************/
dbg__runloopTasks:
/* Currently, there's nothing that needs to be done in the NxOS Run Loop */
    bx      lr

#else
/****************************************************************************
 *
 * NXT Firmware Run Loop
 *
 ****************************************************************************/
    .extern cCommCtrl

dbg__runloopTasks:
    push    {lr}
    /* FIXME: Add necessary cXXXCtrl calls here */
    bl      cCommCtrl
    /* OSWatchdogWrite is a NULL function in the NXT Firmware?! */
    pop     {pc}
#endif


#ifdef __NXOS__
/****************************************************************************
 *
 * GDB Debugger Invocation Routine for NxOS
 *
 ****************************************************************************/
	.code 32
	.align 4

	.extern dbg__install_singlestep
	.extern dbg__activate_singlestep
	.extern irq_stack_frame_address
	.global nxos__handleDebug
/* nxos__handleDebug
 * 		Prepare to switch to Debug Mode
 * int nxos__handleDebug(unsigned char *msg, comm_chan_t channel, long len);
 *
 * This routine is called from NxOS Fantom library to setup
 * Single Step Breakpoint in preparation for Debugger invocation if we're in
 * normal execution mode.
 *
 * It returns to complete the IRQ handling normally, after which the single
 * step breakpoint will be triggered, and the incoming GDB message will then
 * be processed in the dbg__bkpt_waitCMD() loop.
 *
 * If we're in Debugger Mode already, then just return and let the
 * dbg__bkpt_waitCMD() loop handle it normally.
 *
 * If we're operating in normal NxOS mode, return True (!0)
 * If we're already in Debugger Mode, return False (0)
 */
nxos__handleDebug:
		push {r4, r5, lr}
		/* When called, NxOS is in Supervisor mode (MODE_SVC), called from nx__irq_handler()
		 * via fantom_filter_packet().
		 *
		 * The IRQ Stack contains the LR and SPSR from the topmost interrupted task
		 * (NxOS supports nested IRQs)
		 */
		/* R0-R2 has received message related parameters */

        /* Switch to IRQ mode get SPSR to find out how we were called */
        msr 	cpsr_c, #(MODE_IRQ | CPSR_FIQ | CPSR_IRQ)
 		mrs		r3, spsr				/* Copy SPSR to r3 */
        msr 	cpsr_c, #(MODE_SVC)		/* Return to SVC mode, restore interrupts */
 		and 	r3, r3, #CPSR_MODE		/* Get previous mode */
 		teq		r3, #MODE_ABT			/* Are we in Abort (Debug) mode? */
 		moveq	r0, #FALSE
 		beq		exit_nxos__handleDebug	/* Yes, return False */

_nxos_switch2debug:
		/* Retrieve ISR Return Address */
        ldr     r3, =irq_stack_frame_address
        ldmdb   r3, {r4,r5}				/* R4: SPSR, R5: LR */
 		tst		r4, #CPSR_THUMB			/* Check for Thumb Mode */
		mov		r1, r5					/* R5 has interrupted instruction address, setup Single Step Breakpoint for it */
 		orrne	r1, r1, #1				/* Configure for Thumb Single Step Breakpoint */
	    bl  	dbg__install_singlestep /* Setup Single Step, next instruction address returned in r1 */
		bl		dbg__activate_singlestep
		mov	    r0, #TRUE				/* We're going to switch to Debug Mode (via Single Step Breakpoint) */
exit_nxos__handleDebug:
		pop	  {r4, r5, lr}
		mov	  r1, lr					/* Safe code: Thumb mode can't access lr */
    	bx    r1						/* In case we have Interworking from different caller mode */

#else

/****************************************************************************
 *
 * GDB Debugger Invocation Routine for NXT Firmware
 *
 ****************************************************************************/
    .code 16
    .align 2

    .extern dbg__copyNxtDebugMsg
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
