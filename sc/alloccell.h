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
    ssize_t length;           /* contains number of elements if the
				 allocated block is an array; for
				 non-array elements contains value
				 a negative value (say -1). */
    ssize_t element_size;     /* Contains size of elements in the
			         allocated memory block, in bytes (NOT
			         including sizeof(alloccell_t) ). If
			         length > 0, then each element has
			         this size. If nref > 0, then each
			         element contains one reference,
			         otherwise references are allocated at
			         negative offsets and are not included
			         into element_size. If length < 0,
			         then element_size is the size of
			         memory block allocated at the
			         positive offsets after the header. If
			         nref > 0, then these references are
			         included at the beginning of the
			         block. if nref < 0, then the
			         element_size contains only
			         non-references (numbers). */
    ssize_t nref;             /* Number of references (garbage
				 collected pointers) in this memory
				 block. Negative nref signals that the
				 references are allocated before the
				 header, not after it, and grow
				 towards the beginning of the
				 memory. Negative references are not
				 included into the block sizes given
				 by elemet_size.  */
    ssize_t rcount;           /* Reference counter. Used also by garbage collector. */
    ssize_t *vmt_offset;      /* Offset to a virtual method table of a
				 class in the static data area; 0 if
				 the allocated block is not an
				 instance of a class. */
    alloccell_flag_t flags;   /* Various flags for garbage collector, etc. */
    stackcell_t memory[0];    /* Allocated memory starts here;
				 stackcell_t forces alignment */
} alloccell_t;

#endif
