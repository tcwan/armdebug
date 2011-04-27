# bluetooth.py module -- Glue code from NXT_Python to Lightblue, allowing
# NXT_Python to run on Mac without modification.  Supports subset of
# PyBluez/bluetooth.py used by NXT_Python.
#
# Copyright (C) 2011  Tat-Chee Wan
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

import usb


ID_VENDOR_LEGO = 0x0694
ID_PRODUCT_NXT = 0x0002

class USBSocket:
    bsize = 60  # USB socket block size

    def __init__(self, device):
        self.device = device
        self.handle = None
        self.debug = False

    def device_name(self):
        return self.device.filename

    def connect(self):
        'Use to connect to NXT.'
        if self.debug:
            print 'PyUSB Connecting...'
        config = self.device.configurations[0]
        iface = config.interfaces[0][0]
        self.blk_out, self.blk_in = iface.endpoints
        self.handle = self.device.open()
        self.handle.setConfiguration(1)
        self.handle.claimInterface(0)
        self.handle.reset()
        if self.debug:
            print 'Connected.'
        return Brick(self)

    def close(self):
        'Use to close the connection.'
        if self.debug:
            print 'Closing USB connection...'
        self.device = None
        self.handle = None
        self.blk_out = None
        self.blk_in = None
        if self.debug:
            print 'USB connection closed.'

    def send(self, data):
        'Use to send raw data over USB connection ***ADVANCED USERS ONLY***'
        if self.debug:
            print 'Send:',
            print ':'.join('%02x' % ord(c) for c in data)
        self.handle.bulkWrite(self.blk_out.address, data)

    def recv(self, numbytes):
        'Use to recieve raw data over USB connection ***ADVANCED USERS ONLY***'
        data = self.handle.bulkRead(self.blk_in.address, numbytes)
        if self.debug:
            print 'Recv:',
            print ':'.join('%02x' % (c & 0xFF) for c in data)
        # NOTE: bulkRead returns a tuple of ints ... make it sane
        return ''.join(chr(d & 0xFF) for d in data)

def find_devices(lookup_names=False):  # parameter is ignored
    devicelist = []
    for bus in usb.busses():
        for device in bus.devices:
            if device.idVendor == ID_VENDOR_LEGO and device.idProduct == ID_PRODUCT_NXT:
                devicelist.append(device)
    return devicelist


