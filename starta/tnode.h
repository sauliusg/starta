/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __TNODE_H
#define __TNODE_H

/* representation of the type definition parse tree */

typedef struct TNODE TNODE;

#include <stdlib.h>
#include <typetab.h>
#include <tlist.h>
#include <dnode.h>
#include <anode.h>
#include <tcodes.h>
#include <refsize.h>
#include <cexceptions.h>

typedef enum {
    TF_NONE            = 0,
    TF_HAS_REFS        = 0x01,
    TF_HAS_NO_NUMBERS  = 0x02,
    TF_IS_REF          = 0x04,
    TF_IS_FORWARD      = 0x08,
    TF_EXTENDABLE_ENUM = 0x10,
    TF_IS_IMMUTABLE    = 0x20,
    TF_NON_NULL        = 0x40,
    TF_IS_EQUIVALENT   = 0x80,
    TF_HAS_PLACEHOLDER = 0x100,
    TF_CYCLES_BROKEN   = 0x200,
    TF_VISITED         = 0x400, /* Specifies that the node has been
                                   visited during the cycle search. */
    TF_ACCESSIBLE      = 0x800, /* This flag is set when rcount >
                                   rcount2 for the given DNODE,
                                   indicating that there are external
                                   ponters (roots) leading to this
                                   DNODE, and thus this node might be
                                   accessible in the
                                   program. Otherwise, all reference
                                   counts come from cycle references,
                                   and the node can be safely
                                   collected. */
    TF_HAS_GENERICS    = 0x1000, /* Specifies that a (composite) type
                                    has fields (for classes and
                                    structures), elements (for arrays
                                    ot hashes), parameters or reteru
                                    values (for functions and
                                    procedure) of some generic
                                    type. Types that have
                                    TF_HAS_GENERICS flag set need to
                                    be recursively re-described
                                    (re-instantiated) when a concrete
                                    type is substituted for a generic
                                    one.*/
    TF_HAS_GENERIC_FIELD = 0x2000, /* Specifies that a (composite)
                                    type has fields (for classes and
                                    structures), elements (for arrays
                                    ot hashes). It is *not* set when a
                                    class has methods with generic
                                    parameters – only persistently
                                    assignable generic values
                                    coun. Types that have
                                    TF_HAS_GENERIC_FILEDS flag can not
                                    be used for variables on the
                                    global (0) scope..*/
    last_TYPE_FLAG
} type_flag_t;

typedef enum {
    TK_NONE = 0,
    TK_BOOL,
    TK_INTEGER,
    TK_REAL,
    TK_STRING,
    TK_PRIMITIVE,
    TK_ADDRESSOF,
    TK_ARRAY,
    TK_ENUM,      /* Enumeration type a-la C or Pascal. */
    TK_STRUCT,
    TK_CLASS,
    TK_INTERFACE,
    TK_BLOB,
    TK_FUNCTION,
    TK_OPERATOR,
    TK_CLOSURE,
    TK_METHOD, /* class (virtual) methods, or virtual functions */
    TK_CONSTRUCTOR,
    TK_DESTRUCTOR,
    TK_COMPOSITE, /* user-declared array-like types */
    TK_PLACEHOLDER, /* placeholders for 'T'  in 'type array of T = ...' */
    TK_NOMINAL,     /* nominal type, as in 'array of type T' */
    TK_GENERIC,     /* generic types a-la Ada. The compiler MUST have
                       some base type that shares size and load/store
                       operators to compile the generic code; later a
                       specific type will be substituted for the
                       generic via type-erasure mechanism. */
    TK_DERIVED,     /* A new derived type inherits implementation and
                       interface (operators) from its parent, or base,
                       type, but which itself can not be assigned to
                       floats, and two derived types are incompatible
                       with each other. */
    TK_REF,
    TK_FUNCTION_REF,
    TK_NULLREF,
    TK_IGNORE, /* "type" of ignored arguments, e.g. for the "over" operator */
    TK_EXCEPTION,
    TK_TYPE, /* for module parameters that represent types */
    TK_CONST, /* for module parameters that represent constants */
    TK_VAR, /* for module parameters that represent variables */
    TK_PAIR, /* TNODE used to represent type pair; two TNODE
                references will be stored in the 'generic_type' and
                'concrete_type' fields. */
    last_type_kind_t
} type_kind_t;

void delete_tnode( TNODE *tnode );
void dispose_tnode( TNODE *volatile *tnode );
void break_cycles_for_all_tnodes( void );
void tnode_traverse_rcount2( TNODE *tnode );
void traverse_all_tnodes( void );
void tnode_mark_accessible( TNODE *tnode );
void reset_flags_for_all_tnodes( type_flag_t flags );
void set_accessible_flag_for_all_tnodes( void );
void set_rcount2_for_all_tnodes( int value );
void take_ownership_of_all_tnodes( void );
void delete_all_tnodes( void );
TNODE* tnode_break_cycles( TNODE *tnode );
TNODE *new_tnode( cexception_t *ex );
TNODE *new_tnode_type_pair( TNODE *volatile *generic_type,
                            TNODE *volatile *concrete_type,
                            cexception_t *ex );
TNODE *new_tnode_forward( char *name, cexception_t *ex );
TNODE *new_tnode_forward_struct( char *name, cexception_t *ex );
TNODE *new_tnode_forward_class( char *name, cexception_t *ex );
TNODE *new_tnode_forward_interface( char *name, cexception_t *ex );
TNODE *new_tnode_ptr( cexception_t *ex );
TNODE *new_tnode_nullref( cexception_t *ex );
TNODE *new_tnode_ignored( cexception_t *ex );
TNODE *new_tnode_ref( cexception_t *ex );
TNODE *new_tnode_derived( TNODE *volatile *base, cexception_t *ex );
TNODE *new_tnode_derived_composite( TNODE *volatile *base,
                                    TNODE *volatile *element_type,
                                    cexception_t *ex );
TNODE *new_tnode_equivalent( TNODE *volatile *base, cexception_t *ex );
TNODE *new_tnode_blob( TNODE *base_type, cexception_t *ex );
TNODE *copy_unnamed_tnode( TNODE *tnode, cexception_t *ex );
TNODE *tnode_set_nref( TNODE *tnode, ssize_t nref );

TNODE *new_tnode_array( TNODE *element_type,
			TNODE *base_type,
			cexception_t *ex );

TNODE *new_tnode_addressof( TNODE *element_type, cexception_t *ex );

TNODE *new_tnode_function_or_proc_ref( DNODE *parameters,
				       DNODE *return_dnodes,
				       TNODE *base_type,
				       cexception_t *ex );

TNODE *new_tnode_function( char *name, DNODE *parameters, DNODE *return_dnodes,
			   cexception_t *ex );

TNODE *new_tnode_function_NEW( char *name,
                               DNODE *volatile *parameters,
                               DNODE *volatile *return_dnodes,
                               cexception_t *ex );

TNODE *new_tnode_constructor( char *name,
                              DNODE *parameters,
                              DNODE *return_dnodes,
                              cexception_t *ex );

TNODE *new_tnode_constructor_NEW( char *name,
                                  DNODE *volatile *parameters,
                                  DNODE *volatile *return_dnodes,
                                  cexception_t *ex );

TNODE *new_tnode_destructor( char *name,
                             DNODE *parameters,
                             DNODE *return_dnodes,
                             cexception_t *ex );

TNODE *new_tnode_destructor_NEW( char *name,
                                 DNODE *volatile *parameters,
                                 DNODE *volatile *return_dnodes,
                                 cexception_t *ex );

TNODE *new_tnode_method( char *name, DNODE *parameters, DNODE *return_dnodes,
                         cexception_t *ex );

TNODE *new_tnode_method_NEW( char *name,
                             DNODE *volatile *parameters,
                             DNODE *volatile *return_dnodes,
                             cexception_t *ex );

TNODE *new_tnode_operator( char *name, DNODE *parameters, DNODE *return_dnodes,
			   cexception_t *ex );

TNODE *new_tnode_operator_NEW( char *name,
                               DNODE *volatile *parameters,
                               DNODE *volatile *return_dnodes,
                               cexception_t *ex );

TNODE *new_tnode_composite( char *name, TNODE *element_type, cexception_t *ex );

TNODE *new_tnode_placeholder( char *name, cexception_t *ex );

TNODE *new_tnode_nominal( char *name, cexception_t *ex );

TNODE *new_tnode_generic( TNODE *volatile *base_type, cexception_t *ex );

TNODE *new_tnode_implementation( TNODE *generic_tnode,
                                 TYPETAB *generic_types,
                                 cexception_t *ex );

TNODE *tnode_append( TNODE *head, TNODE *volatile *tail );

TNODE *tnode_move_operators( TNODE *dst, TNODE *src );

TNODE *tnode_copy_operators( TNODE *dst, TNODE *src, cexception_t *ex );

TNODE *tnode_copy_conversions( TNODE *dst, TNODE *src, cexception_t *ex );

TNODE *tnode_rename_conversions( TNODE *tnode, char *old_name, char *other_name,
                                 cexception_t *ex );

TNODE *tnode_finish_struct( TNODE * volatile node,
			    cexception_t *ex );

TNODE *tnode_finish_class( TNODE * volatile node,
			   cexception_t *ex );

TNODE *tnode_finish_interface( TNODE * volatile node,
                               ssize_t interface_nr,
			       cexception_t *ex );

TNODE *tnode_finish_enum( TNODE * volatile node,
			  char *name,
			  TNODE *base_type,
			  cexception_t *ex );

TNODE *tnode_insert_operator( TNODE *tnode, DNODE *operator );

TNODE *tnode_merge_field_lists( TNODE *dst, TNODE *src );

DNODE *tnode_fields( TNODE *tnode );

DNODE *tnode_lookup_field( TNODE *tnode, char *field_name );

DNODE *tnode_lookup_method( TNODE *tnode, char *method_name );

DNODE *tnode_lookup_method_prototype( TNODE *tnode, char *method_name );

DNODE *tnode_lookup_operator( TNODE *tnode, char *operator_name, int arity );

DNODE *tnode_lookup_operator_nonrecursive( TNODE *tnode, char *operator_name,
                                           int arity );

DNODE *tnode_lookup_conversion( TNODE *tnode, TNODE *src_type );

TNODE *tnode_lookup_interface( TNODE *class_tnode, char *name );

DNODE *tnode_lookup_argument( TNODE *function_tnode, char *agument_name );

TNODE *tnode_convert_to_element_type( TNODE *tnode );

TNODE *share_tnode( TNODE* node );

TNODE *tnode_shallow_copy( TNODE *dst, TNODE *src );

TNODE *tnode_set_name( TNODE* node, char *name, cexception_t *ex );
TNODE *tnode_set_suffix( TNODE* node, const char *suffix, cexception_t *ex );
TNODE *tnode_set_interface_nr( TNODE* node, ssize_t nr );
char *tnode_name( TNODE *tnode );
char *tnode_suffix( TNODE *tnode );
ssize_t tnode_size( TNODE *tnode );
ssize_t tnode_number_of_references( TNODE *tnode );
ssize_t tnode_interface_number( TNODE *tnode );
TLIST *tnode_interface_list( TNODE *tnode );
ssize_t tnode_max_interface( TNODE *class_descr );
ssize_t tnode_base_class_count( TNODE *tnode );

const char * tnode_kind_name( TNODE * );

int tnode_align( TNODE *tnode );

type_kind_t tnode_kind( TNODE *tnode );

DNODE *tnode_args( TNODE* tnode );

#if 1
DNODE *tnode_arg_next( TNODE* tnode, DNODE *arg );
#endif

#if 0
DNODE *tnode_arg_prev( TNODE* tnode, DNODE *arg );
#endif

DNODE *tnode_retvals( TNODE* tnode );

DNODE *tnode_retval_next( TNODE* tnode, DNODE *retval );

TNODE *tnode_set_size( TNODE *tnode, int size );

void tnode_print( TNODE *tnode );
void tnode_print_indent( TNODE *tnode, int indent );

TNODE *tnode_insert_fields( TNODE* tnode, DNODE *field );
TNODE *tnode_insert_single_operator( TNODE *tnode, DNODE *volatile *operator );
TNODE *tnode_insert_single_conversion( TNODE *tnode, DNODE *conversion );
TNODE *tnode_insert_single_method( TNODE* tnode, DNODE *volatile *method );
TNODE *tnode_insert_type_member( TNODE *tnode, DNODE *volatile *member );
TNODE *tnode_insert_enum_value( TNODE *tnode, DNODE *member );
TNODE *tnode_insert_enum_value_list( TNODE *tnode, DNODE *list );
TNODE *tnode_insert_constructor( TNODE* tnode, DNODE *volatile *constructor );
TNODE *tnode_insert_destructor( TNODE* tnode, DNODE *volatile *destructor );
ssize_t tnode_max_vmt_offset( TNODE *tnode );
ssize_t tnode_vmt_offset( TNODE *tnode );
ssize_t tnode_set_vmt_offset( TNODE *tnode, ssize_t offset );
DNODE *tnode_methods( TNODE *tnode );
TNODE *tnode_base_type( TNODE *tnode );
TNODE *tnode_insert_base_type( TNODE *tnode, TNODE *volatile *base_type );
TNODE *tnode_insert_interfaces( TNODE *tnode, TLIST *interfaces );
TNODE *tnode_first_interface( TNODE *class_tnode );
TNODE *tnode_element_type( TNODE *tnode );
TNODE *tnode_generic_type( TNODE *tnode );
TNODE *tnode_concrete_type( TNODE *tnode );
TNODE *tnode_insert_element_type( TNODE* tnode, TNODE *element_type );
TNODE *tnode_append_element_type( TNODE* tnode, TNODE *element_type );

#if 0
TNODE *tnode_insert_function_parameters( TNODE* tnode, DNODE *parameters );
#endif

int tnode_function_prototypes_match_msg( TNODE *f1, TNODE *f2,
					 char *msg, int msglen );

int tnode_function_prototypes_match( TNODE *f1, TNODE *f2 );

TNODE *tnode_set_flags( TNODE* node, type_flag_t flags );
TNODE *tnode_reset_flags( TNODE* node, type_flag_t flags );
TNODE *tnode_set_has_references( TNODE *tnode );
TNODE *tnode_set_has_no_numbers( TNODE *tnode );
TNODE *tnode_set_has_generics( TNODE *tnode );
int tnode_has_placeholder_element( TNODE *tnode );
int tnode_has_flags( TNODE* node, type_flag_t flags );
int tnode_has_generic_type( TNODE *tnode );
int tnode_has_generic_field( TNODE *tnode );
int tnode_has_references( TNODE *tnode );
int tnode_has_numbers( TNODE *tnode );
int tnode_is_addressof( TNODE *tnode );
int tnode_is_reference( TNODE *tnode );
int tnode_is_non_null_reference( TNODE *tnode );
int tnode_has_non_null_ref_field( TNODE *tnode );
int tnode_is_integer( TNODE *tnode );
int tnode_is_conversion( TNODE *tnode );
int tnode_is_forward( TNODE *tnode );
int tnode_is_extendable_enum( TNODE *tnode );
int tnode_is_array_of_string( TNODE *tnode );
int tnode_is_array_of_file( TNODE *tnode );
int tnode_is_immutable( TNODE *tnode );

TNODE *tnode_set_kind( TNODE *tnode, type_kind_t kind );

TNODE *tnode_set_kind_from_string( TNODE *tnode, const char *kind_name,
				   cexception_t *ex );

TNODE *tnode_set_attribute( TNODE *tnode, ANODE *attribute, cexception_t *ex );

TNODE *tnode_set_integer_attribute( TNODE *tnode, const char *attr_name,
				    ssize_t attr_value, cexception_t *ex );

TNODE *tnode_set_string_attribute( TNODE *tnode, const char *attr_name,
				   const char *attr_value, cexception_t *ex );

DNODE *tnode_default_constructor( TNODE *tnode );

DNODE *tnode_lookup_constructor( TNODE *tnode, const char *name );

TNODE *tnode_type_pair_left( TNODE *tnode );

TNODE *tnode_type_pair_right( TNODE *tnode );

DNODE *tnode_destructor( TNODE *tnode );

TNODE *tnode_next( TNODE* list );

TNODE *tnode_drop_last_argument( TNODE *tnode );

#define foreach_tnode_base_class( NODE, LIST ) \
   for( NODE = LIST; NODE != NULL; NODE = tnode_base_type( NODE ))

void tnode_print_allocated();
void tnode_print_allocated_to_stderr();
void tnode_fprint_allocated( FILE *fp );

void null_allocated_tnodes(void);

#endif
