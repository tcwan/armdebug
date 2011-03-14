"""NXT Fantom driver wrapper."""
from ctypes import c_int, c_uint, c_ushort, c_ubyte, c_char_p, byref, POINTER
import ctypes.util
import platform
import collections

# Check platform.
if platform.system() == 'Darwin':
    import sys
    if sys.maxsize > 2**32:
        raise RuntimeError("fantom drivers not available in 64 bit mode.\n"
                "You can run python in 32 bit mode using:\n"
                "arch -i386 python2.6\n")
    libpath = '/Library/Frameworks/Fantom.framework/Fantom'
    #libpath = ctypes.util.find_library('Fantom')
else:
    raise RuntimeError('unsupported platform')

# Load library.
dll = ctypes.cdll.LoadLibrary(libpath)
dll.nFANTOM100_createNXTIterator.argtypes = [c_ushort, c_uint, POINTER(c_int)]
dll.nFANTOM100_createNXTIterator.restype = c_uint
dll.nFANTOM100_destroyNXTIterator.argtypes = [c_int, POINTER(c_int)]
dll.nFANTOM100_destroyNXTIterator.restype = None
dll.nFANTOM100_iNXTIterator_advance.argtypes = [c_uint, POINTER(c_int)]
dll.nFANTOM100_iNXTIterator_advance.restype = None
dll.nFANTOM100_iNXTIterator_getNXT.argtypes = [c_uint, POINTER(c_int)]
dll.nFANTOM100_iNXTIterator_getNXT.restype = c_uint
dll.nFANTOM100_iNXTIterator_getName.argtypes = [c_uint, c_char_p,
        POINTER(c_int)]
dll.nFANTOM100_iNXTIterator_getName.restype = None
dll.nFANTOM100_createNXT.argtypes = [c_char_p, POINTER(c_int), c_ushort]
dll.nFANTOM100_createNXT.restype = c_uint
dll.nFANTOM100_destroyNXT.argtypes = [c_uint, POINTER(c_int)]
dll.nFANTOM100_destroyNXT.restype = None
dll.nFANTOM100_iNXT_getFirmwareVersion.argtypes = [c_uint, POINTER(c_ubyte),
        POINTER(c_ubyte), POINTER(c_ubyte), POINTER(c_ubyte), POINTER(c_int)]
dll.nFANTOM100_iNXT_getFirmwareVersion.argtypes = None
dll.nFANTOM100_iNXT_getDeviceInfo.argtypes = [c_uint, c_char_p,
        POINTER(c_ubyte), POINTER(c_ubyte), POINTER(c_uint), POINTER(c_int)]
dll.nFANTOM100_iNXT_write.argtypes = [c_uint, c_char_p, c_uint,
        POINTER(c_int)]
dll.nFANTOM100_iNXT_write.restype = c_uint
dll.nFANTOM100_iNXT_read.argtypes = [c_uint, c_char_p, c_uint,
        POINTER(c_int)]
dll.nFANTOM100_iNXT_read.restype = c_uint
dll.nFANTOM100_iNXT_getDeviceInfo.restype = None
dll.nFANTOM100_iNXT_getResourceString.argtypes = [c_uint, c_char_p,
        POINTER(c_int)]
dll.nFANTOM100_iNXT_getResourceString.restype = None

class FantomException(RuntimeError):
    """Exception thrown on Fantom library error."""
    pass

class Status:
    """Status codes used by Fantom library."""

    # Status codes. {{{
    Success = 0
    Offset = -142000
    PairingFailed = Offset - 5
    BluetoothSearchFailed = Offset - 6
    SystemLibraryNotFound = Offset - 7
    UnpairingFailed = Offset - 8
    InvalidFilename = Offset - 9
    InvalidIteratorDereference = Offset - 10
    LockOperationFailed = Offset - 11
    SizeUnknown = Offset - 12
    DuplicateOpen = Offset - 13
    EmptyFile = Offset - 14
    FirmwareDownloadFailed = Offset - 15
    PortNotFound = Offset - 16
    NoMoreItemsFound = Offset - 17
    TooManyUnconfiguredDevices = Offset - 18
    CommandMismatch = Offset - 19
    IllegalOperation = Offset - 20
    BluetoothCacheUpdateFailed = Offset - 21
    NonNXTDeviceSelected = Offset - 22
    RetryConnection = Offset - 23
    PowerCycleNXT = Offset - 24
    FeatureNotImplemented = Offset - 99
    FWIllegalHandle = Offset - 189
    FWIllegalFileName = Offset - 190
    FWOutOfBounds = Offset - 191
    FWModuleNotFound = Offset - 192
    FWFileExists = Offset - 193
    FWFileIsFull = Offset - 194
    FWAppendNotPossible = Offset - 195
    FWNoWriteBuffers = Offset - 196
    FWFileIsBusy = Offset - 197
    FWUndefinedError = Offset - 198
    FWNoLinearSpace = Offset - 199
    FWHandleAlreadyClosed = Offset - 200
    FWFileNotFound = Offset - 201
    FWNotLinearFile = Offset - 202
    FWEndOfFile = Offset - 203
    FWEndOfFileExpected = Offset - 204
    FWNoMoreFiles = Offset - 205
    FWNoSpace = Offset - 206
    FWNoMoreHandles = Offset - 207
    FWUnknownErrorCode = Offset - 208
    # }}}

    # Text description. {{{
    description = {
            Success: "No error",
            PairingFailed: "Bluetooth pairing operation failed.",
            BluetoothSearchFailed: "Bluetooth search failed.",
            SystemLibraryNotFound: "System library not found.",
            UnpairingFailed: "Bluetooth unpairing operation failed.",
            InvalidFilename: "Invalid filename specified.",
            InvalidIteratorDereference: "Invalid iterator dereference.",
            LockOperationFailed: "Resource locking operation failed.",
            SizeUnknown: "Could not determine the requested size.",
            DuplicateOpen: "Cannot open two objects at once.",
            EmptyFile: "File is empty.",
            FirmwareDownloadFailed: "Firmware download failed.",
            PortNotFound: "Could not locate virtual serial port.",
            NoMoreItemsFound: "No more items found.",
            TooManyUnconfiguredDevices: "Too many unconfigured devices.",
            CommandMismatch: "Command mismatch in firmware response.",
            IllegalOperation: "Illegal operation.",
            BluetoothCacheUpdateFailed: "Could not update local Bluetooth"
            " cache with new name.",
            NonNXTDeviceSelected: "Selected device is not an NXT.",
            RetryConnection: "Communication error.  Retry the operation.",
            PowerCycleNXT: "Could not connect to NXT.  Turn the NXT off and"
            " then back on before continuing.",
            FeatureNotImplemented: "This feature is not yet implemented.",
            FWIllegalHandle: "Firmware reported an illegal handle.",
            FWIllegalFileName: "Firmware reported an illegal file name.",
            FWOutOfBounds: "Firmware reported an out of bounds reference.",
            FWModuleNotFound: "Firmware could not find module.",
            FWFileExists: "Firmware reported that the file already exists.",
            FWFileIsFull: "Firmware reported that the file is full.",
            FWAppendNotPossible: "Firmware reported the append operation is"
            " not possible.",
            FWNoWriteBuffers: "Firmware has no write buffers available.",
            FWFileIsBusy: "Firmware reported that file is busy.",
            FWUndefinedError: "Firmware reported the undefined error.",
            FWNoLinearSpace: "Firmware reported that no linear space is"
            " available.",
            FWHandleAlreadyClosed: "Firmware reported that handle has already"
            " been closed.",
            FWFileNotFound: "Firmware could not find file.",
            FWNotLinearFile: "Firmware reported that the requested file is"
            " not linear.",
            FWEndOfFile: "Firmware reached the end of the file.",
            FWEndOfFileExpected: "Firmware expected an end of file.",
            FWNoMoreFiles: "Firmware cannot handle more files.",
            FWNoSpace: "Firmware reported the NXT is out of space.",
            FWNoMoreHandles: "Firmware could not create a handle.",
            FWUnknownErrorCode: "Firmware reported an unknown error code.",
            }
    # }}}

    @staticmethod
    def check(status):
        """Check status, raise on error."""
        if status.value < Status.Success:
            if status.value in Status.description:
                description = Status.description[status.value]
            else:
                description = 'error %d' % status.value
            raise FantomException(description)

class NXTIterator:
    """Interface to an iterator, to find connected NXT."""

    def __init__(self, search_bluetooth, bluetooth_search_timeout_s=5):
        """Initialize iterator."""
        self.search_bluetooth = search_bluetooth
        self.bluetooth_search_timeout_s = bluetooth_search_timeout_s
        self.handle = None
        self.stop = False

    def __iter__(self):
        """Return the iterator object itself."""
        return self

    def next(self):
        """Implement the iterator protocol."""
        if self.stop:
            raise StopIteration()
        # Find first, or find next.
        status = c_int(0)
        if self.handle is None:
            handle = dll.nFANTOM100_createNXTIterator(self.search_bluetooth,
                    self.bluetooth_search_timeout_s, byref(status))
        else:
            handle = self.handle
            dll.nFANTOM100_iNXTIterator_advance(handle, byref(status))
        # Check result.
        if status.value == Status.NoMoreItemsFound:
            self.stop = True
            raise StopIteration()
        Status.check(status)
        self.handle = handle
        # Return itself (not part of the protocol, but it has get_nxt and
        # get_name).
        return self

    def get_nxt(self):
        """Get the NXT instance."""
        if self.handle is None or self.stop:
            raise FantomException('invalid iterator')
        status = c_int(0)
        handle = dll.nFANTOM100_iNXTIterator_getNXT(self.handle, byref(status))
        Status.check(status)
        return NXT(handle)

    def get_name(self):
        """Get the NXT resource name."""
        if self.handle is None or self.stop:
            raise FantomException('invalid iterator')
        status = c_int(0)
        name = ctypes.create_string_buffer(256)
        dll.nFANTOM100_iNXTIterator_getName(self.handle, name, byref(status))
        Status.check(status)
        return name.value

    get_resource_string = get_name

    def __del__(self):
        """Destroy iterator."""
        if self.handle is not None:
            status = c_int(0)
            dll.nFANTOM100_destroyNXTIterator(self.handle, byref(status))

class NXT:
    """Interface to the NXT brick."""

    DeviceInfo = collections.namedtuple('DeviceInfo',
            'name bluetooth_address signal_strength available_flash')

    def __init__(self, name_or_handle):
        """Initialize interface."""
        if isinstance(name_or_handle, basestring):
            status = c_int(0)
            handle = dll.nFANTOM100_createNXT(name_or_handle, byref(status),
                    True)
            Status.check(status)
            self.handle = handle
        else:
            self.handle = name_or_handle

    def get_firmware_version(self):
        """Get protocol and firmware versions installed on this NXT."""
        status = c_int(0)
        protocol_major = c_ubyte(0)
        protocol_minor = c_ubyte(0)
        firmware_major = c_ubyte(0)
        firmware_minor = c_ubyte(0)
        dll.nFANTOM100_iNXT_getFirmwareVersion(self.handle,
                byref(protocol_major), byref(protocol_minor),
                byref(firmware_major), byref(firmware_minor),
                byref(status))
        Status.check(status)
        return (protocol_major.value, protocol_minor.value,
                firmware_major.value, firmware_minor.value)

    def write(self, data):
        """Write, in a generic fashion, to this NXT."""
        status = c_int(0)
        data_buffer = ctypes.create_string_buffer(data)
        ret = dll.nFANTOM100_iNXT_write(self.handle, data_buffer, len(data),
                byref(status))
        Status.check(status)
        return ret

    def read(self, length):
        """Read, in a generic fashion, from this NXT."""
        status = c_int(0)
        data_buffer = ctypes.create_string_buffer(length)
        ret = dll.nFANTOM100_iNXT_write(self.handle, data_buffer, length,
                byref(status))
        Status.check(status)
        assert ret <= length
        return data_buffer.raw[0:ret]

    def get_device_info(self):
        """Get basic information about this NXT."""
        status = c_int(0)
        name = ctypes.create_string_buffer(16)
        bluetooth_address = (c_ubyte * 7)()
        signal_strength = (c_ubyte * 4)()
        available_flash = c_uint(0)
        dll.nFANTOM100_iNXT_getDeviceInfo(self.handle, name,
                bluetooth_address, signal_strength, byref(available_flash),
                byref(status))
        return self.DeviceInfo(
                name = name.value,
                bluetooth_address = ':'.join('%02x' % c
                    for c in bluetooth_address[0:5]),
                signal_strength = tuple(c for c in signal_strength),
                available_flash = available_flash.value,
                )

    def get_resource_string(self):
        """Get the NXT resource name."""
        status = c_int(0)
        name = ctypes.create_string_buffer(256)
        dll.nFANTOM100_iNXT_getResourceString(self.handle, name,
                byref(status))
        Status.check(status)
        return name.value

    def __del__(self):
        """Destroy interface."""
        if self.handle is not None:
            status = c_int(0)
            dll.nFANTOM100_destroyNXT(self.handle, byref(status))

if __name__ == '__main__':
    get_info = False
    write_read = True
    for i in NXTIterator(False):
        if get_info:
            print "name:", i.get_name()
            print "resource string:", i.get_resource_string()
            print "get_nxt:"
            nxt = i.get_nxt()
            print " firmware version:", nxt.get_firmware_version()
            print " get device info:", nxt.get_device_info()
            rs = nxt.get_resource_string()
            print " resource string:", rs
            del nxt
            print "NXT():"
            nxt = NXT(rs)
            print " resource string:", nxt.get_resource_string()
            del nxt
        if write_read:
            nxt = i.get_nxt()
            import struct
            # Write VERSION SYS_CMD.
            # Query:
            #  SYS_CMD: 0x01
            #  VERSION: 0x88
            cmd = struct.pack('2B', 0x01, 0x88)
            r = nxt.write(cmd)
            print "wrote", r
            # Response:
            #  REPLY_CMD: 0x02
            #  VERSION: 0x88
            #  SUCCESS: 0x00
            #  PROTOCOL_VERSION minor
            #  PROTOCOL_VERSION major
            #  FIRMWARE_VERSION minor
            #  FIRMWARE_VERSION major
            rep = nxt.read(7)
            print "read", struct.unpack('%dB' % len(rep), rep)
            # Same thing, without response.
            cmd = struct.pack('2B', 0x81, 0x88)
            r = nxt.write(cmd)
            print "wrote", r
            rep = nxt.read(7)
            print struct.unpack('%dB' % len(rep), rep)
            del nxt
