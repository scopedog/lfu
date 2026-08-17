# LFU Device Input Scanner — prototype build.
#
# One common core (src/lfu_core.c), two backends.  Each binary links the core
# plus its backend, so a host that has only one device library can still
# build that backend (design §3: the MDS build hosts lack ZFS headers, the
# workstation lacks system libext2fs).
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
CORE    := $(SRCDIR)/lfu_core.c $(SRCDIR)/lfu_filter.c
HDRS    := $(SRCDIR)/lfu_lustre.h $(SRCDIR)/lfu_scan.h $(SRCDIR)/lfu_filter.h

# --- ldiskfs backend ------------------------------------------------
E2FSROOT ?=
ifneq ($(E2FSROOT),)
CPPFLAGS += -I$(E2FSROOT)/usr/include
LDFLAGS  += -L$(E2FSROOT)/usr/lib/x86_64-linux-gnu \
            -Wl,-rpath,$(E2FSROOT)/usr/lib/x86_64-linux-gnu
endif

BIN     := $(BINDIR)/lfu-scan-ldiskfs
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
ZFS_BIN      := $(BINDIR)/lfu-scan-zfs
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

.PHONY: all clean test zfs test-zfs

all: $(BIN)

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

clean:
	@rm -rf $(BINDIR)

# --- kernel-stream backend (Option 2 consumer; design step 4) --------
# Needs no device library — it reads /dev/lfu_scan from the lfu_ring
# kernel module.  Build anywhere.
KMDT_BIN := $(BINDIR)/lfu-scan-kmdt

kmdt: $(KMDT_BIN)

$(KMDT_BIN): $(SRCDIR)/lfu_scan_kmdt.c $(CORE) $(HDRS) $(SRCDIR)/kernel/lfu_ring.h | $(BINDIR)
	$(CC) $(CFLAGS) -o $@ $(SRCDIR)/lfu_scan_kmdt.c $(CORE) -lpthread
