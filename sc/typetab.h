/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __TYPETAB_H
#define __TYPETAB_H

/* symbol table to store type definitions */
/* the symbol table stores the pointers to TNODEs, generated by parser
   and sytax tree builder. The reference counting mechanism should be
   used to allow a TNODE have several owners. */

typedef struct TYPETAB TYPETAB; /* symbol table for storing types */

typedef enum {
    TS_NOT_A_SUFFIX,
    TS_INTEGER_SUFFIX,
    TS_FLOAT_SUFFIX,
    TS_STRING_SUFFIX,
    last_TYPE_SUFFIX_TYPE
} type_suffix_t;

#include <tnode.h>
#include <cexceptions.h>

TYPETAB *new_typetab( cexception_t *ex );
void delete_typetab( TYPETAB *table );

TNODE *typetab_insert( TYPETAB *table, const char *name,
		       TNODE *tnode, cexception_t *ex );

void typetab_copy_table( TYPETAB *dst, TYPETAB *src, cexception_t *ex );

TNODE *typetab_lookup( TYPETAB *table, const char *name );

TNODE *typetab_insert_suffix( TYPETAB *table, const char *name,
			      type_suffix_t suffix, TNODE *tnode,
                              int *count, int *is_imported,
			      cexception_t *ex );

void typetab_override_suffix( TYPETAB *table, const char *name,
                              type_suffix_t suffix, TNODE *tnode,
                              cexception_t *ex );

TNODE *typetab_lookup_suffix( TYPETAB *table, const char *name,
			      type_suffix_t suffix );

void typetab_begin_scope( TYPETAB* table, cexception_t *ex );
void typetab_end_scope( TYPETAB* table, cexception_t *ex );

void typetab_begin_subscope( TYPETAB* table, cexception_t *ex );
void typetab_end_subscope( TYPETAB* table, cexception_t *ex );

#endif
