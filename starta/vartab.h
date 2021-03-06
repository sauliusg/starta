/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __VARTAB_H
#define __VARTAB_H

/* symbol table to store defined variables */

typedef struct VARTAB VARTAB; /* variable symbol table */

#include <dnode.h>
#include <tlist.h>
#include <symtab.h>
#include <cexceptions.h>

VARTAB *new_vartab( cexception_t *ex );
void dispose_vartab( VARTAB *volatile *table );
void delete_vartab( VARTAB *table );

void vartab_break_cycles( VARTAB *table );
void vartab_traverse_dnodes_and_set_rcount2( VARTAB *table );
void vartab_traverse_dnodes_and_mark_accessible( VARTAB *table );

int vartab_current_scope( VARTAB *vartab );

void vartab_insert_operator( VARTAB *table, const char *name,
                             DNODE *volatile *dnode, cexception_t *ex );

void vartab_insert_named_operator( VARTAB *table, DNODE *volatile *dnode,
                                   cexception_t *ex );

void vartab_insert_named_vars( VARTAB *table, DNODE *volatile *dnode_list,
			       cexception_t *ex );

void vartab_insert_named( VARTAB *table, DNODE *volatile *dnode,
                          cexception_t *ex );

void vartab_insert( VARTAB *table, const char *name,
		    DNODE *volatile *dnode, cexception_t *ex );

void vartab_insert_module( VARTAB *table, DNODE *volatile *module, char *name,
                           SYMTAB *st, cexception_t *ex );

void vartab_insert_named_module( VARTAB *table, DNODE *volatile *module,
                                 SYMTAB *st, cexception_t *ex );

void vartab_insert_modules_name( VARTAB *table, const char *name,
                                 DNODE *volatile *dnode, cexception_t *ex );

void vartab_copy_table( VARTAB *dst, VARTAB *src, cexception_t *ex );

DNODE *vartab_lookup( VARTAB *table, const char *name );

DNODE *vartab_lookup_module( VARTAB *table, DNODE *module, SYMTAB *symtab );

DNODE *vartab_lookup_silently( VARTAB *table, const char *name, 
                               int *count, int *is_imported );

DNODE *vartab_lookup_operator( VARTAB *table, const char *name,
                               TLIST *argument_types );

void vartab_begin_scope( VARTAB* table, cexception_t *ex );
void vartab_end_scope( VARTAB* table, cexception_t *ex );

void vartab_begin_subscope( VARTAB* table, cexception_t *ex );
void vartab_end_subscope( VARTAB* table, cexception_t *ex );

#endif
