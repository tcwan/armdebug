#!/usr/bin/env python
#
# Copyright (C) 2011 the NxOS developers
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
import nxt.locator
import socket
import optparse
import select
import usb
import struct

DEFAULT_PORT = 2828
SELECT_TIMEOUT = 0.1
DEBUG = True
NXT_RECV_ERR = -1

class NXTGDBServer:

    # Socket read size.
    recv_size = 1024

    # Maximum message size.
    pack_size = 61
    
    # Debug command header, no reply.
    debug_command = 0x8d

    def __init__ (self, port):
        """Initialise server."""
        self.port = port
        self.in_buf = ''

    def pack (self, data, segment_no):
        """Return packed data to send to NXT."""
        # Insert command and length.
        assert len (data) <= self.pack_size
        return struct.pack ('BBB', self.debug_command, segment_no, len (data)) + data

    def unpack (self, data):
        """Return unpacked data from NXT."""
        # May be improved, for now, check command and announced length.
        if len (data) == 0:
            return '', 0  # No message, exit
        if len (data) < 3:
            return '', NXT_RECV_ERR
        header, body = data[0:3], data[3:]
        command, segment_no, length = struct.unpack ('BBB', header)
        if command != self.debug_command or length != len (body):
            return '', NXT_RECV_ERR
        return body, segment_no

    def segment (self, data):
        """Split datas in GDB commands and make segments with each command."""
        segs = [ ]
        self.in_buf += data
        end = self.in_buf.find ('#')
        # Is # found and enough place for the checkum?
        while end >= 0 and end < len (self.in_buf) - 2:
            msg, self.in_buf = self.in_buf[0:end + 3], self.in_buf[end + 3:]
            assert msg[0] == '$', "not a GDB command"
            # Make segments.
            seg_no = 0
            while msg:
                seg, msg = msg[0:self.pack_size], msg[self.pack_size:]
                seg_no += 1
                if not msg: # Last segment.
                    seg_no = 0
                segs.append (self.pack (seg, seg_no))
            # Look for next one.
            end = self.in_buf.find ('#')
        return segs
        
    def reassemble (self, sock):
        msg = ''
        prev_segno = 0
        segno = NXT_RECV_ERR                    # force initial pass through while loop
        while segno != 0:
            try:
                s, segno = self.unpack (sock.recv ())
                if len (s) == 0:
                    if segno == 0 & prev_segno == 0:
                        return ''               # No message pending
                    else:
                        segno = NXT_RECV_ERR    # Keep waiting for segments
                # Ignore error packets
                if segno >= 0:
                    # Check segno, if non-zero it must be monotonically increasing from 1, otherwise 0
                    if segno > 0:
                       assert segno == prev_segno + 1, "segno = %s, prev_segno = %s" % (segno, prev_segno)
                    prev_segno = segno
                    msg.append(s)              
            except usb.USBError as e:
                # Some pyusb are buggy, ignore some "errors".
                if e.args != ('No error', ):
                    raise e
        return msg
        
    def run (self):
        """Endless run loop."""
        # Create the listening socket.
        s = socket.socket (socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt (socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind (('', self.port))
        s.listen (1)
        # Open connection to the NXT brick.
        brick = nxt.locator.find_one_brick ()
        brick.sock.debug = DEBUG
        print "Waiting for GDB connection on port %s..." % self.port
        while True:
            # Wait for a connection.
            client, addr = s.accept ()
            print "Client from", addr
            # Work loop, wait for a message from client socket or NXT brick.
            while client is not None:
                # Wait for a message from client or timeout.
                rlist, wlist, xlist = select.select ([ client ], [ ], [ ],
                        SELECT_TIMEOUT)
                for c in rlist:
                    assert c is client
                    # Data from client, read it and forward it to NXT brick.
                    data = client.recv (self.recv_size)
                    if data:
                        if DEBUG:
                            print "[GDB->NXT] %s" % data
                        segments = self.segment (data)
                        for s in segments:
                            brick.sock.send (s)
                    else:
                        client.close ()
                        client = None
                # Is there something from NXT brick?
                data = reassemble(brick.sock)
                if data:
                    if DEBUG:
                        print "[NXT->GDB] %s" % data
                    client.send (data)
                    data = ''
            print "Connection closed, waiting for GDB connection on port %s..." % self.port

if __name__ == '__main__':
    # Read options from command line.
    parser = optparse.OptionParser (description = """
    Gateway between the GNU debugger and a NXT brick.
    """)
    parser.add_option ('-p', '--port', type = 'int', default = DEFAULT_PORT,
            help = "server listening port (default: %default)", metavar = "PORT")
    (options, args) = parser.parse_args ()
    if args:
        parser.error ("Too many arguments")
    # Run.
    s = NXTGDBServer (options.port)
    s.run ()
