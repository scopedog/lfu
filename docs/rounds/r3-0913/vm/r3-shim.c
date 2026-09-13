/* fd5bc71b: fail LL_IOC_GETOBDCOUNT, pass every other ioctl through */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <sys/ioctl.h>
#include <lustre/lustreapi.h>

int ioctl(int fd, unsigned long req, ...)
{
	static int (*real)(int, unsigned long, ...);
	va_list ap;
	void *arg;

	va_start(ap, req);
	arg = va_arg(ap, void *);
	va_end(ap);
	if (req == LL_IOC_GETOBDCOUNT) {
		fprintf(stderr, "shim: LL_IOC_GETOBDCOUNT -> EIO\n");
		errno = EIO;
		return -1;
	}
	if (real == NULL)
		real = dlsym(RTLD_NEXT, "ioctl");
	return real(fd, req, arg);
}
