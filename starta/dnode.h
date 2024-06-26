/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __DNODE_H
#define __DNODE_H

/* dnodes -- nodes representing variable declarations */

typedef struct DNODE DNODE;

#include <stdio.h>
#include <tnode.h>
#include <typetab.h>
#include <vartab.h>
#include <symtab.h>
#include <cvalue_t.h>
#include <run.h>
#include <cexceptions.h>

typedef enum {
    DF_NONE        = 0x00,
    DF_BYTECODE    = 0x01,
    DF_INLINE      = 0x02,
    DF_IS_READONLY = 0x04,
    DF_FNPROTO     = 0x08,
    DF_HAS_OFFSET  = 0x10,
    DF_HAS_INITIALISER = 0x20,
    DF_LOOP_HAS_VAL    = 0x40, /* describes 'for' loops that need extra
				  value on top of the evluation stack. */
    DF_IS_IMMUTABLE    = 0x080,
    DF_CYCLES_BROKEN   = 0x100,
    DF_VISITED         = 0x200, /* Specifies that the node has been
                                   visited during the cycle search. */
    DF_ACCESSIBLE      = 0x400, /* This flag is set when rcount >
                                   rcount2 for the given DNODE,
                                   indicating that there are external
                                   ponters (roots) leading to this
                                   DNODE, and thus this node might be
                                   accessible in the
                                   program. Otherwise, all reference
                                   counts come from cycle references,
                                   and the node can be safely
                                   collected. */
} dnode_flag_t;

void delete_dnode( DNODE *node );
void dnode_traverse_rcount2( DNODE *dnode );
void traverse_all_dnodes( void );
void dnode_mark_accessible( DNODE *dnode );
void reset_flags_for_all_dnodes( dnode_flag_t flags );
void set_accessible_flag_for_all_dnodes( void );
void set_rcount2_for_all_dnodes( int value );
void dispose_dnode( DNODE *volatile *dnode );

void break_cycles_for_all_dnodes( void );
void take_ownership_of_all_dnodes( void );
void delete_all_dnodes( void );

DNODE *dnode_break_cycles( DNODE *dnode );

DNODE *dnode_shallow_copy( DNODE *dst, DNODE *src, cexception_t *ex );

DNODE* clone_dnode( DNODE *dnode, cexception_t *ex );

DNODE *clone_dnode_list_with_replaced_types( DNODE *dl, TNODE *old, TNODE *new,
                                             cexception_t *ex );

DNODE *new_dnode( cexception_t *ex );

DNODE *new_dnode_name( char *name, cexception_t *ex );

DNODE* new_dnode_typed( char *name, TNODE *tnode, cexception_t *ex );

DNODE* new_dnode_loop( char *name, int ncounters,
                       DNODE *next, cexception_t *ex );

int dnode_loop_counters( DNODE *dnode );

DNODE *new_dnode_exception( char *exception_name,
			    TNODE *exception_type,
			    cexception_t *ex );

DNODE* new_dnode_constant( char *name, const_value_t *value,
			   cexception_t *ex );

DNODE *new_dnode_return_value( TNODE *retval_type, cexception_t *ex );

DNODE* new_dnode_function( char *name,
                           DNODE *volatile *parameters,
                           DNODE *volatile *return_values, 
			   cexception_t *ex );

DNODE* new_dnode_constructor( char *name,
                              DNODE *volatile *parameters,
                              DNODE *volatile *return_values, 
                              cexception_t *ex );

DNODE* new_dnode_destructor( char *name,
                             DNODE *volatile *parameters,
                             cexception_t *ex );

DNODE* new_dnode_method( char *name,
                         DNODE *volatile *parameters,
                         DNODE *volatile *return_values,
                         cexception_t *ex );

DNODE* new_dnode_operator( char *name,
                           DNODE *volatile *parameters,
                           DNODE *volatile *return_values,
			   cexception_t *ex );

DNODE *new_dnode_module( char *name, cexception_t *ex );

DNODE *new_dnode_list_with_concrete_types( DNODE *dnode_with_generics,
                                           TYPETAB *generic_table,
                                           int *has_generics,
                                           cexception_t *ex );
DNODE *share_dnode( DNODE* node );

DNODE *dnode_set_ssize_value( DNODE *dnode, ssize_t val );

ssize_t dnode_ssize_value( DNODE *dnode );

DNODE *dnode_set_value( DNODE *dnode, const_value_t *val );

const_value_t *dnode_value( DNODE *dnode );

#if 0
ssize_t dnode_attribute_value( DNODE *dnode, char *name );
#endif

DNODE *dnode_set_flags( DNODE *dnode, dnode_flag_t flags );

DNODE *dnode_reset_flags( DNODE *dnode, dnode_flag_t flags );

DNODE *dnode_copy_flags( DNODE *dnode, dnode_flag_t flags );

int dnode_has_flags( DNODE *dnode, dnode_flag_t flags );

int dnode_has_initialiser( DNODE *dnode );

dnode_flag_t dnode_flags( DNODE *dnode );

DNODE *dnode_list_set_flags( DNODE *dnode, dnode_flag_t flags );

char *dnode_name( DNODE *dnode );

char *dnode_filename( DNODE *dnode );

int dnode_scope( DNODE *dnode );

DNODE *dnode_set_scope( DNODE *dnode, int scope );

ssize_t dnode_offset( DNODE *dnode );

TNODE *dnode_type( DNODE *dnode );

DNODE *dnode_set_offset( DNODE *dnode, ssize_t offset );

DNODE *dnode_update_offset( DNODE *dnode, ssize_t offset );

DNODE *dnode_module_args( DNODE *dnode );

DNODE *dnode_insert_module_args( DNODE *dnode, DNODE *volatile *args );

void dnode_assign_offset( DNODE *dnode, ssize_t *offset );

void dnode_list_assign_offsets( DNODE *dnode_list, ssize_t *offset );

DNODE *dnode_set_offset( DNODE *dnode, ssize_t offset );

DNODE *dnode_insert_type( DNODE *dnode, TNODE *tnode );

DNODE *dnode_list_insert_type( DNODE *dnode, TNODE *tnode );

DNODE *dnode_replace_type( DNODE *dnode, TNODE *tnode );

DNODE *dnode_set_filename( DNODE *dnode, char *filename, cexception_t *ex );

DNODE *dnode_set_name( DNODE *dnode, char *name, cexception_t *ex );

DNODE *dnode_set_synonim( DNODE *dnode, char *synonim, cexception_t *ex );

DNODE *dnode_insert_synonim( DNODE *dnode, char *volatile *synonim );

char *dnode_synonim( DNODE *dnode );

DNODE *dnode_append_type( DNODE *dnode, TNODE *tnode );

DNODE *dnode_list_append_type( DNODE *dnode, TNODE *tnode );

int dnode_type_is_reference( DNODE *dnode );

int dnode_type_has_references( DNODE *dnode );

int dnode_function_prototypes_match_msg( DNODE *d1, DNODE *d2,
					 char *msg, int msglen );

int dnode_is_function_prototype( DNODE *dnode );

int dnode_list_length( DNODE *dnode );

DNODE *dnode_list_lookup( DNODE *dnode_list, const char *name );

DNODE *dnode_list_lookup_arity( DNODE *dnode_list, const char *name,
				int arity );

DNODE *dnode_list_lookup_compatible( DNODE *dnode_list,
				     DNODE *target );

DNODE *dnode_list_lookup_proto_by_tnodes( DNODE *dnode_list,
					  char *name,
					  int arity,
					  ... );

int dnode_lists_are_type_compatible( DNODE *l1, DNODE *l2,
				     TYPETAB *generic_types,
				     cexception_t *ex );

int dnode_lists_are_type_identical( DNODE *l1, DNODE *l2,
				    TYPETAB *generic_types,
				    cexception_t *ex );

DNODE* dnode_append( DNODE *head, DNODE *tail );

DNODE *dnode_disconnect( DNODE *dnode );

DNODE *dnode_next( DNODE* dnode );

DNODE *dnode_prev( DNODE* dnode );

DNODE *dnode_list_last( DNODE* dnode );

#define foreach_dnode( NODE, LIST ) \
    for( NODE = LIST; NODE != NULL; NODE = dnode_next( NODE ))

#define foreach_reverse_dnode( NODE, LIST ) \
    for( NODE = dnode_list_last(LIST); NODE != NULL; NODE = dnode_prev( NODE ))

DNODE *dnode_rename( DNODE *dnode, char *name, cexception_t *ex );

DNODE *dnode_function_args( DNODE *dnode );

DNODE *dnode_insert_code_fixup( DNODE *dnode, FIXUP *fixup );

DNODE *dnode_adjust_code_fixups( DNODE *dnode, ssize_t address );

FIXUP *dnode_code_fixups( DNODE *dnode );

DNODE *dnode_set_code( DNODE *dnode, thrcode_t *code, ubyte *cod_flags,
		       ssize_t code_length,
		       cexception_t *ex );

thrcode_t *dnode_code( DNODE *dnode, ssize_t *code_length );

ubyte *dnode_code_flags( DNODE *dnode, ssize_t *code_length );

void dnode_vartab_insert_dnode( DNODE *dnode, const char *name,
                                DNODE *volatile *var,
				cexception_t *ex );

VARTAB *dnode_vartab( DNODE *dnode );

VARTAB *dnode_constants_vartab( DNODE *dnode );

VARTAB *dnode_operator_vartab( DNODE *dnode );

TYPETAB *dnode_typetab( DNODE *dnode );

void dnode_vartab_insert_named_dnode( DNODE *dnode, DNODE *volatile *var,
				      cexception_t *ex );

void dnode_vartab_insert_named_vars( DNODE *dnode, DNODE *volatile *vars,
				     cexception_t *ex );

void dnode_optab_insert_named_operator( DNODE *dnode,
                                        DNODE *volatile *operator,
                                        cexception_t *ex );

void dnode_optab_insert_operator( DNODE *dnode, char *opname,
                                  DNODE *volatile *operator,
                                  cexception_t *ex );

DNODE *dnode_vartab_lookup_var( DNODE *dnode, const char *name );

void dnode_consttab_insert_consts( DNODE *dnode,
                                   DNODE *volatile *consts,
				   cexception_t *ex );

DNODE *dnode_consttab_lookup_const( DNODE *dnode, const char *name );

void dnode_typetab_insert_tnode( DNODE *dnode, const char *name, TNODE *tnode, 
				 cexception_t *ex );

void dnode_typetab_insert_tnode_suffix( DNODE *dnode, const char *suffix_name,
					type_suffix_t suffix_type, TNODE *tnode, 
					cexception_t *ex );

void dnode_typetab_insert_named_tnode( DNODE *dnode, TNODE *tnode,
				       cexception_t *ex );

TNODE *dnode_typetab_lookup_type( DNODE *dnode, const char *name );

TNODE *dnode_typetab_lookup_suffix( DNODE *dnode, const char *name,
				    type_suffix_t suffix );

int dnode_module_args_are_identical( DNODE *m1, DNODE *m2, SYMTAB *symtab );

int dnode_list_has_generic_type( DNODE *dnode_list );

DNODE *dnode_remove_last( DNODE *list );

void dnode_print_allocated();
void dnode_print_allocated_to_stderr();
void dnode_fprint_allocated( FILE *fp );

void null_allocated_dnodes(void);

#endif
