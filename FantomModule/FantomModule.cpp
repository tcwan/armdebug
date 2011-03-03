/*
 *  FantomModule.cp
 *  FantomModule
 *
 *  Created by tcmac on 01/03/2011.
 *  Copyright 2011 TC Wan. All rights reserved.
 *
 *  Based on code from Fantom Driver 1.0.2f0 Example
 *  © Copyright 2006, National Instruments Corporation.
 *  All rights reserved. Originated:  10 March 2006
 *
 */

#include <iostream>
#include <string.h>
#include "FantomModule.h"
#include "FantomModulePriv.h"

static PyMethodDef FantomMethods[] = {
    {"finddevices",  fantom_finddevices, METH_VARARGS,
		"Discover NXT Devices (BT Discovery)"},
    {"find_bricks",  fantom_find_bricks, METH_VARARGS,
		"Find and Create NXT Devices (USB)"},
    {"socket",  fantom_socket, METH_VARARGS,
		"Create a Socket for a NXT Brick"},
    {"connect",  fantom_connect, METH_VARARGS,
		"Connect the Socket to a NXT Brick"},
    {"send",  fantom_send, METH_VARARGS,
		"Send Data via the Socket to a NXT Brick"},
    {"recv",  fantom_recv, METH_VARARGS,
		"Receive Data via the Socket from a NXT Brick"},
    {"close",  fantom_close, METH_VARARGS,
		"Close the Socket to a NXT Brick"},
    {NULL, NULL, 0, NULL}        /* Sentinel */
};

extern "C"  PyMODINIT_FUNC
initfantom(void)
{
    (void) Py_InitModule("fantom", FantomMethods);
}

extern "C"  PyObject *fantom_finddevices(PyObject *py_self, PyObject *py_args)
{
	
	PyObject *list = FantomModule::finddevices(py_self,py_args);
	
	return list;	// of resource names
}

extern "C"  PyObject *fantom_find_bricks(PyObject *py_self, PyObject *py_args)
{

	PyObject *list = FantomModule::find_bricks(py_self,py_args);
	
	return list;	// of FantomModule objects
}

extern "C"  PyObject *fantom_socket(PyObject *py_self, PyObject *py_args)
{
	
	ViChar  newPasskey[FANTOM_PASSKEY_LEN] = FANTOM_NXT_PASSKEY;	// Default Passkey

	// FIXME: Retrieve PyObject's proto setting
	const char *proto;
	if (!PyArg_ParseTuple(py_args, "s", &proto))
        return NULL;
	ViBoolean enableBT = strcmp(proto, FANTOM_BT) ? true : false;
	
	// Get new passkey from Python args if specified
	
	// Create a FantomModule object, which has not been connected to an actual NXT yet
	FantomModule *fantomObject;
	fantomObject = new FantomModule;
	
	fantomObject->socket(enableBT, newPasskey);			// Internal object setup

	// FIXME: Convert fantomObject to PyObject and return.

}

extern "C"  PyObject *fantom_connect(PyObject *py_self, PyObject *py_args)
{
	FantomModule *fantomObject;
	// FIXME: Retrieve FantomObject from PyObject variable
	ViChar resourceName[FANTOM_NXTNAME_LEN];
	ViBoolean success;
	
	success = fantomObject->connect(resourceName);
}

extern "C"  PyObject *fantom_send(PyObject *py_self, PyObject *py_args)
{
	FantomModule *fantomObject;
	// FIXME: Retrieve FantomObject from PyObject variable

	ViByte bufferPtr[FANTOM_DATA_BUFLEN];
	ViUInt32 numberOfBytes;
	ViUInt32 bytesSent;
	
	bytesSent = fantomObject->send(bufferPtr,numberOfBytes);
}

extern "C"  PyObject *fantom_recv(PyObject *py_self, PyObject *py_args)
{
	FantomModule *fantomObject;
	// FIXME: Retrieve FantomObject from PyObject variable

	ViByte bufferPtr[FANTOM_DATA_BUFLEN];
	ViUInt32 numberOfBytes;
	ViUInt32 bytesReceived;
	
	bytesReceived = fantomObject->recv(bufferPtr,numberOfBytes);
}

extern "C"  PyObject *fantom_close(PyObject *py_self, PyObject *py_args)
{
	FantomModule *fantomObject;
	// FIXME: Retrieve FantomObject from PyObject variable
	
	ViBoolean success = fantomObject->close();
	delete fantomObject;
	
	// Return success/failure
}


// Static method called directly from C
PyObject *FantomModule::finddevices(PyObject *py_self, PyObject *py_args)
{
	const char *proto;
	if (!PyArg_ParseTuple(py_args, "s", &proto))
        return NULL;

	ViBoolean useBT = strcmp(proto, FANTOM_BT) ? true : false;
	
	PyObject *list = NULL;
	
	nFANTOM100::iNXTIterator* nxtIteratorPtr;
	nFANTOM100::tStatus status;
	
	// Create an NXT iterator object which is used to find all accessible NXT devices.
	nxtIteratorPtr = nFANTOM100::iNXT::createNXTIterator(useBT, (useBT ? FANTOM_BT_TIMEOUTSEC : 0), status);
	
	// Creating the NXT iterator object could fail, better check status before dereferencing a
	//    potentially NULL pointer.
	while (status.isNotFatal())
	{
		ViChar nxtName[FANTOM_NXTNAME_LEN];
		nxtIteratorPtr->getName(nxtName, status);
		
		std::cout << "Found: " << nxtName << std::endl;

		if (status.isNotFatal())
		{
			// Split nxtName into NXT ID (h) and NXT Name (n)
			// return as [(h,n),...]
			// FIXME: Append to Python list
			/*
			 return Py_BuildValue("i", sts);
			 */
		}
		nxtIteratorPtr->advance(status);
		
	}
	// Destroy the NXT iterator object which we no longer need
	nFANTOM100::iNXT::destroyNXTIterator( nxtIteratorPtr );
	return list;
	
}

// Static method called directly from C
PyObject *FantomModule::find_bricks(PyObject *py_self, PyObject *py_args)
{
	const char *host, *name;
	if (!PyArg_ParseTuple(py_args, "ss", &host, &name))
        return NULL;
	
	ViBoolean useBT = false;
	
	PyObject *list = NULL;

	
	nFANTOM100::iNXTIterator* nxtIteratorPtr;
	nFANTOM100::tStatus status;
	
	// Create an NXT iterator object which is used to find all accessible NXT devices.
	nxtIteratorPtr = nFANTOM100::iNXT::createNXTIterator(useBT, (useBT ? FANTOM_BT_TIMEOUTSEC : 0), status);
	
	// Creating the NXT iterator object could fail, better check status before dereferencing a
	//    potentially NULL pointer.
	while (status.isNotFatal())
	{
		ViChar nxtName[FANTOM_NXTNAME_LEN];
		nFANTOM100::iNXT* aNXT = NULL;
		
		nxtIteratorPtr->getName(nxtName, status);
		std::cout << "Found: " << nxtName << std::endl;
		aNXT = nxtIteratorPtr->getNXT(status);
		if (status.isNotFatal())
		{
			FantomModule *aFantomObject = new FantomModule;
			aFantomObject->nxtPtr = aNXT;
			aFantomObject->status.assign(status);
			if (strlcpy(aFantomObject->pairedResourceName, nxtName, FANTOM_NXTNAME_LEN) >= FANTOM_NXTNAME_LEN)
			{
				// Exceeded Name Length
				std::cout << "NXTName Length Exceeded: " << nxtName << std::endl;
				delete aFantomObject;
			}
			else 
			{
				// FIXME: Append to Python list
				/*
				 return Py_BuildValue("i", sts);
				 */
			}

		}
		nxtIteratorPtr->advance(status);
		
	}
	// Destroy the NXT iterator object which we no longer need
	nFANTOM100::iNXT::destroyNXTIterator( nxtIteratorPtr );
	return list;
	
}

ViBoolean FantomModule::socket(ViBoolean enableBT, ViConstString BTkey)
{
	// Internal class object setup
	nxtPtr = NULL;
	useBT = enableBT;
	if (strlcpy(passkey, BTkey, FANTOM_PASSKEY_LEN) >= FANTOM_PASSKEY_LEN)
		return false;
	return true;
	
}

ViBoolean FantomModule::connect(ViConstString resourceName)
{
	// If a NXT is found over BT, the computer and the NXT must be paired before an NXT object can be
	// created.  This can be done programatically using the iNXT::pairBluetooth method.
	// FIXME: Retrieve resource String
	

	if (useBT and !nFANTOM100::iNXT::isPaired((ViConstString)resourceName,status))
		nFANTOM100::iNXT::pairBluetooth((ViConstString) resourceName, (ViConstString) passkey, (ViChar *) pairedResourceName, status);
	
	if (status.isNotFatal())
		{
			nxtPtr = nFANTOM100::iNXT::createNXT((ViConstString) resourceName, status, false);
		}
}

ViUInt32 FantomModule::send(const ViByte *bufferPtr, ViUInt32 numberOfBytes)
{
	nFANTOM100::tStatus status;
	
	return nxtPtr->write(bufferPtr, numberOfBytes, status);
}

ViUInt32 FantomModule::recv(ViByte *bufferPtr, ViUInt32 numberOfBytes)
{
	nFANTOM100::tStatus status;
	
	return nxtPtr->read(bufferPtr, numberOfBytes, status);
}	

ViBoolean FantomModule::close()
{
	
	const char *proto;
	useBT = strcmp(proto, FANTOM_BT) ? true : false;
	if (useBT and nFANTOM100::iNXT::isPaired((ViConstString)pairedResourceName,status))
		nFANTOM100::iNXT::unpairBluetooth((ViConstString) pairedResourceName, status);			// No Effect on Mac OSX

	if (nxtPtr)
		nFANTOM100::iNXT::destroyNXT(nxtPtr);
	nxtPtr = NULL;
	
	return true;
}

FantomModule::~FantomModule()
{
	if (nxtPtr)
		nFANTOM100::iNXT::destroyNXT(nxtPtr);
	nxtPtr = NULL;

}

// Skeleton functions from Xcode
void FantomModule::HelloWorld(const char * s)
{
	 FantomModulePriv *theObj = new FantomModulePriv;
	 theObj->HelloWorldPriv(s);
	 delete theObj;
};

void FantomModulePriv::HelloWorldPriv(const char * s) 
{
	std::cout << s << std::endl;
};

