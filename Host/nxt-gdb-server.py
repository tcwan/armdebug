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

class NXTGDBServer:

    # Maximum message size.
    pack_size = 62
    
    # Debug command header, no reply.
    debug_command = 0x8d
    segment_no = 0

    def __init__ (self, port):
        """Initialise server."""
        self.port = port

    def pack (self, data):
        """Return packed data to send to NXT."""
        # Insert command and length.
        assert len (data) <= self.pack_size
        return struct.pack ('BBB', self.debug_command, self.segment_no, len (data)) + data

    def unpack (self, data):
        """Return unpacked data from NXT."""
        # May be improved, for now, check command and announced length.
        if len (data) < 2:
            return ''
        header, body = data[0:3], data[3:]
        command, self.segment_no, length = struct.unpack ('BBB', header)
        if command != self.debug_command or length != len (body):
            return ''
        return body

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
                    data = client.recv (self.pack_size)
                    if data:
                        brick.sock.send (self.pack (data))
                    else:
                        client.close ()
                        client = None
                # Is there something from NXT brick?
                try:
                    data = self.unpack (brick.sock.recv ())
                    if data:
                        client.send (data)
                except usb.USBError as e:
                    # Some pyusb are buggy, ignore some "errors".
                    if e.args != ('No error', ):
                        raise e
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
