/* Does each kernel_init()/kernel_fini() cycle leak a pthread key? */
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <errno.h>
#include <string.h>
typedef unsigned int uint_t;
extern void kernel_init(int mode);
extern void kernel_fini(void);
extern uint_t rrw_tsd_key;
extern char *spa_config_path;
#define SPA_MODE_READ 1
int main(int argc, char **argv)
{
	int fix = atoi(argv[1]), n = atoi(argv[2]), i;
	pthread_key_t k;
	spa_config_path = (char *)"";
	for (i = 0; i < n; i++) {
		kernel_init(SPA_MODE_READ);
		kernel_fini();
		if (fix)
			pthread_key_delete((pthread_key_t)rrw_tsd_key);
	}
	int free_keys = 0, rc;
	while ((rc = pthread_key_create(&k, NULL)) == 0)
		free_keys++;
	printf("fix=%d cycles=%d: keys still free = %d (then %s), last rrw_tsd_key %u\n",
	       fix, n, free_keys, strerror(rc), rrw_tsd_key);
	return 0;
}
