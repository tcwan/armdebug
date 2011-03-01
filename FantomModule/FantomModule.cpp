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
}

extern "C"  PyObject *fantom_connect(PyObject *py_self, PyObject *py_args)
{
}

extern "C"  PyObject *fantom_send(PyObject *py_self, PyObject *py_args)
{
}

extern "C"  PyObject *fantom_recv(PyObject *py_self, PyObject *py_args)
{
}

extern "C"  PyObject *fantom_close(PyObject *py_self, PyObject *py_args)
{
}

PyObject *FantomModule::finddevices(PyObject *py_self, PyObject *py_args)
{
	const char *proto;
	if (!PyArg_ParseTuple(py_args, "s", &proto))
        return NULL;

	ViBoolean useBT;
	useBT = strcmp(proto, FANTOM_BT) ? true : false;
	
/*
	const char *command;
    int sts;
	
    if (!PyArg_ParseTuple(py_args, "s", &command))
        return NULL;
    sts = system(command);
    return Py_BuildValue("i", sts);
*/
	
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
		}
		nxtIteratorPtr->advance(status);
		
	}
	// Destroy the NXT iterator object which we no longer need
	nFANTOM100::iNXT::destroyNXTIterator( nxtIteratorPtr );
	
}

PyObject *FantomModule::socket(PyObject *py_self, PyObject *py_args)
{
	// Create an NXT object for the first NXT that was found.  Note that if a NXT is found
	//    over BT, the computer and the NXT must be paired before an NXT object can be
	//    created.  This can be done programatically using the iNXT::pairBluetooth method.
	// nxtPtr = nxtIteratorPtr->getNXT( status );
}

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

