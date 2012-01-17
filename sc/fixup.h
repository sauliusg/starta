/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __FIXUP_H
#define __FIXUP_H

#include <stdlib.h>
#include <cexceptions.h>

typedef struct FIXUP FIXUP;

int fixup_is_absolute( FIXUP *fixup );
FIXUP *fixup_next( FIXUP *fixup );
char *fixup_name( FIXUP *fixup );
ssize_t fixup_address( FIXUP *fixup );
FIXUP *fixup_append( FIXUP *head, FIXUP *tail );
FIXUP *fixup_list_merge( FIXUP *head, FIXUP *tail );
void delete_fixup( FIXUP * fixup );
FIXUP *pop_fixup( FIXUP * fixup );

FIXUP *new_fixup( const char *name,
		  ssize_t address,
		  int is_absolute,
		  FIXUP *next,
		  cexception_t *ex );

FIXUP *new_fixup_relative( const char *name,
			   ssize_t address,
			   FIXUP *next,
			   cexception_t *ex );

FIXUP *new_fixup_absolute( const char *name,
			   ssize_t address,
			   FIXUP *next,
			   cexception_t *ex );

void delete_fixup_list( FIXUP * fixup_list );

FIXUP *fixup_swap( FIXUP *list );

FIXUP *fixup_adjust_address( FIXUP *fixup, ssize_t address );

void fixup_list_adjust_addresses( FIXUP *fixup_list, ssize_t address );

#define foreach_fixup( FIXUP, LIST ) \
   for( FIXUP = LIST; FIXUP != NULL; FIXUP = fixup_next( FIXUP ))

#endif

