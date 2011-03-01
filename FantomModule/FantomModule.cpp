/*
 *  FantomModule.cp
 *  FantomModule
 *
 *  Created by tcmac on 01/03/2011.
 *  Copyright 2011 TC Wan. All rights reserved.
 *
 *  Based on code from Fantom Driver 1.0.2f0 Example
 *  © Copyright 2006,
 *  National Instruments Corporation.
 *  All rights reserved.
 * 
 *  Originated:  10 March 2006
 *
 */

#include <iostream>
#include <string.h>
#include "FantomModule.h"
#include "FantomModulePriv.h"

static PyMethodDef FantomMethods[] = {
    {"finddevices",  fantom_finddevices, METH_VARARGS,
		"Find a NXT Device"},
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
	FantomModule *fantomObject;
	fantomObject = new FantomModule;
	
	PyObject *list = fantomObject->finddevices(py_self,py_args);
	delete fantomObject;
	
	return list;
}

extern "C"  PyObject *fantom_socket(PyObject *py_self, PyObject *py_args)
{
	
	// Create a FantomModule object, which has not been connected to an actual NXT yet
	FantomModule *fantomObject;
	fantomObject = new FantomModule;
	
	// FIXME: Attach fantomObject to PyObject variable.
	fantomObject->socket(py_self,py_args);			// Internal object setup
	
}

extern "C"  PyObject *fantom_connect(PyObject *py_self, PyObject *py_args)
{
	FantomModule *fantomObject;
	// FIXME: Retrieve FantomObject from PyObject variable
	
	return fantomObject->connect(py_self,py_args);
}

extern "C"  PyObject *fantom_send(PyObject *py_self, PyObject *py_args)
{
	FantomModule *fantomObject;
	// FIXME: Retrieve FantomObject from PyObject variable
	
	return fantomObject->send(py_self,py_args);
}

extern "C"  PyObject *fantom_recv(PyObject *py_self, PyObject *py_args)
{
	FantomModule *fantomObject;
	// FIXME: Retrieve FantomObject from PyObject variable
	
	return fantomObject->recv(py_self,py_args);
}

extern "C"  PyObject *fantom_close(PyObject *py_self, PyObject *py_args)
{
	FantomModule *fantomObject;
	// FIXME: Retrieve FantomObject from PyObject variable
	
	return fantomObject->close(py_self,py_args);
}

PyObject *FantomModule::finddevices(PyObject *py_self, PyObject *py_args)
{
	const char *proto;
	if (!PyArg_ParseTuple(py_args, "s", &proto))
        return NULL;

	ViBoolean useBT;
	useBT = strcmp(proto, FANTOM_BT) ? true : false;
	
	PyObject *list = NULL;
	
	nFANTOM100::iNXTIterator* nxtIteratorPtr;
	
	// Create an NXT iterator object which is used to find all accessible NXT devices.
	nxtIteratorPtr = nFANTOM100::iNXT::createNXTIterator(useBT, FANTOM_BT_TIMEOUTSEC, status);
	
	// Creating the NXT iterator object could fail, better check status before dereferencing a
	//    potentially NULL pointer.
	if( status.isNotFatal())
	{
		ViChar nxtName[FANTOM_NXTNAME_LEN];
		nxtIteratorPtr->getName(nxtName, status);
		if( status.isNotFatal())
		{
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

PyObject *FantomModule::socket(PyObject *py_self, PyObject *py_args)
{
	// Internal class object setup
	iNXT = NULL;
	
}

PyObject *FantomModule::connect(PyObject *py_self, PyObject *py_args)
{
	// If a NXT is found over BT, the computer and the NXT must be paired before an NXT object can be
	// created.  This can be done programatically using the iNXT::pairBluetooth method.
	// FIXME: Retrieve resource String
	ViConstString resourceName[FANTOM_NXTNAME_LEN];
	ViConstString passkey[FANTOM_NXTNAME_LEN] = { FANTOM_NXT_PASSKEY };

	// FIXME: Retrieve PyObject's proto setting
	ViBoolean	  useBT;
	useBT = strcmp(proto, FANTOM_BT) ? true : false;
	if (useBT)
		nFANTOM100::iNXT::pairBluetooth((ViConstString) resourceName, (ViConstString) passkey, (ViChar *) pairedResourceName, status);
	
	if (status.isNotFatal())
		{
			nxtPtr = nFANTOM100::iNXT::createNXT((ViConstString) resourceName, status, false);
		}
}

PyObject *FantomModule::send(PyObject *py_self, PyObject *py_args)
{
	ViByte bufferPtr[FANTOM_DATA_BUFLEN];
	ViUInt32 numberOfBytes;
	
	nxtPtr->write(bufferPtr, numberOfBytes, status);
}

PyObject *FantomModule::recv(PyObject *py_self, PyObject *py_args)
{
	ViByte bufferPtr[FANTOM_DATA_BUFLEN];
	ViUInt32 numberOfBytes;
	ViUInt32 bytesRead;
	
	bytesRead = nxtPtr->read(bufferPtr, numberOfBytes, status);
}	

PyObject *FantomModule::close(PyObject *py_self, PyObject *py_args)
{
	nFANTOM100::iNXT::destroyNXT(nxtPtr);
	// FIXME: Retrieve resource String
	ViConstString resourceName[FANTOM_NXTNAME_LEN];

	// FIXME: Retrieve PyObject's proto setting
	ViBoolean	  useBT;
	useBT = strcmp(proto, FANTOM_BT) ? true : false;
	if (useBT)
		nFANTOM100::iNXT::unpairBluetooth((ViConstString) resourceName, status);			// No Effect on Mac OSX
	// FIXME: Set PyObject socket to None
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

