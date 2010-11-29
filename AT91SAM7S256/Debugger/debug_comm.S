
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

.data
.align 4

hex2char_lut:
	.ascii	"0123456789ABCDEF"

/* Macros
 */

/* _asciiz
 *		Terminate string given string buffer pointer in \addrptr
 *		reg is used as a scratch register (destroyed)
 *
 */
	.macro	_asciiz	reg, strptr
	mov		\reg, #0					/* NULL character */
	strb		\reg, [\strptr]				/* Terminate ASCIIZ string */
 	.endm

/* _hex2char_lut
 *		Internal routine to intialize the LUT address pointer
 */
	.macro _hex2char_lut	addrptr
	ldr		\addrptr, =hex2char_lut
	.endm

/* _hex2char_cont
 *		Internal routine that assumes that the LUT has been loaded.
 *		This macro accepts a byte sized hex value as a parameter register(7:0) and returns the
 *		ASCII equivalent in in the same register(7:0)
 *		The second parameter is the LUT address pointer register to use (assumed to be initialized)
 *		WARNING: Assumes that the value in register is sanity checked before invoking macro
 */
	.macro	_hex2char_cont	reg, addrptr
	ldrb	\reg, [\addrptr, \reg]
	.endm

/* _hex2char
 *		This macro accepts a byte sized hex value as a parameter register(7:0) and returns the
 *		ASCII equivalent in in the same register(7:0)
 *		The second parameter is the LUT address pointer register to use (register content is destroyed)
 *		WARNING: Assumes that the value in register is sanity checked before invoking macro
 */
	.macro	_hex2char	reg, addrptr
	_hex2char_lut	\addrptr
	_hex2char_cont	\reg, \addrptr
	.endm

/* _char2hex
 *		This macro accepts an ASCII char as a parameter register(7:0) and returns the
 *		equivalent byte sized hex value in in the same register(7:0)
 *		WARNING: Assumes that the char in register is a valid hex char before invoking macro
 */
	.macro	_char2hex	reg
	cmp	\reg, #'A'									/* If Alpha */
	bichs	\reg, \reg, #ASCII_LOWER2UPPER_MASK		/* Convert to Uppercase */
	subhs	\reg, \reg, #7							/* Adjustment to allow for subtraction with 0x30 */
	sub		\reg, \reg, #0x30						/* get final hex value */
	.endm


.code 32
.text
.align 	4


/* Utility Routines
 */

/* hex2char
 *		This routine accepts a byte sized hex value in R0(7:0) and returns the
 *		ASCII equivalent in R0(7:0)
 */
	.global	hex2char

hex2char:
	stmfd	sp!, {r1,lr}
	and		r0, #0x000F			/* make sure that input is sane */
	_hex2char	r0, r1
	ldmfd	sp!, {r1,pc}

/* char2hex
 *		This routine accepts an ASCII character in R0(7:0) and returns the
 *		equivalent byte sized hex value in R0(7:0)
 */
	.global	char2hex

char2hex:
	and		r0, #0x00FF			/* make sure that input is sane */
	cmp		r0, #'0'
	blo		exit_char2hex
	cmp		r0, #'F'
	bhi		exit_char2hex
	_char2hex	r0
exit_char2hex:
	bx		lr

/* byte2ascii_cont
 *		This routine accepts a byte value in R0(7:0), and a ASCII buffer pointer in R1,
 *		and stores the ASCII equivalent byte value in the buffer pointed to by R1.
 *		Note: On return, R1 points to next empty char slot in buffer (i.e., R1 is modified)
 *			  and R0 is destroyed.
 */
byte2ascii_cont:
	stmfd	sp!, {r2,r3,r4, lr}
	mov		r2, r0, lsl #24			/* Keep copy of input byte value R0(7:0), shifted to MSB R2(31:24) */
	mov		r4, #2					/* Loop counter */
	_hex2char_lut	r3				/* initialize LUT pointer */
1:	mov		r0, r2, ror #28			/* Rotate MSNibble R2(31:28) into LSNibble position R0(3:0) */
	and		r0, r0, #NIBBLE0		/* Mask out everything else */
	_hex2char_cont	r0, r3			/* Convert nibble to ASCII char */
	strb	r0, [r1], #1
	subs	r4, r4, #1				/* decrement loop counter */
	bne		1b
	ldmfd	sp!, {r2,r3,r4, pc}

/* byte2ascii
 *		This routine accepts a byte value in R0(7:0), and a ASCII buffer pointer in R1,
 *		and stores the ASCII equivalent byte value in the buffer pointed to by R1.
 *		Note: On return, R1 points to the end of the ASCIIZ string (i.e. NULL character)
 */
	.global	byte2ascii

byte2ascii:
	stmfd	sp!, {r1, lr}			/* Keep ASCII buffer pointer */
	and		r0, #BYTE0				/* sanitize input */
	bl		byte2ascii_cont
	_asciiz	r0, r1
	ldmfd	sp!, {r0, pc}			/* return string pointer in R0 */

/* halfword2ascii
 *		This routine accepts a halfword value in R0(15:0), and a ASCII buffer pointer in R1,
 *		and returns the ASCIIZ equivalent byte value in the buffer pointed to by R0.
 *		Note: On return, R1 points to the end of the ASCIIZ string (i.e. NULL character)
 */
	.global	halfword2ascii
halfword2ascii:
	stmfd	sp!, {r1,r2,r3, lr}		/* Keep ASCII buffer pointer */
	mov		r2, r0, lsl #16			/* copy of input halfword value R0(15:0), shifted to MSH R2(31:16) */
	mov		r3, #2					/* Loop Counter */
	b		_conv_byte2ascii		/* goto Byte conversion loop */

/* word2ascii
 *		This routine accepts a word value in R0(31:0), and a ASCII buffer pointer in R1,
 *		and returns the ASCIIZ equivalent byte value in the buffer pointed to by R0.
 *		Note: On return, R1 points to the end of the ASCIIZ string (i.e. NULL character)
 */
	.global	word2ascii
word2ascii:
	stmfd	sp!, {r1,r2,r3, lr}		/* Keep ASCII buffer pointer */
	mov		r2, r0					/* copy of input word value R0(31:0) */
	mov		r3, #4					/* Loop Counter */

	/* Fall through to byte coversion loop */

_conv_byte2ascii:
	mov		r0, r2, ror #24			/* Rotate MSB R2(31:24) into LSB position R0(7:0) */
	and		r0, #BYTE0			/* Mask out everything else */
	bl		byte2ascii_cont
	subs	r3, r3, #1
	bne		_conv_byte2ascii
	_asciiz	r0, r1
	ldmfd	sp!, {r0,r2,r3, pc}


/* ascii2byte
 *		This routine accepts an ASCII buffer pointer in R0,
 *		and returns the byte value in R0(7:0).
 *		Note: On return, R1 points to the ASCII buffer location after the current 2 chars.
 *		WARNING: This routine assumes that the input buffer was sanitized and contains valid Hex chars,
 *				 otherwise it will return invalid results.
 */
	.global	ascii2byte

ascii2byte:
	stmfd	sp!, {r2,r3, lr}
	mov		r3, #2					/* Loop counter */
	b		_conv_ascii2byte

/* ascii2halfword
 *		This routine accepts an ASCII buffer pointer in R0,
 *		and returns the word value in R0(15:0).
 *		Note: On return, R1 points to the ASCII buffer location after the current 4 chars.
 *		WARNING: This routine assumes that the input buffer was sanitized and contains valid Hex chars,
 *				 otherwise it will return invalid results.
 */
	.global	ascii2halfword

ascii2halfword:
	stmfd	sp!, {r2,r3, lr}
	mov		r3, #4					/* Loop counter */
	b		_conv_ascii2byte


/* ascii2word
 *		This routine accepts an ASCII buffer pointer in R0,
 *		and returns the word value in R0(31:0).
 *		Note: On return, R1 points to the ASCII buffer location after the current 8 chars.
 *		WARNING: This routine assumes that the input buffer was sanitized and contains valid Hex chars,
 *				 otherwise it will return invalid results.
 */
	.global	ascii2word

ascii2word:
	stmfd	sp!, {r2,r3, lr}
	mov		r3, #8					/* Loop counter */

	/* Fall through to byte coversion loop */

_conv_ascii2byte:
	teq		r0, #0
	beq		_exit_conv_ascii2byte	/* exit if NULL pointer in R0 */
	mov		r0, r1					/* Copy of ASCII buffer pointer */
	mov		r2, #0					/* Initialize results */
2:	ldrb	r0, [r1], #1			/* Load ASCII char */
	bl		char2hex				/* on return, hex value in R0 */
	orr		r2, r0, r2, lsl #4		/* merge Nibble into results */
	subs	r3, r3, #1
	bne		2b
	mov		r0, r2					/* Copy it to R0 as return value */
_exit_conv_ascii2byte:
	ldmfd	sp!, {r2,r3, pc}		/* return hex value in R0 */




/* Debugger Communications Routines
 *		It does not make sense to pass information from the Debugger Module to the Comm. link one character
 *		at a time, especially if we're not using a native serial interface (e.g., EIA-232). Consequently
 *		a Message interface has been defined. This can still call getChar() and putChar() subroutines
 *		if so desired, but it'll be a purely internal matter.
 *
 */
	.global	dbg__hasDebugMsg
/* dbg__hasDebugMsg
 *		Checks for pending Debugger Message (Non-Blocking).
 *		On exit:
 *			r0: Boolean (0: no pending message, 1: has pending message)
 */
dbg__hasDebugMsg:
	bx		lr

	.global	dbg__getDebugMsg
/* dbg__getDebugMsg
 *		Returns Debugger Message to calling routine after verifying and removing checksum (Blocking).
 *		On entry:
 *			r0: address of message buffer
 *			r1: maximum size of message buffer (incl NULL character)
 *		On exit:
 *			r0: address of message buffer with NULL terminated message, excluding '#<checksum>'
 *				(NULL if message error)
 *
 */
dbg__getDebugMsg:
	bx		lr

	.global dbg__putDebugMsg
/* dbg__putDebugMsg
 *		Sends Debugger Message from calling routine after appending checksum (Blocking) .
 *		On entry:
 *			r0: address of message buffer with NULL terminated message, without '#<checksum>'
 *		On exit:
 *			r0: status (0: success, -1: error)
 */
dbg__putDebugMsg:
	bx		lr


/* Private functions (if needed) */
_dbg__getChar:
_dbg__putChar:
	bx		lr
