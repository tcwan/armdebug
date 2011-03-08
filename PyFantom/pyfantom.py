from ctypes import *
import ctypes.util
import platform

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
dll = cdll.LoadLibrary(libpath)
dll.nFANTOM100_createNXTIterator.argtypes = [c_ushort, c_uint, POINTER(c_int)]
dll.nFANTOM100_createNXTIterator.restype = c_uint
dll.nFANTOM100_destroyNXTIterator.argtypes = [c_int, POINTER(c_int)]
dll.nFANTOM100_destroyNXTIterator.restype = None
dll.nFANTOM100_iNXTIterator_advance.argtypes = [c_uint, POINTER(c_int)]
dll.nFANTOM100_iNXTIterator_advance.restype = None
dll.nFANTOM100_iNXTIterator_getNXT.argtypes = [c_uint, POINTER(c_int)]
dll.nFANTOM100_iNXTIterator_getNXT.restype = c_uint
dll.nFANTOM100_iNXTIterator_getName.argtypes = [c_uint, c_char_p, POINTER(c_int)]
dll.nFANTOM100_iNXTIterator_getName.restype = None

# Status codes.
StatusOffset = -142000
StatusNoMoreItemsFound = StatusOffset - 17
StatusSuccess = 0

def check_status (status):
    """Check status, raise on error."""
    if status.value < StatusSuccess:
        raise FantomException('bad status')

class FantomException(RuntimeError):
    pass

class NXTIterator:
    """Interface to an iterator, to find connected NXT."""

    def __init__(self, search_bluetooth,
        bluetooth_search_timeout_in_seconds = 5):
        """Initialize iterator."""
        self.search_bluetooth = search_bluetooth
        self.bluetooth_search_timeout_in_seconds = \
                bluetooth_search_timeout_in_seconds
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
                    self.bluetooth_search_timeout_in_seconds, byref(status))
        else:
            handle = self.handle
            dll.nFANTOM100_iNXTIterator_advance(handle, byref(status))
        # Check result.
        if status.value == StatusNoMoreItemsFound:
            self.stop = True
            raise StopIteration()
        check_status (status)
        self.handle = handle
        # Return itself (not part of the protocol, but it has get_nxt and
        # get_name).
        return self

    def get_nxt(self):
        """Get the NXT instance."""
        if self.handle is None or self.stop:
            raise FantomException('invalid iterator')
        status = c_int(0)
        nxt = dll.nFANTOM100_iNXTIterator_getNXT(self.handle, byref(status))
        check_status (status)
        # XXX
        return nxt.value

    def get_name(self):
        """Get the NXT resource name."""
        if self.handle is None or self.stop:
            raise FantomException('invalid iterator')
        status = c_int(0)
        name = create_string_buffer (256)
        dll.nFANTOM100_iNXTIterator_getName(self.handle, name, byref(status))
        check_status (status)
        return name.value

    def __del__(self):
        """Destroy iterator."""
        if self.handle is not None:
            status = c_int(0)
            dll.nFANTOM100_destroyNXTIterator(self.handle, byref(status))

if __name__ == '__main__':
    for i in NXTIterator(False):
        print i.get_name()
