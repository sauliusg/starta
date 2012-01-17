/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __THRLIST_H
#define __THRLIST_H

#include <thrcode.h>

typedef struct THRLIST THRLIST;

typedef void (*thrcode_delete_function_t)( THRCODE* );
typedef void (*thrcode_dispose_function_t)( THRCODE* volatile * );

void delete_thrlist( THRLIST *list );
THRLIST* new_thrlist( THRCODE *thrcode,
		      thrcode_delete_function_t delete_fn,
		      THRLIST *next,
		      cexception_t *ex );
void create_thrlist( THRLIST * volatile *list,
		     THRCODE * volatile *data,
		     thrcode_dispose_function_t dispose_fn,
		     THRLIST *next, cexception_t *ex );
void dispose_thrlist( THRLIST* volatile *list );
THRCODE* thrlist_data( THRLIST *list );
THRCODE* thrlist_extract_data( THRLIST *list );
void thrlist_set_data( THRLIST *list, THRCODE * volatile *code );
THRLIST* thrlist_next( THRLIST *list );
void thrlist_disconnect( THRLIST *list );
void thrlist_push( THRLIST *volatile *list,
		   THRLIST *volatile *node,
		   cexception_t *ex );
void thrlist_push_data( THRLIST *volatile *list,
			THRCODE *volatile *data,
			thrcode_delete_function_t delete_fn,
			thrcode_dispose_function_t dispose_fn,
			cexception_t *ex );
THRLIST* thrlist_pop( THRLIST * volatile *list );
THRCODE* thrlist_pop_data( THRLIST * volatile *list );
void thrlist_drop( THRLIST * volatile *list );
void thrlist_swap( THRLIST * volatile *list );

#endif
