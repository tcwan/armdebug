#!/usr/bin/env python3
#
# Copyright (C) 2011-2022 the NxOS developers
#
# Module Developed by: Nicolas Schodet
#                      TC Wan
#
# See AUTHORS for a full list of the developers.
#
# See COPYING for redistribution license
#
# Exchange GDB messages with the NXT brick.
#
# Every message is encapsulated with the debug command and message length.
# This can be used by the firmware to make the distinction between debug
# messages and regular messages.
#
# Flush stdout immediately

import sys

if sys.version_info[:2] < (3, 3):
    old_print = print
    def print(*args, **kwargs):
        flush = kwargs.pop('flush', False)
        old_print(*args, **kwargs)
        if flush:
            file = kwargs.get('file', sys.stdout)
            # Why might file=None? IDK, but it works for print(i, file=None)
            file.flush() if file is not None else sys.stdout.flush()
            
import nxt.locator
import socket
import optparse
import select
import struct
import sys
from time import sleep

from usb.core import USBError
from nxt.locator import BrickNotFoundError

PROTOCOL_VER = (1, 129)

CTRLC = chr(3)
NAKCHAR = '-'
ACKCHAR = '+'
STATUS_QUERY = "$?#3F"
DEFAULT_PORT = 2828
SELECT_TIMEOUT = 0.1
DEBUG = False
DEBUG2 = False
NXT_RECV_ERR = -1

# Libusb 0.12.x blocks on USB reads
LIBUSB_RECEIVE_BLOCKING = True
# Set number of retries when encountering USB socket read timeout
USB_NUMTRIES = 2


class NXTGDBServer:

    # Socket read size.
    recv_size = 1024

    # Maximum message size.
    pack_size = 61
    
    # Debug command header, no reply.
    debug_command = 0x8d

    def __init__ (self, port, nowait):
        """Initialise server."""
        self.nowait = nowait
        self.port = port
        self.in_buf = b''
        self.brick = None
        self.s = None               # Listening Socket

    def pack (self, data, segment_no):
        """Return packed data to send to NXT."""
        # Insert command and length.
        assert len (data) <= self.pack_size
        return struct.pack ('BBB', self.debug_command, segment_no, len (data)) + data

    def unpack (self, data):
        """Return unpacked data from NXT."""
        # May be improved, for now, check command and announced length.
        if len (data) == 0:
            return b'', 0  # No message, exit
        if len (data) < 3:
            return b'', NXT_RECV_ERR
        header, body = data[0:3], data[3:]
        command, segment_no, length = struct.unpack ('BBB', header)
        if command != self.debug_command or length != len (body):
            return b'', NXT_RECV_ERR
        return body, segment_no

    def segment (self, data):
        """Split messages in GDB commands and make segments with each command."""
        segs = [ ]
        self.in_buf += data

        # Find ACK '+' 
        end = self.in_buf.find (ord(ACKCHAR))
        while end == 0:
            self.in_buf = self.in_buf[end+1:]   # Strip out any leading ACKCHAR
            if DEBUG2:
                print("stripped ACK, remain: ", self.in_buf, flush=True)
            end = self.in_buf.find (ord(ACKCHAR))

        # Find NAK '-' 
        end = self.in_buf.find (ord(NAKCHAR))
        if end == 0:
            msg, self.in_buf = self.in_buf[0:end+1], self.in_buf[end+1:]
            segs.append (self.pack (msg, 0))
            end = self.in_buf.find (ord(NAKCHAR))

        # Find Ctrl-C (assumed to be by itself and not following a normal command)
        end = self.in_buf.find (ord(CTRLC))
        if end >= 0:
            msg, self.in_buf = self.in_buf[0:end+1], self.in_buf[end+1:]
            assert len (msg) <= self.pack_size, "Ctrl-C Command Packet too long!"
            segs.append (self.pack (msg, 0))
            end = self.in_buf.find (ord(CTRLC))
        
        end = self.in_buf.find (ord('#'))
        # Is # found and enough place for the checksum?
        while end >= 0 and end < len (self.in_buf) - 2:
            msg, self.in_buf = self.in_buf[0:end + 3], self.in_buf[end + 3:]
            i = 0
            gdbprefix = msg[i]
            while gdbprefix in [ACKCHAR]:
                # Ignore any '+'
                i += 1
                gdbprefix = msg[i]
                if DEBUG2:
                    print("Checking '", gdbprefix, "'", flush=True)
            assert gdbprefix == ord('$'), "not a GDB command"
            # Make segments.
            seg_no = 0
            while msg:
                seg, msg = msg[0:self.pack_size], msg[self.pack_size:]
                seg_no += 1
                if not msg: # Last segment.
                    seg_no = 0
                segs.append (self.pack (seg, seg_no))
            # Look for next one.
            end = self.in_buf.find (ord('#'))
        return segs
        
    def reassemble (self, sock):
        msg = b''
        prev_segno = 0
        segno = NXT_RECV_ERR                    # force initial pass through while loop
        while segno != 0:
            try:
                s, segno = self.unpack (sock.recv ())
                if len (s) == 0:
                    if segno == 0 and prev_segno == 0:
                        return b''               # No message pending
                    else:
                        segno = NXT_RECV_ERR    # Keep waiting for segments
                # Ignore error packets
                if segno >= 0:
                    # Check segno, if non-zero it must be monotonically increasing from 1, otherwise 0
                    if segno > 0:
                       assert segno == prev_segno + 1, "segno = %s, prev_segno = %s" % (segno, prev_segno)
                    prev_segno = segno
                    msg += s               
            except IOError as e:
                # Some pyusb are buggy, ignore some "errors".
                # print(e.args, flush=True)
                if e.args != ('No error', ):
                    if DEBUG:
                        print("sock.recv() raised exception", flush=True)
                    raise e
        return msg
    
    def try_reassemble (self):
        try_msg = b''
        try:
            try_msg = self.reassemble (self.brick._sock)
        except IOError as e:
            if e.args == (60, 'Operation timed out'):
                self.tries = self.tries + 1
                if (self.tries < USB_NUMTRIES):
                    print("Timed out. Retrying...%d " % self.tries, flush=True)
                    self.brick._sock.close()
                    self.brick = None
                    # sleep(1)
                    self.connect_to_brick()
                    if self.brick != None:
                         self.brick._sock.debug = DEBUG
            else:
                client.close ()
                raise e
        return try_msg
    
    def connect_to_brick(self):
        try:
            self.brick = nxt.locator.find()        
            if self.brick != None:
                prot_version, fw_version = self.brick.get_firmware_version()
                if DEBUG:
                    print("Protocol version: %s.%s" % prot_version, flush=True)
                if prot_version != PROTOCOL_VER:
                    print("Protocol mismatch (found %s.%s): Make sure nxos-armdebug RXE is running!" % prot_version, flush=True)
                    self.brick._sock.close()
                    self.brick = None
        except BrickNotFoundError:
            print(".", flush=True),
            sys.stdout.flush()
        except USBError:
            print("USB Error! Restart NXT", flush=True)
            self.brick = None
    
    def run (self):
        """Endless run loop."""
        # Create the listening socket.
        self.s = socket.socket (socket.AF_INET, socket.SOCK_STREAM)
        self.s.setsockopt (socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.s.bind (('', self.port))
        self.s.listen (1)
        while True:
            self.tries = 0 
            # We should open the NXT connection first, otherwise Python startup delay
            # may cause GDB to misbehave
            if not self.nowait:
                dummy = input('Waiting...Press <ENTER> when NXT GDB Stub is ready. ')
            # Open connection to the NXT brick.
            while self.brick == None:
                self.connect_to_brick()
                if self.brick == None:
                    sleep(2)
            self.brick._sock.debug = DEBUG
            # Wait for a connection.
            print("Waiting for GDB connection on port %s..." % self.port, flush=True)
            client, addr = self.s.accept ()
            print("Client from", addr, flush=True)
            # Work loop, wait for a message from client socket or NXT brick.
            while client is not None and self.brick is not None:
                data = b''
                # Wait for a message from client or timeout.
                rlist, wlist, xlist = select.select ([ client ], [ ], [ ],
                        SELECT_TIMEOUT)
                for c in rlist:
                    assert c is client
                    # Data from client, read it and forward it to NXT brick.
                    data = client.recv (self.recv_size)
                    data = data.strip()
                    if len (data) > 0:
                        #if len (data) == 1 and data.find(CTRLC) >= 0:
                        #   print("CTRL-C Received!", flush=True)
                        #   data = STATUS_QUERY
                        if DEBUG:
                            if data[0] == CTRLC:
                                print("[GDB->NXT] <CTRL-C>", flush=True)
                            else:
                                print("[GDB->NXT] %s" % data, flush=True)
                        segments = self.segment (data)
                        data = b''
                        for seg in segments:
                            try:
                                self.brick._sock.send (seg)
                            except IOError as e:
                                # Some pyusb are buggy, ignore some "errors".
                                # print(e.args, flush=True)
                                if e.args != ('No error', ):
                                    if DEBUG:
                                        print("sock.send() raised exception", flush=True)
                                    if e.args == (19, 'No such device (it may have been disconnected)'):
                                        self.brick._sock.close()
                                        self.brick = None
                                        data = b''
                                    else:
                                        client.close()
                                        raise e
                        if segments != [] and LIBUSB_RECEIVE_BLOCKING:
                            if DEBUG2:
                                print("Accessing Blocking sock.recv()", flush=True)
                            if self.brick:
                                data = self.try_reassemble()
                    else:
                        client.close ()
                        client = None
                if not LIBUSB_RECEIVE_BLOCKING:
                    if DEBUG2:
                         print("Accessing Non-Blocking sock.recv()", flush=True)
                    if self.brick:
                        data = self.try_reassemble ()
                    
                # Is there something from NXT brick?
                if data:
                    if DEBUG:
                        print("[NXT->GDB] %s" % data, flush=True)
                    if client:
                        client.send (data)
                    data = b''
            if self.brick:
                self.brick._sock.close()
                self.brick = None
            print("Connection closed.", flush=True)
#            if self.nowait:
#                break

if __name__ == '__main__':
    # Read options from command line.
    parser = optparse.OptionParser (description = """
    Gateway between the GNU debugger and a NXT brick.
    """)
    parser.add_option ('-p', '--port', type = 'int', default = DEFAULT_PORT,
            help = "server listening port (default: %default)", metavar = "PORT")
    parser.add_option ('-v', '--verbose', action='store_true', dest='verbose', default = False,
            help = "verbose mode (default: %default)")
    parser.add_option ('-n', '--nowait', action='store_true', dest='nowait', default = False,
            help = "Don't wait for NXT GDB Stub Setup before connecting (default: %default)")
    (options, args) = parser.parse_args ()
    if args:
        parser.error ("Too many arguments")
    # Run.
    try:
        DEBUG = options.verbose
        if DEBUG:
            print("Debug Mode Enabled!", flush=True)
        server = NXTGDBServer (options.port, options.nowait)
        server.run ()
    except KeyboardInterrupt:
        print("\n\nException caught. Bye!", flush=True)
        if server.brick is not None:
            server.brick._sock.close()
        if server.s is not None:
            server.s.close()
        sys.exit()
