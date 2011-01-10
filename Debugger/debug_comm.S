/** @file debug_comm.S
 *  @brief GDB Server communications support routines
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


/* #define __NXOS__		*/	/* Defined externally in SConstruct */

#define __ASSEMBLY__
#include "debug_macros.h"
#include "debug_stub.h"
#include "debug_comm.h"

.bss
.align 4

debug_InUSBBuf:
	.space	USB_BUFSIZE,0
debug_OutUSBBuf:
	.space	USB_BUFSIZE,0

debug_msgRxBufPtr:
	.word	0x0
debug_msgTxBufPtr:
	.word	0x0

debug_segmentRxNum:				/* Current Rx Segment Number */
	.word	0x0
debug_segmentTxNum:				/* Current Tx Segment Number */
	.word	0x0

.data
.align 4

nxt_usbcmd_header:
	.byte	USB_NXT_TELEGRAM_RESP, 0x00, 0x00		/* padded to 3 bytes */

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
	and		r0, #NIBBLE0			/* make sure that input is sane */
	_hex2char	r0, r1
	ldmfd	sp!, {r1,pc}

/* char2hex
 *		This routine accepts an ASCII character in R0(7:0) and returns the
 *		equivalent byte sized hex value in R0(7:0)
 */
	.global	char2hex

char2hex:
	and		r0, #BYTE0			/* make sure that input is sane */
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
 * Message Format
 *		Since we need to use EP1&2 (Bulk channels) to communicate with the PC Host, the messages should
 *		follow the NXT Direct Commands message structure (this will allow for interoperability with NXT Firmware
 *		in addition to NxOS). The maximum length of any USB communications via the Bulk channel is 64 bytes.
 *		There is a one byte Telegram Type field which identifies the type of telegram, followed by the
 *		Telegram header and actual message.
 *
 *		The LEGO Mindstorms Communications Protocol Direct Commands GDB Message format (including all headers)
 *		is as follows:
 *
 *		GDB Command
 *		===========
 *			Byte 0:	Telegram Type Field (0x8d Direct Command, No response required)	| USB Channel Header
 *			Byte 1:	Segment No (1-255, 0: Last Segment; limit is MSG_NUMSEGMENTS)	|
 *			Byte 2:	Telegram Size (Len of USB Buffer - 3, max is MSG_SEGMENTSIZE)	|
 *			Byte 3-N: Message data													| GDB Command
 *
 *		The GDB Command (of size M) has the following format:
 *				Offset 0: '$'
 *				Offset 1: GDB Command char
 *				Offset 2 - (M-4): Command packet info
 *				Offset M-3: '#'
 *				Offset M-2: MSB of Checksum
 *				Offset M-1: LSB of Checksum
 *
 *		The maximum size of a GDB Command packet is MSGBUF_SIZE - 5 ('$', '#', 2 byte checksum, trailing NULL char)
 *
 *		GDB Response
 *		============
 *			Byte 0:	Telegram Type Field (0x8d Direct Command, No response required)	| USB Channel Header
 *			Byte 1:	Segment No (1-255, 0: Last Segment; limit is MSG_NUMSEGMENTS)	|
 *			Byte 2:	Telegram Size (Len of USB Buffer - 3, max is MSG_SEGMENTSIZE)	|
 *			Byte 3-N: Message data													| GDB Response
 *
 *		The GDB Response (of size M) has the following format:
 *				Offset 0: '+' or '-' Command Received Status
 *				Offset 1: '$'
 *				Offset 2 - (M-4): Response packet info
 *				Offset M-3: '#'
 *				Offset M-2: MSB of Checksum
 *				Offset M-1: LSB of Checksum
 *
 *		The maximum size of a GDB Response packet is MSGBUF_SIZE - 6 ('-'/'+', '$', '#', 2 byte checksum, trailing NULL char)
 *
 *		Note: The Telegram Size is the actual size of the Message Data portion
 *			  (i.e., excludes the three header bytes, includes the GDB Command/Response Packet trailing NULL character
 *					 in the last segment)
 */

 	.global dbg__comm_init
/* dbg__comm_init
 *		Initialize communications channel.
 *		On Entry:
 *			R0: MSG Rx Buf Pointer
 *			R1: MSG Tx Buf Pointer
 */

dbg__comm_init:
#ifdef __NXOS__
	stmfd	sp!, {lr}
	ldr		r2, =debug_msgRxBufPtr
	stmia	r2, {r0,r1}							/* Assume that the 2 pointers are consecutive */
	bl		_dbg__usbbuf_reset
	ldmfd	sp!, {pc}

_dbg__usbbuf_reset:
	stmfd	sp!, {lr}
	ldr		r0, =debug_InUSBBuf
	mov		r1, #USB_BUFSIZE
	ldr		r2, =nx_usb_read
	mov		lr,pc
	bx		r2
	ldmfd	sp!, {pc}
#else
	/* FIXME: NXT Firmware support */
	bx		lr
#endif

	.global	dbg__hasDebugMsg
/* dbg__hasDebugMsg
 *		Checks for pending Debugger Message (Non-Blocking).
 *		On exit:
 *			r0: !0: (Availale Debugger Message Size), 0: no pending message
 *			r1: message segment number
 */
dbg__hasDebugMsg:
#ifdef __NXOS__
	stmfd	sp!, {lr}
	ldr		r2, =nx_usb_data_read
	mov		lr,pc
	bx		r2					/* Number of bytes read in R0 */
	/* Note: The return value is the USB Buffer Size, includes NXT Direct Command Header */
	/* FIXME: Need to check command type etc. before accepting it as a valid Debugger message */
	ldr		r2, =debug_InUSBBuf
	ldrb	r0, [r2, #USB_NXT_TELEGRAMSIZE_OFFSET]
	ldrb	r1, [r2, #USB_NXT_SEGNUM_OFFSET]
	ldmfd	sp!, {pc}
#else
	/* FIXME: NXT Firmware support */
	bx		lr
#endif

	.global	dbg__getDebugMsg
/* dbg__getDebugMsg
 *		Returns Debugger Message to calling routine after verifying and removing checksum (Blocking).
 *		On entry:
 *			r0: address of message buffer
 *			r1: maximum size of message buffer (incl ASCIIZ character)
 *		On exit:
 *			r0: address of message buffer with ASCIIZ terminated message, excluding '#<checksum>'
 *				(NULL if message error)
 *
 */
 /* FIXME: This does not handle multiple segments currently, we just assume that everything is in one segment */
dbg__getDebugMsg:
#ifdef __NXOS__
	stmfd	sp!, {r4,r5,lr}
	bl		dbg__hasDebugMsg
	cmp		r0, #0
	ble		_exit_getDebugMsg		/* Zero length message, skip */
	teq		r1, #0
	bne		_exit_getDebugMsg		/* Don't process segmented messages for now */

_copy_msg_from_usbbuf:
	/* FIXME: handle multiple segments */
	/* FIXME: Need to check NXT Direct command type etc. before accepting it as a valid Debugger message */
	ldr		r5, =debug_msgRxBufPtr
	ldr		r5, [r5]
	ldr		r1, =debug_InUSBBuf
	ldrb	r2, [r1, #USB_GDBMSG_START]
	mov		r3, #MSGBUF_STARTCHAR
	teq		r2, r3
	bne		_exit_getDebugMsg		/* Debugger Message does not have valid start char '$' */
	ldrb	r2, [r1, r0]
	cmp		r2, #0					/* Check for NULL (in last segment) */
	bne		_exit_getDebugMsg		/* Debugger Message does not have valid terminating NULL char */
	sub		r3, r0, #USB_GDBMSG_CHKSUMOFFSET	/* Message Length - 3 = '#' offset */
	ldrb	r2, [r1, r3]
	mov		r4, #0
	strb	r4, [r1, r3]			/* Zero out '#' char for checksum calc later */
	mov		r3, #MSGBUF_CHKSUMCHAR
	teq		r2, r3
	bne		_exit_getDebugMsg		/* Debugger Message does not have valid checksum char '#' */

	/* Message Buffer copy */
	mov		r3, r0					/* Setup size param for memcpy macro */
	mov		r2, r5					/* Message Rx Buffer Address */
	add		r1, r1, #USB_GDBMSG_START
	_dbg_memcpy	r2, r1, r3			/* This copies over the checksum which follows the inserted NULL char */

	/* Perform Checksum Verification */
	mov		r0, r5					/* Message Rx Buffer Address */
	bl		_dbg__calcChecksum		/* Checksum in R1 */

	/* At this point, we have the checksum of characters in R0, and R1 points to Incoming Checksum char(s) */
	mov		r3, r0					/* Keep calculated checksum in R3 */
	mov		r0, r1					/* Move pointer to R0 for conversion */
	bl		ascii2byte				/* Convert Incoming Checksum from ASCII to byte value in R0 */
	teq		r0, r3					/* They must agree */
	beq		_exit_getDebugMsg		/* Debugger Message has valid checksum */

	/* Invalid message checksum, zero out buffer */
	mov		r0, #0
	ldr		r2, =debug_msgRxBufPtr
	ldr		r2, [r2]
	strb	r0, [r2]

_exit_getDebugMsg:
	bl		_dbg__usbbuf_reset	/* Next USB telegram transaction */
	ldmfd	sp!, {r4,r5,pc}
#else
	/* FIXME: NXT Firmware support */
	bx		lr
#endif

	.global dbg__putDebugMsg
/* dbg__putDebugMsg
 *		Sends Debugger Message from calling routine after appending checksum (Blocking) .
 *		On entry:
 *			r0: address of message buffer with ASCIIZ terminated message, without '#<checksum>'
 *		On exit:
 *			r0: status (0: success, -1: error)
 */
dbg__putDebugMsg:
#ifdef __NXOS__
	stmfd	sp!, {r4,lr}
	/* Perform Checksum Calculation */
	ldr		r4, =debug_OutUSBBuf
	bl		_dbg__calcChecksum		/* Checksum in R0 */

	/* At this point, we have the checksum of characters in R0, and R1 points to Outgoing Checksum char(s) */
	mov		r2, #MSGBUF_CHKSUMCHAR
	strb	r2, [r1, #-1]			/* Store checksum char '#' into buffer (overwriting ASCIIZ character) */
	bl		byte2ascii				/* On return, R1 points to ASCIIZ character */

	/* Calculate size of message to copy */
	ldr		r2, =debug_msgTxBufPtr
	ldr		r2, [r2]
	sub		r3, r1, r2				/* calculate length of message */
	add		r3, #1					/* length is 1 more */
	ldr		r1, =nxt_usbcmd_header
	ldr		r0, [r1]
	str		r0, [r4]				/* Straight copy of the header (Endianness issues?) */
	/* FIXME: handle multiple segments */
	strb	r3, [r4, #USB_NXT_TELEGRAMSIZE_OFFSET]	/* Update the size field */
	add		r1, r4, #USB_GDBMSG_START
	_dbg_memcpy	r1, r2, r3			/* This copies over the message + checksum which follows */

	/* Message Buffer copy */
	ldmfd	sp!, {r4,pc}
#else
	/* FIXME: NXT Firmware support */
	bx		lr
#endif

/* _dbg__calcChecksum
 *		Calculate Checksum for NULL terminated message
 *		On entry:
 *			r0: address of message buffer with ASCIIZ terminated message, without '#<checksum>'
 *		On exit:
 *			r0: checksum modulo 256
 *			r1: pointer to buffer following ASCIIZ message character
 *			r2: destroyed
 */
_dbg__calcChecksum:
	mov		r2, #0					/* Intermediate checksum calculation */
1:
	ldrb	r1, [r0], #1
	teq		r1, #0
	addne	r2, r1, r2				/* sum of each character in message */
	bne		1b

	mov		r1, r0					/* Keep pointer in R1 for return parameter */
	and		r0, r2, #BYTE0			/* Checksum is sum of char values modulo 256 */
	bx		lr


/* Private functions (if needed) */
_dbg__getChar:
_dbg__putChar:
	bx		lr
