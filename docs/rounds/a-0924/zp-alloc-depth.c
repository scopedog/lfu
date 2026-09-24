/* llapi_find_device() with a find_param straight from the allocator */
#include <stdio.h>
#include <stdlib.h>
#include <lustre/lustreapi.h>

int main(int argc, char **argv)
{
	struct llapi_scan_param sp = { .lfsp_size = sizeof(sp),
				       .lfsp_flags = LLAPI_SCAN_F_INTERNAL };
	struct find_param *param = llapi_find_param_alloc();
	int rc;

	if (argc > 2)
		param->fp_max_depth = atoi(argv[2]);
	rc = llapi_find_device(argv[1], param, &sp);
	fprintf(stderr, "rc=%d\n", rc);
	llapi_find_param_free(param);
	return 0;
}
