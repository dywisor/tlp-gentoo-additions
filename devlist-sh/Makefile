# Makefile for tlp-pcilist.sh, tlp-usblist.sh

S := $(CURDIR)
O := $(S)

# Evaluate parameters
ifeq ($(STANDALONE),y)
TLP_LIBDIR ?= $(CURDIR)
TLP_BIN    ?= $(CURDIR)
TLP_TLIB    = $(CURDIR)
else
TLP_LIBDIR ?= /usr/lib
TLP_BIN    ?= /usr/bin
TLP_TLIB    = $(TLP_LIBDIR)/tlp-pm
endif

# Catenate DESTDIR to paths
_BIN   = $(DESTDIR)$(TLP_BIN)
_TLIB  = $(DESTDIR)$(TLP_TLIB)

DEVLIST_SCRIPTS = $(addprefix tlp-,$(addsuffix list.sh,pci usb))

PHONY =

# Make targets
PHONY += all
all: $(addprefix $(O)/,$(DEVLIST_SCRIPTS))

PHONY += clean
clean:
	rm -f -- $(addprefix $(O)/,$(DEVLIST_SCRIPTS))


PHONY += install-functions
install-functions:
	install -D -m 755 -- tlp-devlist-functions $(_TLIB)/tlp-devlist-functions

PHONY += install-pcilist
install-pcilist:
	install -D -m 755 -- tlp-pcilist.sh $(_BIN)/tlp-pcilist

PHONY += install-ubslist
install-usblist:
	install -D -m 755 -- tlp-usblist.sh $(_BIN)/tlp-usblist


$(O)/tlp-%.sh: $(S)/gen-tlp-devlist-prog.sh FORCE
	mkdir -p -- $(@D)
	$< '$*' '$(TLP_TLIB)' > $@.make_tmp
	sh -n $@.make_tmp
	mv -- $@.make_tmp $@

FORCE:

.PHONY: $(PHONY)
