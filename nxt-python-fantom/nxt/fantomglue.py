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

    def __str__(self):
        return 'FantomGlue BT (%s)' % self.device_name()

    def device_name(self):
        devinfo = self._sock.get_device_info()
        return devinfo.name

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
            self._sock = None

    def __del__(self):
        """Destroy interface."""
        if self._sock is not None:
            del self._sock
            print "NXT object deleted"
        else:
            print "No NXT Object when calling __del__ for BluetoothSocket"

class BluetoothError(IOError):
    pass    

def _check_brick(arg, value):
    return arg is None or arg == value


def find_devices(lookup_names=False):  # parameter is ignored
    devicelist = []
    for d in pyfantom.NXTIterator(False):
        #name = d.get_name()
        #addr = d.get_resource_string()
        #print "NXT addr: ", addr
        nxt = d.get_nxt()
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

    def __str__(self):
        return 'FantomGlue USB (%s)' % self.device_name()

    def device_name(self):
        devinfo = self._sock.get_device_info()
        return devinfo.name

    def connect(self):
        if self._sock is None:
            # Port is ignored
            if self.debug:
                print "No NXT object assigned"
            self._sock = pyfantom.NXT(addr)         # FIXME: No address!
        else:
            if self.debug:
                print "Using existing NXT object"
    
    def send(self, data):
        return self._sock.write( data )

    def recv(self, numbytes):
        return self._sock.read( numbytes )

    #def poll_command(self, numbytes):
        # I'm not sure if this is specific to Direct Command Processing
        # Or if it refers to any data transmission
        #print "Bytes Available:", self._sock.bytes_available()
        #return self._sock.read_buffer( numbytes, 0 )
    
    def close(self):
        if self._sock is not None:
            del self._sock
            self._sock = None

    def __del__(self):
        """Destroy interface."""
        if self._sock is not None:
            del self._sock
            print "NXT object deleted"
        else:
            print "No NXT Object when calling __del__ for USBSocket"

if __name__ == '__main__':
    #get_info = False
    get_info = True
    write_read = True
    for i in find_devices():
        if get_info:
            print " firmware version:", i.get_firmware_version()
            print " get device info:", i.get_device_info()
            rs = i.get_resource_string()
            print " resource string:", rs
        if write_read:
            nxt = USBSocket(i)
            import struct
            # Write VERSION SYS_CMD.
            # Query:
            #  SYS_CMD: 0x01
            #  VERSION: 0x88
            cmd = struct.pack('2B', 0x01, 0x88)
            r = nxt.send(cmd)
            print "wrote", r
            # Response:
            #  REPLY_CMD: 0x02
            #  VERSION: 0x88
            #  SUCCESS: 0x00
            #  PROTOCOL_VERSION minor
            #  PROTOCOL_VERSION major
            #  FIRMWARE_VERSION minor
            #  FIRMWARE_VERSION major
            #rep = nxt.recv(USB_BUFSIZE)    # Doesn't work if it exceeds buffer content length (exception)
            #rep = nxt.recv(7)              # Works, since reply is 7 bytes
            rep = nxt.recv(5)               # Works, read length < remaining buffer content length
            print "read", struct.unpack('%dB' % len(rep), rep)
            rep = nxt.recv(2)               # Works, read length <= remaining buffer content length
            print "read", struct.unpack('%dB' % len(rep), rep)
            #rep = nxt.recv(1)              # Doesn't work if it exceeds buffer content length (exception)
            # Same thing, without response.
            #cmd = struct.pack('2B', 0x81, 0x88)
            #r = nxt.send(cmd)
            #print "wrote", r
            #rep = nxt.recv(USB_BUFSIZE)
            #rep = nxt.recv(7)
            #print "read", struct.unpack('%dB' % len(rep), rep)
            del nxt
