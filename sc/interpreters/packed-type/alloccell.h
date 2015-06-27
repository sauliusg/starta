/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __ALLOCCELL_H
#define __ALLOCCELL_H

#include <stackcell.h>

#define BC_MAGIC 0x55AA55AA

typedef enum {
    AF_NONE = 0x00,
    AF_USED = 0x01,
    AF_last
} alloccell_flag_t;

typedef struct alloccell_t {
    int magic;                /* Magic number */
    struct alloccell_t *next; /* Next node in a garbage colector's list */
    struct alloccell_t *prev; /* Previous node in a garbage colector's list */
    short flags;              /* Various flags for garbage collector, etc. */
    short element_size;       /* Contains size of elements in the
			         allocated memory block, in bytes (NOT
			         including sizeof(alloccell_t)). */
    ssize_t size;             /* Contains size the allocated memory
			         block in bytes (NOT including
			         sizeof(alloccell_t) ). If length > 0,
			         'size' there MUST be enough for at
			         least 'length' blocks of size
			         'element_size'. If length == 0, there
			         MAY be *no* blocks allocated after
			         the alloccell_t header (and size ==
			         0). If length == -1, the allocated
			         block is not an array, but rather a
			         structure or an object and there is
			         exactely *one* block of size 'size'
			         allocated. Sizes of fields both
			         before the header (references) and
			         after the header (plain numbers) are
			         added up in this value, with
			         paddings. */
    ssize_t length;           /* contains number of elements if the
				 allocated block is an array; for
				 non-array elements contains value a
				 negative value -1. Other negative
				 values are reserved.*/
    ssize_t nref;             /* Number of references (garbage
				 collected pointers) in this memory
				 block. Negative nref signals that the
				 references are allocated before the
				 header, not after it, and grow
				 towards the beginning of the
				 memory. Negative references are not
				 included into the block sizes given
				 by elemet_size.  */
    ssize_t rcount;           /* Reference counter. Used by garbage collectors. */
    ssize_t *vmt_offset;      /* Offset to a virtual method table of a
				 class in the static data area; 0 if
				 the allocated block is not an
				 instance of a class. */
    char memory[0];           /* Allocated memory starts here;
				 stackcell_t forces alignment */
} alloccell_t;

void alloccell_set_values( alloccell_t *hdr, ssize_t element_size,
                           ssize_t len );

#endif
