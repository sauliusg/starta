/*---------------------------------------------------------------------------*\
** $Author$
** $Date$ 
** $Revision$
** $URL$
\*---------------------------------------------------------------------------*/

#ifndef _BYTECODE_FILE_H
#define _BYTECODE_FILE_H

/* uses: */
#include <stdio.h>
#include <typesize.h>
#include <stackcell.h>

typedef struct {
    /* Garbage collected pointer fields must be at the beginning of
       the structure, so that garbage collector finds them */
    stackcell_t filename;
    stackcell_t int_format;
    stackcell_t float_format;
    stackcell_t string_format;
    stackcell_t string_scanf_format;
    int fd;
    int flags;
    FILE *fp;
} bytecode_file_hdr_t;

/* INTERPRET_FILE_PTRS is a number of garbage collected pointers
   in bytecode_file_hdr_t, to be used when allocating
   interpret_exception_t on the heap.
 */

#define INTERPRET_FILE_PTRS 5

#endif
