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

ssize_t strpool_insert_string( STRPOOL *p, char *volatile *str, cexception_t *ex );
ssize_t strpool_add_string( STRPOOL *p, char *str, cexception_t *ex );
ssize_t strpool_strclone( STRPOOL *p, char *str );
ssize_t strpool_strnclone( STRPOOL *p, char *str, size_t length );
char *obtain_string_from_strpool( STRPOOL *p, ssize_t index );
char *strpool_get_string( STRPOOL *p, ssize_t index );

#endif
