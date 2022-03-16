# Top level makefile

# Armdebug does not have Python2 dependencies
PYTHONPATH=
SCONS=`which scons`
# Build all just compiles the ASM files into Object files
# nxos-armdebug will be the one to build the actual library
all:
	$(PYTHONPATH) $(SCONS)
	
clean:
	$(PYTHONPATH) $(SCONS) -c -u 
	
