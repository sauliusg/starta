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

typedef struct STRPOOL STRPOOL;

STRPOOL *new_strpool( cexception_t *ex );
void delete_strpool( STRPOOL *pool );
void dispose_strpool( STRPOOL *volatile *pool );
void free_strpool( STRPOOL *p );

ssize_t pool_insert_string( STRPOOL *p, char *volatile *str, cexception_t *ex );
ssize_t pool_add_string( STRPOOL *p, char *str, cexception_t *ex );
ssize_t pool_clone_string( STRPOOL *p, char *str );
ssize_t pool_strnclone( STRPOOL *p, char *str, size_t length );
char *obtain_string_from_pool( STRPOOL *p, ssize_t index );
char *get_string_from_pool( STRPOOL *p, ssize_t index );

#endif
