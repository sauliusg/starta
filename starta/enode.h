/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __ENODE_H
#define __ENODE_H

typedef struct ENODE ENODE;

#include <tnode.h>
#include <dnode.h>
#include <cexceptions.h>

typedef enum {
    EF_NONE          = 0x00,
    EF_RETURN_VALUE  = 0x01,
    EF_GUARDING_ARG  = 0x02,
    EF_HAS_ERRORS    = 0x04,
    EF_VARADDR_EXPR  = 0x08,
    EF_IS_READONLY   = 0x10,
    EF_IS_CONSTANT   = 0x20,
    EF_IS_ZERO       = 0x40
} enode_flag_t;

void dispose_enode( ENODE *volatile *node );

void delete_enode( ENODE* node );

ENODE *enode_make_type_to_element_type( ENODE *enode );

ENODE *enode_make_type_to_addressof( ENODE *enode, cexception_t *ex );

ENODE *enode_replace_type( ENODE *enode, TNODE *replacement );

TNODE *enode_type( ENODE *enode );

DNODE *enode_variable( ENODE *enode );

ENODE *enode_next( ENODE *enode );

int enode_size( ENODE *enode );

ENODE *enode_set_flags( ENODE *enode, enode_flag_t flags );

ENODE *enode_reset_flags( ENODE *enode, enode_flag_t flags );

int enode_has_flags( ENODE *enode, enode_flag_t flags );

ENODE *enode_set_has_errors( ENODE *enode );

int enode_has_errors( ENODE *enode );

enode_flag_t enode_flags( ENODE *enode );

int enode_is_varaddr( ENODE *enode );

int enode_is_guarding_retval( ENODE *enode );

int enode_is_readonly_compatible_with_expr( ENODE *expr, ENODE *target );

int enode_is_readonly_compatible_with_var( ENODE *expr, DNODE *variable );

int enode_is_readonly_compatible_for_init( ENODE *expr, DNODE *variable );

int enode_is_readonly_compatible_for_param( ENODE *expr, DNODE *variable );

ENODE* enode_append( ENODE *head, ENODE *tail );

ENODE *share_enode( ENODE *enode );

ENODE *new_enode( cexception_t *ex );

ENODE *new_enode_typed( TNODE *volatile *tnode, cexception_t *ex );

ENODE *new_enode_return_value( TNODE *retval_tnode, cexception_t *ex );

ENODE *new_enode_guarding_arg( cexception_t *ex );

ENODE *new_enode_varaddr_expr( DNODE *var_dnode, cexception_t *ex );

void enode_append_element_type( ENODE *enode, TNODE *base );

void enode_list_push( ENODE **ptr_list, ENODE *enode );

ENODE *enode_list_pop( ENODE **ptr_list );

void enode_list_drop( ENODE **ptr_list );

void enode_list_swap( ENODE **ptr_list );

#define foreach_enode( NODE, LIST ) \
   for( NODE = LIST; NODE != NULL; NODE = enode_next( NODE ))

void enode_print_allocated(void);
void enode_print_allocated_to_stderr(void);
void enode_fprint_allocated( FILE *fp );

#endif
