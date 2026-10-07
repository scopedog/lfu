struct page;
struct bio;
#include <stddef.h>
#include <stdio.h>
#include <sys/zfs_context.h>
#include <sys/dnode.h>
#include <sys/dbuf.h>
#include <sys/abd.h>
int main(void)
{
	printf("sizeof(zfs_refcount_t)=%zu sizeof(dnode_t)=%zu "
	       "offsetof(dn_num_slots)=%zu offsetof(dn_tx_holds)=%zu "
	       "offsetof(dn_holds)=%zu offsetof(dn_dbufs_mtx)=%zu "
	       "sizeof(dmu_buf_t)=%zu sizeof(abd_t)=%zu\n",
	       sizeof(zfs_refcount_t), sizeof(dnode_t),
	       offsetof(dnode_t, dn_num_slots), offsetof(dnode_t, dn_tx_holds),
	       offsetof(dnode_t, dn_holds), offsetof(dnode_t, dn_dbufs_mtx),
	       sizeof(dmu_buf_t), sizeof(abd_t));
	return 0;
}
