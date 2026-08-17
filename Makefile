# LFU Device Input Scanner — prototype build.
#
# One common core (src/lfu_core.c), three backends, and one command over them.
#
# `lfind` is the user-facing name; the backends are separate binaries only
# because a host that has just one device library must still be able to build
# the backend it can (design §3: the MDS build hosts lack ZFS headers, a
# workstation may lack libext2fs).  lfind picks one from the target and execs
# it, so that packaging constraint does not reach the command line.
#
# libext2fs is not a system package on this workstation.  Point E2FSROOT at an
# extracted libext2fs-dev tree to build against it without installing:
#
#   make E2FSROOT=/path/to/extracted/root
#
# With libext2fs-dev installed system-wide, plain `make` works.

CC      ?= gcc
CFLAGS  ?= -O2 -g -Wall -Wextra -Wno-unused-parameter
CFLAGS  += -std=gnu11

SRCDIR  := src
BINDIR  := build
# The core is two files: the scan pipeline and the filter compiler.  Both
# are device-library-free, so every backend links the same pair.
CORE    := $(SRCDIR)/lfu_core.c $(SRCDIR)/lfu_filter.c $(SRCDIR)/lfu_filter_eval.c
HDRS    := $(SRCDIR)/lfu_lustre.h $(SRCDIR)/lfu_scan.h $(SRCDIR)/lfu_filter.h

# --- ldiskfs backend ------------------------------------------------
E2FSROOT ?=
ifneq ($(E2FSROOT),)
CPPFLAGS += -I$(E2FSROOT)/usr/include
LDFLAGS  += -L$(E2FSROOT)/usr/lib/x86_64-linux-gnu \
            -Wl,-rpath,$(E2FSROOT)/usr/lib/x86_64-linux-gnu
endif

BIN     := $(BINDIR)/lfind-ldiskfs
LDLIBS  += -lext2fs -lcom_err -lpthread

# --- ZFS backend (design-zfs-scanner.md route 1) --------------------
# Needs zfs dev headers.  Two layouts in the wild:
#
#   Ubuntu (libzfslinux-dev)  — installed headers are self-contained:
#       make zfs
#
#   RHEL/Rocky (libzfs5-devel) — /usr/include/libzfs omits the userspace
#   os-specific headers (sys/abd_os.h and friends), so a libzpool consumer
#   cannot be built from them.  Build against the zfs source tree the
#   dkms package unpacks instead — the same include set OpenZFS uses for
#   libzpool itself:
#       make zfs ZFS_SRC=/usr/src/zfs-2.2.10
#
# Separate target, not in `all`: the MDS build hosts lack these headers.
ZFS_BIN      := $(BINDIR)/lfind-zfs
ZFS_SRC      ?=
ifeq ($(ZFS_SRC),)
ZFS_CPPFLAGS := -I/usr/include/libzfs -I/usr/include/libspl
else
ZFS_CPPFLAGS := -I$(ZFS_SRC)/lib/libzpool/include \
                -I$(ZFS_SRC)/lib/libspl/include \
                -I$(ZFS_SRC)/lib/libspl/include/os/linux \
                -I$(ZFS_SRC)/include
endif
ZFS_LDLIBS   := -lzpool -lnvpair -lpthread

# The dispatcher links no device library, so it builds anywhere.
FRONT   := $(BINDIR)/lfind

# --- install ---------------------------------------------------------
# GNU-standard variables, so a spec file can override any of them and
# DESTDIR staging works:  make install DESTDIR=%{buildroot}
prefix      ?= /usr
exec_prefix ?= $(prefix)
sbindir     ?= $(exec_prefix)/sbin
datarootdir ?= $(prefix)/share
mandir      ?= $(datarootdir)/man
INSTALL     ?= install
MANPAGE     := Documentation/man8/lfind.8

# Everything goes in one directory, front-end and backends together.  The
# front-end finds a backend next to itself first (src/lfind.c: dirname of
# argv[0], then $LFIND_LIBEXEC, then PATH), so co-location needs no compiled-in
# path and no environment variable, and it keeps working whether lfind is
# invoked by absolute path or found on PATH.  A libexec split would need one of
# the two, for no gain -- these are all root-only tools reading a raw target.

.PHONY: all clean test zfs test-zfs front install install-man uninstall

all: $(FRONT) $(BIN)

front: $(FRONT)

$(FRONT): $(SRCDIR)/lfind.c | $(BINDIR)
	$(CC) $(CFLAGS) -o $@ $(SRCDIR)/lfind.c

$(BIN): $(SRCDIR)/lfu_scan_ldiskfs.c $(CORE) $(HDRS) | $(BINDIR)
	$(CC) $(CFLAGS) $(CPPFLAGS) -o $@ \
		$(SRCDIR)/lfu_scan_ldiskfs.c $(CORE) $(LDFLAGS) $(LDLIBS)

$(BINDIR):
	@mkdir -p $(BINDIR)

zfs: $(ZFS_BIN)

$(ZFS_BIN): $(SRCDIR)/lfu_scan_zfs.c $(CORE) $(HDRS) | $(BINDIR)
	$(CC) $(CFLAGS) $(ZFS_CPPFLAGS) -o $@ \
		$(SRCDIR)/lfu_scan_zfs.c $(CORE) $(ZFS_LDLIBS)

test: $(BIN)
	@tests/run_tests.sh

test-zfs: $(ZFS_BIN)
	@tests/run_tests_zfs.sh

# Installs what this host actually built, rather than depending on `all`:
# no host builds all three backends (the MDS hosts lack ZFS headers, and the
# kmdt backend is only useful where lfu_ring is loaded), so a hard dependency
# would make `install` fail on every real machine.  Build first, then install.
#
# The man page is installed by a sub-make rather than a prerequisite so that a
# failed binary check leaves nothing behind at all -- prerequisite order is not
# guaranteed under -j.
install:
	@test -d $(BINDIR) || { \
		echo "make install: nothing built -- run make [zfs] [kmdt] first" >&2; \
		exit 1; }
	@found=; \
	for b in lfind lfind-ldiskfs lfind-zfs lfind-kmdt; do \
		test -x $(BINDIR)/$$b || continue; \
		found="$$found $$b"; \
	done; \
	test -n "$$found" || { \
		echo "make install: nothing built -- run make [zfs] [kmdt] first" >&2; \
		exit 1; }; \
	$(INSTALL) -d $(DESTDIR)$(sbindir); \
	for b in $$found; do \
		echo "  install $$b -> $(DESTDIR)$(sbindir)"; \
		$(INSTALL) -m 755 $(BINDIR)/$$b $(DESTDIR)$(sbindir)/$$b || exit 1; \
	done; \
	case "$$found" in \
	*lfind-*) ;; \
	*) echo "make install: warning: lfind installed with no backend" >&2 ;; \
	esac
	@$(MAKE) --no-print-directory install-man

install-man:
	@$(INSTALL) -d $(DESTDIR)$(mandir)/man8
	@echo "  install $(MANPAGE) -> $(DESTDIR)$(mandir)/man8"
	@$(INSTALL) -m 644 $(MANPAGE) $(DESTDIR)$(mandir)/man8/lfind.8

uninstall:
	@for b in lfind lfind-ldiskfs lfind-zfs lfind-kmdt; do \
		rm -f $(DESTDIR)$(sbindir)/$$b; \
	done
	@rm -f $(DESTDIR)$(mandir)/man8/lfind.8

clean:
	@rm -rf $(BINDIR)

# --- kernel-stream backend (Option 2 consumer; design step 4) --------
# Needs no device library — it reads /dev/lfu_scan from the lfu_ring
# kernel module.  Build anywhere.
KMDT_BIN := $(BINDIR)/lfind-kmdt

kmdt: $(KMDT_BIN)

$(KMDT_BIN): $(SRCDIR)/lfu_scan_kmdt.c $(CORE) $(HDRS) $(SRCDIR)/kernel/lfu_ring.h | $(BINDIR)
	$(CC) $(CFLAGS) -o $@ $(SRCDIR)/lfu_scan_kmdt.c $(CORE) -lpthread
