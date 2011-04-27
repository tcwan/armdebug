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

try:
    import pyusbglue as usb
except ImportError:
    import pyfantom as usb

from nxt.brick import Brick

class USBSock(object):
    'Object for USB connection to NXT'

    bsize = 60  # USB socket block size

    def __init__(self, device):
        self.sock = USBSocket(device)
        self.debug = False

    def __str__(self):
        # FIXME: This breaks encapsulation
        return 'USB (%s)' % (self.sock.filename)

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
        data = self.sock.recv(64)
        if self.debug:
            print 'Recv:',
            print ':'.join('%02x' % (c & 0xFF) for c in data)
        # NOTE: bulkRead returns a tuple of ints ... make it sane
        return ''.join(chr(d & 0xFF) for d in data)

def _check_brick(arg, value):
    return arg is None or arg == value

def find_bricks(host=None, name=None):
    'Use to look for NXTs connected by USB only. ***ADVANCED USERS ONLY***'
    for d in usb.find_devices(lookup_names=True):
        # FIXME: probably should check host and name
        yield USBSock(d)
