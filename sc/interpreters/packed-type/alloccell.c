/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* exports: */
#include <alloccell.h>

/* uses: */
#include <assert.h>

void alloccell_set_values( alloccell_t *hdr, ssize_t element_size,
                           ssize_t len )
{
    assert( hdr );
    hdr->magic = BC_MAGIC;
    hdr->flags |= AF_USED;
    hdr->length = len;
    hdr->element_size = element_size;
}

