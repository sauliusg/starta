/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __COMMON_H
#define __COMMON_H

#include <stdlib.h>

void *moveptr( void *volatile *p );
char *process_escapes( char *str );
char translate_escape( char **s );

#endif
