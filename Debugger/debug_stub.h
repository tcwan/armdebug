/** @file debug_stub.h
 *  @brief Shared C/ASM header file for debugger stub
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

#ifndef __DEBUG_STUB_H__
#define __DEBUG_STUB_H__

#include "_c_arm_macros.h"


/** @addtogroup debugger */
/*@{*/


/* Declarations go here. */
/** @name Debug Message Constants.
 *
 * Debug Message Values
 */
/*@{*/

/*
 * USB Buffer Sizes:    Ctrl    Intr    Iso     Bulk
 * Full Speed Device    64      64      1023    64
 * High Speed Device    64      1024    1024    512
 */

#define USB_BUFSIZE     64
#define USB_NUMDATAPKTS 3                               /* For packet transfers */

#define MSGBUF_SIZE     (USB_BUFSIZE*USB_NUMDATAPKTS)   /* Debug Message Buffer Size, 64 x 3 = 192 chars = ~90 bytes */
#define MSGBUF_STARTCHAR '$'
#define MSGBUF_ACKCHAR   '+'
#define MSGBUF_NAKCHAR   '-'
#define MSGBUF_ERRCHAR   'E'
#define MSGBUF_SIGCHAR   'S'
#define MSGBUF_CPSRREG   '!'
#define MSGBUF_SETCHAR   '='
#define MSGBUF_CMDINDEX_OUTOFRANGE_VAL     -1

/*@}*/
/** @name Debug Stack Constants.
 *
 * Debug Stack Manipulation Values
 */
/*@{*/
#define DBGSTACK_USERCPSR_OFFSET   (DBGSTACK_USERCPSR_INDEX-DBGSTACK_USERREG_INDEX)       /* = -1, offset for calculating Debug Stack index */
#define DBGSTACK_USERCPSR_INDEX 1                /* User CPSR (SPSR_UNDEF) is at index 1 from bottom of Debug Stack */
#define DBGSTACK_USERREG_INDEX  2                /* R0 starts at index 2 from bottom of Debug Stack */
/*@}*/

/** @name Bitmask Definitions.
 *
 * Various Bitmasks used for data manipulation.
 */
/*@{*/
#define BKPT_STATE_THUMB_FLAG	0x01             /* Flag Thumb Breakpoint */
#define ASCII_LOWER2UPPER_MASK	0x20             /* ASCII Conversion bitmask */
#define NIBBLE0	0x0000000F                       /* Nibble 0 word(3:0) */
#define NIBBLE1	0x000000F0                       /* Nibble 1 word(7:4) */
#define NIBBLE2	0x00000F00                       /* Nibble 2 word(11:8) */
#define NIBBLE3	0x0000F000                       /* Nibble 3 word(15:12) */
#define NIBBLE4	0x000F0000                       /* Nibble 4 word(19:16) */
#define NIBBLE5	0x00F00000                       /* Nibble 5 word(23:20) */
#define NIBBLE6	0x0F000000                       /* Nibble 6 word(27:24) */
#define NIBBLE7	0xF0000000                       /* Nibble 7 word(31:28) */
#define BYTE0	0x000000FF                       /* Byte 0 word(7:0) */
#define BYTE1	0x0000FF00                       /* Byte 1 word(15:8) */
#define BYTE2	0x00FF0000                       /* Byte 2 word(23:16) */
#define BYTE3	0xFF000000                       /* Byte 3 word(31:24) */
#define HLFWRD0	0x0000FFFF                       /* Halfword 0 word(15:0) */
#define HLFWRD1	0xFFFF0000                       /* Halfword 0 word(31:16) */
/*@}*/

/** @name CPSR Bit Definitions.
 *
 * Various Bit definitions for accessing the CPSR register.
 */
/*@{*/
#define CPSR_THUMB      0x00000020
#define CPSR_FIQ        0x00000040
#define CPSR_IRQ        0x00000080

/*@}*/

/** @name BKPT suppport constants
 *
 * ARM and Thumb Breakpoint Instructions.
 */
/*@{*/
#define BKPT32_INSTR   		0xE1200070	/* ARM BKPT instruction */
#define BKPT32_ENUM_MASK	0x000FFF0F	/* ARM BKPT Enum Mask */
#define BKPT32_AUTO_BKPT	0x00080000	/* ARM BKPT Auto-Step Flag (for CONT support) */
#define BKPT32_MANUAL_BKPT	0x0007FF0F	/* Manually inserted ARM Breakpoint */

#define BKPT16_INSTR   		0xBE00		/* Thumb BKPT instruction */
#define BKPT16_ENUM_MASK	0x00FF		/* Thumb BKPT Enum Mask */
#define BKPT16_AUTO_BKPT	0x0080		/* Thumb BKPT Auto-Step Flag (for CONT support) */
#define BKPT16_MANUAL_BKPT	0x007F		/* Manually inserted Thumb Breakpoint */
/*@}*/

/** Debugger State Enums
 *
 * Debugger State.
 * The enums must be consecutive, starting from 0
 */
ENUM_BEGIN
ENUM_VALASSIGN(DBG_RESET, 0)  /**< Initial State. */
ENUM_VAL(DBG_INIT)            /**< Debugger Initialized. */
ENUM_VAL(DBG_MANUAL_BKPT_ARM)     /**< Manual ARM Breakpoint. */
ENUM_VAL(DBG_NORMAL_BKPT_ARM)     /**< Normal ARM Breakpoint (Single Step, Normal). */
ENUM_VAL(DBG_MANUAL_BKPT_THUMB)     /**< Manual Thumb Breakpoint. */
ENUM_VAL(DBG_NORMAL_BKPT_THUMB)     /**< Normal Thumb Breakpoint (Single Step, Normal). */
ENUM_END(dbg_state_t)

/** Debugger Message Error Enums
 *
 * Debugger Error Message Enums.
 * The enums must be consecutive, starting from 1
 */
ENUM_BEGIN
ENUM_VALASSIGN(MSG_ERRIMPL, 0)    /**< Stub (not implemented) Error. */
ENUM_VAL(MSG_ERRCHKSUM)           /**< Checksum Error. */
ENUM_VAL(MSG_ERRFORMAT)           /**< Message Format Error. */
ENUM_VAL(MSG_UNKNOWNCMD)          /**< Unrecognized Command Error. */
ENUM_VAL(MSG_UNKNOWNPARAM)        /**< Unrecognized Parameter Error. */
ENUM_END(dbg_msg_errno)


#ifndef __ASSEMBLY__

/* Define C stuff */
/** @defgroup debug_public */
/*@{*/


/** Initialize Debugger.
 * 		Equivalent to GDB set_debug_traps() routine
 */
FUNCDEF void dbg__bkpt_init(void);

/** Debugger Handler Routine (called by Exception Handler Trap).
 * 		Equivalent to GDB handle_exception() routine
 */
FUNCDEF void dbg__bkpt_handler(void);

/** dbg_breakpoint_arm.
 * 		Equivalent to GDB breakpoint() routine for ARM code
 */
/* FUNCDEF */ inline void dbg_breakpoint_arm(void) { asm volatile (".word BKPT32_INSTR | BKPT32_MANUAL_BKPT") }

/** dbg_breakpoint_thumb.
 * 		Equivalent to GDB breakpoint() routine for Thumb code
 */
/* FUNCDEF */ inline void dbg_breakpoint_thumb(void) { asm volatile (".hword BKPT16_INSTR | BKPT16_MANUAL_BKPT") }

/*@}*/

#else
/* Define Assembly stuff */

/* dbg__bkpt_arm
 * 		GDB breakpoint() for ARM mode
 */
 	.macro dbg__bkpt_arm
 	.word	(BKPT32_INSTR | BKPT32_MANUAL_BKPT)
 	.endm

/* dbg__bkpt_arm
 * 		GDB breakpoint() for Thumb mode
 */
 	.macro dbg__bkpt_thumb
 	.hword	(BKPT16_INSTR | BKPT16_MANUAL_BKPT)
 	.endm

#endif
 /*@}*/

#endif /* __DEBUG_STUB_H__ */
