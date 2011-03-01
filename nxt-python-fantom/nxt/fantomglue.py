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

import fantom

FANTOM_BT='BT'
FANTOM_USB='USB'


def discover_devices(lookup_names=False):  # parameter is ignored
    pairs = []
    d = fantom.finddevices(proto = FANTOM_BT)
    for p in d:
        h = p[0]
        n = p[1]
        pairs.append((h, n))
    return pairs

class BluetoothSocket:

    def __init__(self, proto = FANTOM_BT, _sock=None):
        if _sock is None:
            _sock = fantom.socket(proto)
        self._sock = _sock
        self._proto = proto

    def connect(self, addrport):
        addr, port = addrport
        self._sock.connect( (addr, port ))
    
    def send(self, data):
        return self._sock.send( data )

    def recv(self, numbytes):
        return self._sock.recv( numbytes )
    
    def close(self):
        return self._sock.close()
    
class BluetoothError(IOError):
    pass    

