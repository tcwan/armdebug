/*
 *  FantomModule.h
 *  FantomModule
 *
 *  Created by tcmac on 01/03/2011.
 *  Copyright 2011 __MyCompanyName__. All rights reserved.
 *
 */

#ifndef FantomModule_
#define FantomModule_

#include "Python.h"
#include "fantom/iNXT.h"
#include "fantom/iNXTIterator.h"
#include "fantom/tStatus.h"

#define FANTOM_BT "BT"
#define FANTOM_USB "USB"
#define FANTOM_BT_TIMEOUTSEC 5
#define FANTOM_NXTNAME_LEN 256
#define FANTOM_DATA_BUFLEN 256
#define FANTOM_NXT_PASSKEY "1234"

/* The classes below are exported */
#pragma GCC visibility push(default)

extern "C"  PyMODINIT_FUNC initfantom(void);

extern "C"  PyObject *fantom_finddevices(PyObject *py_self, PyObject *py_args); // BT Discovery function
extern "C"  PyObject *fantom_find_bricks(PyObject *py_self, PyObject *py_args); // BT & USB function
extern "C"  PyObject *fantom_socket(PyObject *py_self, PyObject *py_args);
extern "C"  PyObject *fantom_connect(PyObject *py_self, PyObject *py_args);
extern "C"  PyObject *fantom_send(PyObject *py_self, PyObject *py_args);
extern "C"  PyObject *fantom_recv(PyObject *py_self, PyObject *py_args);
extern "C"  PyObject *fantom_close(PyObject *py_self, PyObject *py_args);

class FantomModule
{
		nFANTOM100::iNXT* nxtPtr;
		ViChar	pairedResourceName[FANTOM_NXTNAME_LEN];
	
	public:
		static PyObject *finddevices(PyObject *py_self, PyObject *py_args);
		static PyObject *find_bricks(PyObject *py_self, PyObject *py_args);
		PyObject *socket(PyObject *py_self, PyObject *py_args);
		PyObject *connect(PyObject *py_self, PyObject *py_args);
		PyObject *send(PyObject *py_self, PyObject *py_args);
		PyObject *recv(PyObject *py_self, PyObject *py_args);
		PyObject *close(PyObject *py_self, PyObject *py_args);
		~FantomModule();
		void HelloWorld(const char *);
};

#pragma GCC visibility pop
#endif
