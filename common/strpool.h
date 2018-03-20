/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __STRPOOL_H
#define __STRPOOL_H

#include <stdlib.h>
#include <cexceptions.h>

typedef union {
    int next;
    char *str;
} strpool_t;

ssize_t pool_insert_string( char *volatile *str, cexception_t *ex );
ssize_t pool_add_string( char *str, cexception_t *ex );
ssize_t pool_clone_string( char *str );
ssize_t pool_strnclone( char *str, size_t length );
char *obtain_string_from_pool( ssize_t index );
char *get_string_from_pool( ssize_t index );
void free_pool();

#endif
