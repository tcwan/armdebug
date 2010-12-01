/** @file _c_arm_macros.h
 *  @brief Define macros to support shared C and ASM headers
 *
 */

/* Copyright (C) 2007,2009 the NxOS developers
 * Thanks to Bartli (forum post @ embdev.net ARM programming with GCC/GNU tools forum)
 *
 * See AUTHORS for a full list of the developers.
 *
 * Redistribution of this file is permitted under
 * the terms of the GNU Public License (GPL) version 2.
 */

#ifndef __NXOS_BASE_C_ARM_MACROS__
#define __NXOS_BASE_C_ARM_MACROS__

#ifdef __ASSEMBLY__

#define NULL   0x0	    /* Stick the definition here instead of making types.h messy */
#define FALSE   0
#define TRUE    ~FALSE

#define TYPEDEF @
#define FUNCDEF @

  .set last_enum_value, 0
  .macro enum_val name
  .equiv \name, last_enum_value
  .set last_enum_value, last_enum_value + 1
  .endm

#define ENUM_BEGIN  .set last_enum_value, 0

#define ENUM_VAL(name) enum_val name
#define ENUM_VALASSIGN(name, value)            \
  .set last_enum_value, value                 ;\
  enum_val name
#define ENUM_END(enum_name)

/** Macro to define driver ioctl table
 *  First five table entries are predefined
 *  0: init
 *  1: shutdown
 *  2: sleep
 *  3: wakeup
 *  4: poll
 *
 */
#define DRIVER_IOCTL(driver)     \
/* Dummy sleep and wakeup routines for now */       ;\
  .set driver ## _sleep, NULL  ;\
  .set driver ## _wakeup, NULL ;\
  .set driver ## _poll, NULL ;\
.data                           ;\
  .align 4                      ;\
  .global driver ## _ioctl      ;\
driver ## _ioctl:               ;\
  .word   driver ## _init       ;\
  .word   driver ## _shutdown   ;\
  .word   driver ## _sleep      ;\
  .word   driver ## _wakeup     ;\
  .word   driver ## _poll       ;\
  .set num_ ## driver ## _cmds, 5

/** Macro to define additional driver ioctl commands
 *  Be careful to follow the sequence defined for the CMD enums
 *  The first CMD should have an enum value of 5
 *
 */
#define DRIVER_CMD(driver, cmd)  \
  .word   driver ## _ ## cmd    ;\
  .set num_ ## driver ## _cmds, num_ ## driver ## _cmds + 1

/** Macro to define driver state
 *  MUST BE DEFINED AFTER DRIVER_IOCTL section
 *  @param driver name of driver
 *  @param driverenum enum value of driver (in [31:25])
 *
 *  The number of commands for driver (in [24:17]) -- derived from num_driver_cmds
 *
 *  Format of driver_state table:
 *     driver signature (driverenum << 24 | numcommands << 16)
 *     driver parameters (per device instance)
 */
#define DRIVER_STATE(driver, driverenum) \
.bss                        ;\
  .global driver ## _state  ;\
driver ## _state:           ;\
  .set driver ## _signature, (driverenum << 24) | (num_ ## driver ## _cmds << 16) ;\
  .word NULL	/* driver_signature */


/** Macro to define actual driver routine in .S
 *  On entry:
 *    r0 - address of driver_state
 *    r1-r3 - parameters (variable)
 *    r12 - number of parameters (IPC scratch register)
 *    Stack - parameters (variable)
 */
#define DRIVER_ROUTINE(driver, cmd) \
  .global driver ## _ ## cmd ##    ;\
driver ## _ ## cmd ## :

#else
/** Macro to control typedef generation
 *
 */
#define TYPEDEF typedef

/** Macro to control extern generation
 *
 */
#ifndef FUNCDEF
#define FUNCDEF extern
#endif

/** Macro to control typedef enum generation
 *
 */
#define ENUM_BEGIN typedef enum {

/** Macro to specify enum instance (auto value assignment)
 *
 */
#define ENUM_VAL(name) name,

/** Macro to control enum specification and value assignment
*
*/
#define ENUM_VALASSIGN(name, value) name = value,

/** Macro to control enum named type generation
 *
 */
#define ENUM_END(enum_name) } enum_name;

#endif

ENUM_BEGIN
ENUM_VAL(INIT)             /**< Driver Init Routine. */
ENUM_VAL(SHUTDOWN)         /**< Driver Shutdown Routine. */
ENUM_VAL(SLEEP)            /**< Driver Sleep Routine. */
ENUM_VAL(WAKEUP)           /**< Driver Wakeup Routine. */
ENUM_VAL(POLL)             /**< Driver Poll Routine. */
ENUM_END(nx_driver_default_cmd)


#endif /* __NXOS_BASE_C_ARM_MACROS__ */
