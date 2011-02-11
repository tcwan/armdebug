/** @file debug_runloop.S
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
 * before entering the Platform Run Loop. This switches processing over to the
 * Debugger Run Loop which will wait for the GDB command to Go/Step/Cont before
 * returning control to the Platform Run Loop.
 *
 * Subsequently, Debugger Run Loop will be triggered by Breakpoints, or
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

    .global dbg__runloopTasks


#ifdef __NXOS__
/* NxOS Run Loop */
dbg__runloopTasks:
/* Currently, there's nothing that needs to be done in the NxOS Run Loop */
    bx      lr

#else
/* NXT Firmware Run Loop */
    .extern cCommCtrl

dbg__runloopTasks:
    /* FIXME: Add necessary cXXXCtrl calls here */
    bl      cCommCtrl
    /* OSWatchdogWrite is a NULL function in the NXT Firmware?! */
    bx      lr
#endif
