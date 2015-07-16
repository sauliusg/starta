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
    AF_READONLY = 0x02,
    AF_HAS_REFS = 0x04,
    AF_last
} alloccell_flag_t;

typedef struct alloccell_t {
    int magic;                /* Magic number */
    struct alloccell_t *next; /* Next node in a garbage colector's list */
    struct alloccell_t *prev; /* Previous node in a garbage colector's list */
    ssize_t length;           /* contains number of elements if the
				 allocated block is an array; for
				 non-array elements contains value
				 -1. For strings should contain
				 strlen() of the string, which will be
				 as a rule size - 1 (the last '\0'
				 byte is not counted in 'length'. */
    ssize_t size;             /* Contains size the allocated memory
			         block in bytes (NOT including
			         sizeof(alloccell_t) ). */
    ssize_t nref;             /* Number of references (garbage collected 
				 pointers) in this memory block */
    ssize_t rcount;           /* Reference counter. Used also by garbage collector. */
    ssize_t *vmt_offset;      /* Offset to a virtual method table of a
				 class in the static data area; 0 if
				 the allocated block is not an
				 instance of a class. */
    alloccell_flag_t flags;   /* Various flags for garbage collector, etc. */
    stackcell_t memory[0];    /* Allocated memory starts here;
				 stackcell_t forces alignment */
} alloccell_t;

void alloccell_set_values( alloccell_t *hdr, ssize_t element_size,
                           ssize_t len );

#define alloccell_has_references(ac)  (((ac).flags & AF_HAS_REFS) != 0)

#endif
