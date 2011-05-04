# fantom.py module -- Glue code from NXT_Python to Fantom, allowing
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

import pyfantom

USB_BUFSIZE = 64

RFCOMM=11           # lightblue const
FANTOM_BT = RFCOMM  # For compatibilty with lightblue
FANTOM_USB = 0

# Bluetooth Iterator
def discover_devices(lookup_names=False):  # parameter is ignored
    pairs = []
    for d in pyfantom.NXTIterator(True):
        # h: host, n: name
        h = d.get_resource_string()
        nxt = d.get_nxt()
        device_info = nxt.get_device_info()
        n = device_info.name
        del nxt
        pairs.append((h, n))
    return pairs

class BluetoothSocket:

    def __init__(self, proto = FANTOM_BT, _sock=None):
        # We instantiate a NXT object only when we connect if none supplied
        self._sock = _sock
        self._proto = proto

    def connect(self, addrport):
        addr, port = addrport
        if self._sock is None:
            # Port is ignored
            self._sock = pyfantom.NXT(addr)
    
    def send(self, data):
        return self._sock.write( data )

    def recv(self, numbytes):
        return self._sock.read( numbytes )
    
    def close(self):
        if self._sock is not None:
            del self._sock
    
class BluetoothError(IOError):
    pass    

def _check_brick(arg, value):
    return arg is None or arg == value


def find_devices(lookup_names=False):  # parameter is ignored
    devicelist = []
    for d in pyfantom.NXTIterator(False):
        addr = d.get_resource_string()
        print "NXT addr: ", addr
        nxt = d.get_nxt()
        # BUG?: If nxt.get_firware_version() is enabled, d.get_nxt() will throw an exception
        # Related to Reference Counting for Obj-C Objects?
        #print " firmware version:", nxt.get_firmware_version()
        devicelist.append(nxt)
    return devicelist

# FIXME: The semantics of find_devices is different from discover_devices
#
#        # h: host, n: name
#        hostmatched = None
#        namematched = None
#        h = d.get_resource_string()
#        nxt = d.get_nxt()
#        device_info = nxt.get_device_info()
#        n = device_info.name
#        if _check_brick(host, h) and _check_brick(name, n):
#            yield nxt
#        else:
#            del nxt             # Does not match criteria

class USBSocket:

    def __init__(self, device=None):
        # We instantiate a NXT object only when we connect if none supplied
        # FIXME: The addr is not passed in, so we can't actually create a NXT object later
        #self.device = device
        self._sock = device
        self.debug = False

    def device_name(self):
        devinfo = self._sock.deviceinfo()
        return devinfo.name

    def connect(self):
        if self._sock is None:
            # Port is ignored
            self._sock = pyfantom.NXT(addr)         # FIXME: No address!
    
    def send(self, data):
        return self._sock.write( data )

    def recv(self, numbytes):
        return self._sock.read( numbytes )
    
    def close(self):
        if self._sock is not None:
            del self._sock
