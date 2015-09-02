S := $(CURDIR)
O := $(S)/build

X_GIT     = git
X_EDITSRC = bash $(S)/bin/tlp-editsrc.bash
X_READVER = awk -f $(S)/bin/readver
# *** scp-upload not included in this repo ***
X_UPLOAD      = $(S)/bin/scp-upload

TLP_GIT_URI      = https://github.com/linrunner/TLP.git
ifeq ($(DEVEL),1)
TLP_GIT_BRANCH   = devel
else
TLP_GIT_BRANCH   = master
endif
TLP_GIT_CHECKOUT = origin/$(TLP_GIT_BRANCH)

TLP_GIT_CPICK    =


TLP_FAKEVER   =
TLP_APPENDVER =
OFFLINE       =
FORCE_REPLACE =


PATCHES_DISTDIR    = $(S)/dist/patches
TLP_GIT_MIRROR_DIR = $(S)/local/git-src/tlp.git

GIT_COMMIT_OPTS    =
GIT_FMT_PATCH_OPTS =

BASE_PATCHES =
BASE_PATCHES += systemd-compat-no-nm-workaround.patch
EXTRA_GIT_PATCHES ?=


_GENPATCHES_WORKDIR = $(O)/work/gentoo


ifeq ($(OFFLINE),1)
UPLOAD = 0
_GITMIRROR_DEP = $(TLP_GIT_MIRROR_DIR)
else
UPLOAD = 1
_GITMIRROR_DEP = update-mirror
endif

define PRINT_HLINE
	@printf "\n%s\n\n" \
		"=================================================================="
endef

# overall, there are 4 patch steps
# * base patches
define _BASEPATCH
	test -n "$(1)"
	{ set -e; \
		$(foreach p,$(TLP_GIT_CPICK),\
			$(X_GIT) -C "$(1)" cherry-pick -x $(p) || exit;) \
	} </dev/null

	{ set -e; \
		$(foreach p,$(EXTRA_GIT_PATCHES),\
			if [ -d "$(p)" ]; then \
				for pf in $$(\
					find "$(p)" -type f -name "*.patch" | LC_ALL=C LANG=C sort \
				); do \
					$(X_GIT) -C "$(1)" am < "$${pf}" || exit; \
				done; \
			else \
				$(X_GIT) -C "$(1)" am < "$(p)" || exit; \
			fi;\
		) \
	} </dev/null

	{ $(foreach p,$(BASE_PATCHES),\
		 patch -N -d "$(1)" -up 1 -i "$(S)/files/patches/$(p)" &&\
	) true; } </dev/null;
endef

# * gentoo-base
define _GENPATCH_BASE
	test -n "$(1)"
	$(X_EDITSRC) -d "$(1)" \
		$(if    $(TLP_FAKEVER),MACRO setver $(TLP_FAKEVER)) \
		$(if    $(TLP_APPENDVER),MACRO appendver $(TLP_APPENDVER)) \
		CFGVAR  TLP_ENABLE 0 \
		MACRO   TLP_LOAD_MODULES \
		MACRO   TLP_DEBUG _ \
		MACRO   pcilist-sbin
endef

# * unbundle-tpacpi-bat  (controlled by the "tpacpi-bundled" USE flag)
define _GENPATCH_UNBUNDLE_TPACPIBAT
	test -n "$(1)"
	$(X_EDITSRC) -d "$(1)" EDITVAR TPACPIBAT /usr/bin/tpacpi-bat
endef


PHONY =

PHONY += default
default:
	@echo "Usage: make [DEVEL=1] [UPLOAD=1] [TLP_FAKEVER=] genpatches" >&2
	@echo "Usage: make [TLP_APPENDVER=] [TLP_SRC=] livepatch-base" >&2
	@echo "Usage: make [TLP_SRC=] livepatch-unbundle-tpacpi-bat" >&2
	@false

_LIVEPATCH_TARGETS = \
	$(addprefix livepatch-,basepatch base unbundle-tpacpi-bat)

PHONY += $(_LIVEPATCH_TARGETS) basepatch
ifeq ($(TLP_SRC),)
$(_LIVEPATCH_TARGETS):
	$(error $@: TLP_SRC is not set)
else
$(_LIVEPATCH_TARGETS): livepatch-%: $(TLP_SRC)/.lp_%.stamp


$(TLP_SRC)/.lp_basepatch.stamp:
	$(call _BASEPATCH,$(@D))
	touch $@

$(TLP_SRC)/.lp_base.stamp: $(TLP_SRC)/.lp_basepatch.stamp
	$(call _GENPATCH_BASE,$(@D))
	touch $@


$(TLP_SRC)/.lp_unbundle-tpacpi-bat.stamp: $(TLP_SRC)/.lp_base.stamp
	$(call _GENPATCH_UNBUNDLE_TPACPIBAT,$(@D))
	touch $@
endif

PHONY += genpatches
genpatches: $(_GENPATCHES_WORKDIR)/patches.tar.xz | $(_GENPATCHES_WORKDIR)/tlp.git
	$(eval MY_GENPATCHES_TLPVER = \
		$(shell $(X_READVER) "$(_GENPATCHES_WORKDIR)/tlp.git/tlp-functions.in"))
	test -n '$(MY_GENPATCHES_TLPVER)'

	$(eval MY_GENPATCHES_DISTFILE = \
		$(PATCHES_DISTDIR)/tlp-gentoo-patches-$(MY_GENPATCHES_TLPVER).tar.xz)

	# check if distfile checksum exists (don't replace uploaded files)
ifeq ($(FORCE_REPLACE),1)
	rm -f -- '$(MY_GENPATCHES_DISTFILE).sha512'
endif
	test ! -e '$(MY_GENPATCHES_DISTFILE).sha512'
	test ! -e '$(MY_GENPATCHES_DISTFILE)' || \
		mv -vf -- '$(MY_GENPATCHES_DISTFILE)' '$(MY_GENPATCHES_DISTFILE).old'

	mkdir -p -- $(dir $(MY_GENPATCHES_DISTFILE))
	cp -- "$<" "$(MY_GENPATCHES_DISTFILE)"

	$(call PRINT_HLINE)
	@echo "Created $(notdir $(MY_GENPATCHES_DISTFILE:%.tar.xz=%)):"
	@tar fat '$(MY_GENPATCHES_DISTFILE)' | \
		grep -v -- '/$$' | sed 's,^[.]/,  ,' | sort

	@printf "\n%s\n" "Unpacking to $(S)/gentoo-patches"
	test ! -e "$(S)/gentoo-patches" || rm -r -- "$(S)/gentoo-patches"
	mkdir -p "$(S)/gentoo-patches"
	tar xJ -C "$(S)/gentoo-patches" -f "$<" --xform="s@^[.]/patches@.@"

ifeq ($(UPLOAD),1)
	@printf "\n%s\n" "Uploading tarball"
	cd "$(dir $(MY_GENPATCHES_DISTFILE))" && \
	$(X_UPLOAD) '$(notdir $(MY_GENPATCHES_DISTFILE))'
endif



PHONY += clean
clean:
	test '$(O)' != '$(S)'
	rm -rf -- $(O)


$(_GENPATCHES_WORKDIR)/patches.tar.xz: $(_GENPATCHES_WORKDIR)/tlp.git
	$(X_GIT) -C "$<" reset --hard

	# base patches / gentoo-base
	$(call _BASEPATCH,$<)
	$(call _GENPATCH_BASE,$<)

	$(X_GIT) -C "$<" commit -a -m "gentoo-base" $(GIT_COMMIT_OPTS)

	# USE: tpacpi-bundled
	$(call _GENPATCH_UNBUNDLE_TPACPIBAT,$<)
	$(X_GIT) -C "$<" commit -a -m "unbundle-tpacpi-bat" $(GIT_COMMIT_OPTS)

	# format-patch
	mkdir -- "$</patches"
	$(X_GIT) -C "$<" format-patch \
		-o "$</patches" $(GIT_FMT_PATCH_OPTS) "$(TLP_GIT_CHECKOUT).."

	# tar it
	tar cJ --owner=root --group=root --numeric-owner -C "$<" ./patches/ -f "$(<)/$(@F)"
	mv -- "$(<)/$(@F)" "$@"


$(O)/%/tlp.git: $(_GITMIRROR_DEP) FORCE
	rm -rf -- "$@"
	mkdir -p -- "$(@D)"
	$(X_GIT) -C "$(@D)/" clone "$(TLP_GIT_MIRROR_DIR)" "$@"
	$(X_GIT) -C "$@/" checkout -b work "$(TLP_GIT_CHECKOUT)"


$(TLP_GIT_MIRROR_DIR):
	mkdir -p -- "$(@D)"
	$(X_GIT) -C "$(@D)/" clone --mirror "$(TLP_GIT_URI)/" "$@"

PHONY += update-mirror
update-mirror: $(TLP_GIT_MIRROR_DIR)
	$(X_GIT) -C "$(TLP_GIT_MIRROR_DIR)/" fetch origin
	$(X_GIT) -C "$(TLP_GIT_MIRROR_DIR)/" remote prune origin


FORCE:

.PHONY: $(PHONY)

# run one patch target at any time
.NOTPARALLEL:
