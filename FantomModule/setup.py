from distutils.core import setup, Extension
import sys
import os

def getextensions():
    mac_ext = Extension("FantomModule",
        define_macros=[('PYFANTOM_DEBUG', '0')],    # set to '1' to print debug messges
        include_dirs=['.'],
        extra_compile_args=["-Wno-strict-prototypes"],
        extra_link_args=["-framework Fantom"],
        sources=["FantomModule.cpp"]
        )
    return [mac_ext]

# Must specify i386 arch via environment variable since Fantom libraries are i386 only
# Order of gcc flags is important, it can't be specified via Extension() module
os.environ['ARCHFLAGS'] = '-arch i386'

# install the main library
setup(name="pyfantom",
    version="0.1",
    author="Tat-Chee Wan",
    author_email="tcwan@cs.usm.my",
    url="",
    description="Python Extension to call Fantom Driver",
    long_description="Python Wrapper for Fantom Driver on Mac OS X.",
    license="GPL",
    packages=["pyfantom"],
    ext_modules=getextensions(),
    classifiers = [ "Development Status :: 3 - Alpha",
        "Intended Audience :: Developers",
        # Need to confirm Fantom / NI-VISA license compatibility
        # "License :: OSI Approved :: GNU General Public License (GPL)",
        # "License :: OSI Approved :: GNU General Public License v2",
        "Programming Language :: C++",
        "Topic :: Software Development :: Libraries",
        "Topic :: System :: Networking",
        "Topic :: Communications",
        "Operating System :: MacOS :: MacOS X" ]
    )
