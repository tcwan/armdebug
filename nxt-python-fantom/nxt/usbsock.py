# nxt.usbsock module -- USB socket communication with LEGO Minstorms NXT
# Copyright (C) 2006, 2007  Douglas P Lau
# Copyright (C) 2009  Marcus Wanner
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

USB_BUFSIZE = 64

try:
    import fantomglue as usb
except ImportError:
    import pyusbglue as usb

from nxt.brick import Brick

class USBSock(object):
    'Object for USB connection to NXT'

    bsize = 60  # USB socket block size

    def __init__(self, device):
        self.sock = usb.USBSocket(device)
        self.debug = True

    def __str__(self):
        return 'USB (%s)' % (self.sock.device_name())

    def connect(self):
        'Use to connect to NXT.'
        if self.debug:
            print 'Connecting via USB...'
        self.sock.connect()
        return Brick(self)

    def close(self):
        'Use to close the connection.'
        if self.debug:
            print 'Closing USB connection...'
        self.sock.close()
        if self.debug:
            print 'USB connection closed.'

    def send(self, data):
        'Use to send raw data over USB connection ***ADVANCED USERS ONLY***'
        if self.debug:
            print 'Send:',
            print ':'.join('%02x' % ord(c) for c in data)
        self.sock.send(data)

    def recv(self):
        'Use to recieve raw data over USB connection ***ADVANCED USERS ONLY***'
        data = self.sock.recv(USB_BUFSIZE)      # FIXME: This will cause an exception since we cannot read more than the actual buffer contents
        if self.debug:
            print 'Recv:',
            print ':'.join('%02x' % (c & 0xFF) for c in data)
        # NOTE: bulkRead returns a tuple of ints ... make it sane
        return ''.join(chr(d & 0xFF) for d in data)

def _check_brick(arg, value):
    return arg is None or arg == value

def find_bricks(host=None, name=None):
    get_info = False
    'Use to look for NXTs connected by USB only. ***ADVANCED USERS ONLY***'
    for d in usb.find_devices(lookup_names=True):
        if get_info:
            print " firmware version:", d.get_firmware_version()
            print " get device info:", d.get_device_info()
            rs = d.get_resource_string()
            print " resource string:", rs
        # FIXME: probably should check host and name
        yield USBSock(d)

if __name__ == '__main__':
    write_read = True
    socks = find_bricks()
    for s in socks:
        print s.sock
        brick = s.connect()
        if write_read:
            import struct
            # Write VERSION SYS_CMD.
            # Query:
            #  SYS_CMD: 0x01
            #  VERSION: 0x88
            cmd = struct.pack('2B', 0x01, 0x88)
            #brick.sock.send(cmd)
            #s.send(cmd)
            s.sock.send(cmd)
            print "wrote", len(cmd)
            # Response:
            #  REPLY_CMD: 0x02
            #  VERSION: 0x88
            #  SUCCESS: 0x00
            #  PROTOCOL_VERSION minor
            #  PROTOCOL_VERSION major
            #  FIRMWARE_VERSION minor
            #  FIRMWARE_VERSION major
            #rep = brick.sock.recv()
            #rep = s.recv()
            rep = s.sock.recv(7)
            print "read", struct.unpack('%dB' % len(rep), rep)
            # Same thing, without response.
            #cmd = struct.pack('2B', 0x81, 0x88)
            #brick.sock.send(cmd)
            #print "wrote", cmd
            #rep = brick.sock.recv()
            #print "read", struct.unpack('%dB' % len(rep), rep)
        del brick

