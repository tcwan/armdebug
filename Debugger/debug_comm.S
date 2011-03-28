/** @file debug_comm.S
 *  @brief GDB Server communications support routines
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


/* #define __NXOS__		*/	/* Defined externally in SConstruct */

#define __ASSEMBLY__
#include "debug_macros.h"
#include "debug_stub.h"
#include "debug_internals.h"
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

debug_msgRxBuf_AppendPtr:
    .word   0x0
debug_msgTxBuf_AppendPtr:
    .word   0x0

    .equ    RXAPPENDPTR_OFFSET, (debug_msgRxBuf_AppendPtr - debug_msgRxBufPtr)
    .equ    TXAPPENDPTR_OFFSET, (debug_msgTxBuf_AppendPtr - debug_msgTxBufPtr)

debug_segmentRxNum:				/* Current Rx Segment Number */
	.word	0x0

#ifndef __NXOS__
debug_nxtMsgLength:            /* NXT Firmware Received USB Message Length */
    .word   0x0
#endif

.data
.align 4

nxt_usbcmd_header:
	.byte	USB_NXT_TELEGRAMTYPE, 0x00, 0x00		/* padded to 3 bytes */

hex2char_lut:
	.ascii	"0123456789ABCDEF"

/* Macros
 */


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
 *  GDB requires command parameters to be specified as Big Endian values.
 *  However, the read/write register command expect the register contents to be specified in target byte order.
 *  Hence we need both versions of multibyte conversion routines for word sized values.
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
 *		equivalent byte sized hex value in R0(7:0).
 *		It accepts lowercase and uppercase ASCII Hex char inputs.
 *      Invalid inputs return -1 as the value
*      On entry:
 *          R0: ASCII character
 *      On exit:
 *          R0: Hex value
 */
	.global	char2hex

char2hex:
	and		r0, r0, #BYTE0			/* make sure that input is sane */
	cmp		r0, #'0'
	blo		char2hex_error
	cmp     r0, #'9'
	bls     perform_char2hex
	cmp     r0, #'A'
	blo    char2hex_error
	cmp     r0, #'F'
	bls     perform_char2hex
    cmp     r0, #'a'
    blo    char2hex_error
	cmp		r0, #'f'
	bhi		char2hex_error
	/* Validated Hex Char */
perform_char2hex:
	_char2hex	r0					/* Return hex value in R0 */
	bx		lr

char2hex_error:
	mov     r0, #-1                 /* Set Return value to Error value */
	bx		lr

/* byte2ascii_cont
 *      (Shared routine, does not perform sanity checks)
 *      On entry:
 *          R0: ASCII buffer pointer
 *          R1[7:0]: byte value
 *      On exit:
 *          R0: Address of next empty char slot in buffer
 *          R1: Destroyed
 *
 *      This routine accepts an ASCII buffer pointer in R0 and a byte value in R1,
 *		and stores the ASCII equivalent byte value in the buffer pointed to by R0.
 *		Note: On return, R0 points to next empty char slot in buffer
 */
byte2ascii_cont:
	stmfd	sp!, {r2,r3,r4, lr}
	lsl		r2, r1, #24			    /* Keep copy of input byte value R1[7:0], shifted to MSB R2[31:24] */
	mov		r4, #2					/* Loop counter */
	_hex2char_lut	r3				/* initialize LUT pointer */
1:	ror		r2, r2, #28 			/* Rotate MSNibble R2[31:28] into LSNibble position R2[3:0] */
	and		r1, r2, #NIBBLE0		/* Mask out everything else, store Nibble in R1 */
	_hex2char_cont	r1, r3			/* Convert nibble to ASCII char */
	strb	r1, [r0], #1
	subs	r4, r4, #1				/* decrement loop counter */
	bne		1b
	ldmfd	sp!, {r2,r3,r4, pc}

/* byte2ascii
 *      On entry:
 *          R0: ASCII buffer pointer
 *          R1[7:0]: Byte value
 *      On exit:
 *          R0: Address of next empty char slot in buffer
 *          R1: Original Address of Buffer
 *
 *		This routine accepts an ASCII buffer pointer in R0 and a byte value in R1,
 *		and stores the ASCII equivalent byte value in the buffer pointed to by R0.
 *		Note: On return, R0 points to the next empty char slot in buffer
 */
	.global	byte2ascii

byte2ascii:
	stmfd	sp!, {r0, lr}			/* Keep ASCII buffer pointer */
	and		r1, #BYTE0				/* sanitize input */
	bl		byte2ascii_cont
	ldmfd	sp!, {r1, pc}			/* return original string pointer in R1 */

/* halfword2ascii_be
 *      Big Endian version of halfword2ascii conversion routine
 *      On entry:
 *          R0: ASCII buffer pointer
 *          R1[15:0]: Halfword value
 *      On exit:
 *          R0: Address of next empty char slot in buffer
 *          R1: Original Address of Buffer
 *
 *      This routine accepts an ASCII buffer pointer in R0 and a halfword value in R1,
 *      and stores the ASCII equivalent halfword value in the buffer pointed to by R0.
 *      Note: On return, R0 points to the next empty char slot in buffer
 */
	.global	halfword2ascii_be
halfword2ascii_be:
	stmfd	sp!, {r0,r2,r3, lr}		/* Keep ASCII buffer pointer */
    mov     r3, #2                  /* Loop Counter */
    mov     r2, r1, lsl #16         /* copy of input halfword value R1[15:0], shifted to MSH R2[31:16] */
    b       _conv_byte2ascii_be     /* goto Byte conversion loop */

/* halfword2ascii_le
 *      Little Endian version of halfword2ascii conversion routine
 *      On entry:
 *          R0: ASCII buffer pointer
 *          R1[15:0]: Halfword value
 *      On exit:
 *          R0: Address of next empty char slot in buffer
 *          R1: Original Address of Buffer
 *
 *      This routine accepts an ASCII buffer pointer in R0 and a halfword value in R1,
 *      and stores the ASCII equivalent halfword value in the buffer pointed to by R0.
 *      Note: On return, R0 points to the next empty char slot in buffer
 */
    .global halfword2ascii_le
halfword2ascii_le:
    stmfd   sp!, {r0,r2,r3, lr}     /* Keep ASCII buffer pointer */
    mov     r3, #2                  /* Loop Counter */
    b       _conv_byte2ascii_le     /* goto Byte conversion loop */


/* word2ascii_be
 *      Big Endian version of word2ascii conversion routine
 *      On entry:
 *          R0: ASCII buffer pointer
 *          R1[31:0]: Word value
 *      On exit:
 *          R0: Address of next empty char slot in buffer
 *          R1: Original Address of Buffer
 *
 *      This routine accepts an ASCII buffer pointer in R0 and a word value in R1,
 *      and stores the ASCII equivalent word value in the buffer pointed to by R0.
 *      Note: On return, R0 points to the next empty char slot in buffer
 */
	.global	word2ascii_be
word2ascii_be:
	stmfd	sp!, {r0,r2,r3, lr}		/* Keep ASCII buffer pointer */
	mov		r2, r1					/* copy of input word value R1[31:0] */
	mov		r3, #4					/* Loop Counter */

	/* Fall through to byte coversion loop */


/* Big Endian Multibyte Convert: Rotate then convert */
_conv_byte2ascii_be:
	ror		r2, r2, #24			    /* Rotate MSB R2[31:24] into LSB position R2[7:0] */
	and		r1, r2, #BYTE0			/* Copy byte value in R2[7:0] into R1 */
	bl		byte2ascii_cont         /* R0: next ASCII buffer location pointer, R1: destroyed */
	subs	r3, r3, #1
	bne		_conv_byte2ascii_be
	ldmfd	sp!, {r1,r2,r3, pc}

/* word2ascii_le
 *      Little Endian version of word2ascii conversion routine
 *      On entry:
 *          R0: ASCII buffer pointer
 *          R1[31:0]: Word value
 *      On exit:
 *          R0: Address of next empty char slot in buffer
 *          R1: Original Address of Buffer
 *
 *      This routine accepts an ASCII buffer pointer in R0 and a word value in R1,
 *      and stores the ASCII equivalent word value in the buffer pointed to by R0.
 *      Note: On return, R0 points to the next empty char slot in buffer
 */
    .global word2ascii_le
word2ascii_le:
    stmfd   sp!, {r0,r2,r3, lr}     /* Keep ASCII buffer pointer */
    mov     r2, r1                  /* copy of input word value R1[31:0] */
    mov     r3, #4                  /* Loop Counter */

    /* Fall through to byte coversion loop */

/* Little Endian Multibyte Convert: Convert then rotate */
_conv_byte2ascii_le:
    and     r1, r2, #BYTE0          /* Copy byte value in R2[7:0] into R1 */
    bl      byte2ascii_cont         /* R0: next ASCII buffer location pointer, R1: destroyed */
    ror     r2, r2, #8              /* Rotate LSB+1 R2[15:8] into LSB position R2[7:0] */
    subs    r3, r3, #1
    bne     _conv_byte2ascii_le
    ldmfd   sp!, {r1,r2,r3, pc}


/* ascii2hex_varlen_be
 *      Big Endian version of ascii2hex_varlen conversion routine
 *      (There is no Little Endian Version)
 *      On entry:
 *          R0: ASCII buffer pointer
 *      On exit:
 *          R0: Hex value
 *          R1: Address of next char slot in buffer
 *
 *      This routine accepts an ASCII buffer pointer in R0,
 *      and returns the hex value in R0 for up to 8 Hex characters.
 *      Note: On return, R1 points to the ASCII buffer location after the hex value chars.
 */
    .global ascii2hex_varlen_be

ascii2hex_varlen_be:
    stmfd   sp!, {r2,r3, lr}
    mov     r3, #CMD_REG_REGPARAMLEN /* Set max count to 8 (Max Register size) */
    mov     r1, r0                  /* Use R1 as ASCII buffer pointer */
    mov     r2, #0                  /* Initialize Cummulative Results */
2:  ldrb    r0, [r1]	            /* Load ASCII char for Hex Value */
    bl      char2hex                /* on return, hex value in R0, -1 for error */
    cmp     r0, #-1
    beq     _exit_ascii2hex_varlen
    orr     r2, r0, r2, lsl #4      /* combined byte value */
    subs    r3, r3, #1              /* Decrement Counter */
    add		r1, r1, #1				/* Go to next char slot */
    bne     2b
_exit_ascii2hex_varlen:
    mov     r0, r2                  /* Return results in R0 */
    ldmfd   sp!, {r2,r3, pc}


/* ascii2byte
 *      On entry:
 *          R0: ASCII buffer pointer
 *      On exit:
 *          R0[7:0]: Byte value
 *          R1: Address of next char slot in buffer
 *
 *		This routine accepts an ASCII buffer pointer in R0,
 *		and returns the byte value in R0[7:0].
 *		Note: On return, R1 points to the ASCII buffer location after the current 2 chars.
 *		WARNING: This routine assumes that the input buffer was sanitized and contains valid Hex chars,
 *				 otherwise it will return invalid results.
 */
	.global	ascii2byte

ascii2byte:
    stmfd   sp!, {r2, lr}
    mov     r1, r0                  /* Use R1 as ASCII buffer pointer */
    ldrb    r0, [r1], #1            /* Load ASCII char for MSN */
    bl      char2hex                /* on return, hex value in R0, -1 for error (ignored) */
    mov     r2, r0, lsl #4          /* Intermediate Results register */
    ldrb    r0, [r1], #1            /* Load ASCII char for LSN */
    bl      char2hex                /* on return, hex value in R0, -1 for error (ignored) */
    orr     r0, r2, r0              /* combined byte value */
    ldmfd   sp!, {r2, pc}

/* ascii2halfword_be
 *      Big Endian version of ascii2halfword conversion routine
 *      On entry:
 *          R0: ASCII buffer pointer
 *      On exit:
 *          R0[15:0]: Halfword value
 *          R1: Address of next char slot in buffer
 *
 *		This routine accepts an ASCII buffer pointer in R0,
 *		and returns the Halfword value in R0[15:0].
 *		Note: On return, R1 points to the ASCII buffer location after the current 4 chars.
 *		WARNING: This routine assumes that the input buffer was sanitized and contains valid Hex chars,
 *				 otherwise it will return invalid results.
 */
	.global	ascii2halfword_be

ascii2halfword_be:
	stmfd	sp!, {r2,r3, lr}
	mov		r3, #2					/* Loop counter */
    b       _conv_ascii2byte_be

/* ascii2halfword_le
 *      Little Endian version of ascii2halfword conversion routine
 *      On entry:
 *          R0: ASCII buffer pointer
 *      On exit:
 *          R0[15:0]: Halfword value
 *          R1: Address of next char slot in buffer
 *
 *      This routine accepts an ASCII buffer pointer in R0,
 *      and returns the Halfword value in R0[15:0].
 *      Note: On return, R1 points to the ASCII buffer location after the current 4 chars.
 *      WARNING: This routine assumes that the input buffer was sanitized and contains valid Hex chars,
 *               otherwise it will return invalid results.
 */
    .global ascii2halfword_le

ascii2halfword_le:
    stmfd   sp!, {r2,r3, lr}
    mov     r3, #2                  /* Loop counter */
    b       _conv_ascii2byte_le


/* ascii2word_be
 *      Big Endian version of ascii2word conversion routine
 *      On entry:
 *          R0: ASCII buffer pointer
 *      On exit:
 *          R0[31:0]: Word value
 *          R1: Address of next char slot in buffer
 *
 *		This routine accepts an ASCII buffer pointer in R0,
 *		and returns the word value in R0[31:0].
 *		Note: On return, R1 points to the ASCII buffer location after the current 8 chars.
 *		WARNING: This routine assumes that the input buffer was sanitized and contains valid Hex chars,
 *				 otherwise it will return invalid results.
 */
	.global	ascii2word_be

ascii2word_be:
	stmfd	sp!, {r2,r3, lr}
	mov		r3, #4					/* Loop counter */

	/* Fall through to byte coversion loop */

_conv_ascii2byte_be:
	teq		r0, #0
	beq		_exit_conv_ascii2byte_be	/* exit if NULL pointer in R0 */
    mov     r2, #0                  /* Initialize Cummulative value */
2:  bl      ascii2byte
    orr     r2, r0, r2, lsl #8      /* Merge current byte with cummulative value */
    mov     r0, r1                  /* Copy next char pointer to R0 for next byte */
    subs    r3, r3, #1
    bne     2b
    mov     r0, r2                  /* Copy it to R0 as return value */

_exit_conv_ascii2byte_be:
	ldmfd	sp!, {r2,r3, pc}		/* return hex value in R0 */

/* ascii2word_le
 *      Litle Endian version of ascii2word conversion routine
 *      On entry:
 *          R0: ASCII buffer pointer
 *      On exit:
 *          R0[31:0]: Word value
 *          R1: Address of next char slot in buffer
 *
 *      This routine accepts an ASCII buffer pointer in R0,
 *      and returns the word value in R0[31:0].
 *      Note: On return, R1 points to the ASCII buffer location after the current 8 chars.
 *      WARNING: This routine assumes that the input buffer was sanitized and contains valid Hex chars,
 *               otherwise it will return invalid results.
 */
    .global ascii2word_le

ascii2word_le:
    stmfd   sp!, {r2,r3, lr}
    mov     r3, #4                  /* Loop counter */

    /* Fall through to byte coversion loop */

_conv_ascii2byte_le:
    teq     r0, #0
    beq     _exit_conv_ascii2byte_le    /* exit if NULL pointer in R0 */
    push    {r3}                    /* Need to keep couter for final value adjustment */
    mov     r2, #0                  /* Initialize Cummulative value */
2:  bl      ascii2byte
    orr     r2, r0, r2, ror #8       /* Merge current byte with cummulative value */
    mov     r0, r1                  /* Copy next char pointer to R0 for next byte */
    subs    r3, r3, #1
    bne     2b
    /* Cummulative value done, need to rotate it into the correct position for return value */
    pop     {r3}                    /* retrieve counter */
    rsb     r3, r3, #5              /* 5 - count */
    lsl     r3, r3, #3              /* [(5-count) x 8] bits to rotate */
    mov     r0, r2, ror r3           /* Copy it to R0 as return value */

_exit_conv_ascii2byte_le:
    ldmfd   sp!, {r2,r3, pc}        /* return hex value in R0 */




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
 *              Offset 0: '+'/'-' Command Received Status (Optional)
 *				Offset 1/0: '$'
 *				Offset 2/1: GDB Command char
 *				Offset 3 - (M-4): Command packet info
 *				Offset M-3: '#'
 *				Offset M-2: MSB of Checksum
 *				Offset M-1: LSB of Checksum
 *
 *      To be safe, we assume that the Command Received Status is always sent by the GDB server. Therefore,
 *		The maximum size of a GDB Command packet is MSGBUF_SIZE - 5 ('+'/'-', '$', '#', 2 byte checksum)
 *
 *		GDB Response
 *		============
 *			Byte 0:	Telegram Type Field (0x8d Direct Command, No response required)	| USB Channel Header
 *			Byte 1:	Segment No (1-255, 0: Last Segment; limit is MSG_NUMSEGMENTS)	|
 *			Byte 2:	Telegram Size (Len of USB Buffer - 3, max is MSG_SEGMENTSIZE)	|
 *			Byte 3-N: Message data													| GDB Response
 *
 *      The GDB Retransmission Request has the following format:
 *              Offset 0: '-' Command Received Status
 *
 *		The GDB Response (of size M) has the following format:
 *				Offset 0: '+' Command Received Status
 *				Offset 1: '$'
 *				Offset 2 - (M-4): Response packet info
 *				Offset M-3: '#'
 *				Offset M-2: MSB of Checksum
 *				Offset M-1: LSB of Checksum
 *
 *		The maximum size of a GDB Response packet is MSGBUF_SIZE - 5 ('+', '$', '#', 2 byte checksum)
 *
 *		Note: The Telegram Size is the actual size of the Message Data portion
 *			  (i.e., excludes the three header bytes, includes the GDB Command/Response Packet checksum bytes
 *					 in the last segment)
 */

 	.global dbg__comm_init
/* dbg__comm_init
 *      Initialize communications channel.
 *      On Entry:
 *          R0: MSG Rx Buf Pointer
 *          R1: MSG Tx Buf Pointer
 */

dbg__comm_init:
	stmfd	sp!, {lr}
	ldr     r2, =debug_msgRxBufPtr
	stmia   r2!, {r0, r1}          /* debug_msgRxBufPtr and debug_msgTxBufPtr */
	stmia   r2!, {r0, r1}          /* debug_msgRxBuf_AppendPtr and debug_msgTxBuf_AppendPtr */
	bl		_dbg__usb_readbuf_reset
	ldmfd	sp!, {pc}

_dbg__usb_readbuf_reset:
#ifdef __NXOS__
	stmfd	sp!, {lr}
	ldr		r0, =debug_InUSBBuf
	mov		r1, #USB_BUFSIZE
	ldr		r2, =nx_usb_read
	mov		lr, pc
	bx		r2
	ldmfd	sp!, {pc}
#else
    ldr     r1, =debug_nxtMsgLength
    mov     r0, #0
    str     r0, [r1]                        /* Clear NXT USB Received Message Length */
	bx		lr

    .global dbg__copyNxtDebugMsg
/* dbg__copyNxtDebugMsg
 *      Copy NXT Firmware Debug Message to our own Buffers, indicate Msg Received status.
 *      On Entry:
 *          R0: NXT USB Input Buf Pointer
 *          R1: USB Command Bit
 *          R2: USB Raw Message Length
 *      On Exit:
 *          R0-R3: Destroyed
 */

dbg__copyNxtDebugMsg:
    ldr     r1, =debug_nxtMsgLength
    str     r2, [r1]
    ldr     r1, =debug_InUSBBuf
    _dbg_memcpy r1, r0, r2, r3                  /* r3: scratch register */
    bx      lr
#endif

/* _dbg_reset_msgTxBuf_AppendPtr
 *      Internal variable to reset pointers.
 *      On Exit:
 *          R0: debug_msgTxBuf_AppendPtr
 *          R1: destroyed
 */
_dbg_reset_msgTxBuf_AppendPtr:
    ldr     r1, =debug_msgTxBufPtr              /* Should not be modified */
    ldr     r0, [r1]
    str     r0, [r1, #TXAPPENDPTR_OFFSET]
    mov     pc, lr

/* _dbg__usbHasMsg
 *		Internal Segment Reassembly Routine.
 *		On exit:
 *			r0: !0: (Availale Telegram Message Size), 0: no incoming message/segment
 *			r1: message segment number
 */
_dbg__usbHasMsg:
	stmfd	sp!, {lr}
#ifdef __NXOS__
	ldr		r2, =nx_usb_data_read
	mov		lr,pc
	bx		r2					    /* Number of bytes read in R0 */
	/* Note: The return value in R0 is the USB Buffer Size, includes NXT Direct Command Header */
#else
    ldr     r0, =debug_nxtMsgLength
    ldr     r0, [r0]                /* R0 contains the USB Buffer Size, including the NXT Direct Command Header */
#endif

	ldr		r2, =debug_InUSBBuf
	ldrb    r1, [r2, #USB_NXT_TELEGRAMTYPE_OFFSET]
	cmp     r1, #USB_NXT_TELEGRAMTYPE
	bne     invalid_USBMsg          /* Invalid telegram type, ignore */

	ldrb	r1, [r2, #USB_NXT_TELEGRAMSIZE_OFFSET]
	sub     r0, r0, r1              /* USB Buffer Size - Telegram Size = 3 (header size) */
	cmp     r0, #USB_GDBMSG_START   /* Start offset is equal to header size */
    bne     invalid_USBMsg          /* Invalid Message Length, ignore */

    mov     r0, r1                  /* Telegram Message Size */
	ldrb	r1, [r2, #USB_NXT_SEGNUM_OFFSET]
    b       _exit_dbg__usbHasMsg

invalid_USBMsg:
    mov   r0, #0
_exit_dbg__usbHasMsg:
    ldmfd   sp!, {pc}

/* _copy_msg_from_usbbuf
 *      Internal USB buffer copy routine, handles segment reassembly.
 *      On entry:
 *          r0: number of bytes to copy
 *          r1: segment number
 *      On exit:
 *          r0: cummulative message length
 *          r1: segment number
 *          r2, r3: Destroyed
 */
_copy_msg_from_usbbuf:
    stmfd   sp!, {r1,r4,r5,r6,lr}
    movs    r4, r0
    beq     _exit_copy_msg_from_usbbuf

    ldr     r6, =debug_msgRxBufPtr              /* Address of Pointers */
    ldr     r5, [r6]                            /* Rx buffer Start Address */
    ldr     r2, [r6, #RXAPPENDPTR_OFFSET]       /* Append Pointer */

    sub     r3, r2, r5                          /* r3: current length of message */
    add     r3, r3, r4                          /* new cummulative length of message */
    cmp     r3, #MSGBUF_SIZE
    movhi   r4, #0                              /* Buffer overflow! */
    strhi   r5, [r6, #RXAPPENDPTR_OFFSET]       /* Reset AppendPtr to beginning of Rx Buffer */
    bhi     _exit_copy_msg_from_usbbuf

    ldr     r3, =debug_InUSBBuf
    add     r3, r3, #USB_GDBMSG_START
    _dbg_memcpy r2, r3, r4, r0                  /* r2 updated to point to next empty char slot in Rx buffer */
    sub     r4, r2, r5                          /* r4: cummulative length of message */

    /* Update debug_msgRxBuf_AppendPtr */
    teq     r1, #0                              /* Check if this is last segment (segment 0) */
    streq   r5, [r6, #RXAPPENDPTR_OFFSET]       /* Reset AppendPtr to beginning of Rx Buffer if so */
    strne   r2, [r6, #RXAPPENDPTR_OFFSET]       /* Otherwise, update Append Pointer to receive next segment */

_exit_copy_msg_from_usbbuf:
    bl      _dbg__usb_readbuf_reset             /* Next USB telegram transaction */
    mov     r0, r4                              /* Return cummulative message length in R0 */
    ldmfd   sp!, {r1,r4,r5,r6,pc}               /* Return segment number in R1 */


/* _msgbuf_checksum
 *      Internal routine to calculate checksum character buffer.
 *      On entry:
 *          r0: pointer to character buffer to checksum (assume ASCIIZ terminated)
 *      On exit:
 *          r0: pointer to character buffer after ASCIIZ
 *          r1: checksum (8-bit binary)
 *          r2: message length
 *          r3: destroyed
 */
_msgbuf_checksum:
    mov     r1, #0                              /* clear checksum */
    mov     r2, #0                              /* clear length */
1:  ldrb    r3, [r0], #1                        /* Iterate through buffer */
    add     r1, r1, r3                          /* cummulative sum of char */
    teq     r3, #0
    addne   r2, r2, #1                          /* increment message length */
    bne     1b                                  /* until ASCIIZ found */
    and     r1, #BYTE0                          /* Modulo 256 */
    mov     pc, lr

    .global dbg__getDebugMsg
/* dbg__getDebugMsg
 *      Retrieve pending Debugger Message if available (Non-Blocking).
 *      On entry:
 *          No parameters (assume pointers were initialized previously using dbg__comm_init)
 *      On exit:
 *          r0: >0 = Valid GDB Message Length (incl '$', excluding '#' and checksum),
 *              0 = no valid message (yet), -1 = error
 *          r1: GDB Message Buffer Pointer  (incl '$', excluding '#' and checksum)
 *          r2, r3: Destroyed
 *      Note: If GDB Message were returned, it is ASCIIZ terminated, does not include '#' and checksum
 */
dbg__getDebugMsg:
    stmfd   sp!, {r4,r5,lr}
    bl      _dbg__usbHasMsg                     /* r0: message length, r1: segment number */
    teq     r0, #0
    beq     exit_dbg__getDebugMsg               /* no new message, exit with R0 = 0 */

    ldr     r4, =debug_segmentRxNum
    ldr     r2, [r4]                            /* Get current Segment Number */
    add     r2, r2, #1                          /* Expected Segment Number for comparison */
    teq     r1, #0
    streq   r1, [r4]                            /* Update current Segment Number with 0 since it is the last segment */
    beq     _hasMsg2Copy
    cmp     r1, #MSG_NUMSEGMENTS                /* Segment Number < MSG_NUMSEGMENTS? */
    bhs     _invalid_segment
    teq     r1, r2                              /* Valid Segment Number, check against Expected Segment Number */
    beq     _hasMsg2Copy                        /* Segment Number matches Expected Segment Number, update buffers */

_invalid_segment:
    bl      _dbg__usb_readbuf_reset             /* Invalid, Next USB telegram transaction */
    mov     r0, #0                              /* Reset Segment Number */
    str     r0, [r4]                            /* Update current Segment Number with 0 to prepare for new message */
    b       exit_dbg__getMsgError               /* Exit with error */

_hasMsg2Copy:
    str     r1, [r4]                            /* Update current Segment Number */
    bl      _copy_msg_from_usbbuf               /* r0: cummulative message length, r1: segment number */
    teq     r1, #0
    movne   r0, #0                              /* Incomplete message, ignore for now */
    bne     exit_dbg__getDebugMsg               /* Message not complete yet, exit */

    /* Check for valid GDB message */
    mov     r4, r0                              /* keep message length in R4, assume to be within MSGBUF_SIZE */
    ldr     r5, =debug_msgRxBufPtr
    ldr     r5, [r5]                            /* Rx buffer Start Address */

/* Need to account for Packet Acknowledgement */
1:  ldrb    r0, [r5]
    teq     r0, #MSGBUF_NAKCHAR               /* Look for '-' */
    beq		exit_dbg__getMsgError			  /* FIXME: We can't handle retransmission, flag message error */
    teq     r0, #MSGBUF_ACKCHAR               /* Look for '+' */
    addeq   r5, r5, #1                        /* Adjust Buffer Start Pointer (excl '+') */
    subeq	r4, r4, #1						  /* Adjust Message Length */
    beq     1b                                /* Skip all Packet Acknowledgements */

	/* Note: Here we assume that we won't get a single ACK '+' or NAK '-' character message.
	 *       If we do, it'll be flagged as an error
	 */
    subs    r2, r4, #MSGBUF_CHKSUMOFFSET        /* Look for '#': Message Length - 3 = '#' offset */
    blt		exit_dbg__getMsgError				/* Message Length is too short, exit with error */
    ldrb    r0, [r5, r2]
    teq     r0, #MSGBUF_CHKSUMCHAR
    bne     exit_dbg__getMsgError               /* No checksum char '#', exit with error */

    mov     r1, #0
    strb    r1, [r5, r2]                        /* Zero out '#' char for checksum calc later */

#ifdef CHECK_GDBSTARTCHAR
    /* Checked in dbg__bkpt_waitCMD */
    ldrb    r0, [r5]
    teq     r0, #MSGBUF_STARTCHAR               /* Look for '$' */
    bne     exit_dbg__getMsgError               /* No start char '$', exit with error */
#endif

    add     r0, r5, #1                          /* Checksum packet data (excl '$') */
    bl      _msgbuf_checksum                    /* R2: length (excl '$'), R1: calculated checksum, R0: pointer to checksum in receive buffer */
    mov     r3, r1                              /* Keep calculated checksum in R3 (R1 destroyed by ascii2byte) */
    bl      ascii2byte                          /* R0: received checksum, R1: address of next buffer location */
    teq     r0, r3                              /* Compare calculated checksum in R3 against received checksum in R0 */
    bne     exit_dbg__getMsgError               /* Checksums do not match, exit with error */

    subeq   r0, r4, #MSGBUF_CHKSUMOFFSET        /* Update message length (incl '$') as return parameter */
    add     r2, r2, #1                          /* expected message length (from _msgbuf_checksum) */
    teq     r0, r2
    beq     exit_dbg__getDebugMsg               /* Valid length, return */

exit_dbg__getMsgError:
    mov     r0, #MSGBUF_MSGERROR
exit_dbg__getDebugMsg:
    mov     r1, r5                              /* Return GDB Message Buffer Pointer in R1 */
	ldmfd	sp!, {r4,r5,pc}

/* _dbg__sendUSBMsg
 *      Internal USB send routine (interfaces with drivers).
 *      On entry:
 *          R0: Total USB Message Buffer length
 *      On exit:
            R0: Tx Status (TRUE if data sent)
 */
_dbg__sendUSBMsg:
    stmfd   sp!, {r4, lr}
    mov     r4, r0                              /* Keep USB Buffer length in R4 */
#ifdef __NXOS__
    /* Check USB bus status, transmit message if possible */
    bl      nx_usb_is_connected                 /* R0 = True if USB is ready */
    cmp     r0, #TRUE
    bne     _exit_dbg__sendUSBMsg

    /* Actual transmission (blocking) */
    ldr     r0, =debug_OutUSBBuf                /* data pointer parameter */
    mov     r1, r4                              /* USB buffer length */
    bl      nx_usb_write

1:  bl      nx_usb_data_written                 /* R0 = True if data has been sent */
    cmp     r0, #TRUE
    /* FIXME: implement timeout */
    bne     1b                                  /* Busy Wait Loop */
#else
    /* Check USB bus status, transmit message if possible */
    bl      dUsbIsConfigured                    /* R0: UByte status, TRUE / FALSE */
    teq     r0, #nxt_UBYTE_TRUE
    movne   r0, #FALSE
    bne     _exit_dbg__sendUSBMsg

    /* Actual transmission (blocking) */
    ldr     r0, =debug_OutUSBBuf                /* data pointer parameter */
    mov     r1, r4                              /* USB buffer length */
    bl      dUsbWrite                           /* call NXT Firmware USB driver, return 0: done, !0: remaining chars */
    teq     r0, #0                              /* Tx done if returned length is 0 */
    movne   r0, #FALSE
    moveq   r0, #TRUE                           /* Convert NXT firmware return value to our Status (TRUE/FALSE) */
#endif

_exit_dbg__sendUSBMsg:
    ldmfd   sp!, {r4, pc}


/* _copy_msg_to_usbbuf
 *      Internal USB buffer copy routine, handles segment fragmentation.
 *      On entry:
 *          r0: number of bytes to copy
 *          r1: segment number
 *      On exit:
 *          r0: cummulative message length
 *          r1: segment number
 *          r2, r3: Destroyed
 */
_copy_msg_to_usbbuf:
    stmfd   sp!, {r1,r4,r5,r6,lr}
    ldr     r6, =debug_msgTxBufPtr              /* Address of Pointers */
    ldr     r5, [r6, #TXAPPENDPTR_OFFSET]       /* Retrieve Tx Append Pointer */

    movs    r4, r0
    beq     _exit_copy_msg_to_usbbuf

#ifdef CHECK_TXLEN
    add     r0, r4, #USB_GDBMSG_START   /* offset = header size */
    cmp     r0, #USB_BUFSIZE
    bhi     _exit_copy_msg_to_usbbuf    /* We let calling routine detect problem (segment number will increment) */
#endif

    /* Fill in USB Message Header */
    ldr     r3, =debug_OutUSBBuf
    mov     r2, #USB_NXT_TELEGRAMTYPE
    strb    r2, [r3], #1            /* Telegram type */
    strb    r1, [r3], #1            /* Segment Number */
    strb    r0, [r3], #1            /* Message Length */

    mov     r2, r5                              /* Copy to R2 for updating */
    mov     r1, r4                              /* actual GDB message fragment length (exclude USB header) */
    _dbg_memcpy r3, r2, r1, r0                  /* This copies over the message fragment, r3, r2 updated */
    mov     r5, r2                              /* Updated Tx Append Pointer, keep in R5 for now */

    add     r0, r4, #USB_GDBMSG_START           /* Total USB Buffer Size for Tx (USB_GDBMSG_START offset = header size) */
    bl      _dbg__sendUSBMsg                    /* Common interface routine to USB drivers */
    cmp     r0, #TRUE
    ldrne   r5, [r6, #TXAPPENDPTR_OFFSET]       /* Tx failed, Retrieve Original Tx Append Pointer */
    streq   r5, [r6, #TXAPPENDPTR_OFFSET]       /* Tx succeeded, Update Tx Append Pointer to new position */

_exit_copy_msg_to_usbbuf:
    ldr     r6, [r6]                            /* Retrieve Tx Buffer Start Address */
    sub     r0, r5, r6                          /* Return calculated cummulative message length (R0) */
    ldmfd   sp!, {r1,r4,r5,r6,pc}               /* Return segment number in R1 */

	.global dbg__putDebugMsg
/* dbg__putDebugMsg
 *		Sends Debugger Message from calling routine after appending checksum (Blocking) .
 *		On entry:
 *			No parameters (assume pointers were initialized previously using dbg__comm_init)
 *		On exit:
 *			r0: status (0: success, -1: error)
 *      Note: GDB Message to be sent must be ASCIIZ terminated, does not include '#' and checksum
 *            Response packets start with '+' followed by '$' (2 bytes prefix)
 */
dbg__putDebugMsg:
	stmfd	sp!, {r4,r5,lr}
	/* Perform Checksum Calculation */
    ldr     r5, =debug_msgTxBufPtr              /* R5: data structure base pointer */
    ldr     r4, [r5]                            /* Tx buffer Start Address */
    str     r4, [r5, #TXAPPENDPTR_OFFSET]       /* Reset Tx buffer Append Pointer */
    add     r0, r4, #2                          /* skip '+' and '$' */
    bl      _msgbuf_checksum                    /* R2: length (excl '+' and '$'), R1: calculated checksum, R0: pointer to checksum in tx buffer */

#ifdef CHECK_TXLEN
    add     r2, r2, #2                          /* r2: returned length from _msgbuf_checksum, added with prefix length */
    sub     r3, r0, r4                          /* r3: calculated length from pointers (incl. prefix length) */
    teq     r2, r3
    bne     exit_dbg__putMsgError
#endif

    mov     r3, #MSGBUF_CHKSUMCHAR
    strb    r3, [r0, #-1]                       /* Insert '#' */
    bl      byte2ascii                          /* On return, R0 points to location after checksum bytes, R1 is original pointer to checksum */
    sub     r4, r0, r4                          /* R4 = Calculated total message length (incl '+' and '$', '#' and checksum bytes */
    cmp     r4, #MSG_SEGMENTSIZE                /* If total message length > MSG_SEGMENTSIZE */
    mov     r1, #0                              /* Initialize Segment Number = 0 (last segment) first */
    mov     r0, #0                              /* Initial cummulative message length */
    mov     r5, #0                              /* Previous cummulative message length */

    /* We assume unsigned message lengths, so the arithmetic MUST NOT result in negative values */
_cont_putMsg:
    cmp     r4, r0
    movls   r0, #0                              /* R0: Exit status (success) */
    bls     exit_dbg__putDebugMsg               /* If Total message length (r4) <= Cummulative message length (r0), we're done */
    add     r2, r0, #MSG_SEGMENTSIZE            /* R2: calculate new Max cummulative message length */
    cmp     r4, r2                              /* Check total message length (R4) against new Max cummulative message length (R2) */
    subls   r0, r4, r0                          /* if total message length (R4) <= new Max cummulative message length (R2), send remainder */
    movls   r1, #0                              /* Flag as last segment (Segment Number = 0) */
    movhi   r0, #MSG_SEGMENTSIZE                /* else send MSG_SEGMENTSIZE bytes */
    addhi   r1, r1, #1                          /* Increment Segment Number */
    cmp     r1, #MSG_NUMSEGMENTS
    bhs     exit_dbg__putMsgError               /* If Segment Number >= MSG_NUMSEGMENTS, flag error */
    bl      _copy_msg_to_usbbuf                 /* R0: cummulative message length, R1: segment number */
    teq     r5, r0                              /* Check if we managed to transmit the previous message */
    beq     exit_dbg__putMsgError               /* No, flag error */
    movne   r5, r0                              /* Update previous cummulative message length */
    b       _cont_putMsg

exit_dbg__putMsgError:
    mov     r0, #MSGBUF_MSGERROR
exit_dbg__putDebugMsg:
	ldmfd	sp!, {r4,r5,pc}

	.global dbg__requestRetransmission
/* dbg__requestRetransmission
 *		Request for Retransmission due to received message Checksum error (Blocking) .
 *		On entry:
 *			No parameters (assume pointers were initialized previously using dbg__comm_init)
 *		On exit:
 *			r0: status (0: success, -1: error)
 *			r1: destroyed
 *      Note: A Retransmission is indicated by '-', which is prepended with the USB header and sent (without checksum)
 */
dbg__requestRetransmission:
	stmfd	sp!, {lr}
    ldr     r1, =debug_msgTxBufPtr              /* R2: data structure base pointer */
    ldr     r0, [r1]                            /* Tx buffer Start Address */
    str     r0, [r1, #TXAPPENDPTR_OFFSET]       /* Reset Tx buffer Append Pointer */

	mov     r1, #0                              /* Initialize Segment Number = 0 (last segment) */
    mov     r0, #1                              /* Retransmission message length = 1 */
    bl      _copy_msg_to_usbbuf                 /* R0: cummulative message length, R1: segment number */
    cmp     r0, #1                              /* Check if we managed to transmit the previous message */
    moveq	r0, #0								/* R0: Exit status (success) */
    movne	r0, #MSGBUF_MSGERROR				/* R0: Exit status (error) */
	ldmfd	sp!, {pc}

