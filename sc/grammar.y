/*-------------------------------------------------------------------------*\
* $Author$
* $Date$ 
* $Revision$
* $URL$
\*-------------------------------------------------------------------------*/

%{
/* exports: */
#include <grammar_y.h>

/* uses: */
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <ctype.h>
#include <dlfcn.h>
#include <cexceptions.h>
#include <cxprintf.h>
#include <allocx.h>
#include <stringx.h>
#include <stdiox.h>
#include <tcodes.h>
#include <thrcode.h>
#include <thrlist.h>
#include <tnode.h>
#include <anode.h>
#include <enode.h>
#include <elist.h>
#include <dlist.h>
#include <tlist.h>
#include <vartab.h>
#include <typetab.h>
#include <symtab.h>
#include <stlist.h>
#include <fixup.h>
#include <tnode_compat.h>
#include <bytecode_file.h> /* for bytecode_file_hdr_t, needed by
			      compiler_native_type_size() */
#include <cvalue_t.h>
#include <lexer_flex.h>
#include <yy.h>
#include <alloccell.h>
#include <rtti.h>
#include <implementation.h>
#include <assert.h>

static char *compiler_version = "0.0";

/* COMPILER_STATE contains necessary compiler state that must be
   saved and restored when include files are processed. */

typedef struct COMPILER_STATE {
    char *filename;
    char *use_package_name;
    FILE *yyin;
    ssize_t line_no;
    ssize_t column_no;
    struct COMPILER_STATE *next;
} COMPILER_STATE;

static void delete_compiler_state( COMPILER_STATE *state )
{
    if( state ) {
	freex( state );
    }
}

static COMPILER_STATE *new_compiler_state( char *filename,
					   char *use_package_name,
					   FILE *file,
					   ssize_t line_no,
					   ssize_t column_no,
					   COMPILER_STATE *next,
					   cexception_t *ex )
{
    COMPILER_STATE * volatile state = callocx( sizeof( *state ), 1, ex );

    state->filename = filename;
    state->use_package_name = use_package_name;
    state->yyin = file;
    state->line_no = line_no;
    state->column_no = column_no;
    state->next = next;

    return state;
}

#define starting_local_offset -1

typedef struct {
    THRCODE *thrcode;  /* thrcode should not be freed in
			  delete_compiler(), it should point either to
			  the same object as main_thrcode or to the
			  same object as function_thrcode; both of
			  these fields should be freed in
			  delete_compiler(). */
    THRCODE *main_thrcode;
    THRCODE *function_thrcode;

    THRLIST *thrstack; /* a stack to push generated thrcode bodies
                          when generating nested control
                          structures. */

    char *static_data;
    ssize_t static_data_size;
    VARTAB *vartab;   /* declared variables, with scopes */
    VARTAB *consts;   /* declared constants, with scopes */
    TYPETAB *typetab; /* declared types and their scopes */
    VARTAB *operators; /* operators declared outside of type definitions */

    STLIST *symtab_stack; /* pushed symbol tables */

    int local_offset;
    int *local_offset_stack;
    int local_offset_stack_size;

    int last_interface_number;

    /* the addr_stack is an array-used-as-stack and holds entry
       addresses of the loops that are currently being compiled. */
    int addr_stack_size;
    ssize_t *addr_stack;

    /* Paths to search for included files, modules, and libraries: */
    char **include_paths; /* these paths are reused between different
			     compiler instances, can be in the static
			     memory and therefore should not be
			     deleted (freed) in
			     delete_compiler()... */

    /* The following three fields are used to process include files: */
    char *filename;
    FILE *yyin;
    char *use_package_name;
    COMPILER_STATE *include_files;

    DNODE *current_function; /* Function that is currently being
				compiled. NOTE! this field must not be
				deleted in delete_compiler() */

    DLIST *current_function_stack;

    TNODE *current_type;     /* Type declaration that is currently
				being compiled. NOTE! this field must
				not be deleted in delete_compiler() */

    DNODE *current_call;     /* function call that is currently
				being processed. */
    DLIST *current_call_stack;

    DNODE *current_arg;        /* formal function argument that is currently
				  being processed. NOTE! this field
				  must not be deleted in delete_compiler() */
    DLIST *current_arg_stack;

    /* The enodes in the e_stack mimick the evaluation stack of an
       expression or statement under compilation and hold types of all
       intermediate values. First enode in the list is the top of the
       stack. */
    ENODE *e_stack;

    /* the saved_estacks holds stacks of types loaded by the code
       pushed onto the thrstack. */
    ELIST *saved_estacks;

    /* labels and fixups in the 'bytecode' statements: */
    DNODE *bytecode_labels;
    FIXUP *bytecode_fixups;

    /* loop stack for the describing nested loops, needed to implement
       'break' and 'continue' statements: */
    DNODE *loops;
    DLIST *loop_stack;

    /* track down exception declared in each module or in the main
       program; start from the beginning in each new module and
       restore the previous value when the compilation of the module
       is finished: */
    int latest_exception_nr;
    int *latest_exception_stack;
    int latest_exception_stack_size;

    /* the following variables describe nesting try{} blocks */
    int try_block_level;
    ssize_t *try_variable_stack;

    /* catch and switch jumpover stack */
    ssize_t catch_jumpover_nr;
    ssize_t *catch_jumpover_stack;
    int catch_jumpover_stack_length;

    /* fields used for the implementation of packages: */
    VARTAB *compiled_packages;
    DLIST *current_package_stack;
    DNODE *current_package; /* this field must not be deleted when deleting
			       COMPILER */

    /* track which non-null reference fields of a structure are
       initialised: */
    VARTAB *initialised_references;
    STLIST *initialised_ref_symtab_stack;

} COMPILER;

static void compiler_drop_include_file( COMPILER *c );

static void delete_compiler( COMPILER *c )
{
    if( c ) {
	while( c->include_files ) {
	    compiler_drop_include_file( c );
	}
	freex( c->filename );
	if( c->yyin ) fclosex( c->yyin, NULL );

        delete_thrcode( c->main_thrcode );
        delete_thrcode( c->function_thrcode );

        delete_thrlist( c->thrstack );

	freex( c->static_data );
	delete_vartab( c->vartab );
	delete_vartab( c->consts );
	delete_vartab( c->compiled_packages );
	delete_typetab( c->typetab );
	delete_vartab( c->operators );

	delete_stlist( c->symtab_stack );

	delete_dnode( c->bytecode_labels );
	delete_fixup_list( c->bytecode_fixups );

	delete_dnode( c->loops );
        delete_dlist( c->loop_stack );

        freex( c->local_offset_stack );
	freex( c->addr_stack );
	delete_elist( c->saved_estacks );
	delete_enode( c->e_stack );
	freex( c->latest_exception_stack );
        freex( c->try_variable_stack );

	delete_dnode( c->current_call );

	delete_dlist( c->current_call_stack );
#if 0
        delete_dlist( c->current_arg_stack );
#else
        assert( !c->current_arg_stack );
#endif

	delete_dlist( c->current_package_stack );

        delete_vartab( c->initialised_references );
	delete_stlist( c->initialised_ref_symtab_stack );

        delete_dlist( c->current_function_stack );

        freex( c );
    }
}

static COMPILER *new_compiler( char *filename,
					   char **include_paths,
					   cexception_t *ex )
{
    cexception_t inner;
    COMPILER *cc = callocx( 1, sizeof(COMPILER), ex );

    cexception_guard( inner ) {
	cc->filename = strdupx( filename, &inner );
        cc->main_thrcode = new_thrcode( &inner );
        cc->function_thrcode = new_thrcode( &inner );

	/* cc->thrcode = cc->function_thrcode; */
	cc->thrcode = NULL;

	thrcode_set_immediate_printout( cc->function_thrcode, 1 );

	cc->vartab = new_vartab( &inner );
	cc->consts = new_vartab( &inner );
	cc->compiled_packages = new_vartab( &inner );
	cc->typetab = new_typetab( &inner );
	cc->operators = new_vartab( &inner );

	cc->local_offset = starting_local_offset;

	cc->include_paths = include_paths;
    }
    cexception_catch {
        delete_compiler( cc );
        cexception_reraise( inner, ex );
    }
    return cc;
}

static void compiler_save_flex_stream( COMPILER *c, char *filename,
				       cexception_t *ex  )
{
    assert( !c->filename );
    c->filename = strdupx( filename, ex );
    c->yyin = yyin = fopenx( filename, "r", ex );

    compiler_flex_push_state( yyin, ex );
    compiler_flex_set_current_line_number( 1 );
    compiler_flex_set_current_position( 1 );
}

static void compiler_restore_flex_stream( COMPILER *c )
{
    COMPILER_STATE *top;

    top = c->include_files;
    assert( top );

    if( c->yyin ) fclose( c->yyin );
    c->yyin = yyin = top->yyin;
    freex( c->filename );
    c->filename = NULL;

    compiler_flex_set_current_line_number( top->line_no );
    compiler_flex_set_current_position( top->column_no );
    compiler_flex_pop_state();
}

static void compiler_push_compiler_state( COMPILER *c,
					  cexception_t *ex )
{
    COMPILER_STATE *cstate;

    cstate = new_compiler_state( c->filename, c->use_package_name, c->yyin,
				 compiler_flex_current_line_number(),
				 compiler_flex_current_position(),
				 c->include_files, ex );

    c->filename = NULL;
    c->use_package_name = NULL;
    c->include_files = cstate;
}

void compiler_pop_compiler_state( COMPILER *c )
{
    COMPILER_STATE *top;

    top = c->include_files;
    assert( top );

    freex( c->use_package_name );
    c->use_package_name = top->use_package_name;

    c->include_files = top->next;
    assert( !c->filename );
    c->filename = top->filename;

    delete_compiler_state( top );
}

static char *make_full_file_name( char *filename, char *path,
                                  char *version, cexception_t *ex )
{
    static ssize_t volatile full_path_size;
    static char *volatile full_path;
    ssize_t n;
    ssize_t size;

    if( !filename ) { /* a hack to free memory */
	free( full_path );
	full_path = NULL;
	full_path_size = 0;
	return NULL;
    }

    if( full_path_size == 0 ) {
	size = 50;
	full_path = reallocx( full_path, size, ex );
	full_path_size = size;
    }

    while(1) {
        if( version ) {
            n = snprintf( full_path, full_path_size, "%s/%s/%s",
                          path, version, filename );
        } else {
            n = snprintf( full_path, full_path_size, "%s/%s",
                          path, filename );
        }
	if( n > -1 && n < full_path_size ) {
	    return full_path;
	}
	if( n > -1 ) {
	    size = n + 1;
	} else {
	    size = full_path_size * 2;
	}
	full_path = reallocx( full_path, size, ex );
	full_path_size = size;
    }
}

static char *compiler_find_include_file( COMPILER *c, char *filename,
					 cexception_t *ex )
{
    char **path;
    char *full_path;
    char *version = compiler_version;

    assert( c );

    if( !filename ) {
	return make_full_file_name( NULL, NULL, NULL, ex );
    }

    if( !c->include_paths ) {
	return filename;
    } else {
	for( path = c->include_paths; *path != NULL; path ++ ) {
	    FILE *f;
            /* first, check a compiler version-specific library: */
	    full_path = make_full_file_name( filename, *path, version, ex );
	    f = fopen( full_path, "r" );
	    if( f ) {
		fclose( f );
		/* printf( "Found '%s'\n", full_path ); */
		return full_path;
	    }
            /* if no luck, check for a generic library: */
	    full_path = make_full_file_name( filename, *path, NULL, ex );
	    f = fopen( full_path, "r" );
	    if( f ) {
		fclose( f );
		/* printf( "Found '%s'\n", full_path ); */
		return full_path;
	    }
	}
	make_full_file_name( NULL, NULL, NULL, ex );
	return filename;
    }
}

static void compiler_open_include_file( COMPILER *c, char *filename,
					cexception_t *ex )
{
    char *full_name = compiler_find_include_file( c, filename, ex);
    compiler_push_compiler_state( c, ex );
    compiler_save_flex_stream( c, full_name, ex );
}

static void compiler_push_symbol_tables( COMPILER *c,
					 cexception_t *ex )
{
    SYMTAB *symtab = new_symtab( c->vartab, c->consts, c->typetab,
                                 c->operators, ex );
    stlist_push_symtab( &c->symtab_stack, &symtab, ex );

    c->vartab = new_vartab( ex );
    c->consts = new_vartab( ex );
    c->typetab = new_typetab( ex );
    c->operators = new_vartab( ex );
}

static void compiler_use_exported_package_names( COMPILER *c,
						 DNODE *module,
						 cexception_t *ex )
{
    assert( module );

    /* printf( "importing package '%s'\n", dnode_name( module )); */

    vartab_copy_table( c->vartab, dnode_vartab( module ), ex );
    vartab_copy_table( c->consts, dnode_constants_vartab( module ), ex );
    typetab_copy_table( c->typetab, dnode_typetab( module ), ex );
    vartab_copy_table( c->operators, dnode_operator_vartab( module ), ex );
}

static void compiler_pop_symbol_tables( COMPILER *c )
{
    SYMTAB *symtab = stlist_pop_data( &c->symtab_stack );

    if( symtab ) {
	delete_vartab( c->vartab );
	delete_vartab( c->consts );
	delete_typetab( c->typetab );
	delete_vartab( c->operators );

	obtain_tables_from_symtab( symtab, &c->vartab, &c->consts,
				   &c->typetab, &c->operators );

	delete_symtab( symtab );
    }
}

static void compiler_push_initialised_ref_tables( COMPILER *c,
                                                  cexception_t *ex )
{
    SYMTAB *symtab = new_symtab( c->initialised_references, NULL, NULL, NULL, ex );
    stlist_push_symtab( &c->initialised_ref_symtab_stack, &symtab, ex );

    c->initialised_references = new_vartab( ex );
}

static void compiler_pop_initialised_ref_tables( COMPILER *c )
{
    SYMTAB *symtab = stlist_pop_data( &c->initialised_ref_symtab_stack );
    VARTAB *dummy_v = NULL;
    TYPETAB *dummy_t = NULL;
    VARTAB *dummy_o = NULL;

    delete_vartab( c->initialised_references );
    c->initialised_references = NULL;

    if( symtab ) {
	obtain_tables_from_symtab( symtab, &c->initialised_references,
                                   &dummy_v, &dummy_t, &dummy_o );
	delete_symtab( symtab );
    }
}

static void compiler_drop_include_file( COMPILER *c )
{
    compiler_restore_flex_stream( c );
    compiler_pop_compiler_state( c );
}

static void compiler_close_include_file( COMPILER *c,
					 cexception_t *ex )
{
    compiler_restore_flex_stream( c );

    if( c->use_package_name ) {
	DNODE *module = NULL;
	module = vartab_lookup( c->compiled_packages, c->use_package_name );
	if( module ) {
	    /* printf( "module '%s' is being used\n", c->use_package_name ); */
	    compiler_use_exported_package_names( c, module, ex );
	} else {
	    yyerrorf( "no module named '%s'?", c->use_package_name );
	}
    }

    compiler_pop_compiler_state( c );
}

static void push_int( int **array, int *size, int value, cexception_t *ex )
{
    *array = reallocx( *array, ( *size + 1 ) * sizeof(**array), ex );
    (*array)[*size] = value;
    (*size) ++;
}

static int pop_int( int **array, int *size, cexception_t *ex )
{
    (*size) --;
    return (*array)[*size];
}

static void push_ssize_t( ssize_t **array, int *size, ssize_t value,
                          cexception_t *ex )
{
    *array = reallocx( *array, ( *size + 1 ) * sizeof(**array), ex );
    (*array)[*size] = value;
    (*size) ++;
}

static void compiler_push_current_address( COMPILER *c, cexception_t *ex )
{
    push_ssize_t( &c->addr_stack, &c->addr_stack_size,
		  thrcode_length(c->thrcode), ex );
}

static ssize_t pop_ssize_t( ssize_t **array, int *size, cexception_t *ex )
{
    (*size) --;
    return (*array)[*size];
}

static ssize_t compiler_pop_address( COMPILER *c, cexception_t *ex )
{
    return pop_ssize_t( &c->addr_stack, &c->addr_stack_size, ex );
}

static ssize_t compiler_pop_offset( COMPILER *c, cexception_t *ex )
{
    return pop_ssize_t( &c->addr_stack, &c->addr_stack_size, ex )
           - thrcode_length( c->thrcode );
}

static ssize_t compiler_code_length( COMPILER *c )
{
    return thrcode_length( c->thrcode );
}

static void compiler_push_relative_fixup( COMPILER *c, cexception_t *ex )
{
    thrcode_push_relative_fixup_here( c->thrcode, "", ex );
}

static void compiler_push_absolute_fixup( COMPILER *c, cexception_t *ex )
{
    thrcode_push_absolute_fixup_here( c->thrcode, "", ex );
}

static void compiler_fixup_here( COMPILER *c )
{
    thrcode_internal_fixup_here( c->thrcode );
}

static void compiler_fixup( COMPILER *c, ssize_t value )
{
    thrcode_internal_fixup( c->thrcode, value );
}

static void compiler_swap_fixups( COMPILER *c )
{
    thrcode_internal_fixup_swap( c->thrcode );
}

static void compiler_check_enum_basetypes( TNODE *lookup_tnode, TNODE *tnode )
{
    if( tnode && lookup_tnode ) {
	TNODE *base1 = tnode_base_type( lookup_tnode );
	TNODE *base2 = tnode_base_type( tnode );
	char *name = tnode_name( lookup_tnode );

	if( base2 && base1 != base2 ) {
	    if( name ) {
		yyerrorf( "enum type '%s' is being extended with "
			  "wrong parent type", name );
	    } else {
		yyerrorf( "enum type is being extended with "
			  "wrong parent type", name );
	    }
	}
    }
}

static TNODE *compiler_typetab_insert_msg( COMPILER *cc,
					char *name,
					type_suffix_t suffix_type,
					TNODE *tnode,
					char *type_conflict_msg,
					cexception_t *ex )
{
    TNODE *lookup_node;
    int count = 0;
    int is_imported = 0;

    lookup_node =
	typetab_insert_suffix( cc->typetab, name, suffix_type, tnode,
                               &count, &is_imported, ex );

    if( lookup_node != tnode ) {
	if( tnode_is_forward( lookup_node )) {
            if( tnode_is_non_null_reference( tnode ) !=
                tnode_is_non_null_reference( lookup_node )) {
                yyerrorf( "redeclaration of forward type '%s' changes "
                          "non-null flag", tnode_name( lookup_node ) );
            }
	    tnode_shallow_copy( lookup_node, tnode );
	    delete_tnode( tnode );
            tnode = NULL;
	} 
	else if( tnode_is_extendable_enum( lookup_node )) {
	    tnode_merge_field_lists( lookup_node, tnode );
	    compiler_check_enum_basetypes( lookup_node, tnode );
	    delete_tnode( tnode );
	} else if( !is_imported ) {
	    char *name = tnode_name( tnode );
	    if( strstr( type_conflict_msg, "%s" ) != NULL ) {
		yyerrorf( type_conflict_msg, name );
	    } else {
		yyerrorf( type_conflict_msg );
	    }
	}
    }
    if( tnode && lookup_node != tnode && is_imported ) {
        return tnode;
    } else {
        return lookup_node;
    }
}

static int compiler_current_scope( COMPILER *cc )
{
    return vartab_current_scope( cc->vartab );
}

static void compiler_typetab_insert( COMPILER *cc,
				  TNODE *tnode,
				  cexception_t *ex )
{
    TNODE *lookup_tnode =
	compiler_typetab_insert_msg( cc, tnode_name( tnode ),
				  TS_NOT_A_SUFFIX, tnode,
				  "type '%s' is already declared", ex );
    if( cc->current_package && lookup_tnode == tnode &&
        compiler_current_scope( cc )  == 0 ) {
	dnode_typetab_insert_named_tnode( cc->current_package,
					  share_tnode( tnode ), ex );
    }
}

static void compiler_vartab_insert_named_vars( COMPILER *cc,
					    DNODE *vars,
					    cexception_t *ex )
{
    vartab_insert_named_vars( cc->vartab, vars, ex );
    if( cc->current_package && dnode_scope( vars ) == 0 ) {
	dnode_vartab_insert_named_vars( cc->current_package,
					share_dnode( vars ), ex );
    }
}

static void compiler_vartab_insert_single_named_var( COMPILER *cc,
                                                  DNODE *var,
                                                  cexception_t *ex )
{
    char *name = dnode_name( var );
    assert( name );

    vartab_insert( cc->vartab, name, var, ex );
    if( cc->current_package && dnode_scope( var ) == 0 ) {
	dnode_vartab_insert_dnode( cc->current_package, name,
                                   share_dnode( var ), ex );
    }
}

static void compiler_consttab_insert_consts( COMPILER *cc, DNODE *consts,
					  cexception_t *ex )
{
    vartab_insert_named_vars( cc->consts, consts, ex );
    if( cc->current_package ) {
	dnode_consttab_insert_consts( cc->current_package,
				      share_dnode( consts ), ex );
    }
}

static void compiler_insert_tnode_into_suffix_list( COMPILER *cc,
						 TNODE *tnode,
						 cexception_t *ex )
{
    TNODE *base_type = NULL;
    char *suffix;
    type_kind_t type_kind;
    char *type_conflict_msg = NULL;

    suffix = tnode_suffix( tnode );
    if( !suffix ) suffix = "";

    type_kind = tnode_kind( tnode );

    if( type_kind == TK_DERIVED &&
	(base_type = tnode_base_type( tnode )) ) {
	type_kind = tnode_kind( base_type );
    }

    switch( type_kind ) {
    case TK_BOOL:
    case TK_INTEGER:
        if( !suffix || suffix[0] == '\0' ) {
	    type_conflict_msg = "integer type with empty suffix is already "
    	    		        "defined in the current scope";
        } else {
	    type_conflict_msg = "integer type with suffix '%s' is already "
    	    		        "defined in the current scope";
	}
	compiler_typetab_insert_msg( cc, suffix, TS_INTEGER_SUFFIX, tnode,
				  type_conflict_msg, ex );
	share_tnode( tnode );
	if( cc->current_package ) {
	    dnode_typetab_insert_tnode_suffix( cc->current_package, suffix,
					       TS_INTEGER_SUFFIX,
					       share_tnode( tnode ), ex );
	}
	break;
    case TK_REAL:
        if( !suffix || suffix[0] == '\0' ) {
	    type_conflict_msg = "real type with empty suffix is already "
    	    		        "defined in the current scope";
        } else {
	    type_conflict_msg = "real type with suffix '%s' is already "
    	    		        "defined in the current scope";
	}
	compiler_typetab_insert_msg( cc, suffix, TS_FLOAT_SUFFIX, tnode,
				  type_conflict_msg, ex );
	share_tnode( tnode );
	if( cc->current_package ) {
	    dnode_typetab_insert_tnode_suffix( cc->current_package, suffix,
					       TS_FLOAT_SUFFIX,
					       share_tnode( tnode ), ex );
	}
	break;
    case TK_STRING:
        if( !suffix || suffix[0] == '\0' ) {
	    type_conflict_msg = "string type with empty suffix is already "
    	    		        "defined in the current scope";
        } else {
	    type_conflict_msg = "string type with suffix '%s' is already "
    	    		        "defined in the current scope";
	}
	compiler_typetab_insert_msg( cc, suffix, TS_STRING_SUFFIX, tnode,
				  type_conflict_msg, ex );
	share_tnode( tnode );
	if( cc->current_package ) {
	    dnode_typetab_insert_tnode_suffix( cc->current_package, suffix,
					       TS_STRING_SUFFIX,
					       share_tnode( tnode ), ex );
	}
	break;
    case TK_NONE:
        if( !suffix || suffix[0] == '\0' ) {
	    type_conflict_msg = "type with empty suffix is already "
    	    		        "defined in the current scope";
        } else {
	    type_conflict_msg = "type with suffix '%s' is already "
    	    		        "defined in the current scope";
	}
	compiler_typetab_insert_msg( cc, suffix, TS_NOT_A_SUFFIX, tnode,
				  type_conflict_msg, ex );
	share_tnode( tnode );
	if( cc->current_package ) {
	    dnode_typetab_insert_tnode_suffix( cc->current_package, suffix,
					       TS_NOT_A_SUFFIX,
					       share_tnode( tnode ), ex );
	}
	break;
    case TK_STRUCT:
    case TK_CLASS:
    case TK_BLOB:
    case TK_ARRAY:
    case TK_COMPOSITE:
    case TK_ENUM:
    case TK_REF:
    case TK_FUNCTION_REF:
    case TK_DERIVED:
	break;
    default:
	yyerrorf( "types of kind '%s' do not have suffix table",
		  tnode_kind_name( tnode ));
	break;
    }
}

static void compiler_push_type( COMPILER *c, TNODE *tnode,
			     cexception_t *ex )
{
    ENODE *expr_enode = NULL;

    expr_enode = new_enode_typed( tnode, ex );
    enode_list_push( &c->e_stack, expr_enode );
}

static void compiler_push_error_type( COMPILER *c,
				   cexception_t *ex )
{
    ENODE *expr_enode = NULL;

    expr_enode = new_enode( ex );
    enode_set_has_errors( expr_enode );
    enode_list_push( &c->e_stack, expr_enode );
}

static void compiler_append_expression_type( COMPILER *c,
					  TNODE *base_tnode )
{
    assert( c->e_stack );
    enode_append_element_type( c->e_stack, base_tnode );
}

static TNODE *new_tnode_array_snail( TNODE *element_type,
				     TYPETAB *typetab,
				     cexception_t *ex )
{
    TNODE *base_type = share_tnode( typetab_lookup( typetab, "array" ));
    return new_tnode_array( element_type, base_type, ex );
}

static TNODE *new_tnode_blob_snail( TYPETAB *typetab, cexception_t *ex )
{
    TNODE *base_type = share_tnode( typetab_lookup( typetab, "blob" ));
    return new_tnode_blob( base_type, ex );
}

static void compiler_compile_exception( COMPILER *c,
				     char *exception_name,
				     ssize_t exception_nr,
				     cexception_t *ex )
{
    cexception_t inner;
    TNODE *exception_type =
	share_tnode( typetab_lookup( c->typetab, "exception" ));
    DNODE * volatile exception = NULL;

    cexception_guard( inner ) {
	exception =
	    new_dnode_exception( exception_name, exception_type, &inner );

	dnode_set_ssize_value( exception, exception_nr );
	vartab_insert_named( c->vartab, exception, &inner );
        if( c->current_package && dnode_scope( exception ) == 0 ) {
            dnode_vartab_insert_named_vars( c->current_package,
                                            share_dnode( exception ), ex );
        }
    }
    cexception_catch {
	delete_dnode( exception );
	cexception_reraise( inner, ex );
    }
}

static void compiler_compile_next_exception( COMPILER *c,
					  char *exception_name,
					  cexception_t *ex )
{
    compiler_compile_exception( c, exception_name, ++c->latest_exception_nr, ex );
}

static void compiler_push_array_of_type( COMPILER *c, TNODE *tnode,
				      cexception_t *ex )
{
    cexception_t inner;
    ENODE *expr_enode = NULL;
    TNODE * volatile array_type = NULL;

    cexception_guard( inner ) {
	array_type = new_tnode_array_snail( tnode, c->typetab, &inner );
	share_tnode( tnode );
	expr_enode = new_enode_typed( array_type, &inner );
	enode_list_push( &c->e_stack, expr_enode );
    }
    cexception_catch {
	delete_tnode( array_type );
	cexception_reraise( inner, ex );
    }
}

static void compiler_drop_top_expression( COMPILER *cc )
{
    assert( cc->e_stack );
    enode_list_drop( &cc->e_stack );
}

static void compiler_swap_top_expressions( COMPILER *cc )
{
    ENODE *e1 = enode_list_pop( &cc->e_stack );
    ENODE *e2 = enode_list_pop( &cc->e_stack );

    enode_list_push( &cc->e_stack, e1 );
    enode_list_push( &cc->e_stack, e2 );    
}

static void compiler_check_and_remove_index_type( COMPILER *cc )
{
    ENODE *idx_enode;

    idx_enode = enode_list_pop( &cc->e_stack );
    delete_enode( idx_enode );
}

static void tnode_report_missing_operator( TNODE *tnode,
					   const char *operator_name,
					   int arity )
{
    char *arity_name = "";
    char pad[80];
    char *type_name;

    if( !tnode ) return;

    type_name = tnode_name( tnode );

    if( arity > 0 ) {
	switch( arity ) {
	    case 1: arity_name = "unary ";  break;
	    case 2: arity_name = "binary "; break;
	    case 3: arity_name = "ternary "; break;
	    default:
		memset( pad, 0, sizeof( pad ));
		snprintf( pad, sizeof(pad)-1, "arity %d ", arity );
		arity_name = pad;
		break;
	}
    }

    if( type_name ) {
	yyerrorf( "type '%s' has no %soperator named '%s'", type_name,
		  arity_name, operator_name );
    } else {
	yyerrorf( "this type has no %soperator named '%s'",
		  arity_name, operator_name );
    }
}

static void compiler_emit( COMPILER *cc,
			cexception_t *ex,
			const char *format, ... )
{
    cexception_t inner;
    va_list ap;

    va_start( ap, format );
    cexception_guard( inner ) {
	thrcode_emit_va( cc->thrcode, &inner, format, ap );
    }
    cexception_catch {
	int code = cexception_error_code( &inner );
	const void *tag = cexception_subsystem_tag( &inner );
	if( code == THRCODE_UNRECOGNISED_OPCODE && tag == thrcode_subsystem ) {
	    yyerrorf( (char*)cexception_message( &inner ));
	} else {
	    va_end( ap );
	    cexception_reraise( inner, ex );
	}
    }
    va_end( ap );
}

typedef struct {
    char *key;
    ssize_t val;
} key_value_t;

static ssize_t lookup_ssize_value( key_value_t *dict, char *name )
{
    key_value_t *curr = dict;

    while( curr && curr->key ) {
	if( strcmp( curr->key, name ) == 0 ) {
	    return curr->val;
	}
	curr ++;
    }

    yyerrorf( "keyword '%%%%%s' is not available here", name );

    if( dict && dict->key ) {
	fprintf( stderr, "available keywords are:\n" );
	for( curr = dict; curr && curr->key; curr ++ ) {
	    fprintf( stderr, "'%%%%%s'\n", curr->key );
	}
    } else {
	fprintf( stderr, "keyword table is empty at this point\n" );
    }

    return 0;
}

static key_value_t *make_tnode_key_value_list( TNODE *tnode )
{
    static key_value_t empty_list[1] = {{ NULL }};
    static key_value_t list[] = {
	{ "element_nref" },
        { "element_size" },
        { "element_align" },
        { "nref" },
        { "alloc_size" },
        { "vmt_offset" },
	{ NULL },
    };

    if( !tnode ) return empty_list;

    list[0].val = tnode_is_reference( tnode ) ? 1 : 0;
    list[1].val = tnode_is_reference( tnode ) ? 
        REF_SIZE : tnode_size( tnode );
    list[2].val = tnode_align( tnode );

    list[3].val = tnode_number_of_references( tnode );
    list[4].val = tnode_size( tnode );
    list[5].val = tnode_vmt_offset( tnode );

    /* For placeholders, we just in case allocate arrays thay say they
       contain references. This is necessary so that GC does not
       collect allocated elements in case the generic type is indeed a
       reference, and we assign them as elements to an allocated array
       of generic type: */

    list[0].val = tnode_is_reference( tnode ) ? 1 : 
        (tnode_kind(tnode) == TK_PLACEHOLDER ? 1 : 0);

    return list;
}

static key_value_t *make_mdalloc_key_value_list( TNODE *tnode, ssize_t level )
{
    static key_value_t empty_list[1] = {{ NULL }};
    static key_value_t list[] = {
	{ "element_nref" },
	{ "level" },
        { "element_size" },
        { "element_align" },
	{ NULL },
    };

    if( !tnode ) return empty_list;

    list[0].val = tnode_is_reference( tnode ) ? 1 : 0;
    list[1].val = level;
    list[2].val = tnode_is_reference( tnode ) ? 
        REF_SIZE : tnode_size( tnode );
    list[3].val = tnode_align( tnode );

    return list;
}

static void compiler_fixup_inlined_function( COMPILER *cc,
					  DNODE *function,
					  key_value_t *fixup_values,
					  ssize_t code_start )
{
    FIXUP *fixup, *fixup_list;

    assert( function );
    fixup_list = dnode_code_fixups( function );

    foreach_fixup( fixup, fixup_list ) {
	char *name = fixup_name( fixup );
	ssize_t value = lookup_ssize_value( fixup_values, name );
	thrcode_fixup_offsetted( cc->thrcode, fixup, code_start, value );
    }
}

static void compiler_emit_function_call( COMPILER *cc,
				      DNODE *function,
				      key_value_t *fixup_values,
				      char *trailer,
				      cexception_t *ex )
{
    int is_bytecode = dnode_has_flags( function, DF_BYTECODE );

    if( dnode_has_flags( function, DF_INLINE )) {
	ssize_t code_length, i;
	thrcode_t *code = dnode_code( function, &code_length );
	ssize_t code_start = thrcode_length( cc->thrcode );

	if( code_length > 0 ) {
	    if( !is_bytecode ) {
		compiler_emit( cc, ex, "\tc\n", PUSHFRM );
                code_start ++;
	    }
	    thrcode_emit( cc->thrcode, ex, "\t" );
	    for( i = 0; i < code_length; i++ ) {
		if( code[i].ssizeval > 1000 ) {
		    thrcode_emit( cc->thrcode, ex, "c", code[i].fn );
		} else {
		    thrcode_emit( cc->thrcode, ex, "e", &code[i].ssizeval );
		}
	    }
	    if( trailer && trailer[0] != '\0' ) {
		thrcode_emit( cc->thrcode, ex, trailer );
	    }
	    if( !is_bytecode ) {
		compiler_emit( cc, ex, "\n\tc\n", POPFRM );
	    }
	}
	if( fixup_values ) {
	    compiler_fixup_inlined_function( cc, function, fixup_values,
					  code_start );
	}
    } else {
	TNODE *fn_tnode = function ? dnode_type( function ) : NULL;
        type_kind_t fn_kind = fn_tnode ? tnode_kind( fn_tnode ) : TK_NONE;

	if( fn_kind == TK_FUNCTION_REF || fn_kind == TK_CLOSURE ) {
	    compiler_emit( cc, ex, "\tc\n", ICALL );
	} else if( fn_tnode && tnode_kind( fn_tnode ) == TK_METHOD ) {
	    char *fn_name = dnode_name( function );
	    ssize_t fn_address = dnode_offset( function );
	    ssize_t interface_nr = tnode_interface_number( fn_tnode );
	    compiler_emit( cc, ex, "\tceeN\n", VCALL,
			&interface_nr, &fn_address, fn_name );
	} else {
	    char *fn_name = dnode_name( function );
	    ssize_t fn_address = dnode_offset( function );
	    ssize_t zero = 0;
	    if( fn_address == 0 && fn_name ) {
		thrcode_push_forward_function( cc->thrcode, fn_name,
					       thrcode_length( cc->thrcode ) + 1,
					       ex );
		compiler_emit( cc, ex, "\tceN\n", CALL, &zero, fn_name );
	    } else {
		/* ssize_t code_length = thrcode_length( compiler_cc->thrcode ); */
		/* fn_address -= code_length; */
		compiler_emit( cc, ex, "\tceN\n", CALL, &fn_address, fn_name );
	    }
	}
    }
}

static void compiler_push_function_retvals( COMPILER *cc, DNODE *function,
                                         TYPETAB *generic_types,
					 cexception_t *ex )
{
    cexception_t inner;
    TNODE *function_tnode;
    DNODE *retval_dnode, *function_retvals;
    TNODE *volatile retval_tnode = NULL;
    ENODE *volatile retval_enode = NULL;

    function_tnode = dnode_type( function );
    function_retvals = tnode_retvals( function_tnode );

    cexception_guard( inner ) {
        foreach_dnode( retval_dnode, function_retvals ) {
            retval_tnode = new_tnode_implementation( dnode_type( retval_dnode ),
                                                     generic_types, &inner );
            retval_enode = new_enode_return_value( retval_tnode, &inner );
            enode_list_push( &cc->e_stack, retval_enode );
            retval_tnode = NULL;
            retval_enode = NULL;
        }
    }
    cexception_catch {
        delete_tnode( retval_tnode );
        delete_enode( retval_enode );
        cexception_reraise( inner, ex );
    }
}

static void compiler_compile_type_conversion( COMPILER *cc,
					   char *target_name,
					   cexception_t *ex )
{
    cexception_t inner;
    ENODE * volatile expr = enode_list_pop( &cc->e_stack );
    ENODE * volatile converted_expr = NULL;
    TNODE * expr_type = expr ? enode_type( expr ) : NULL;
    char *source_name = expr_type ? tnode_name( expr_type ) : NULL;

    cexception_guard( inner ) {
	if( !expr ) {
	    yyerrorf( "not enough values on the stack for type conversion "
		      "from '%s' to '%s'", source_name, target_name );
	} else {
	    TNODE *target_type =
		typetab_lookup( cc->typetab, target_name );
	    DNODE *conversion =
		target_type ?
		    tnode_lookup_conversion( target_type, source_name ) :
		    NULL;
	    TNODE *optype = conversion ? dnode_type( conversion ) : NULL;
	    DNODE *retvals = optype ? tnode_retvals( optype ) : NULL;
	    int retval_nr = dnode_list_length( retvals );

	    if( !target_type ) {
		yyerrorf( "type conversion impossible - "
			  "target type '%s' not defined in the current scope",
			  target_name );
	    } else
	    if( !conversion ) {
		if( source_name && target_name ) {
		    yyerrorf( "type '%s' has no conversion from type '%s'",
			      target_name, source_name );
		} else {
		    if( target_name ) {
			yyerrorf( "type '%s' has no conversion from the given "
				  "type",  target_name );
		    } else {
			yyerrorf( "the required type has no conversion from "
				  "the given type" );
		    }
		}
	    } else
	    if( retval_nr != 1 ) {
		yyerrorf( "type conversion operators should return "
			  "a single value, but conversion to from '%s' to '%s' "
			  "returns %d values",
			  target_name, source_name, retval_nr );
	    }
	    if( conversion ) {
		compiler_emit_function_call( cc, conversion, NULL, "\n", ex );
	    }

	    if( target_type ) {
		converted_expr = new_enode_typed( target_type, &inner );
		share_tnode( target_type );
		enode_list_push( &cc->e_stack, converted_expr );
		delete_enode( expr );
	    } else {
		enode_list_push( &cc->e_stack, expr );
	    }
	}
    }
    cexception_catch {
	enode_list_push( &cc->e_stack, expr );
	cexception_reraise( inner, ex );
    }
}

static void compiler_compile_return( COMPILER *cc,
				  int nretvals,
				  cexception_t *ex )
{
    int i;
    DNODE *function = cc ? cc->current_function : NULL;
    TNODE *fn_type = function ? dnode_type( function ) : NULL;
    DNODE *fn_retvals = fn_type ? tnode_retvals( fn_type ) : NULL;
    DNODE *retval = NULL;
    ENODE *expr = NULL;

    assert( cc );

    fn_retvals = dnode_list_invert( fn_retvals );
    retval = fn_retvals;
    expr = cc->e_stack;
    for( i = 0; expr && i < nretvals; i++ ) {
	TNODE *available_type;
	TNODE *returned_type;

	if( !retval || enode_is_guarding_retval( expr )) {
	    break;
	}

	returned_type = dnode_type( retval );
	available_type = enode_type( expr );

	/* if( !tnode_types_are_identical( returned_type, available_type )) { */
	if( !tnode_types_are_assignment_compatible
            ( returned_type, available_type, NULL /* generic type table */,
              ex )) {
#if 1
            char *available_type_name = available_type ?
                tnode_name( available_type ) : NULL;
            char *returned_type_name = returned_type ?
                tnode_name( returned_type ) : NULL;
            if( available_type_name && returned_type_name && 
                i == 0 &&
                tnode_lookup_conversion( returned_type,
                                         available_type_name  )) {
                compiler_compile_type_conversion( cc, returned_type_name, ex );
                expr = cc->e_stack;
                if( expr ) {
                    available_type = enode_type( expr );
                }
            } else {
#endif
                yyerrorf( "incompatible types of returned value %d "
                          "of function '%s'",
                          nretvals - i, dnode_name( cc->current_function ));
#if 1
            }
#endif
	}

	retval = dnode_next( retval );
	expr = enode_next( expr );
    }
    fn_retvals = dnode_list_invert( fn_retvals );

    if( !cc->current_function ) {
	yyerrorf( "the \"return\" statement should be used only in "
		  "subroutines, not in the main script" );
    } else {
	if( !expr ) {
	    yyerrorf( "too little values on the stack returned "
		      "from function '%s'",
		      dnode_name( cc->current_function ));
	} else {
	    if( !enode_is_guarding_retval( expr )) {
		yyerrorf( "too many values returned from function '%s'",
			  dnode_name( cc->current_function ));
	    } else {
		if( retval ) {
		    yyerrorf( "too little values returned from function '%s'",
			      dnode_name( cc->current_function ));
		}
	    }
	}
    }

    while( cc->e_stack && !enode_is_guarding_retval( cc->e_stack )) {
	compiler_drop_top_expression( cc );
    }

    if( enode_is_guarding_retval( cc->e_stack )) {
	compiler_drop_top_expression( cc );
    }

    {
	int i;
	for( i = 0; i < cc->try_block_level; i++ ) {
	    compiler_emit( cc, ex, "\tc\n", RESTORE );
	}
    }

    if( function && !dnode_has_flags( function, DF_INLINE )) {
	compiler_emit( cc, ex, "\tc\n", RET );
    }
}

static DNODE *
compiler_lookup_optab_operator( COMPILER *cc,
                                char *operator_name,
                                TNODE *argument_tnode,
                                int arity,
                                cexception_t *ex )
{
    cexception_t inner;
    ENODE *top_expr = cc->e_stack;
    ENODE *expr = NULL;
    TNODE *current = NULL;
    TLIST *volatile expr_types = NULL; 
    DNODE *operator_dnode = NULL;
    int i = 0;

    cexception_guard( inner ) {
        if( !top_expr && strcmp( operator_name, "st" ) == 0 ) {
            share_tnode( argument_tnode );
            tlist_push_tnode( &expr_types, &argument_tnode, &inner );
        } else {
            for( expr = top_expr; expr; expr = enode_next( expr )) {
                if( enode_has_flags( expr, EF_GUARDING_ARG )) {
                    break;
                }
                current = share_tnode( enode_type( expr ));
                tlist_push_tnode( &expr_types, &current, &inner );
                i++;
                if( i >= arity ) break;
            }
        }
    }
    cexception_catch {
        delete_tlist( expr_types );
        cexception_reraise( inner, ex );
    }

#if 0
    if( i < arity ) {
        yyerrorf( "too little expressions (%d) for an operator '%s' "
                  "of arity %d",
                  i, operator_name, arity );
    }
#endif

    operator_dnode = vartab_lookup_operator( cc->operators, operator_name,
                                             expr_types );

#if 0
    if( !operator_dnode ) {
        yyerrorf( "could not find matching operator '%s' of arity %d",
                  operator_name, arity );
    }
#endif

    delete_tlist( expr_types );

    return operator_dnode;
}

static DNODE* compiler_lookup_operator( COMPILER *cc,
                                        TNODE *tnode,
                                        char *operator_name,
                                        int arity,
                                        cexception_t *ex )
{
    DNODE *operator;

    if( (operator = compiler_lookup_optab_operator( cc, operator_name,
                                                    tnode, arity, ex ))) {
        return operator;
    } else {
        return tnode_lookup_operator( tnode, operator_name, arity );
    }
}

#define OD_MAGIC 0x12345678

typedef enum {
    ODF_NONE = 0,
    ODF_IS_INHERITED = 0x01,
} operator_description_flags_t;

typedef struct {
    int magic;
    int flags;
    char *name;
    int arity;
    DNODE *operator;
    TNODE *containing_type;
    TNODE *describing_type;
    DNODE *retvals;
    int retval_nr;
} operator_description_t;

static void compiler_init_operator_description( operator_description_t *od,
                                             COMPILER *cc,
					     TNODE *op_type,
					     char *op_name,
					     int arity,
                                             cexception_t *ex )
{
    assert( od );

    memset( od, 0, sizeof(*od) );

    od->magic = OD_MAGIC;
    od->flags = ODF_NONE;
    od->name = op_name;
    od->arity = arity;
    od->containing_type = op_type;
    od->operator = 
        compiler_lookup_optab_operator( cc, op_name, op_type, arity, ex );
    if( !od->operator ) {
        od->operator = op_type ?
            tnode_lookup_operator_nonrecursive( op_type, op_name, arity )
            : NULL;
    }
    if( !od->operator ) {
	od->operator = op_type ? tnode_lookup_operator( op_type, op_name, arity )
	                         : NULL;
	if( od->operator  ) {
	    od->flags |= ODF_IS_INHERITED;
	}
    }
    od->describing_type = od->operator ? dnode_type( od->operator ) : NULL;
    od->retvals = od->describing_type ?
	tnode_retvals( od->describing_type ) : NULL;
    od->retval_nr = dnode_list_length( od->retvals );
}

static void compiler_check_operator_args( COMPILER *cc,
				       operator_description_t *od,
				       TYPETAB *generic_types,
                                       cexception_t *ex )
{
    DNODE *op_args;
    DNODE *arg;
    ENODE *expr;
    int nargs;

    assert( od );
    assert( od->magic == OD_MAGIC );
    assert( cc );
    
    if( od->operator ) {
	op_args = od->describing_type ? tnode_args( od->describing_type ) :
	    NULL;

        if( strcmp( od->name, "st" ) == 0 ) {
            /* The custom "st" operators will be emitted when
               compiling function parameter list (stores); at that
               point there will be no expressions emulated on the
               e_stack, and the compatibility check needs a special
               treatment: */
            TNODE *arg_type = op_args ? dnode_type( op_args ) : NULL;

            if( !arg_type ||
                !tnode_types_are_assignment_compatible( dnode_type( op_args ),
                                                        od->containing_type,
                                                        generic_types,
                                                        ex )) {
                yyerrorf( "incompatible type of an argument "
                          "for operator '%s'", od->name );
            }
        } else {
            expr = cc->e_stack;

            nargs = dnode_list_length( op_args );

            foreach_dnode( arg, op_args ) {
                TNODE *argument_type;
                TNODE *expr_type;

                if( !expr ) {
                    yyerrorf( "too little values in the stack for operator '%s'",
                              dnode_name( od->operator ));
                    break;
                }

                argument_type = dnode_type( arg );
                expr_type = enode_type( expr );

#if 1
                if( !tnode_types_are_compatible( argument_type, expr_type,
                                                 generic_types, ex )) {
#else
                if( !tnode_types_are_assignment_compatible( argument_type,
                                                            expr_type,
                                                            generic_types,
                                                            ex )) {
#endif
                    yyerrorf( "incompatible type of argument %d "
                              "for operator '%s'",
                              nargs, dnode_name( od->operator ));
                }

                expr = enode_next( expr );
                nargs --;
            }
	}
    }
}

static void compiler_drop_operator_args( COMPILER *cc,
				      operator_description_t *od )
{
    DNODE *op_args;
    DNODE *arg;

    assert( od );
    assert( od->magic == OD_MAGIC );
    assert( cc );
    
    if( od->operator ) {
	op_args = od->describing_type ?
	    tnode_args( od->describing_type ) : NULL;
	foreach_dnode( arg, op_args ) {
	    compiler_drop_top_expression( cc );
	}
    }
}

static void compiler_push_operator_retvals( COMPILER *cc,
					 operator_description_t *od,
					 ENODE * volatile *on_error_expr,
                                         TYPETAB *generic_types,
					 cexception_t *ex )
{
    TNODE *retval_type;

    assert( od );
    assert( od->magic == OD_MAGIC );

    retval_type = od->retvals ? dnode_type( od->retvals ) : NULL;

    if( od->containing_type &&
	    ( tnode_kind( od->containing_type ) == TK_DERIVED ||
	      tnode_kind( od->containing_type ) == TK_ENUM ) &&
	    (od->flags & ODF_IS_INHERITED) != 0 ) {
	TNODE *base_type = tnode_base_type( od->containing_type );
	if( retval_type == base_type ) {
	    retval_type = od->containing_type;
	}
    }

    if( generic_types ) {
    // if( 0 ) {
        // CHECK MEMORY USAGE HERE!!! S.G.
        retval_type = new_tnode_implementation( retval_type, generic_types, ex );
    }

    if( od->containing_type && retval_type &&
        tnode_kind( retval_type ) == TK_PLACEHOLDER ) {
	TNODE *element_type = tnode_element_type( od->containing_type );
	if( element_type ) {
	    retval_type = element_type;
	}
    }

    if( retval_type ) {
	compiler_push_type( cc, retval_type, ex );
	share_tnode( retval_type );
    }  else {
	if( !od->operator && on_error_expr && *on_error_expr ) {
	    enode_set_has_errors( *on_error_expr );
	    enode_list_push( &cc->e_stack, *on_error_expr );
	    *on_error_expr = NULL; /* let's not delete expression :) */
	}
    }
}

static void compiler_emit_operator_or_report_missing( COMPILER *cc,
						   operator_description_t *od,
						   key_value_t *fixup_values,
						   char *trailer,
						   cexception_t *ex )
{
    assert( od );
    assert( od->magic == OD_MAGIC );

    if( od->operator ) {
	compiler_emit_function_call( cc, od->operator, fixup_values, trailer, ex );
    } else {
	tnode_report_missing_operator( od->containing_type,
				       od->name, od->arity );
    }
}

static void compiler_check_operator_retvals( COMPILER *cc,
					  operator_description_t *od,
					  int minvals,
					  int maxvals )
{
    assert( od );
    assert( od->magic == OD_MAGIC );

    if( od->operator && !od->describing_type ) {
	yyerrorf( "type '%s' operator '%s' does not have "
		  "an operator type description!",
		  tnode_name(od->containing_type), od->name );
    }

    if( od->describing_type &&
	( od->retval_nr < minvals || od->retval_nr > maxvals )) {
	if( minvals == 1 && maxvals == 1 ) {
	    yyerrorf( "type '%s' operator '%s' should return one value",
		      tnode_name(od->containing_type), od->name );
	} else
	if( minvals == 0 && maxvals == 1 && od->arity == 1 ) {
	    yyerrorf( "currently, unary operators should return no value "
		      "or a single value, but operator '%s' "
		      "returns %d values", od->name, od->retval_nr );
	} else
	if( minvals == maxvals ) {
	    yyerrorf( "operator '%s' should return %d values, but it is "
		      "declared to return %d values",
		      od->name, maxvals, od->retval_nr );
	} else {
	    yyerrorf( "operator '%s' should return no more than %d "
		      "and not less than %d values, but it is declared "
		      "to return %d values",
		      od->name, maxvals, minvals, od->retval_nr );
	}
    }
}

static int compiler_test_top_types_are_identical( COMPILER *cc,
						  cexception_t *ex )
{
    ENODE * expr1 = NULL, * expr2 = NULL;

    assert( cc );

    expr1 = cc->e_stack;
    expr2 = expr1 ? enode_next( expr1 ) : NULL;

    if( !expr1 || !expr2 ) {
	return 0;
    } else {
	TNODE *type1 = enode_type( expr1 );
	TNODE *type2 = enode_type( expr2 );

	if( !tnode_types_are_identical( type1, type2, NULL, ex )) {
	    return 0;
	} else {
	    return 1;
	}
    }    
}

static int compiler_test_top_types_are_assignment_compatible(
    COMPILER *cc,
    cexception_t *ex )
{
    ENODE * expr1 = NULL, * expr2 = NULL;

    assert( cc );

    expr1 = cc->e_stack;
    expr2 = expr1 ? enode_next( expr1 ) : NULL;

    if( !expr1 || !expr2 ) {
	return 0;
    } else {
	TNODE *type1 = enode_type( expr1 );
	TNODE *type2 = enode_type( expr2 );

	if( !tnode_types_are_assignment_compatible
            ( type1, type2, NULL /* generic type table */, ex )) {
	    return 0;
	} else {
	    return 1;
	}
    }    
}

static int compiler_test_top_types_are_readonly_compatible_for_copy(
    COMPILER *cc,
    cexception_t *ex )
{
    ENODE * expr1 = NULL, * expr2 = NULL;

    assert( cc );

    expr1 = cc->e_stack;
    expr2 = expr1 ? enode_next( expr1 ) : NULL;

    if( !expr1 || !expr2 ) {
	return 0;
    } else {
        TNODE *tnode2 = enode_type( expr2 );
	if( enode_has_flags( expr2, EF_IS_READONLY ) ||
            ( tnode2 && tnode_is_immutable( tnode2 ))) {
	    return 0;
	} else {
            return 1;
	}
    }
}

static int compiler_check_top_2_expressions_are_identical( COMPILER *cc,
							   char *binop_name,
							   cexception_t *ex )
{
    ENODE * volatile expr1 = NULL, * volatile expr2 = NULL;

    assert( cc );

    expr1 = cc->e_stack;
    expr2 = expr1 ? enode_next( expr1 ) : NULL;

    if( !expr1 || !expr2 ) {
	yyerrorf( "not enough values on the stack "
		  "for binary operator '%s'", binop_name );
	return 0;
    } else {
	TNODE *type1 = enode_type( expr1 );
	TNODE *type2 = enode_type( expr2 );

	if( strcmp( binop_name, "%%" ) != 0 && 
#if 0
            strcmp( binop_name, "!=" ) != 0 &&
            strcmp( binop_name, "==" ) != 0 &&
#endif
	    !tnode_types_are_identical( type1, type2, NULL, ex )) {
	    yyerrorf( "incompatible types for binary operator '%s'",
		      binop_name );
	    return 0;
	}
	return 1;
    }
}

static void compiler_check_top_2_expressions_and_drop( COMPILER *cc,
						       char *binop_name,
						       cexception_t *ex )
{
    compiler_check_top_2_expressions_are_identical( cc, binop_name, ex );
    compiler_drop_top_expression( cc );
}

/*
  NB: on function naming:

  functions that are called ..._emit_...() just emit bytecode
  operators and do not modify type stack; on the contrary
  ..._compile_...() functions both generate code and adjust type
  stack.

  Consequence: "compile" functions can (and do) call "emit" functions,
  but not the other way round.

  Saulius Grazulis 2006.08.14 (Orenburg)

*/

static void compiler_compile_binop( COMPILER *cc,
				 char *binop_name,
				 cexception_t *ex )
{
    cexception_t inner;
    ENODE * expr1 = NULL, * expr2 = NULL;
    ENODE * volatile top1 = NULL, * volatile top2 = NULL;
    int stack_is_ok;
    TYPETAB *volatile generic_types = NULL;

    expr1 = cc->e_stack;
    expr2 = expr1 ? enode_next( expr1 ) : NULL;

    stack_is_ok =
	compiler_check_top_2_expressions_are_identical( cc, binop_name, ex );

    generic_types = new_typetab( ex );
    cexception_guard( inner ) {
	if( expr1 && expr2 ) {
	    TNODE *type1 = enode_type( expr1 );
	    operator_description_t od;

	    compiler_init_operator_description( &od, cc, type1,
                                             binop_name, 2, ex );
	    if( !od.operator ) {
		TNODE *type2 = enode_type( expr2 );
		compiler_init_operator_description( &od, cc, type2,
                                                 binop_name, 2, ex );
	    }

	    if( stack_is_ok ) {
		compiler_check_operator_args( cc, &od, generic_types, &inner );
	    }

	    top1 = enode_list_pop( &cc->e_stack );
	    top2 = enode_list_pop( &cc->e_stack );

	    compiler_emit_operator_or_report_missing( cc, &od, NULL, "\n",
                                                   &inner );
	    compiler_check_operator_retvals( cc, &od, 1, 1 );
	    compiler_push_operator_retvals( cc, &od, &top2, generic_types,
                                         &inner );
	}
    }
    cexception_catch {
	delete_enode( top1 );
	delete_enode( top2 );
        delete_typetab( generic_types );
	cexception_reraise( inner, ex );
    }
    delete_enode( top1 );
    delete_enode( top2 );
    delete_typetab( generic_types );
}

static key_value_t *make_array_element_key_value_list( TNODE *array )
{
    TNODE *element_type = array ? tnode_element_type( array ) : NULL;

    if( !element_type ) return NULL;

    return make_tnode_key_value_list( element_type );
}

static void compiler_compile_unop( COMPILER *cc,
				char *unop_name,
				cexception_t *ex )
{
    cexception_t inner;
    ENODE * volatile expr = cc->e_stack;
    ENODE * volatile top = NULL;
    TYPETAB *volatile generic_types = NULL;

    generic_types = new_typetab( ex );
    cexception_guard( inner ) {
	if( !expr ) {
	    yyerrorf( "not enough values on the stack for unary operator '%s'",
		      unop_name );
	} else {
	    TNODE *expr_type = enode_type( expr );
	    operator_description_t od;
	    key_value_t *fixup_values =
		make_array_element_key_value_list( expr_type );

	    compiler_init_operator_description( &od, cc, expr_type,
                                             unop_name, 1, ex );
	    compiler_check_operator_args( cc, &od, generic_types, &inner );

	    top = enode_list_pop( &cc->e_stack );

	    compiler_emit_operator_or_report_missing( cc, &od, fixup_values,
						   "\n", ex );
	    compiler_check_operator_retvals( cc, &od, 0, 1 );
	    compiler_push_operator_retvals( cc, &od, &top, generic_types, &inner );
	}
    }
    cexception_catch {
	delete_enode( top );
        delete_typetab( generic_types );
	cexception_reraise( inner, ex );	
    }
    delete_enode( top );
    delete_typetab( generic_types );
}

static void compiler_emit_st( COMPILER *cc,
			   TNODE *expr_type,
			   char *var_name,
			   ssize_t var_offset,
			   int var_scope,
			   cexception_t *ex )
{
    operator_description_t od;

    if( var_scope == compiler_current_scope( cc )) {

	compiler_init_operator_description( &od, cc, expr_type, "st", 1, ex );
	compiler_check_operator_args( cc, &od, NULL /*generic_types*/, ex );

	if( od.operator ) {
	    compiler_emit_function_call( cc, od.operator, NULL, "", ex );
	    compiler_emit( cc, ex, "eN\n", &var_offset, var_name );
	} else {
	    if( tnode_is_reference( expr_type )) {
		compiler_emit( cc, ex, "\tceN\n", PST, &var_offset, var_name );
	    } else {
		compiler_emit( cc, ex, "\tceN\n", ST, &var_offset, var_name );
	    }
	}
    } else {
	if( var_scope == 0 ) {
	    compiler_init_operator_description( &od, cc, expr_type, "stg", 1, ex );
	    compiler_check_operator_args( cc, &od, NULL /*generic_types*/, ex );

	    if( od.operator ) {
		compiler_emit_function_call( cc, od.operator, NULL, "", ex );
		compiler_emit( cc, ex, "eN\n", &var_offset, var_name );
	    } else {
		if( tnode_is_reference( expr_type )) {
		    compiler_emit( cc, ex, "\tceN\n", PSTG, &var_offset, var_name );
		} else {
		    compiler_emit( cc, ex, "\tceN\n", STG, &var_offset, var_name );
		}
	    }
	} else {
	    yyerrorf( "can only store variables in the current scope"
		      "or in the scope 0" );
	}
    }

    compiler_check_operator_retvals( cc, &od, 0, 0 );
}

static void compiler_compile_variable_assignment_or_init(
    COMPILER *cc,
    DNODE *variable,
    int (*enode_is_readonly_compatible)( ENODE *, DNODE * ),
    cexception_t *ex )
{
    ENODE *expr = cc->e_stack;

    if( !expr ) {
	yyerrorf( "not enough values on the stack for assignment to "
		  "variable '%s'", dnode_name( variable ));
    } else {
	TNODE *expr_type = enode_type( expr );

	char *var_name = variable ? dnode_name( variable ) : NULL;
	TNODE *var_type = variable ? dnode_type( variable ) : NULL;
	ssize_t var_offset = variable ? dnode_offset( variable ) : 0;
	int var_scope = variable ? dnode_scope( variable ) : -1;

        /* TYPETAB *generic_types = new_typetab( ex ); */
        TYPETAB *generic_types = NULL;
        if( !tnode_types_are_assignment_compatible( var_type, expr_type, 
                                                    generic_types, ex )) {
	    char *src_name = expr_type ? tnode_name( expr_type ) : NULL;
	    char *dst_name = var_type ? tnode_name( var_type ) : NULL;
	    if( src_name && dst_name &&
		tnode_lookup_conversion( var_type, src_name )) {
		compiler_compile_type_conversion( cc, dst_name, ex );
		expr = cc->e_stack;
		expr_type = enode_type( expr );
		compiler_emit_st( cc, expr_type, var_name, var_offset,
			       var_scope, ex );
	    } else {
		if( var_name ) {
		    yyerrorf( "incompatible types for assignment to variable "
			      "'%s'", var_name );
		} else {
		    yyerrorf( "incompatible types for assignment to variable" );
		}
	    }
	} else if( !(*enode_is_readonly_compatible)( expr, variable )) {
	    char *name = variable ? dnode_name( variable ) : NULL;
	    if( dnode_has_flags( variable, DF_IS_READONLY )) {
		if( name ) {
		    yyerrorf( "can not assign to the readonly variable '%s'",
			      name );
		} else {
		    yyerrorf( "can not assign to a readonly variable" );
		}
	    } else {
		if( name ) {
		    yyerrorf( "can not assign readonly content to variable '%s'",
			      name );
		} else {
		    yyerrorf( "can not assign readonly content to this "
			      "variable" );
		}
	    }
	} else {
	    compiler_emit_st( cc, expr_type, var_name, var_offset,
			   var_scope, ex );
	}
        delete_typetab( generic_types );
        compiler_drop_top_expression( cc );
    }
}

static void compiler_compile_variable_assignment( COMPILER *cc,
					       DNODE *variable,
					       cexception_t *ex )
{
    compiler_compile_variable_assignment_or_init(
        cc, variable, enode_is_readonly_compatible_with_var, ex );
}

static void compiler_compile_variable_initialisation( COMPILER *cc,
						   DNODE *variable,
						   cexception_t *ex )
{
    compiler_compile_variable_assignment_or_init(
        cc, variable, enode_is_readonly_compatible_for_init, ex );
}

static void compiler_compile_store_variable( COMPILER *cc,
					  DNODE *varnode,
					  cexception_t *ex )
{
    if( varnode ) {
        compiler_compile_variable_assignment( cc, varnode, ex );
    } else {
        compiler_emit( cc, ex, "\tcNN\n", ST, "???", "???" );
    }
}

static void compiler_compile_initialise_variable( COMPILER *cc,
					       DNODE *varnode,
					       cexception_t *ex )
{
    if( varnode ) {
        compiler_compile_variable_initialisation( cc, varnode, ex );
    } else {
        compiler_emit( cc, ex, "\tcNN\n", ST, "???", "???" );
    }
}

static void compiler_stack_top_dereference( COMPILER *cc )
{
    if( cc->e_stack ) {
	TNODE *expr_type = enode_type( cc->e_stack );
	if( tnode_kind( expr_type ) != TK_ADDRESSOF ) {
	    yyerror( "only address of some type can be dereferenced" );
	}
	enode_make_type_to_element_type( cc->e_stack );
    } else {
	yyerror( "not enough values on the evaluation stack for "
		 "dereferencing?" );
    }    
}

static int compiler_stack_top_is_addressof( COMPILER *cc )
{
    ENODE *enode = cc ? cc->e_stack : NULL;
    TNODE *etype = enode ? enode_type( enode ) : NULL;
#if 1
    return etype ? tnode_is_addressof( etype ) : 0;
#else
    return etype ? tnode_kind( etype ) == TK_ADDRESSOF : 0;
#endif
}

static void compiler_compile_ldi( COMPILER *cc, cexception_t *ex )
{
    ENODE * volatile expr;

    expr = cc->e_stack;

    if( !compiler_stack_top_is_addressof( cc )) return;

    if( !expr ) {
	yyerrorf( "not enough values on the stack for indirect load (LDI)" );
    } else {
	TNODE *expr_type = enode_type( expr );
	TNODE *element_type =
	    expr_type ? tnode_element_type( expr_type ) : NULL;
	operator_description_t od;

	compiler_init_operator_description( &od, cc, element_type, "ldi", 1, ex );

	if( !expr_type || tnode_kind( expr_type ) != TK_ADDRESSOF ) {
	    yyerrorf( "lvalue is needed for indirect load (LDI)" );
	} else {
	    compiler_check_operator_args( cc, &od, NULL /*generic_types*/, ex );
	}

	if( od.operator ) {
	    cexception_t inner;

	    expr = enode_list_pop( &cc->e_stack );
	    cexception_guard( inner ) {
		compiler_emit_function_call( cc, od.operator, NULL, "\n", &inner );
		compiler_check_operator_retvals( cc, &od, 1, 1 );
		compiler_push_operator_retvals( cc, &od, &expr,
                                             NULL /*generic_types*/, &inner );
	    }
	    cexception_catch {
		delete_enode( expr );
		cexception_reraise( inner, ex );
	    }
	    delete_enode( expr );
	} else {
	    TNODE *element_type =
		expr_type ? tnode_element_type( expr_type ) : NULL;
	    ssize_t element_size =
		element_type ? 
                ( tnode_is_reference( element_type ) ? 
                  REF_SIZE : tnode_size( element_type )) : 0;
	    char *name = element_type ? tnode_name( element_type ) : NULL;

	    if( element_size > sizeof(union stackunion)) {
		if( name ) {
		    yyerrorf( "value of type '%s' is too large to be loaded "
			      "onto the stack", name );
		} else {
		    yyerrorf( "value to be loaded by LDI is too large "
			      "to fit onto the stack" );
		}
	    }

	    if( element_type && !tnode_is_reference( element_type ) &&
		tnode_number_of_references( element_type ) > 0 ) {
		yyerrorf( "values with references should not be loaded "
			  "onto the stack" );
	    }

            if( element_type && tnode_kind( element_type ) == TK_PLACEHOLDER ) {
		compiler_emit( cc, ex, "\tcs\n", GLDI, &element_size );
	    } else if( element_type && tnode_is_reference( element_type )) {
		compiler_emit( cc, ex, "\tc\n", PLDI );
	    } else {
		compiler_emit( cc, ex, "\tcs\n", LDI, &element_size );
	    }
	    compiler_stack_top_dereference( cc );
	}
    }
}

static void compiler_compile_sti( COMPILER *cc, cexception_t *ex )
{
    cexception_t inner;
    ENODE *expr = NULL;
    ENODE *lval = NULL;
    ENODE * volatile top1 = NULL;
    ENODE * volatile top2 = NULL;

    expr = cc->e_stack;
    lval = expr ? enode_next( expr ) : NULL;

    cexception_guard( inner ) {
	if( !expr || !lval ) {
	    yyerrorf( "not enough values on the stack for assignment" );
	} else {
	    TNODE *expr_type = enode_type( expr );
	    TNODE *addr_type = enode_type( lval );
	    TNODE *element_type =
		addr_type ? tnode_element_type( addr_type ) : NULL;
	    operator_description_t od;

	    if( element_type && expr_type ) {
		/* if( !tnode_types_are_identical( element_type, expr_type )) {
		 */
		if( !tnode_types_are_assignment_compatible
                    ( element_type, expr_type, NULL /* generic_type_table*/, ex )) {
		    char *src_name = tnode_name( expr_type );
		    char *dst_name = tnode_name( element_type );
		    if( src_name && dst_name &&
			tnode_lookup_conversion( element_type, src_name )) {
			compiler_compile_type_conversion( cc, dst_name, ex );
			expr = cc->e_stack;
		    } else {
			yyerrorf( "incompatible types for assignment" );
		    }
		}
	    }

	    if( !enode_is_readonly_compatible_with_expr( expr, lval )) {
		if( enode_has_flags( lval, EF_IS_READONLY )) {
		    yyerrorf( "can not assign to a readonly component" );
		} else {
		    yyerrorf( "can not assign readonly content" );
		}
	    }

	    compiler_init_operator_description( &od, cc, expr_type, "sti", 2, ex );

	    if( ( !addr_type || tnode_kind( addr_type ) != TK_ADDRESSOF ) &&
                !enode_has_errors( lval )) {
		yyerrorf( "lvalue is needed for assignment" );
	    } else {
		compiler_check_operator_args( cc, &od, NULL /*generic_types*/,
                                           &inner );
	    }

	    top1 = enode_list_pop( &cc->e_stack );
	    top2 = enode_list_pop( &cc->e_stack );

	    if( od.operator ) {
		compiler_emit_function_call( cc, od.operator, NULL, "\n", &inner );
		compiler_check_operator_retvals( cc, &od, 0, 0 );
	    } else {
                ssize_t expr_size = expr_type ? tnode_size( expr_type ) : 0;
		if( expr_type && tnode_kind( expr_type ) == TK_PLACEHOLDER ) {
		    compiler_emit( cc, &inner, "\tcs\n", GSTI, &expr_size );
                } else if( expr_type && tnode_is_reference( expr_type )) {
		    compiler_emit( cc, &inner, "\tc\n", PSTI );
		} else {
		    compiler_emit( cc, &inner, "\tcs\n", STI, &expr_size );
		}
	    }
	}
    }
    cexception_catch {
	delete_enode( top1 );
	delete_enode( top2 );
	cexception_reraise( inner, ex );
    }
    delete_enode( top1 );
    delete_enode( top2 );
}

static void compiler_duplicate_top_expression( COMPILER *cc,
					       cexception_t *ex )
{
    ENODE *expr;

    expr = cc->e_stack;

    if( !expr ) {
	yyerrorf( "not enough values on the stack for duplication "
		  "of expression" );
    } else {
	TNODE *expr_type = enode_type( expr );
	compiler_push_type( cc, share_tnode( expr_type ), ex );
    }
}

static void compiler_compile_operator( COMPILER *cc,
				    TNODE *tnode,
				    char *operator_name,
				    int arity,
				    cexception_t *ex )
{
    operator_description_t od;

    compiler_init_operator_description( &od, cc, tnode, operator_name, arity, ex );
    compiler_emit_operator_or_report_missing( cc, &od, NULL, "", ex );
    compiler_check_operator_retvals( cc, &od, 0, 1 );
    compiler_push_operator_retvals( cc, &od, NULL, NULL /* generic_types */, ex );
}

static void compiler_check_and_compile_operator( COMPILER *cc,
					      TNODE *tnode,
					      char *operator_name,
					      int arity,
					      key_value_t *fixup_values,
					      cexception_t *ex )
{
    cexception_t inner;
    operator_description_t od;
    TYPETAB *volatile generic_types = NULL;

    generic_types = new_typetab( ex );
    cexception_guard( inner ) {
	compiler_init_operator_description( &od, cc, tnode, 
                                         operator_name, arity, ex );
	compiler_check_operator_args( cc, &od, generic_types, ex );
	compiler_drop_operator_args( cc, &od );
	compiler_emit_operator_or_report_missing( cc, &od, fixup_values, "", ex );
	compiler_check_operator_retvals( cc, &od, 0, 1 );
	compiler_push_operator_retvals( cc, &od, NULL, generic_types, ex );
    }
    cexception_catch {
	delete_typetab( generic_types );
	cexception_reraise( inner, ex );
    }
    delete_typetab( generic_types );
}

static void compiler_check_and_compile_top_operator( COMPILER *cc,
						  char *operator,
						  int arity,
						  cexception_t *ex )
{
    ENODE *expr = cc->e_stack;
    TNODE *tnode = NULL;

    if( !expr ) {
	yyerrorf( "not enough values on the stack for '%s' operator",
		  operator );
    } else 
    if( (tnode = enode_type(expr)) == NULL ){
	yyerrorf( "stack top expression has no type in '%s' operator",
		  operator );
    } else {
	TNODE *left_type = NULL;	
	ENODE *left_expr = expr ? enode_next( expr ) : NULL;
	if( arity > 1 ) {
	    if( left_expr ) {
		left_type = enode_type( left_expr );
	    } else {
		yyerrorf( "no left operand for binary operator '%s'?",
			  operator );
	    }
	}
	compiler_check_and_compile_operator( cc, tnode, operator, arity, 
					  /*fixup_values:*/ NULL, ex );
    }
}

static void compiler_check_and_compile_top_2_operator( COMPILER *cc,
						    char * operator,
						    int arity,
						    cexception_t *ex )
{
    ENODE *expr = cc->e_stack;
    ENODE *expr2 = cc->e_stack ? enode_next( cc->e_stack ) : NULL;
    TNODE *tnode = NULL;
    TNODE *tnode2 = NULL;

    if( !expr || ! expr2 ) {
	yyerrorf( "not enough values on the stack for '%s' operator "
		  "(need 2 values)", operator );
    } else 
    if( (tnode = enode_type(expr)) == NULL ||
	(tnode2 = enode_type(expr2)) == NULL){
	yyerrorf( "one two stack top expressions has no type "
		  "in '%s' operator", operator );
    } else {
	if( tnode_is_addressof( tnode2 )) {
	    tnode2 = tnode_element_type( tnode2 );
	}
	if( compiler_lookup_operator( cc, tnode2, operator, arity, ex )) {
	    TNODE *element_type = tnode_element_type( tnode2 );
	    key_value_t *fixup_values = element_type ?
		make_tnode_key_value_list( element_type ) : NULL;

	    compiler_check_and_compile_operator( cc, tnode2, operator, arity,
					      fixup_values, ex );
	} else {
	    compiler_check_and_compile_operator( cc, tnode, operator, arity, 
					      /*fixup_values:*/ NULL, ex );
	}
    }
}

static void compiler_compile_dup( COMPILER *cc, cexception_t *ex )
{
    ENODE *expr;

    expr = cc->e_stack;

    if( !expr ) {
	yyerrorf( "not enough values on the stack for duplication (DUP)" );
    } else {
	TNODE *expr_type = enode_type( expr );
	operator_description_t od;

	compiler_init_operator_description( &od, cc, expr_type, "dup", 1, ex );

	if( od.operator ) {
	    ENODE *new_expr = expr;
	    compiler_emit_function_call( cc, od.operator, NULL, "\n", ex );
	    compiler_check_operator_args( cc, &od, NULL /*generic_types*/, ex );
	    compiler_check_operator_retvals( cc, &od, 1, 1 );
	    compiler_push_operator_retvals( cc, &od, &new_expr,
                                         NULL /* generic_types */, ex );
	    if( !new_expr ) {
		share_enode( expr );
	    }
	} else {
	    compiler_emit( cc, ex, "\tc\n", DUP );
	    compiler_push_type( cc, expr_type, ex );
	    share_tnode( expr_type );
	}
    }
}

static int compiler_dnode_is_reference( COMPILER *cc, DNODE *dnode )
{
    return dnode ? dnode_type_is_reference( dnode ) : 0;
}

static int compiler_stack_top_is_integer( COMPILER *cc )
{
    ENODE *enode = cc ? cc->e_stack : NULL;
    TNODE *etype = enode ? enode_type( enode ) : NULL;
    return etype ? tnode_is_integer( etype ) : 0;
}

static int compiler_stack_top_is_reference( COMPILER *cc )
{
    ENODE *enode = cc ? cc->e_stack : NULL;
    TNODE *etype = enode ? enode_type( enode ) : NULL;
    return etype ? tnode_is_reference( etype ) : 0;
}

static int compiler_stack_top_base_is_reference( COMPILER *cc )
{
    ENODE *enode = cc ? cc->e_stack : NULL;
    TNODE *etype = enode ? enode_type( enode ) : NULL;
    TNODE *ebase = etype ? tnode_element_type( etype ) : NULL;
    return ebase ? tnode_is_reference( ebase ) : 0;
}
 
static int compiler_stack_top_is_array( COMPILER *cc )
{
    ENODE *enode = cc ? cc->e_stack : NULL;
    TNODE *etype = enode ? enode_type( enode ) : NULL;
    return etype ? tnode_kind( etype ) == TK_ARRAY : 0;
}

static int compiler_stack_top_has_references( COMPILER *cc,
					   ssize_t drop_retvals )
{
    ssize_t i;
    ENODE *expr = cc->e_stack;

    for( i = 0; i < drop_retvals && expr; i++ ) {
	TNODE *expr_type = enode_type( expr );

	if( expr_type && tnode_is_reference( expr_type )) {
	    return 1;
	}
	expr = enode_next( expr );
    }

    return 0;
}

static void compiler_compile_drop( COMPILER *cc, cexception_t *ex )
{
    if( compiler_stack_top_is_reference( cc )) {
	compiler_emit( cc, ex, "\tc\n", PDROP );
    } else {
	compiler_emit( cc, ex, "\tc\n", DROP );
    }
    compiler_drop_top_expression( cc );
}

static void compiler_compile_dropn( COMPILER *cc,
				 ssize_t drop_values,
				 cexception_t *ex )
{
    ssize_t i;

    if( compiler_stack_top_has_references( cc, drop_values )) {
	compiler_emit( cc, ex, "\tce\n", PDROPN, &drop_values );
    } else {
	compiler_emit( cc, ex, "\tce\n", DROPN, &drop_values );
    }
    for( i = 0; i < drop_values; i ++ ) {
	compiler_drop_top_expression( cc );
    }
}

static void compiler_compile_swap( COMPILER *cc, cexception_t *ex )
{
    ENODE *expr1 = enode_list_pop( &cc->e_stack );
    ENODE *expr2 = enode_list_pop( &cc->e_stack );

    if( !expr1 || !expr2 ) {
	yyerrorf( "not enough values on the stack for SWAP" );
    }
    
    enode_list_push( &cc->e_stack, expr1 );
    enode_list_push( &cc->e_stack, expr2 );

    compiler_emit( cc, ex, "\tc\n", SWAP );
}

static void compiler_compile_over( COMPILER *cc, cexception_t *ex )
{
    ENODE *expr1 = cc->e_stack;
    ENODE *expr2 = expr1 ? enode_next( expr1 ) : NULL;
    TNODE *expr2_type = expr2 ? enode_type( expr2 ) : NULL;
    TYPETAB *generic_types = NULL;
    cexception_t inner;

    if( !expr1 || !expr2 ) {
	yyerrorf( "not enough values on the stack for OVER" );
    }

    generic_types = new_typetab( ex );

    cexception_guard( inner ) {
	if( compiler_lookup_operator( cc, expr2_type, "over", 2, ex )) {
	    operator_description_t od;

	    compiler_init_operator_description( &od, cc, expr2_type,
                                             "over", 2, ex );
	    compiler_check_operator_args( cc, &od, generic_types, ex );
	    compiler_emit_operator_or_report_missing( cc, &od, NULL, "", ex );
	    compiler_check_operator_retvals( cc, &od, 1, 1 );
	    compiler_push_operator_retvals( cc, &od, NULL, generic_types,
					 ex );
	    compiler_emit( cc, ex, "\n" );
	} else {
	    if( expr2_type ) {
		compiler_push_type( cc, expr2_type, ex );
		share_tnode( expr2_type );
	    } else {
		yyerrorf( "when generating OVER, second expression from the "
			  "stack top has no type (?!)" );
	    }
	    compiler_emit( cc, ex, "\tc\n", OVER );
	}
    }
    cexception_catch {
	delete_typetab( generic_types );
	cexception_reraise( inner, ex );
    }
    delete_typetab( generic_types );
}

static int compiler_stack_top_has_operator( COMPILER *c,
					 char *operator_name,
					 int arity,
                                         cexception_t *ex )
{
    ENODE *expr_enode = c ? c->e_stack : NULL;
    TNODE *expr_tnode = expr_enode ? enode_type( expr_enode ) : NULL;

    if( !expr_tnode ) {
	return 0;
    }
    
    if( !compiler_lookup_operator( c, expr_tnode, operator_name, arity, ex )) {
	return 0;
    }

    return 1;
}

static int compiler_nth_stack_value_has_operator( COMPILER *c,
					       int number_from_top,
					       char *operator_name,
					       int arity,
                                               cexception_t *ex )
{
    ENODE *expr_enode = c ? c->e_stack : NULL;
    TNODE *expr_tnode; 

    while( number_from_top > 0 && expr_enode ) {
	expr_enode = enode_next( expr_enode );
	number_from_top --;
    }

    expr_tnode = expr_enode ? enode_type( expr_enode ) : NULL;

    if( !expr_tnode ) {
	return 0;
    }

    if( tnode_is_addressof( expr_tnode )) {
	expr_tnode = tnode_element_type( expr_tnode );
    }

    if( !compiler_lookup_operator( c, expr_tnode, operator_name, arity, ex )) {
	return 0;
    }

    return 1;
}

static int compiler_variable_has_operator( COMPILER *c,
                                        DNODE *var_dnode,
					char *operator_name,
					int arity,
                                        cexception_t *ex )
{
    TNODE *var_tnode = NULL;
    DNODE *operator = NULL;

    if( ! var_dnode ) {
	return 0;
    }

    if( !( var_tnode = dnode_type( var_dnode ))) {
	return 0;
    }
    
    if( !( operator = compiler_lookup_operator( c, var_tnode, operator_name,
                                                arity, ex ))) {
	return 0;
    }

    return 1;
}

static void compiler_compile_jnz_or_jz( COMPILER *c,
				     ssize_t offset,
				     char *operator_name,
				     void *pointer_opcode,
				     void *number_opcode,
				     cexception_t *ex )
{
    ENODE * volatile top_enode = c->e_stack;
    TNODE * volatile top_tnode = top_enode ? enode_type( top_enode ) : NULL;

    if( compiler_lookup_operator( c, top_tnode, operator_name, 1, ex )) {
	compiler_check_and_compile_operator( c, top_tnode, operator_name,
					  /*arity:*/ 1,
					  /*fixup_values:*/ NULL, ex );
	compiler_emit( c, ex, "e\n", &offset );
    } else {
	if( tnode_is_reference( top_tnode )) {
	    compiler_emit( c, ex, "\tce\n", pointer_opcode, &offset );
	} else {
	    ssize_t zero = 0;
	    tnode_report_missing_operator( top_tnode, operator_name, 1 );
	    /* emit JMP instead of missing JNZ/JZ to avoid triggering
	       assertions later during backpatching: */
	    compiler_emit( c, ex, "\tce\n", JMP, &zero );
	}
	compiler_drop_top_expression( c );
    }
}

static void compiler_compile_jnz( COMPILER *c,
			       ssize_t offset,
			       cexception_t *ex )
{
    compiler_compile_jnz_or_jz( c, offset, "jnz", PJNZ, JNZ, ex );
}

static void compiler_compile_jz( COMPILER *c,
			      ssize_t offset,
			      cexception_t *ex )
{
    compiler_compile_jnz_or_jz( c, offset, "jz", PJZ, JZ, ex );
}

static void compiler_compile_loop( COMPILER *c,
				ssize_t offset,
				cexception_t *ex )
{
    ENODE * volatile limit_enode = c->e_stack;
    TNODE * volatile limit_tnode = limit_enode ?
	enode_type( limit_enode ) : NULL;

    ENODE * volatile counter_enode = limit_enode ?
	enode_next( limit_enode ) : NULL;
    TNODE * volatile counter_tnode = counter_enode ?
	enode_type( counter_enode ) : NULL;

    TNODE * volatile counter_base = counter_tnode ?
	tnode_element_type( counter_tnode ) : NULL;

    if( !counter_enode ) {
	yyerrorf( "too little values on the eval stack for LOOP operator" );
    }

    if( counter_base && limit_tnode &&
	!tnode_types_are_compatible( counter_base, limit_tnode, NULL, ex )) {
	yyerrorf( "incompatible types in counter and limit of 'for' "
		  "operator" );
    }

    if( limit_tnode ) {
	if( compiler_lookup_operator( c, limit_tnode, "loop", 2, ex )) {
	    compiler_check_and_compile_operator( c, limit_tnode, "loop",
					      /*arity:*/ 2,
					      /*fixup_values:*/ NULL, ex );
	    compiler_emit( c, ex, "e\n", &offset );
	} else {
	    tnode_report_missing_operator( limit_tnode, "loop", 2 );
	}
    }
}

static void compiler_compile_next( COMPILER *c,
                                   cexception_t *ex )
{
    ssize_t offset = 0;
    ssize_t ncounters, i;

    ENODE * volatile limit_enode = c->e_stack;
    TNODE * volatile limit_tnode = limit_enode ?
	enode_type( limit_enode ) : NULL;

    TNODE * volatile limit_base = limit_tnode ?
	tnode_element_type( limit_tnode ) : NULL;

    ENODE * volatile counter_enode = limit_enode ?
	enode_next( limit_enode ) : NULL;
    TNODE * volatile counter_tnode = counter_enode ?
	enode_type( counter_enode ) : NULL;

    TNODE * volatile counter_base = counter_tnode ?
	tnode_element_type( counter_tnode ) : NULL;

    if( !counter_enode ) {
	yyerrorf( "too little values on the eval stack for NEXT operator" );
    }

    if( counter_base && limit_base &&
	!tnode_types_are_compatible( counter_base, limit_base, NULL, ex )) {
	yyerrorf( "incompatible types in counter and limit of 'foreach' "
		  "operator" );
    }

#if 0
    if( limit_tnode ) {
	if( compiler_lookup_operator( c, limit_tnode, "next", 2, ex )) {
	    compiler_check_and_compile_operator( c, limit_tnode, "next",
					      /*arity:*/ 2,
					      /*fixup_values:*/ NULL, ex );
	    compiler_emit( c, ex, "e\n", &offset );
	} else {
	    tnode_report_missing_operator( limit_tnode, "next", 2 );
	}
    }
#else
    compiler_emit( c, ex, "\tcI\n", LDC, 1 );
    compiler_emit( c, ex, "\tc\n", INDEX );    

    compiler_compile_over( c, ex );
    compiler_compile_over( c, ex );
    compiler_emit( c, ex, "\tc\n", PEQBOOL );
    offset = compiler_pop_offset( c, ex );
    compiler_drop_top_expression( c );
    compiler_drop_top_expression( c );
    {
        cexception_t inner;
        TNODE *volatile bool_tnode =
            share_tnode( typetab_lookup( c->typetab, "bool" ));
        cexception_guard( inner ) {
            compiler_push_type( c, bool_tnode, &inner );
        }
        cexception_catch {
            delete_tnode( bool_tnode );
            cexception_reraise( inner, ex );
        }
    }
    compiler_compile_jz( c, offset, ex );

    ncounters = dnode_loop_counters( c->loops );
    if( ncounters > 0 ) {
        compiler_emit( c, ex, "\tce\n", PDROPN, &ncounters );
    }
    for( i = 0; i < ncounters; i ++ ) {
        compiler_drop_top_expression( c );
    }
#endif
}

static void compiler_compile_alloc( COMPILER *cc,
				 TNODE *alloc_type,
				 cexception_t *ex )
{
    compiler_push_type( cc, alloc_type, ex );
    if( !tnode_is_reference( alloc_type )) {
	yyerrorf( "only reference-implemented types can be "
		  "used in new operator" );
    }
    if( tnode_kind( alloc_type ) == TK_ARRAY ) {
	yyerrorf( "arrays should be allocated with array-new operator "
		  "(e.g. 'a = new int[20]')" );
    }

    /* if( tnode_has_operator( cc, "new", 1, ex )) { */
    if ( compiler_lookup_operator( cc, alloc_type, "new",
                                   /* arity = */0, ex )) {
	/* compiler_drop_top_expression( cc ); */
        TNODE *element_type =
            alloc_type && tnode_kind( alloc_type ) == TK_COMPOSITE ?
            tnode_element_type( alloc_type ) : NULL;
        key_value_t *fixup_values =
            make_tnode_key_value_list( element_type ? element_type : alloc_type );
	compiler_check_and_compile_operator( cc, alloc_type, "new",
                                          /* arity = */0, 
                                          fixup_values, ex );
    } else {
	ssize_t alloc_size = tnode_size( alloc_type );
	ssize_t alloc_nref = tnode_number_of_references( alloc_type );
	ssize_t vmt_offset = tnode_vmt_offset( alloc_type );

	if( vmt_offset == 0 ) {
	    compiler_emit( cc, ex, "\tcee\n", ALLOC, &alloc_size, &alloc_nref );
	} else {
	    compiler_emit( cc, ex, "\tceee\n", ALLOCVMT, &alloc_size, &alloc_nref,
			&vmt_offset );
	}
    }
}

static char *compiler_make_typed_operator_name( TNODE *index_type1,
                                             TNODE *index_type2,
					     char *name_format,
					     cexception_t *ex )
{
    static char pad[20];
    static char *buff;
    ssize_t len;

    if( !index_type1 ) return NULL;

    if( index_type2 ) {
        len = snprintf( pad, sizeof(pad), name_format,
                        tnode_name( index_type1 ),
                        tnode_name( index_type2 ));
    } else {
        len = snprintf( pad, sizeof(pad), name_format,
                        tnode_name( index_type1 ));
    }

    if( len < sizeof( pad )) {
	return pad;
    } else {
	freex( buff );
	buff = NULL;
	buff = callocx( len+1, 1, ex );
        if( index_type2 ) {
            snprintf( buff, len+1, name_format,
                      tnode_name( index_type1 ),
                      tnode_name( index_type2 ));
        } else {
            snprintf( buff, len+1, name_format, tnode_name( index_type1 ));
        }
	return buff;
    }
}

static char* compiler_indexing_operator_name( TNODE *index_type,
					   cexception_t *ex )
{
    return compiler_make_typed_operator_name( index_type, NULL, "[%s]", ex );
}

static void compiler_compile_composite_alloc_operator( COMPILER *cc,
						    TNODE *composite_type,
						    key_value_t *fixup_values,
						    cexception_t *ex )
{
    ENODE *volatile top_expr = cc->e_stack;
    TNODE *volatile top_type = top_expr ? enode_type( top_expr ) : NULL;
    const int arity = 1;
    char *operator_name;

    operator_name =
        compiler_make_typed_operator_name( top_type, NULL, "new[%s]", ex );

    if( compiler_lookup_operator( cc, composite_type, operator_name,
                                  arity, ex )) {
	compiler_check_and_compile_operator( cc, composite_type, operator_name,
					  arity, fixup_values, ex );
	/* Return value pushed by ..._compile_operator() function must
	   be dropped, since it only describes return value as having
	   type 'composite'. The caller of the current function will push
	   a correct return value 'composite of proper_element_type' */
	compiler_drop_top_expression( cc );
    } else {
	compiler_check_and_remove_index_type( cc );
	tnode_report_missing_operator( composite_type, operator_name, arity );
    }
}

static void compiler_compile_composite_alloc( COMPILER *cc,
					   TNODE *composite_type,
					   TNODE *element_type,
					   cexception_t *ex )
{
    TNODE *allocated_type = NULL;
    key_value_t *fixup_values = make_tnode_key_value_list( element_type );

    allocated_type = new_tnode_composite_synonim( composite_type, element_type,
						  ex );

    compiler_compile_composite_alloc_operator( cc, allocated_type,
					    fixup_values, ex );

    compiler_push_type( cc, allocated_type, ex );
    /* compiler_push_composite_of_type( cc, composite_type, element_type, ex ); */
}

static void compiler_compile_array_alloc_operator( COMPILER *cc,
						char *operator_name,
						key_value_t *fixup_values,
						cexception_t *ex )
{
    ENODE *volatile top_expr = cc->e_stack;
    TNODE *volatile top_type = top_expr ? enode_type( top_expr ) : NULL;
    const int arity = 1;

    if( compiler_stack_top_has_operator( cc, operator_name, arity, ex )) {
	compiler_check_and_compile_operator( cc, top_type, operator_name,
					  arity, fixup_values, ex );
	/* Return value pushed by ..._compile_operator() function must
	   be dropped, since it only describes return value as having
	   type 'array'. The caller of the current function will push
	   a correct return value 'array of proper_element_type' */
	compiler_drop_top_expression( cc );
        compiler_emit( cc, ex, "\n" );
    } else {
	compiler_check_and_remove_index_type( cc );
	tnode_report_missing_operator( top_type, operator_name, arity );
    }
}

static void compiler_compile_array_alloc( COMPILER *cc,
				       TNODE *element_type,
				       cexception_t *ex )
{
    key_value_t *fixup_values = make_tnode_key_value_list( element_type );

    if( tnode_kind( element_type ) != TK_PLACEHOLDER ) {
        compiler_compile_array_alloc_operator( cc, "new[]", fixup_values, ex );
    } else {
        yyerrorf( "in this type representation, can not allocate array "
                  "of generic type %s", tnode_name( element_type ));
    }
    compiler_push_array_of_type( cc, element_type, ex );
}

static void compiler_compile_blob_alloc( COMPILER *cc,
				      cexception_t *ex )
{
    static key_value_t fixup_values[] = {
	{ "element_nref", 0 },
	{ "element_size", 1 },
	{ NULL },
    };

    compiler_compile_array_alloc_operator( cc, "blob[]", fixup_values, ex );
    compiler_push_type( cc, new_tnode_blob_snail( cc->typetab, ex ), ex );
}

static void compiler_compile_mdalloc( COMPILER *cc,
				   TNODE *element_type,
				   int level,
				   cexception_t *ex )
{
    TNODE *array_tnode = new_tnode_array_snail( NULL, cc->typetab, ex );

    if( element_type ) {
	key_value_t *fixup_values =
	    make_mdalloc_key_value_list( element_type, level );

	compiler_compile_array_alloc_operator( cc, "new[][]", fixup_values, ex );
	compiler_append_expression_type( cc, array_tnode );
	compiler_append_expression_type( cc, share_tnode( element_type ));
    } else {
	key_value_t fixup_vals[] = {
	    { "element_size", sizeof(void*) },
	    { "element_nref", 1 },
	    { "element_align", sizeof(void*) },
	    { "level", level },
	    { NULL }
	};

	if( level == 0 ) {
	    compiler_compile_array_alloc_operator( cc, "new[]", fixup_vals, ex );
	    compiler_push_type( cc, array_tnode, ex );
	} else {
	    compiler_compile_array_alloc_operator( cc, "new[][]", fixup_vals, ex );
	    compiler_append_expression_type( cc, array_tnode );
	}
    }
}

static void compiler_begin_scope( COMPILER *c,
			       cexception_t *ex )
{
    assert( c );
    assert( c->vartab );

    push_int( &c->local_offset_stack, &c->local_offset_stack_size,
	      c->local_offset, ex );
    c->local_offset = starting_local_offset;
    vartab_begin_scope( c->vartab, ex );
    vartab_begin_scope( c->consts, ex );
    vartab_begin_scope( c->operators, ex );

    typetab_begin_scope( c->typetab, ex );
}

static void compiler_end_scope( COMPILER *c, cexception_t *ex )
{
    assert( c );
    assert( c->vartab );

    c->local_offset = pop_int( &c->local_offset_stack,
			       &c->local_offset_stack_size, ex );
    vartab_end_scope( c->consts, ex );
    vartab_end_scope( c->vartab, ex );
    vartab_end_scope( c->operators, ex );

    typetab_end_scope( c->typetab, ex );
}

static void compiler_begin_subscope( COMPILER *c,
				  cexception_t *ex )
{
    assert( c );
    assert( c->vartab );

    vartab_begin_subscope( c->vartab, ex );
    vartab_begin_subscope( c->consts, ex );
    vartab_begin_subscope( c->operators, ex );
    typetab_begin_subscope( c->typetab, ex );
}

static void compiler_end_subscope( COMPILER *c, cexception_t *ex )
{
    assert( c );
    assert( c->vartab );

    vartab_end_subscope( c->consts, ex );
    vartab_end_subscope( c->vartab, ex );
    vartab_end_subscope( c->operators, ex );
    typetab_end_subscope( c->typetab, ex );
}

static void compiler_push_guarding_arg( COMPILER *cc, cexception_t *ex )
{
    ENODE *arg = new_enode_guarding_arg( ex );
    enode_list_push( &cc->e_stack, arg );
}

static void compiler_push_guarding_retval( COMPILER *cc, cexception_t *ex )
{
    ENODE *arg = new_enode_guarding_arg( ex );
    enode_set_flags( arg, EF_RETURN_VALUE );
    enode_list_push( &cc->e_stack, arg );
}

static DNODE* compiler_lookup_dnode_silently( COMPILER *cc,
					   char *module_name,
					   char *identifier )
{
    DNODE *module;

    if( !module_name ) {
	return vartab_lookup( cc->vartab, identifier );
    } else {
	module = vartab_lookup( cc->vartab, module_name );
	if( !module ) {
	    yyerrorf( "module '%s' is not available in the current scope",
		      module_name  );
	    return NULL;
	} else {
	    return dnode_vartab_lookup_var( module, identifier );
	}
    }
}

static DNODE* compiler_lookup_dnode( COMPILER *cc,
				  char *module_name,
				  char *identifier,
				  char *message )
{
    DNODE *varnode =
	compiler_lookup_dnode_silently( cc, module_name, identifier );

    if( !varnode ) {
	if( !message ) message = "name";
	if( module_name ) {
	    yyerrorf( "%s '%s::%s' is not declared in the "
		      "current scope", message, module_name,
		      identifier );
	} else {
	    yyerrorf( "%s '%s' is not declared in the "
		      "current scope", message, identifier );
	}
    }
    return varnode;
}

/*
  Function compiler_push_varaddr_expr() pushes a fake expression with
  variable reference onto the stack. It is fake because no code is
  generated to push this "address". Instead, code emitter will emit
  'ST %variable' when encountered such expression.

  In principle, assignement to variables could be implemented as 'LDA
  %variable; compute_value; STI', but the scheme with fake variable
  references produces more efficient code 'compute_value; ST
  %variable'.
*/

static void compiler_push_varaddr_expr( COMPILER *cc,
				     char *variable_name,
				     cexception_t *ex )
{
    DNODE *var_dnode = compiler_lookup_dnode( cc, NULL /* module_name */,
                                           variable_name, "variable" );
    ENODE *arg = var_dnode ?
        new_enode_varaddr_expr( var_dnode, ex ) : NULL;
    if( arg ) {
        share_dnode( var_dnode );
        enode_list_push( &cc->e_stack, arg );
    } else {
        compiler_push_error_type( cc, ex );
    }
}

static type_kind_t compiler_stack_top_type_kind( COMPILER *cc )
{
    ENODE *top_expr = cc->e_stack;
    TNODE *top_type = top_expr ? enode_type( cc->e_stack ) : NULL;

    if( top_type ) {
	return tnode_kind( top_type );
    } else {
	return TK_NONE;
    }
}

static void compiler_make_stack_top_element_type( COMPILER *cc )
{
    if( cc->e_stack ) {
	enode_make_type_to_element_type( cc->e_stack );
    } else {
	yyerror( "not enough values on the evaluation stack for "
		 "taking base type?" );
    }
}

static DNODE* compiler_make_stack_top_field_type( COMPILER *cc,
					       char *field_name )
{
    if( cc->e_stack ) {
	TNODE *struct_type = enode_type( cc->e_stack );
	DNODE *field = NULL;

	if( struct_type && tnode_kind( struct_type ) == TK_ADDRESSOF ) {
	    struct_type = tnode_element_type( struct_type );
	}

	field = struct_type ? 
	    tnode_lookup_field( struct_type, field_name ) : NULL;

	if( !field ) {
	    char *type_name = struct_type ? tnode_name( struct_type ) : NULL;
	    if( type_name ) {
		yyerrorf( "type '%s' has no field named '%s'",
			  type_name, field_name );
	    } else {
		yyerrorf( "this type has no field named '%s'", field_name );
	    }
	} else {
	    enode_replace_type( cc->e_stack,
                                share_tnode( dnode_type( field )));
            if( field && dnode_has_flags( field, DF_IS_READONLY )) {
                enode_set_flags( cc->e_stack, EF_IS_READONLY );
            }
	}
	return field;
    } else {
	yyerror( "not enough values on the evaluation stack for "
		 "taking base type?" );
	return NULL;
    }
}

static void compiler_make_stack_top_addressof( COMPILER *cc,
					    cexception_t *ex )
{
    if( cc->e_stack ) {
	enode_make_type_to_addressof( cc->e_stack, ex );
    } else {
	yyerror( "not enough values on the evaluation stack for "
		 "taking address?" );
    }    
}

static void compiler_check_and_drop_function_args( COMPILER *cc,
						DNODE *function,
                                                TYPETAB *generic_types,
                                                cexception_t *ex )
{
    DNODE *function_args = dnode_function_args( function );
    DNODE *formal_arg = NULL;
    TNODE *formal_type, *actual_type;
    ssize_t n = 0;
    ssize_t nargs = dnode_list_length( function_args );

    foreach_dnode( formal_arg, function_args ) {
        if( !cc->e_stack || enode_has_flags( cc->e_stack, EF_GUARDING_ARG )) {
            if( cc->e_stack /* && !dnode_has_initialiser( formal_arg ) */) {
                yyerrorf( "too little arguments in call to function '%s'",
                          dnode_name( function ));
            }
            break;
        } else {
            ENODE *actual_arg = enode_list_pop( &cc->e_stack );
            formal_type = dnode_type( formal_arg );
            actual_type = enode_type( actual_arg );
            /* if( !tnode_types_are_identical( formal_type, actual_type )) { */
            if( !tnode_types_are_assignment_compatible
                ( formal_type, actual_type, generic_types, ex )) {
                yyerrorf( "incompatible types for function '%s' argument "
                          "nr. %d"/* " (%s)" */, dnode_name( function ),
                          nargs - n, dnode_name( formal_arg ));
            }
            if( !enode_is_readonly_compatible_for_param( actual_arg,
                                                         formal_arg )) {
                char *name = dnode_name( formal_arg );
                yyerrorf( "can not pass readonly value for r/w parameter "
                          "'%s'", name );
            }
            delete_enode( actual_arg );
            n++;
        }
    }

    if( cc->e_stack && !enode_has_flags( cc->e_stack, EF_GUARDING_ARG )) {
	char *fn_name = dnode_name( function );
	if( fn_name ) {
	    yyerrorf( "too many arguments in call to function '%s'",
		      dnode_name( function ));
	} else {
	    yyerrorf( "too many arguments in call to an anonymous function" );
	}
	while( cc->e_stack &&
	       !enode_has_flags( cc->e_stack, EF_GUARDING_ARG )) {
	    enode_list_drop( &cc->e_stack );
	}
    }
    enode_list_drop( &cc->e_stack );
}

static DNODE *compiler_check_and_set_fn_proto( COMPILER *cc,
					    DNODE *fn_proto,
					    cexception_t *ex )
{
    DNODE *fn_dnode = NULL;
    TNODE *fn_tnode = NULL;
    int count = 0, is_imported = 0;
    char msg[100];

    fn_dnode = vartab_lookup_silently( cc->vartab, dnode_name( fn_proto ),
                                       &count, &is_imported );
    if( fn_dnode && !is_imported ) {
	fn_tnode = dnode_type( fn_dnode );
	if( !dnode_is_function_prototype( fn_dnode )) {
	    yyerrorf( "function '%s' is already declared in this scope",
		      dnode_name( fn_proto ));
	} else
	if( !tnode_function_prototypes_match_msg( fn_tnode,
					          dnode_type( fn_proto ),
					          msg, sizeof( msg ))) {
	    yyerrorf( "prototype of function %s() does not match "
		      "previous definition - %s", dnode_name( fn_proto ),
		      msg );
	}
	dnode_shallow_copy( fn_dnode, fn_proto, ex );
	delete_dnode( fn_proto );
	return fn_dnode;
    } else {
	compiler_vartab_insert_single_named_var( cc, fn_proto, ex );
	return fn_proto;
    }
}

static void compiler_emit_argument_list( COMPILER *cc,
                                      DNODE *argument_list,
				      cexception_t *ex )
{
    DNODE *varnode;

    foreach_dnode( varnode, argument_list ) {
	TNODE *argtype = dnode_type( varnode );

	dnode_assign_offset( varnode, &cc->local_offset );
	vartab_insert_named( cc->vartab, varnode, ex );
	share_dnode( varnode );

	compiler_emit_st( cc, argtype, dnode_name( varnode ),
		       dnode_offset( varnode ), dnode_scope( varnode ), ex );
    }
}

static void compiler_emit_function_arguments( DNODE *function, COMPILER *cc,
					   cexception_t *ex )
{
    assert( function );
    compiler_emit_argument_list( cc, dnode_function_args( function ), ex );
}

static void compiler_emit_drop_returned_values( COMPILER *cc,
					     ssize_t drop_retvals,
					     cexception_t *ex  )
{
    if( drop_retvals > 1 ) {
	compiler_compile_dropn( cc, drop_retvals, ex );
    } else if( drop_retvals == 1 ) {
	compiler_compile_drop( cc, ex );
    }    
}

static ssize_t compiler_assemble_static_data( COMPILER *cc,
					      void *data,
					      ssize_t data_size,
					      cexception_t *ex )
{
    ssize_t new_size, old_size;

    assert( cc );

    old_size = cc->static_data_size;
    new_size = old_size + data_size;
    cc->static_data = reallocx( cc->static_data, new_size, ex );
    if( data ) {
	memcpy( cc->static_data + old_size, data, data_size );
    } else {
	memset( cc->static_data + old_size, 0, data_size );
    }
    cc->static_data_size = new_size;

    return old_size;
}

#define ALIGN_NUMBER(N,lim)  ( (N) += ((lim) - ((ssize_t)(N)) % (lim)) % (lim) )

static void compiler_assemble_static_alloc_hdr( COMPILER *cc,
                                                ssize_t element_size,
						ssize_t len,
						cexception_t *ex )
{
    ssize_t old_size, new_size;
    alloccell_t *hdr;

    new_size = old_size = cc->static_data_size;
    ALIGN_NUMBER( new_size, sizeof(void*) );

    compiler_assemble_static_data( cc, /* data */ NULL,
				   new_size - old_size + sizeof(alloccell_t),
				   ex );

    hdr = (alloccell_t*)(cc->static_data + new_size);
    alloccell_set_values( hdr, element_size, len );
}

static ssize_t compiler_assemble_static_ssize_t( COMPILER *cc,
						 ssize_t size,
						 cexception_t *ex )
{
    return compiler_assemble_static_data( cc, &size, sizeof(size), ex );
}

static ssize_t compiler_assemble_static_string( COMPILER *cc,
						char *str,
						cexception_t *ex )
{
    compiler_assemble_static_alloc_hdr( cc, 1, strlen(str) + 1, ex );
    return compiler_assemble_static_data( cc, str, strlen(str) + 1, ex );
}

static TNODE *compiler_lookup_suffix_tnode( COMPILER *cc,
					 type_suffix_t suffix_type,
					 char *module_name,
					 char *suffix,
					 char *constant_kind_name )
{
    TNODE *const_type = NULL;
    DNODE *module  = NULL;

    if( module_name ) {
	module = vartab_lookup( cc->vartab, module_name );
	if( !module ) {
	    yyerrorf( "module '%s' is not available in the current scope",
		      module_name  );
	} else {
	    const_type =
		dnode_typetab_lookup_suffix( module, suffix ? suffix : "",
					     suffix_type );
	    if( !const_type ) {
		const_type =
		    dnode_typetab_lookup_type( module, suffix ? suffix : "" );
	    }
	}
    } else {
	const_type =
	    typetab_lookup_suffix( cc->typetab, suffix ? 
				   suffix : "", suffix_type );
	if( !const_type ) {
	    const_type = typetab_lookup( cc->typetab, suffix ? suffix : "" );
	    /* enumerator types should not be looked up: */
	}
    }

    if( !const_type ) {
	if( suffix ) {
	    yyerrorf( "type with suffix '%s' is not defined "
		      "in this scope for types of kind '%s'\n",
		      suffix, constant_kind_name );
	} else {
	    yyerrorf( "type with empty suffix is not defined "
		      "in this scope for types of kind '%s'\n",
		      constant_kind_name );
	}
    }

    return const_type;
}

static void compiler_compile_enum_const_from_tnode( COMPILER *cc,
						 char *value_name,
						 TNODE *const_type,
						 cexception_t *ex )
{
    DNODE *const_dnode = const_type ?
	tnode_lookup_field( const_type, value_name ) : NULL;
    ssize_t string_offset = const_dnode ?
	dnode_offset( const_dnode ) : 0;

    if( !const_type ) {
	compiler_push_error_type( cc, ex );
	return;
    }

    if( compiler_lookup_operator( cc, const_type, "ldc", 0, ex ) != NULL ) {
	compiler_compile_operator( cc, const_type, "ldc", 0, ex );
    } else {
	compiler_push_type( cc, const_type, ex );
	share_tnode( const_type );
	tnode_report_missing_operator( const_type, "ldc", 0 );
    }

    if( !const_dnode ) {
	yyerrorf( "enumeration type '%s' does not have value '%s'",
		  tnode_name( const_type ), value_name );
    } else {
	if( !dnode_has_flags( const_dnode, DF_HAS_OFFSET )) {
	    ssize_t value = dnode_ssize_value( const_dnode );
	    char value_str[100];

	    snprintf( value_str, sizeof(value_str), "%d", value );
	    string_offset =
		compiler_assemble_static_string( cc, value_str, ex );
	    dnode_set_offset( const_dnode, string_offset );
	}
    }

    compiler_emit( cc, ex, "e\n", &string_offset );
}

static TNODE* compiler_lookup_tnode_with_function( COMPILER *cc,
                                                char *module_name,
                                                char *identifier,
                                                TNODE* (*typetab_lookup_fn)
                                                    (TYPETAB*,const char*))
{
    if( !module_name ) {
	return (*typetab_lookup_fn)( cc->typetab, identifier );
    } else {
	DNODE *module = vartab_lookup( cc->vartab, module_name );
	if( !module ) {
	    yyerrorf( "module '%s' is not available in the current scope",
		      module_name  );
	    return NULL;
	} else {
	    return dnode_typetab_lookup_type( module, identifier );
	}
    }
}

static TNODE* compiler_lookup_tnode_silently( COMPILER *cc,
					   char *module_name,
					   char *identifier )
{
    return compiler_lookup_tnode_with_function( cc, module_name,
                                             identifier,
                                             typetab_lookup_silently );
}

static TNODE* compiler_lookup_tnode( COMPILER *cc,
				  char *module_name,
				  char *identifier,
				  char *message )
{
    TNODE *typenode = compiler_lookup_tnode_with_function( cc, module_name, 
                                                        identifier, 
                                                        typetab_lookup );

    if( !typenode ) {
	if( !message ) message = "name";
	if( module_name ) {
	    yyerrorf( "%s '%s::%s' is not declared in the "
		      "current scope", message, module_name,
		      identifier );
	} else {
	    yyerrorf( "%s '%s' is not declared in the "
		      "current scope", message, identifier );
	}
    }
    return typenode;
}

static void compiler_compile_enumeration_constant( COMPILER *cc,
						char *module_name,
						char *value_name,
						char *type_name,
						cexception_t *ex )
{
    TNODE *const_type =
	compiler_lookup_tnode( cc, module_name, type_name, "enumeration type" );

    return compiler_compile_enum_const_from_tnode( cc, value_name, const_type, ex );
}

static void compiler_compile_typed_constant( COMPILER *cc,
					  TNODE *const_type,
					  char *value,
					  cexception_t *ex )
{
    if( const_type ) {
	ssize_t string_offset;

	if( tnode_kind( const_type ) == TK_ENUM ) {
	    if( strstr( value, " " )) {
		cexception_t inner;
		char *enum_value_name = strdupx( value, ex );
		char *val_end = strstr( enum_value_name, " " );

		if( val_end ) *val_end = '\0';
		cexception_guard( inner ) {
		    compiler_compile_enum_const_from_tnode( cc, enum_value_name,
							 const_type, &inner );
		}
		cexception_catch {
		    freex( enum_value_name );
		    cexception_reraise( inner, ex );
		}
		freex( enum_value_name );
		return;
	    } else {
		yyerrorf( "enumerator type '%s' should not be given an "
			  "integer value\n",
			  tnode_name(const_type) ? tnode_name(const_type) : "" );
	    }
	}

	if( compiler_lookup_operator( cc, const_type, "ldc", 0, ex ) != NULL ) {
	    compiler_compile_operator( cc, const_type, "ldc", 0, ex );
	} else {
	    compiler_push_type( cc, const_type, ex );
	    share_tnode( const_type );
	    tnode_report_missing_operator( const_type, "ldc", 0 );
	}
	string_offset = compiler_assemble_static_string( cc, value, ex );
	compiler_emit( cc, ex, "e\n", &string_offset );
    }
}

static void compiler_compile_constant( COMPILER *cc,
				    type_suffix_t suffix_type,
				    char *module_name,
				    char *suffix, char *constant_kind_name,
				    char *value,
				    cexception_t *ex )
{
    TNODE *const_type =
	compiler_lookup_suffix_tnode( cc, suffix_type, module_name,
				   suffix, constant_kind_name );

    compiler_compile_typed_constant( cc, const_type, value, ex );
}

static DNODE* compiler_lookup_constant( COMPILER *cc,
				     char *module_name,
				     char *identifier,
				     char *message )
{
    DNODE *module;
    DNODE *constnode;

    if( !module_name ) {
	constnode = vartab_lookup( cc->consts, identifier );
    } else {
	module = vartab_lookup( cc->vartab, module_name );
	if( !module ) {
	    yyerrorf( "module '%s' is not available in the current scope",
		      module_name  );
	    constnode = NULL;
	} else {
	    constnode = dnode_consttab_lookup_const( module, identifier );
	}
    }
    if( !constnode ) {
	if( !message ) message = "name";
	if( module_name ) {
	    yyerrorf( "%s '%s::%s' is not declared in the "
		      "current scope", message, module_name,
		      identifier );
	} else {
	    yyerrorf( "%s '%s' is not declared in the "
		      "current scope", message, identifier );
	}
    }
    return constnode;
}

static void compiler_compile_ld( COMPILER *cc,
			      DNODE *varnode,
			      char *operator_name,
			      void *fallback_opcode,
			      TNODE* (*tnode_creator)
			          ( TNODE *base, cexception_t *xx ),
			      cexception_t *ex )
{
    cexception_t inner;
    DNODE *operator = NULL;
    const int arity = 0;
    ssize_t varnode_offset = 0;

    if( varnode ) {
	TNODE *var_type = dnode_type( varnode );
	TNODE * volatile expr_type = NULL;
	operator =
            compiler_lookup_operator( cc, var_type, operator_name, arity, ex );

	cexception_guard( inner ) {
	    if( tnode_creator ) {
		expr_type = tnode_creator( var_type, &inner );
	    } else {
		expr_type = var_type;
	    }
	    share_tnode( var_type );
	    compiler_push_type( cc, expr_type, &inner );
	    if( dnode_has_flags( varnode, DF_IS_READONLY )) {
		enode_set_flags( cc->e_stack, EF_IS_READONLY );
	    }
	}
	cexception_catch {
	    delete_tnode( expr_type );
	    cexception_reraise( inner, ex );
	}

	if( operator ) {
	    compiler_emit_function_call( cc, operator, NULL, "", ex );
	} else {
	    if( fallback_opcode == LDA ) {
		if( dnode_scope( varnode ) == compiler_current_scope( cc )) {
		    if( tnode_is_reference( var_type )) {
			compiler_emit( cc, ex, "\tc", PLDA );
		    } else {
			compiler_emit( cc, ex, "\tc", LDA );
		    }
		} else {
		    if( dnode_scope( varnode ) == 0 ) {
			operator = compiler_lookup_operator( cc, var_type,
                                                             "ldga",
                                                             arity, ex );
			if( operator ) {
			    compiler_emit_function_call( cc, operator, NULL,
						      "", ex );
			} else {
			    if( tnode_is_reference( var_type )) {
				compiler_emit( cc, ex, "\tc", PLDGA );
			    } else {
				compiler_emit( cc, ex, "\tc", LDGA );
			    }
			}
		    } else {
			yyerrorf( "can only fetch variables either from the "
				  "current scope of from the scope 0" );
		    }
		}
	    } else if( fallback_opcode == LD ) {
		if( dnode_scope( varnode ) == compiler_current_scope( cc )) {
		    if( tnode_is_reference( var_type )) {
			compiler_emit( cc, ex, "\tc", PLD );
		    } else {
			compiler_emit( cc, ex, "\tc", LD );
		    }
		} else {
		    if( dnode_scope( varnode ) == 0 ) {
			operator = compiler_lookup_operator( cc, var_type,
                                                             "ldg",
                                                             arity, ex );
			if( operator ) {
			    compiler_emit_function_call( cc, operator, NULL,
						      "", ex );
			} else {
			    if( tnode_is_reference( var_type )) {
				compiler_emit( cc, ex, "\tc", PLDG );
			    } else {
				compiler_emit( cc, ex, "\tc", LDG );
			    }
			}
		    } else {
			yyerrorf( "can only fetch variable addressess either "
				  "from the current scope of from "
				  "the scope 0" );
		    }
		}
	    } else {
		compiler_emit( cc, ex, "\tc", fallback_opcode );
	    }
	}
	varnode_offset = dnode_offset( varnode );
	compiler_emit( cc, ex, "eN\n", &varnode_offset, dnode_name( varnode ));
    } else {
	/* yyerrorf( "name '%s' not declared in the current scope",
	   identifier ); */
	compiler_emit( cc, ex, "\tcNN\n", operator, "???", "???" );
	compiler_push_error_type( cc, ex );
    }
}

static void compiler_compile_load_variable_value( COMPILER *cc,
					       DNODE *varnode,
					       cexception_t *ex )
{
    compiler_compile_ld( cc, varnode, "ld", LD, NULL, ex );
}

static void compiler_compile_load_function_address( COMPILER *cc,
						 DNODE *varnode,
						 cexception_t *ex )
{
    compiler_compile_ld( cc, varnode, "ldfn", LDFN, NULL, ex );
}

static void compiler_compile_load_variable_address( COMPILER *cc,
						 DNODE *varnode,
						 cexception_t *ex )
{
    compiler_compile_ld( cc, varnode, "lda", LDA, new_tnode_addressof, ex );
}

static void compiler_fixup_function_calls( THRCODE *tc, DNODE *funct )
{
    char *name;
    int address;

    assert( funct );
    name = dnode_name( funct );
    address = dnode_offset( funct );

    thrcode_fixup_function_calls( tc, name, address );
}

static void compiler_compile_function_thrcode( COMPILER *cc )
{
    assert( cc );
    assert( cc->thrcode != cc->function_thrcode );
    cc->thrcode = cc->function_thrcode;
}

static void compiler_compile_main_thrcode( COMPILER *cc )
{
    assert( cc );
    assert( cc->thrcode != cc->main_thrcode );
    cc->thrcode = cc->main_thrcode;
}

static void compiler_merge_functions_and_main( COMPILER *cc,
					    cexception_t *ex  )
{
    assert( cc );
    thrcode_merge( cc->function_thrcode, cc->main_thrcode, ex );
    delete_thrcode( cc->main_thrcode );
    cc->main_thrcode = cc->function_thrcode;
    cc->function_thrcode = NULL;
    cc->thrcode = cc->main_thrcode;
}

static void compiler_push_thrcode( COMPILER *sc,
			 cexception_t *ex )
{
    thrlist_push_data( &sc->thrstack, &sc->thrcode, delete_thrcode, NULL, ex );
    create_thrcode( &sc->thrcode, ex );
    elist_push_data( &sc->saved_estacks, &sc->e_stack, delete_enode, NULL, ex );
    sc->e_stack = NULL;
}

static void compiler_swap_thrcodes( COMPILER *sc )
{
    THRCODE *code1 = thrlist_extract_data( sc->thrstack );
    ENODE *enode1 = elist_extract_data( sc->saved_estacks );

    thrlist_set_data( sc->thrstack, &sc->thrcode );
    assert( !sc->thrcode );
    sc->thrcode = code1;

    elist_set_data( sc->saved_estacks, &sc->e_stack );
    assert( !sc->e_stack );
    sc->e_stack = enode1;
}

static void compiler_merge_top_thrcodes( COMPILER *sc, cexception_t *ex )
{
    thrcode_merge( sc->thrcode, thrlist_data( sc->thrstack ), ex );
    thrlist_drop( &sc->thrstack );
    sc->e_stack = 
	enode_append( elist_pop_data( &sc->saved_estacks ), sc->e_stack );
}

static void compiler_merge_functions_and_top( COMPILER *cc,
                                           cexception_t *ex )
{
    assert( cc );
    assert( cc->function_thrcode != cc->thrcode );
    assert( cc->function_thrcode != cc->main_thrcode );

    thrcode_merge( cc->function_thrcode, cc->thrcode, ex );

    delete_thrcode( cc->thrcode );

    cc->thrcode = thrlist_pop_data( &cc->thrstack );

    /* Actually, after function compilation the e-stack of the
       finished function should be empty, so in fact the following
       code should instead be an assert()... S.G. */
    cc->e_stack = 
	enode_append( elist_pop_data( &cc->saved_estacks ), cc->e_stack );
}

static void compiler_get_inline_code( COMPILER *cc,
					    DNODE *function,
					    cexception_t *ex )
{
    ssize_t code_start = compiler_pop_address( cc, ex );
    ssize_t code_end = thrcode_length( cc->thrcode );
    ssize_t code_length = code_end - code_start;
    int is_inline = dnode_has_flags( function, DF_INLINE );

    if( code_length > 0 && is_inline ) {
	thrcode_t *opcodes = NULL;
	opcodes = thrcode_instructions( cc->thrcode );
	dnode_set_code( function, opcodes + code_start, code_length, ex );
	dnode_adjust_code_fixups( function, code_start );
    }
}

static int compiler_count_return_values( DNODE *funct )
{
    TNODE *function_type = funct ? dnode_type( funct ) : NULL;
    DNODE *retvals = function_type ? tnode_retvals( function_type ) : NULL;

    return dnode_list_length( retvals );
}

static void compiler_compile_address_of_indexed_element( COMPILER *cc,
						      cexception_t *ex )
{
    cexception_t inner;
    ENODE * volatile index_expr = NULL;
    ENODE * volatile array_expr = NULL;
    TNODE *index_type = NULL;
    TNODE *array_type = NULL;
    TNODE *element_type = NULL;
    char *idx_name = NULL;
    operator_description_t od;
    const int idx_arity = 2;
    TYPETAB *volatile generic_types = NULL;

    index_expr = cc->e_stack;

    index_type = index_expr ? enode_type( index_expr ) : NULL;
    array_expr = cc->e_stack ? enode_next( cc->e_stack ) : NULL;

    cexception_guard( inner ) {
        generic_types = new_typetab( &inner );
	idx_name = compiler_indexing_operator_name( index_type, &inner );

	if( array_expr ) {
	    array_type = enode_type( array_expr );
	    if( array_type && tnode_kind( array_type ) == TK_ADDRESSOF ) {
		array_type = tnode_element_type( array_type );
	    }
	    element_type = array_type ? tnode_element_type( array_type ) : NULL;
	}

	if( !array_type ) {
	    yyerrorf( "not enough values on the stack for indexing operator" );
	}

	if( compiler_lookup_operator( cc, array_type, idx_name,
                                      idx_arity, ex )) {
	    compiler_init_operator_description( &od, cc, array_type, idx_name,
					     idx_arity, ex );
	} else {
	    compiler_init_operator_description( &od, cc, index_type, "[]",
                                             idx_arity, ex );
	}

	if( od.operator ) {
	    compiler_check_operator_args( cc, &od, generic_types,
                                       &inner );
	}

	index_expr = enode_list_pop( &cc->e_stack );

	if( od.operator ) {
	    TNODE *return_type = NULL;
	    key_value_t *fixup_values = NULL;

	    array_expr = cc->e_stack;

	    fixup_values = make_tnode_key_value_list( element_type );

	    compiler_emit_operator_or_report_missing( cc, &od, fixup_values,
						   "", &inner );

	    compiler_check_operator_retvals( cc, &od, 1, 1 );
	    return_type = od.retvals ? dnode_type( od.retvals ) : NULL;

	    if( return_type ) {
		if( tnode_kind( return_type ) == TK_ADDRESSOF &&
		    tnode_element_type( return_type ) == NULL ) {
		    if( !element_type ) {
			yyerrorf( "can not index array with unknown element "
				  "type" );
		    }
		    if( compiler_stack_top_type_kind( cc ) ==  TK_ADDRESSOF ) {
			compiler_make_stack_top_element_type( cc );
		    }
		    compiler_make_stack_top_element_type( cc );
		    compiler_make_stack_top_addressof( cc, &inner );
		} else {
		    enode_list_drop( &cc->e_stack );
		    compiler_push_type( cc, return_type, &inner );
		    share_tnode( return_type );
		}
	    }
	    compiler_emit( cc, &inner, "\n" );
	} else {
	    compiler_make_stack_top_element_type( cc );
	    compiler_make_stack_top_addressof( cc, &inner );
	    tnode_report_missing_operator( index_type, "[]", idx_arity );
	}
    }
    cexception_catch {
	delete_enode( index_expr );
        delete_typetab( generic_types );
	cexception_reraise( inner, ex );
    }
    delete_enode( index_expr );
    delete_typetab( generic_types );
}

static void compiler_compile_subarray( COMPILER *cc,
                                    cexception_t *ex )
{
    cexception_t inner;
    ENODE * volatile index_expr1 = NULL;
    ENODE * volatile index_expr2 = NULL;
    ENODE * volatile array_expr = NULL;
    TNODE *index_type1 = NULL;
    TNODE *index_type2 = NULL;
    TNODE *array_type = NULL;
    TNODE *element_type = NULL;
    char *idx_name = NULL;
    operator_description_t od;
    const int idx_arity = 3;
    TYPETAB *volatile generic_types = NULL;

    index_expr1 = cc->e_stack;
    index_expr2 = index_expr1 ? enode_next( index_expr1 ) : NULL;
    array_expr = index_expr2 ? enode_next( index_expr2 ) : NULL;
    
    index_type1 = index_expr1 ? enode_type( index_expr1 ) : NULL;
    index_type2 = index_expr2 ? enode_type( index_expr2 ) : NULL;

    if( !index_expr1 || !index_expr2 ) {
        /* The compiler tried to emit two expressions (the ones in the
           [expr1..expr2] brackets), and told us that we should have
           them, but they are not on the emlated expression stack --
           something must have been very wrong during the compilation
           of the range... S.G. */
        cexception_raise
            ( ex, COMPILER_UNRECOVERABLE_ERROR,
              "subarray index range expressions were not generated properly" );
    }
    /* From now on, index_expr1 and index_expr2 are not NULL */

    cexception_guard( inner ) {
        generic_types = new_typetab( &inner );
        idx_name = compiler_make_typed_operator_name( index_type1, index_type2,
                                                   "[%s..%s]", ex );

	if( array_expr ) {
	    array_type = enode_type( array_expr );
	    if( array_type && tnode_kind( array_type ) == TK_ADDRESSOF ) {
		array_type = tnode_element_type( array_type );
	    }
	    element_type = array_type ? tnode_element_type( array_type ) : NULL;
	}

	if( !array_type ) {
	    yyerrorf( "not enough values on the stack "
                      "for a subarray/substring operator" );
	}

	if( compiler_lookup_operator( cc, array_type, idx_name,
                                      idx_arity, &inner )) {
	    compiler_init_operator_description( &od, cc, array_type, idx_name,
					     idx_arity, &inner );
	} else if( tnode_lookup_operator( index_type1, idx_name, idx_arity )) {
	    compiler_init_operator_description( &od, cc, index_type1, "[..]",
                                             idx_arity, &inner );
	} else {
            compiler_init_operator_description( &od, cc, index_type2, "[..]",
                                             idx_arity, &inner );
        }

	if( od.operator ) {
	    compiler_check_operator_args( cc, &od, generic_types,
                                       &inner );
	}

	index_expr1 = enode_list_pop( &cc->e_stack );
	index_expr2 = enode_list_pop( &cc->e_stack );

	if( od.operator ) {
	    TNODE *return_type = NULL;
	    key_value_t *fixup_values = NULL;

	    array_expr = cc->e_stack;

	    fixup_values = make_tnode_key_value_list( element_type );

	    compiler_emit_operator_or_report_missing( cc, &od, fixup_values,
						   "", &inner );

	    compiler_check_operator_retvals( cc, &od, 1, 1 );
	    return_type = od.retvals ? dnode_type( od.retvals ) : NULL;

	    if( return_type ) {
		assert( tnode_kind( return_type ) != TK_ADDRESSOF );
                if( tnode_kind( return_type ) == TK_ARRAY &&
                    tnode_element_type( return_type )) {
                    enode_list_drop( &cc->e_stack );
                    compiler_push_type( cc, return_type, &inner );
                    share_tnode( return_type );
                }
	    }
	    compiler_emit( cc, &inner, "\n" );
	} else {
	    tnode_report_missing_operator( index_type1, "[..]", idx_arity );
	}
    }
    cexception_catch {
	delete_enode( index_expr1 );
	delete_enode( index_expr2 );
        delete_typetab( generic_types );
	cexception_reraise( inner, ex );
    }
    delete_enode( index_expr1 );
    delete_enode( index_expr2 );
    delete_typetab( generic_types );
}

static void compiler_compile_indexing( COMPILER *cc,
				    int array_is_reference,
				    int expr_count,
				    cexception_t *ex )
{
    if( expr_count == 1 ) {
	compiler_compile_address_of_indexed_element( cc, ex );
    } else if( expr_count == 0 ) {
	assert( array_is_reference );
        compiler_emit( cc, ex, "\tc\n", CLONE );
    } else if( expr_count == -1 ) {
	assert( 0 );
    } else if( expr_count == 2 ) {
	// assert( array_is_reference );
        compiler_compile_subarray( cc, ex );
    } else {
	assert( 0 );
    }
}

static void compiler_compile_type_declaration( COMPILER *cc,
					    TNODE *type_descr,
					    cexception_t *ex )
{
    cexception_t inner;
    ANODE * volatile suffix = NULL;
    TNODE *tnode = NULL;
    char * volatile type_name = NULL;

    if( !type_descr ) {
	cc->current_type = NULL;
        return;
    }

    type_name = strdupx( tnode_name( cc->current_type ), ex );

    cexception_guard( inner ) {
	assert( type_descr );
	if( tnode_name( type_descr ) == NULL ) {
	    tnode = tnode_set_name( type_descr, type_name, &inner );
	} else if( type_descr != cc->current_type ) {
	    tnode = tnode_set_name( new_tnode_synonim( type_descr, &inner ),
				    type_name, &inner );
	    suffix = new_anode_string_attribute( "suffix", tnode_name( tnode ),
						 &inner );
	    tnode_set_attribute( tnode, suffix, &inner );
	} else {
	    tnode = type_descr;
	}
	compiler_typetab_insert( cc, tnode, &inner );
	tnode = typetab_lookup_silently( cc->typetab, type_name );
	tnode_reset_flags( tnode, TF_IS_FORWARD );
	compiler_insert_tnode_into_suffix_list( cc, tnode, &inner );
	cc->current_type = NULL;
	freex( type_name );
    }
    cexception_catch {
	freex( type_name );
	delete_anode( suffix );
	cexception_reraise( inner, ex );
    }
    delete_anode( suffix );
}

static ssize_t compiler_native_type_size( const char *name )
{
    if( strcmp( name, "int" ) == 0 ) {
	return sizeof( int );
    } else
    if( strcmp( name, "long" ) == 0 ) {
	return sizeof( long );
    } else
    if( strcmp( name, "short" ) == 0 ) {
	return sizeof( short );
    } else
    if( strcmp( name, "char" ) == 0 ) {
	return sizeof( char );
    } else
    if( strcmp( name, "float" ) == 0 ) {
	return sizeof( float );
    } else
    if( strcmp( name, "double" ) == 0 ) {
	return sizeof( double );
    } else
    if( strcmp( name, "ldouble" ) == 0 ) {
	return sizeof( ldouble );
    } else
    if( strcmp( name, "long double" ) == 0 ) {
	return sizeof( long double );
    } else
    if( strcmp( name, "llong" ) == 0 ) {
	return sizeof( llong );
    } else
    if( strcmp( name, "ullong" ) == 0 ) {
	return sizeof( ullong );
    } else
    if( strcmp( name, "long long" ) == 0 ) {
	return sizeof( long long );
    } else
    if( strcmp( name, "size_t" ) == 0 ) {
	return sizeof( size_t );
    } else
    if( strcmp( name, "ssize_t" ) == 0 ) {
	return sizeof( ssize_t );
    } else
    if( strcmp( name, "void*" ) == 0 ) {
	return sizeof( void* );
    } else
    if( strcmp( name, "char*" ) == 0 ) {
	return sizeof( char* );
    } else
    if( strcmp( name, "bytecode_file_hdr_t" ) == 0 ) {
	return sizeof( bytecode_file_hdr_t );
    } else {
	yyerrorf( "native type '%s' is not known to the compiler", name );
	return -1;
    } 
}

static ssize_t compiler_native_type_nreferences( const char *name )
{
    if( strcmp( name, "bytecode_file_hdr_t" ) == 0 ) {
	return INTERPRET_FILE_PTRS;
    } else {
#if 1
	return 0;
#else
	yyerrorf( "number of references in type '%s' "
		  "is not known to the compiler", name );
	return -1;
#endif
    } 
}

static int compiler_check_and_emit_program_arguments( COMPILER *cc,
						      DNODE *args,
						      cexception_t *ex )
{
    DNODE *arg;
    int n = 1;
    int retval = 1;

    args = dnode_list_invert( args );
    foreach_dnode( arg, args ) {
	TNODE *arg_type = dnode_type( arg );
	switch( n ) {
	case 1:
	case 3:
	    if( !tnode_is_array_of_string( arg_type )) {
		yyerrorf( "argument nr. %d of the program must be "
			  "'array of string'", n );
		retval = 0;
	    }
	    if( n == 1 ) {
		compiler_emit( cc, ex, "\tcT\n", ALLOCARGV, "(* argv *)" );
	    } else {
		compiler_emit( cc, ex, "\tcT\n", ALLOCENV, "(* env *)" );
	    }
	    break;
	case 2:
	    if( !tnode_is_array_of_file( arg_type )) {
		yyerrorf( "argument nr. %d of the program must be "
			  "'array of file'", n );
		retval = 0;
	    }
	    compiler_emit( cc, ex, "\tcT\n", ALLOCSTDIO, "(* stdio *)" );
	    break;
	}
	n++;
    }
    args = dnode_list_invert( args );
    if( --n > 3 ) {
	yyerrorf( "too many arguments for the program "
		  "(found %d, must be <= 3)", n );
	retval = 0;
    }
    return retval;
}

static void compiler_compile_program_args( COMPILER *cc,
					   char *program_name,
					   DNODE *argument_list,
					   cexception_t *ex )
{
    if( compiler_check_and_emit_program_arguments( cc, argument_list, ex )) {
	compiler_emit_argument_list( cc, argument_list, ex );
    }
}

static void compiler_emit_catch_comparison( COMPILER *cc,
					 char *module_name,
					 char *exception_name,
					 cexception_t *ex )
{
    DNODE *exception =
        compiler_lookup_dnode( cc, module_name, exception_name, "exception" );
    ssize_t zero = 0;
    ssize_t exception_val;
    ssize_t try_var_offset = cc->try_variable_stack ?
	cc->try_variable_stack[cc->try_block_level-1] : 0;

    if( module_name ) {
	compiler_emit( cc, ex, "\n\tce\n", PLD, &try_var_offset );
	compiler_emit( cc, ex, "\n\tc\n", EXCEPTIONMODULE );
	compiler_emit( cc, ex, "\tce\n", SLDC, &module_name );
	compiler_emit( cc, ex, "\tc\n", PEQBOOL );
	compiler_emit( cc, ex, "\tc\n", DUP );
	compiler_push_relative_fixup( cc, ex );
	compiler_emit( cc, ex, "\tce\n", BJNZ, &zero );
	compiler_emit( cc, ex, "\tc\n", DROP );
    }

    compiler_emit( cc, ex, "\n\tce\n", PLD, &try_var_offset );
    compiler_emit( cc, ex, "\n\tc\n", EXCEPTIONID );

    exception_val = exception ? dnode_ssize_value( exception ) : 0;
    compiler_emit( cc, ex, "\tce\n", LDC, &exception_val );
    compiler_emit( cc, ex, "\tc\n", EQBOOL );

    if( module_name ) {
	compiler_fixup_here( cc );
    }
}

static void compiler_finish_catch_comparisons( COMPILER *cc,
					    int nfixups,
					    cexception_t *ex )
{
    int i;
    ssize_t zero = 0;

    compiler_push_relative_fixup( cc, ex );
    compiler_emit( cc, ex, "\tce\n", BJZ, &zero );
    for( i = 0; i < nfixups; i ++ ) {
	/* fixup all JNZs emitted in the 'exception_identifier_list'
	   rule: */
	compiler_swap_fixups( cc );
	compiler_fixup_here( cc );
    }
}

static void compiler_finish_catch_block( COMPILER *cc, cexception_t *ex )
{
    ssize_t zero = 0;

    cc->catch_jumpover_nr ++;
    compiler_push_relative_fixup( cc, ex );
    compiler_emit( cc, ex, "\tce\n", JMP, &zero );
    compiler_swap_fixups( cc );
    compiler_fixup_here( cc );
}

static void compiler_check_enum_attributes( TNODE *tnode )
{
    TNODE *base = tnode ? tnode_base_type( tnode ) : NULL;
    char *name = tnode ? tnode_name( tnode ) : NULL;

    if( base ) {
	if( tnode_size( base ) != tnode_size( tnode )) {
	    if( name ) {
		yyerrorf( "specified size of the enum '%s' does not match size"
			  "of its parent type", name );
	    } else {
		yyerrorf( "specified size of the enum does not match size"
			  "of its parent type" );
	    }
	}
    }
}

static void compiler_convert_function_argument( COMPILER *cc,
					     cexception_t *ex )
{
    TNODE *arg_type = cc->current_arg ? dnode_type( cc->current_arg ) : NULL;
    TNODE *exp_type = cc->e_stack ? enode_type( cc->e_stack ) : NULL;

    if( arg_type && exp_type ) {
	if( tnode_kind( arg_type ) != TK_PLACEHOLDER &&
	    !tnode_types_are_assignment_compatible( arg_type, exp_type, NULL, ex )) {
	    char *arg_type_name = tnode_name( arg_type );
	    if( arg_type_name ) {
		compiler_compile_type_conversion( cc, arg_type_name, ex );
	    }
	}
    }
    cc->current_arg = cc->current_arg ? dnode_prev( cc->current_arg ) : NULL;
}

static void compiler_compile_typed_const_value( COMPILER *cc,
					     TNODE *const_type,
					     const_value_t *v,
					     cexception_t *ex )
{
    cexception_t inner;
    value_t vtype = v->value_type;
    TNODE * volatile tnode = NULL;

    cexception_guard( inner ) {
	switch( vtype ) {
	    case VT_INT:
		const_value_to_string( v, &inner );
		compiler_compile_typed_constant( cc, const_type,
					      const_value_string( v ),
					      &inner );
		break;
	    case VT_FLOAT:
		const_value_to_string( v, &inner );
		compiler_compile_typed_constant( cc, const_type,
					      const_value_string( v ),
					      &inner );
		break;
	    case VT_STRING:
		const_value_to_string( v, &inner );
		compiler_compile_typed_constant( cc, const_type,
					      const_value_string( v ),
					      &inner );
		break;
	    case VT_ENUM:
		const_value_to_string( v, &inner );
		compiler_compile_typed_constant( cc, const_type,
					      const_value_string( v ),
					      &inner );
		break;
	    case VT_NULL: {
		    tnode = new_tnode_nullref( &inner );
		    compiler_push_type( cc, tnode, &inner );
		    tnode = NULL;
		    compiler_emit( cc, &inner, "\tc\n", PLDZ );
	        }
		break;
	    default:
		assert(0);
	}
	const_value_free( v );
    }
    cexception_catch {
	const_value_free( v );
	delete_tnode( tnode );
	cexception_reraise( inner, ex );
    }
}

static void compiler_compile_multitype_const_value( COMPILER *cc,
                                                 const_value_t *v,
                                                 char *module_name,
                                                 char *suffix_name,
                                                 cexception_t *ex )
{
    TNODE *const_type = NULL;
    value_t vtype = v->value_type;

    switch( vtype ) {
    case VT_INT:
	const_type = compiler_lookup_suffix_tnode( cc, TS_INTEGER_SUFFIX,
						module_name, suffix_name,
						"integer" );
	break;
    case VT_FLOAT:
	const_type = compiler_lookup_suffix_tnode( cc, TS_FLOAT_SUFFIX,
						module_name, suffix_name,
						"float" );
	break;
    case VT_STRING:
	const_type = compiler_lookup_suffix_tnode( cc, TS_STRING_SUFFIX,
						module_name, suffix_name,
						"string" );
	break;
    case VT_ENUM: {
	cexception_t inner;
	char *volatile value_name = NULL;
	char *type_name;
	char *value_name_terminator;

	assert( v->value.s );

	type_name = strstr( v->value.s, " " );
	assert( type_name );
	type_name ++;

	value_name = strdupx( v->value.s, ex );
	value_name_terminator = strstr( value_name, " " );
	assert( value_name_terminator );
	*value_name_terminator = '\0';

	cexception_guard( inner ) {
	    compiler_compile_enumeration_constant( cc, module_name,
						value_name, type_name,
						&inner );
	}
	cexception_catch {
	    freex( value_name );
	    cexception_reraise( inner, ex );
	}
	freex( value_name );
	return;
	break;
    }
    case VT_NULL:
	const_type = NULL;
	break;
    default:
	assert( 0 );
	break;
    }

    compiler_compile_typed_const_value( cc, const_type, v, ex );
}

static void compiler_emit_default_arguments( COMPILER *cc,
					  char *arg_name,
					  cexception_t *ex )
{
    DNODE *arg;

    arg = cc->current_arg;
    while( arg && ( !arg_name || strcmp( arg_name, dnode_name( arg )) != 0 )) {
	if( dnode_has_initialiser( arg )) {
	    const_value_t const_value = make_zero_const_value();

	    const_value_copy( &const_value, dnode_value( arg ), ex );
	    compiler_compile_typed_const_value( cc, dnode_type( arg ),
					     &const_value, ex );
	} else {
	    if( arg ) {
		if( arg_name ) {
		    yyerrorf( "parameter '%s' has no default value, "
			      "please supply its value before '%s'",
			      dnode_name( arg ), arg_name );
		} else {
		    yyerrorf( "parameter '%s' has no default value, "
			      "please supply its value",
			      dnode_name( arg ) );
		}
	    }
	}
	arg = dnode_prev( arg );
    }
    if( arg == NULL && arg_name != NULL ) {
	yyerrorf( "function '%s' has no argument '%s' to emit",
		  dnode_name( cc->current_call ), arg_name );
    }
    cc->current_arg = arg;
}

static void compiler_check_forward_functions( COMPILER *c )
{
    FIXUP *f;
    FIXUP *forward_calls = thrcode_forward_functions( c->thrcode );

    foreach_fixup( f, forward_calls ) {
	char *name = fixup_name( f );
	yyerrorf( "function %s() declared forward but never defined", name );
    }
}

static void compiler_check_raise_expression( COMPILER *c,
					     char *exception_name,
					     cexception_t *ex )
{
    TNODE *top_type = NULL;

    if( !c->e_stack ) {
	yyerrorf( "Not enough values on the stack for raising exception?" );
    }
    if( !(top_type = enode_type( c->e_stack ))) {
	yyerrorf( "Value on the top of the stack is untyped when "
		  "raising exception?" );
    }
    compiler_check_and_compile_operator( c, top_type, "exceptionset", 1,
                                      NULL, ex );
}

static struct {
    char *exception_name;
    sl_exception_t exception_nr;
} default_exceptions[] = {
    { "TestException",            SL_EXCEPTION_TEST_EXCEPTION     },
    { "OutOfMemoryException",     SL_EXCEPTION_OUT_OF_MEMORY      },
    { "FileOpenError",            SL_EXCEPTION_FILE_OPEN_ERROR    },
    { "FileReadError",            SL_EXCEPTION_FILE_READ_ERROR    },
    { "FileWriteError",           SL_EXCEPTION_FILE_WRITE_ERROR   },
    { "NullPointerError",         SL_EXCEPTION_NULL_ERROR         },
    { "SystemException",          SL_EXCEPTION_SYSTEM_ERROR,      },
    { "ExternalLibraryException", SL_EXCEPTION_EXTERNAL_LIB_ERROR },
    { "MissingIncludePathException", SL_EXCEPTION_MISSING_INCLUDE_PATH },
    { "HashFullException",        SL_EXCEPTION_HASH_FULL} ,
    { "BoundError",               SL_EXCEPTION_BOUND_ERROR },
    { "BlobOverflowException",    SL_EXCEPTION_BLOB_OVERFLOW },
    { "BadBlobDescriptor",        SL_EXCEPTION_BLOB_BAD_DESCR },
    { "ArrayOverflowException",   SL_EXCEPTION_ARRAY_OVERFLOW },
    { "TruncatedInteger",         SL_EXCEPTION_TRUNCATED_INTEGER },

    { NULL, SL_EXCEPTION_NULL }
};

static void compiler_insert_default_exceptions( COMPILER *c,
					     cexception_t *ex )
{
    int i;

    for( i = 0; default_exceptions[i].exception_name != NULL; i ++ ) {

	compiler_compile_exception( c, default_exceptions[i].exception_name,
				 default_exceptions[i].exception_nr, ex );

	c->latest_exception_nr = default_exceptions[i].exception_nr;

    }
}

static void compiler_compile_file_input_operator( COMPILER *cc,
					       cexception_t *ex )
{
    ENODE *top_expr = cc->e_stack;
    TNODE *top_type = top_expr ? enode_type( top_expr ) : NULL;

    if( top_type && tnode_is_addressof( top_type )) {
	top_type = tnode_element_type( top_type );
    }

    compiler_swap_thrcodes( cc );

    if( top_type ) {
	ENODE *file_expr = cc->e_stack;
	TNODE *file_type = file_expr ? enode_type( file_expr ) : NULL;

	if( file_type ) {
	    compiler_push_type( cc, share_tnode( file_type ), ex );
	} else {
	    compiler_push_type( cc, NULL, ex );
	}
	compiler_check_and_compile_operator( cc, top_type, ">>",
					  /*arity:*/ 1,
					  /*fixup_values:*/ NULL, ex );
	compiler_emit( cc, ex, "\n" );
    }

    compiler_merge_top_thrcodes( cc, ex );
    compiler_compile_swap( cc, ex );
    compiler_compile_sti( cc, ex );
}

static void compiler_check_non_null_variable( DNODE *dnode )
{
    TNODE *var_type = dnode_type( dnode );
    if( tnode_is_non_null_reference( var_type )) {
        yyerrorf( "'%s' was declared as non-null reference -- "
                  "it must be initialised", dnode_name( dnode ) );
    }
}

static void compiler_check_non_null_variables( DNODE *dnode_list )
{
    DNODE *var_dnode;

    foreach_dnode( var_dnode, dnode_list ) {
        compiler_check_non_null_variable( var_dnode );
    }
}

static void compiler_compile_variable_initialisations( COMPILER *cc,
						    DNODE *lst,
						    cexception_t *ex )
{
    DNODE *var;

    foreach_dnode( var, lst ) {
	if( dnode_has_flags( var, DF_HAS_INITIALISER )) {
	    compiler_compile_initialise_variable( cc, var, ex );
	} else {
            compiler_check_non_null_variable( var );
        }
    }
}

static void compiler_compile_zero_out_stackcells( COMPILER *cc,
					       DNODE *variables,
					       cexception_t *ex )
{
    DNODE *var;
    ssize_t nvars = 0;
    ssize_t offset = 0;
    ssize_t min_offset = 0;
    int must_zero = 0;

    foreach_dnode( var, variables ) {
	if( !dnode_has_flags( var, DF_HAS_INITIALISER )) {
	    must_zero = 1;
	}
	nvars ++;
	offset = dnode_offset( var );
	if( min_offset == 0 || offset < min_offset ) {
	    min_offset = offset;
	}
    }
    if( must_zero ) {
	compiler_emit( cc, ex, "\tcee\n", ZEROSTACK, &min_offset, &nvars );
    }
}

static void compiler_begin_package( COMPILER *c,
				    DNODE *package,
				    cexception_t *ex )
{
    compiler_push_symbol_tables( c, ex );
    vartab_insert_named( c->compiled_packages, package, ex );
    vartab_insert_named( c->vartab, share_dnode( package ), ex );
    dlist_push_dnode( &c->current_package_stack, &c->current_package, ex );
    c->current_package = package;
}

static void compiler_end_package( COMPILER *c, cexception_t *ex )
{
    compiler_pop_symbol_tables( c );
    c->current_package = dlist_pop_data( &c->current_package_stack );
}

static char *compiler_find_package( COMPILER *c,
				    const char *package_name,
				    cexception_t *ex )
{
    static char buffer[300];
    ssize_t len;

    len = snprintf( buffer, sizeof(buffer), "%s.slib", package_name );

    assert( len < sizeof(buffer) );

    return buffer;
}

static int compiler_can_compile_use_statement( COMPILER *cc,
					       char *statement )
{
    assert( cc );
    if( cc->current_function ) {
	yyerrorf( "'%s' statement should not be used within subroutines",
		  statement );
	return 0;
    }
    if( cc->loops ) {
	yyerrorf( "'%s' statement should not be used within loops",
		  statement );
	return 0;
    }
    return 1;
}

static void compiler_import_package( COMPILER *c,
				     char *package_name,
				     cexception_t *ex )
{
    DNODE *package = vartab_lookup( c->compiled_packages, package_name );

    if( !compiler_can_compile_use_statement( c, "import" )) {
	return;
    }

    if( package != NULL ) {
	vartab_insert_named( c->vartab, share_dnode( package ), ex );
	/* printf( "found compiled package '%s'\n", package_name ); */
    } else {
	char *pkg_path = compiler_find_package( c, package_name, ex );
	compiler_open_include_file( c, pkg_path, ex );
    }
}

static void compiler_use_package( COMPILER *c,
				  char *package_name,
				  cexception_t *ex )
{
    DNODE *package = vartab_lookup( c->compiled_packages, package_name );

    if( !compiler_can_compile_use_statement( c, "use" )) {
	return;
    }

    if( package != NULL ) {
        char *package_name = dnode_name( package );
        DNODE *existing_package = package_name ?
            vartab_lookup( c->vartab, package_name ) : NULL;
        if( !existing_package || existing_package != package ) {
            vartab_insert_named( c->vartab, share_dnode( package ), ex );
        }
	/* printf( "found compiled package '%s'\n", package_name ); */
	compiler_use_exported_package_names( c, package, ex );
    } else {
	char *pkg_path = compiler_find_package( c, package_name, ex );
	compiler_open_include_file( c, pkg_path, ex );
	if( c->use_package_name ) {
	    freex( c->use_package_name );
	}
	c->use_package_name = strdupx( package_name, ex );
    }
}

static void compiler_debug()
{
    printf( "Debug statement reached in line %d\n",
	    compiler_flex_current_line_number() );
}

static void compiler_compile_multiple_assignment( COMPILER *cc,
					       ssize_t nvars,
					       ssize_t nvars_left,
					       ssize_t nvalues,
					       cexception_t *ex )
{
    ssize_t i;

    if( nvars > nvalues ) {
	yyerrorf( "there are more variables than values to asign" );
    }

    if( nvars < nvalues ) {
	compiler_compile_dropn( cc, nvalues - nvars, ex );
    }

    for( i = 0; i < nvars_left; i++ ) {
	compiler_merge_top_thrcodes( cc, ex );
	if( enode_is_varaddr( cc->e_stack )) {
	    DNODE *var = enode_variable( cc->e_stack );

	    share_dnode( var );
	    compiler_drop_top_expression( cc );
	    compiler_compile_variable_assignment( cc, var, ex );
	    delete_dnode( var );
	} else {
	    compiler_compile_swap( cc, ex );
	    compiler_compile_sti( cc, ex );
	}
    }
    compiler_swap_thrcodes( cc );
    compiler_merge_top_thrcodes( cc, ex );
}

static void compiler_compile_array_expression( COMPILER* cc,
					    ssize_t nexpr,
					    cexception_t *ex )
{
    ssize_t i;

    if( nexpr > 0 ) {
	ENODE *top = enode_list_pop( &cc->e_stack );
	TNODE *top_type = enode_type( top );
	ssize_t element_size = tnode_size( top_type );
	ssize_t nrefs = tnode_is_reference( top_type ) ? 1 : 0;

	for( i = 1; i < nexpr; i++ ) {
	    ENODE *curr = enode_list_pop( &cc->e_stack );
	    TNODE *curr_type = enode_type( curr );
	    if( !tnode_types_are_identical( top_type, curr_type, NULL, ex )) {
		yyerrorf( "incompatible types of array components" );
	    }
	    delete_enode( curr );
	}
	if( tnode_is_reference( top_type )) {
	    compiler_emit( cc, ex, "\tce\n", PMKARRAY, &nexpr );
	} else {
	    compiler_emit( cc, ex, "\tcsee\n", MKARRAY, &element_size,
                        &nrefs, &nexpr );
	}
	compiler_push_array_of_type( cc, share_tnode( top_type ), ex );
	delete_enode( top );
    }
}

static void compiler_push_loop( COMPILER *cc, char *loop_label,
                                int ncounters,
                                cexception_t *ex )
{
    char label[200];
    cc->loops =
	new_dnode_loop( loop_label, ncounters, cc->loops, ex );

    if( !loop_label ) {
	snprintf( label, sizeof(label), "@%p", cc->loops );
	dnode_set_name( cc->loops, label, ex );
    }
}

static void compiler_pop_loop( COMPILER *cc )
{
    DNODE *top_loop = cc->loops;

    assert( top_loop );
    cc->loops = dnode_next( top_loop );
    dnode_disconnect( top_loop );

    delete_dnode( top_loop );
}

static void compiler_fixup_op_continue( COMPILER *cc, cexception_t *ex )
{
    DNODE *loop = cc->loops;

    assert( loop );

    thrcode_fixup_op_continue( cc->thrcode, dnode_name( loop ),
			       thrcode_length( cc->thrcode ));
}

static void compiler_fixup_op_break( COMPILER *cc, cexception_t *ex )
{
    DNODE *loop = cc->loops;

    assert( loop );

    thrcode_fixup_op_break( cc->thrcode, dnode_name( loop ),
			    thrcode_length( cc->thrcode ));
}

static char *compiler_get_loop_name( COMPILER *cc, char *label )
{
    if( !label ) {
	DNODE *latest_loop = cc->loops;
	char *name = latest_loop ? dnode_name( latest_loop ) : NULL;
	return name;
    } else {
#if 0
	DNODE *loop;
	int found = 0;
	foreach_dnode( loop, cc->loops ) {
	    if( strcmp( dnode_name(loop), label ) == 0 ) {
		found = 1;
		break;
	    }
	}
	if( !found ) {
	    yyerrorf( "label '%s' is not defined in the current scope",
		      label );
	}
#endif
	return label;
    }
}

static ssize_t check_loop_types( COMPILER *cc, int omit_last_loop,
                                 char *label )
{
    DNODE *loop;
    int found = 0;
    ssize_t prev_count = 0;
    ssize_t count = 0;

    foreach_dnode( loop, cc->loops ) {
	if( dnode_has_flags( loop, DF_LOOP_HAS_VAL )) {
            prev_count = count;
	    count += dnode_loop_counters( loop );
	}
	if( strcmp( dnode_name(loop), label ) == 0 ) {
	    found = 1;
	    break;
	}
    }
    if( !found ) {
	yyerrorf( "label '%s' is not defined in the current scope", label );
    }
    return omit_last_loop ? prev_count : count;
}

static int compiler_check_break_and_cont_statements( COMPILER *cc )
{
    assert( cc );
    if( !cc->loops ) {
	yyerrorf( "'break' and 'continue' statements can be used "
		  "only in loops" );
	return 0;
    }
    return 1;
}

static void compiler_drop_loop_counters( COMPILER *cc, char *name,
                                         int delta,
                                         cexception_t *ex )
{
    ssize_t loop_counters = check_loop_types( cc, delta, name );

    if( loop_counters > 0 ) {
        compiler_emit( cc, ex, "\tce\n", PDROPN, &loop_counters );
    }
}

static void compiler_compile_break( COMPILER *cc, char *label,
				 cexception_t *ex )
{
    ssize_t zero = 0;

    if( compiler_check_break_and_cont_statements( cc )) {
	char *name = compiler_get_loop_name( cc, label );

	compiler_drop_loop_counters( cc, name, 0, ex );

	if( name ) {
	    thrcode_push_op_break_fixup( cc->thrcode, name, ex );
	}
	compiler_emit( cc, ex, "\tce\n", JMP, &zero );
    }
}

static void compiler_compile_continue( COMPILER *cc, char *label,
				    cexception_t *ex )
{
    ssize_t zero = 0;

    if( compiler_check_break_and_cont_statements( cc )) {
	char *name = compiler_get_loop_name( cc, label );

	compiler_drop_loop_counters( cc, name, 1, ex );

	if( name ) {
	    thrcode_push_op_continue_fixup( cc->thrcode, name, ex );
	}
	compiler_emit( cc, ex, "\tce\n", JMP, &zero );
    }
}

static void compiler_set_function_arguments_readonly( TNODE *funct_type )
{
    DNODE *arg;
    DNODE *arg_list = funct_type ? tnode_args( funct_type ) : NULL;

    foreach_dnode( arg, arg_list ) {
	TNODE *arg_type = dnode_type( arg );
	if( tnode_is_reference( arg_type ) &&
	    !tnode_is_immutable( arg_type )) {
	    dnode_set_flags( arg, DF_IS_READONLY );
	}
    }
}

static void compiler_check_default_value_compatibility( DNODE *arg,
						     const_value_t *val )
{
    TNODE *arg_type = dnode_type( arg );
    type_kind_t arg_kind = arg_type ? tnode_kind( arg_type ) : TK_NONE;
    value_t val_kind = const_value_type( val );

    if( arg_kind == TK_INTEGER || arg_kind == TK_BOOL ) {
	if( val_kind != VT_INT ) {
	    yyerrorf( "default value is not compatible with the "
		      "function argument '%s' of type '%s'",
		      dnode_name( arg ), tnode_name( arg_type ));
	}
    } else
    if( arg_kind == TK_REAL ) {
	if( val_kind != VT_FLOAT && val_kind != VT_INT ) {
	    yyerrorf( "default value is not compatible with the "
		      "function argument '%s' of type '%s'",
		      dnode_name( arg ), tnode_name( arg_type ));
	}
    } else
    if( arg_kind == TK_STRING ) {
	if( val_kind != VT_STRING && val_kind != VT_NULL ) {
	    yyerrorf( "default value is not compatible with the "
		      "function argument '%s' of type '%s'",
		      dnode_name( arg ), tnode_name( arg_type ));
	}
    } else
    if( arg_kind == TK_ENUM ) {
	if( val_kind != VT_ENUM ) {
	    yyerrorf( "default value is not compatible with the "
		      "function argument '%s' of type '%s'",
		      dnode_name( arg ), tnode_name( arg_type ));
	}
    } else
    if( tnode_is_reference( arg_type )) {
	if( val_kind != VT_NULL ) {
	    yyerrorf( "default value is not compatible with the "
		      "function argument '%s' of type '%s'",
		      dnode_name( arg ), tnode_name( arg_type ));
	}
    } else {
	yyerrorf( "default value is not compatible with the "
		  "function argument '%s'", dnode_name( arg ));
    }
}

static const_value_t compiler_make_compiler_attribute( char *attribute_name,
						       cexception_t *ex )
{
    if( strcmp( attribute_name, "stackcellsize" ) == 0 ) {
	return make_const_value( ex, VT_INT, sizeof(stackcell_t) );
    } else {
	yyerrorf( "unknown compiler attribute '%s' requested",
		  attribute_name );
	return make_zero_const_value();
    }
}

static 
const_value_t compiler_get_tnode_compile_time_attribute( TNODE *tnode,
							 char *attribute_name,
							 cexception_t *ex )
{
    if( strcmp( attribute_name, "size" ) == 0 ) {
	return make_const_value( ex, VT_INT, tnode_size( tnode ));
    } else
    if( strcmp( attribute_name, "nref" ) == 0 ) {
	return make_const_value( ex, VT_INT,
				 tnode_number_of_references( tnode ));
    } else {
	yyerrorf( "unknown compile-time attribute '%s' requested",
		  attribute_name );
	return make_zero_const_value();
    }
}

static
const_value_t compiler_get_dnode_compile_time_attribute( DNODE *dnode,
							 char *attribute_name,
							 cexception_t *ex )
{
    if( !dnode ) {
	return make_zero_const_value();
    }

    if( strcmp( attribute_name, "offset" ) == 0 ) {
	return make_const_value( ex, VT_INT, dnode_offset( dnode ));
    } else {
	TNODE *tnode = dnode_type( dnode );
	return compiler_get_tnode_compile_time_attribute( tnode,
							  attribute_name, ex );
    }
}

static const_value_t compiler_make_compile_time_value( COMPILER *cc,
						       char *package_name,
						       char *identifier,
						       char *attribute_name,
						       cexception_t *ex )
{
    DNODE *variable = NULL;
    TNODE *tnode = NULL;

    variable = compiler_lookup_dnode_silently( cc, package_name, identifier );

    if( !variable ) {
	tnode = compiler_lookup_tnode_silently( cc, package_name, identifier );
	if( tnode ) {
	    return compiler_get_tnode_compile_time_attribute( tnode,
							      attribute_name,
							      ex );
	} else {
	    if( !tnode ) {
		yyerrorf( "neither type nor variable '%s' can be found to "
			  "provide attribute '%s'",
			  identifier, attribute_name );
	    }
	    return make_zero_const_value();
	}
    } else {
	return compiler_get_dnode_compile_time_attribute( variable,
							  attribute_name, ex );
    }
}

static DNODE* compiler_lookup_type_field( COMPILER *cc,
					  char *package_name,
					  char *identifier,
					  char *field_identifier )
{
    DNODE *variable = NULL;
    TNODE *tnode = NULL;
    DNODE *field;

    variable = compiler_lookup_dnode_silently( cc, package_name, identifier );

    if( !variable ) {
	tnode = compiler_lookup_tnode_silently( cc, package_name, identifier );
	if( !tnode ) {
	    yyerrorf( "neither type nor variable '%s' can be found when "
		      "searching for field '%s'", identifier, field_identifier );
	}
    } else {
	tnode = dnode_type( variable );
	if( !tnode ) {
	    yyerrorf( "type of variable '%s' is not defined",
		      identifier );	    
	}
    }
    if( tnode ) {
	field = tnode_lookup_field( tnode, field_identifier );
	if( !field ) {
	    yyerrorf( "%s '%s' does not have member '%s'",
		      variable ? "variable" : "type",
		      identifier, field_identifier );
	    return NULL;
	} else {
	    return field;
	}
    } else {
	return NULL;
    }
}

static DNODE* compiler_lookup_tnode_field( COMPILER *cc,
                                           TNODE *tnode,
                                           char *field_identifier )
{
    DNODE *field;

    if( tnode ) {
	field = tnode_lookup_field( tnode, field_identifier );
	if( !field ) {
	    yyerrorf( "type '%s' does not have member '%s'",
		      tnode_name( tnode ), field_identifier );
	    return NULL;
	} else {
	    return field;
	}
    } else {
	return NULL;
    }
}

static char *basename( char *filename )
{
    char *start = filename;

    if( !start ) return NULL;
    while( *start ) start++;
    while( start >= filename && *start != '/' ) start --;
    return start+1;
}

static char *extension( char *filename )
{
    if( !filename ) return NULL;
    while( *filename && *filename != '.' ) filename ++;
    return filename;
}

typedef void DL_HANDLE;

static void compiler_load_library( COMPILER *compiler_cc,
				   char *library_filename,
				   char *opcode_array_name,
				   cexception_t *ex )
{
    cexception_t inner;
    char *library_name_start = basename( library_filename );
    char *library_name_end = extension( library_name_start );
    ssize_t library_name_length = library_name_end - library_name_start;
    char *library_name = callocx( 1, library_name_length + 1, ex );

    char *library_path =
        compiler_find_include_file( compiler_cc, library_filename, ex );

    strncpy( library_name, library_name_start, library_name_length );

    cexception_guard( inner ) {
	const char *opcodes_symbol = "OPCODES";
	DL_HANDLE *lib = dlopen( library_path, RTLD_LAZY );

	if( !lib ) {
	    char *errmsg = dlerror();
	    errmsg = rindex( errmsg, ':' );
	    if( errmsg ) errmsg ++;
	    if( errmsg && *errmsg == ' ' ) errmsg ++;
	    if( errmsg && *errmsg ) {
		yyerrorf( "could not open shared library '%s' - %c%s",
			  library_filename, tolower(*errmsg), errmsg+1 );
	    } else {
		yyerrorf( "could not open shared library '%s'",
                          library_filename );
	    }
	} else {
	    char **opcodes = dlsym( lib, opcodes_symbol );
	    int (*init)( istate_t* );
	    int (*trace_on)( int );
	    if( !opcodes ) {
		yyerrorf( "shared library '%s' does not contain symbol %s",
			  library_filename, opcodes_symbol );
	    } else {
		tcode_add_table( library_name, lib, opcodes, &inner );
	    }
	    if( (init = dlsym( lib, "init" )) != NULL ) {
		(*init)( &istate );
	    }
	    if( (trace_on = dlsym( lib, "trace_on" )) != NULL ) {
		(*trace_on)( trace );
	    }
	}
    }
    cexception_catch {
	freex( library_name );
	cexception_reraise( inner, ex );
    }
    freex( library_name );
}

static void compiler_check_and_push_function_name( COMPILER *cc,
						char *module_name,
						char *function_name,
						cexception_t *ex )
{
    TNODE *fn_tnode = NULL;
    type_kind_t fn_kind;

    dlist_push_dnode( &cc->current_call_stack,
		      &cc->current_call, ex );

    dlist_push_dnode( &cc->current_arg_stack,
		      &cc->current_arg, ex );

    cc->current_call = 
	share_dnode( compiler_lookup_dnode( cc, module_name, function_name,
					 "function" ));

    fn_tnode = cc->current_call ?
	dnode_type( cc->current_call ) : NULL;

    fn_kind = fn_tnode ? tnode_kind( fn_tnode ) : TK_NONE;

    if( fn_tnode &&
        fn_kind != TK_FUNCTION_REF &&
	fn_kind != TK_FUNCTION &&
	fn_kind != TK_OPERATOR &&
        fn_kind != TK_CLOSURE ) {
	char *fn_name = cc->current_call ?
	    dnode_name( cc->current_call ) : NULL;
	if( fn_name ) {
	    yyerrorf( "call to non-function '%s'", fn_name );
	} else {
	    yyerrorf( "call to non-function" );
	}
    }
}

static ssize_t compiler_compile_multivalue_function_call( COMPILER *cc,
						       cexception_t *ex )
{
    cexception_t inner;
    DNODE *funct = cc->current_call;
    TNODE *fn_type = funct ? dnode_type( funct ) : NULL;
    ssize_t rval_nr = 0;
    /* Generic types represented by "placeholder" tnodes pointing to
       the actual instances of these types in a particular function
       call: */
    TYPETAB *volatile generic_types = NULL; 

    cexception_guard( inner ) {
	generic_types = new_typetab( &inner );
        if( funct && fn_type ) {
            compiler_emit_default_arguments( cc, NULL, &inner );
            compiler_check_and_drop_function_args( cc, funct, generic_types,
                                                &inner );
            compiler_emit_function_call( cc, funct, NULL, "\n", &inner );
            if( tnode_kind( fn_type ) == TK_FUNCTION_REF ) {
                compiler_drop_top_expression( cc );
            }
            compiler_push_function_retvals( cc, funct, generic_types, &inner );
            rval_nr = compiler_count_return_values( funct );
        } else {
            while( cc->e_stack &&
                   !enode_has_flags( cc->e_stack, EF_GUARDING_ARG )) {
                compiler_drop_top_expression( cc );
            }
            assert( cc->e_stack );
            assert( enode_has_flags( cc->e_stack, EF_GUARDING_ARG ));
            compiler_drop_top_expression( cc );
            /* Push NULL value to maintain stack value balance and
               avoid segfaults or asserts in the downstream code: */
            compiler_push_error_type( cc, &inner );
            rval_nr = 1;
        }
	delete_typetab( generic_types );
    }
    cexception_catch {
	delete_typetab( generic_types );
        cexception_reraise( inner, ex );
    }

    delete_dnode( cc->current_call );

    cc->current_call =
	dlist_pop_data( &cc->current_call_stack );
    cc->current_arg =
	dlist_pop_data( &cc->current_arg_stack );

    return rval_nr;
}

/*

             <--- ssize_t --->
             alloccell_t:
             +...............+
             |               |
             | ...           |
             +---------------+
             | vmt_address   |>-\
             +---------------+  |
                                |
VMT layout:                     |
                                |
itable[]:                       |
---------                       |
             +---------------+  |
vmt_address: | n_interfaces  |<-/
             +---------------+
             |class VMT offs.|
             +---------------+
             |i-face 1 VMT o.|>-\
             +---------------+  |
             |i-face 2 VMT o.|  |
             +---------------+  |
             |               |  |
             | ...           |  |
             +---------------+  |
             |i-face n VMT o.|  |
             +---------------+  |
                                |
vtable[]:                       |
---------                       |
static data +                   |
i-face 1 VMT offs.:             |
             +---------------+  |
             | nr of methods |<-/
             +---------------+
             | method 1 offs.|
             +---------------+
             |               |
             | ...           |
             +---------------+
             | method k offs.| k = nr of methods 
             +---------------+

*/

static void compiler_start_virtual_method_table( COMPILER *cc,
                                                 TNODE *class_descr,
                                                 cexception_t *ex )
{
    ssize_t vmt_address;
    ssize_t interface_nr;

    assert( class_descr );

    if( tnode_kind( class_descr ) == TK_INTERFACE ) {
        return;
    }

    interface_nr = tnode_max_interface( class_descr );

#if 0
    printf( ">>> interface_nr = %d\n", interface_nr );
#endif
#if 0
    printf( ">>> class name = %s\n", tnode_name(class_descr) );
#endif

    compiler_assemble_static_alloc_hdr( cc, sizeof(ssize_t),
                                        sizeof(ssize_t), ex );

    vmt_address = compiler_assemble_static_ssize_t( cc, 1 + interface_nr, ex );

    tnode_set_vmt_offset( class_descr, vmt_address );

#if 0
    compiler_assemble_static_ssize_t( cc, vmt_address +
                                      (2+interface_nr) * sizeof(ssize_t), ex );
    compiler_assemble_static_data( cc, NULL,
				   interface_nr * sizeof(ssize_t), ex );
#else
    compiler_assemble_static_data( cc, NULL,
				   (1+interface_nr) * sizeof(ssize_t), ex );
#endif

}

static void compiler_finish_virtual_method_table( COMPILER *cc,
                                                  TNODE *class_descr,
                                                  cexception_t *ex )
{
    ssize_t vmt_address, vmt_start, i;
    ssize_t max_vmt_entry;
    ssize_t interface_nr;
    ssize_t *itable; /* interface VMT offset table */
    ssize_t *vtable; /* a VMT table with method offsets*/
    DNODE *volatile method;
    TNODE *volatile base;

    assert( class_descr );
    assert( tnode_kind( class_descr ) != TK_INTERFACE );

    vmt_address = tnode_vmt_offset( class_descr );
    max_vmt_entry = tnode_max_vmt_offset( class_descr );
    interface_nr = tnode_max_interface( class_descr );

#if 0
    printf( ">>> interface_nr = %d\n", interface_nr );
#endif

    vmt_start =
	compiler_assemble_static_ssize_t( cc, max_vmt_entry, ex );

    // assert( vmt_start == vmt_address + (2+interface_nr) * sizeof(ssize_t) );

    itable = (ssize_t*)(cc->static_data + vmt_address);
    itable[1] = vmt_start;

#if 0
    printf( ">>> class '%s', interface table starts at %d, vmt[1] starts at %d\n",
            tnode_name( class_descr ),
            vmt_address, vmt_start );
#endif

    /* allocate the main class VMT: */
    compiler_assemble_static_data( cc, NULL,
				   max_vmt_entry * sizeof(ssize_t), ex );

    /* Temporarily, let's store method counts instead of interface vmt
       offsets in the first layer of the VMT (the itable). Later, we
       will allocate VMT's for each interface, for exactely the stored
       number of methods (plus one entry for the method count), and
       replace the method counts here with the VMT offsets. */
    itable = (ssize_t*)(cc->static_data + vmt_address);
    foreach_tnode_base_class( base, class_descr ) {
	DNODE *methods = tnode_methods( base );
	foreach_dnode( method, methods ) {
            TNODE *method_type = dnode_type( method );
	    ssize_t method_index = dnode_offset( method );
            ssize_t method_interface = method_type ?
                tnode_interface_number( method_type ) : 0;
            if( method_interface > 0 &&
                itable[method_interface+1] < method_index ) {
                itable[method_interface+1] = method_index;
            }
        }
    }

    /* Now, let's allocate VMTs for methods and replace itable[]
       entries with table offsets: */
    for( i = 2; i <= interface_nr+1; i++ ) {
        ssize_t method_count = itable[i];
#if 0
        printf( ">>> class '%s', interface %d, method count  %d\n",
                tnode_name( base ), i, method_count );
#endif
        itable[i] = compiler_assemble_static_data( cc, NULL,
                                                   (method_count + 1) *
                                                   sizeof(ssize_t), ex );
        itable = (ssize_t*)(cc->static_data + vmt_address);
        ((ssize_t*)(cc->static_data + itable[i]))[0] = method_count;
    }

    /* Now, fill the VMT table with the real method addresses: */
    itable = (ssize_t*)(cc->static_data + vmt_address);
    foreach_tnode_base_class( base, class_descr ) {
	DNODE *methods = tnode_methods( base );
	foreach_dnode( method, methods ) {
	    ssize_t method_index = dnode_offset( method );
	    ssize_t method_address = dnode_ssize_value( method );
            TNODE *method_type = dnode_type( method );
            ssize_t method_interface = method_type ?
                tnode_interface_number( method_type ) : -1;
#if 0
	    ssize_t compiled_addr;
	    printf( ">>> class '%s', interface %d, method '%s', offset %d, address %d\n",
		    tnode_name( base ), method_interface, dnode_name( method ),
		    dnode_offset( method ), dnode_ssize_value( method ));
#endif

#if 1
            vtable = (ssize_t*)(cc->static_data + itable[method_interface+1]);
            if( vtable[method_index] == 0 ) {
                vtable[method_index] = method_address;
            }
#endif

#if 0
            if( method_interface == 0 ) {
                compiled_addr =
                    *(ssize_t*)
                    (&cc->static_data[vmt_start + method_index * sizeof(ssize_t)]);
                if( method_index != 0 && method_address != 0 && compiled_addr == 0 ) {
                    compiler_patch_static_data( cc, /* void *data: */ &method_address,
                                                /* ssize_t data_size: */
                                                sizeof(method_address),
                                                /* ssize_t offset: */
                                                vmt_start +
                                                method_index * sizeof(ssize_t),
                                                ex );
                }
            }
#endif
	}
    }

    /* check whether all methods are implemented: */

    {
        DNODE *methods = tnode_methods( class_descr );
        char *class_name = class_descr ? tnode_name( class_descr ) : "???";
	foreach_dnode( method, methods ) {
	    /* ssize_t method_index = dnode_offset( method ); */
	    ssize_t method_address = dnode_ssize_value( method );
            TNODE *method_type = dnode_type( method );
            ssize_t method_interface = method_type ?
                tnode_interface_number( method_type ) : -1;
            if( method_address == 0 ) {
                yyerrorf( "class '%s', interface %d, method '%s' is declared "
                          "but not implemented\n",
                          class_name, method_interface, 
                          method ? dnode_name( method ) : "???" );
            }
        }
    }
}

static void compiler_check_array_component_is_not_null( TNODE *tnode )
{
    if( tnode_is_non_null_reference( tnode )) {
        char *type_name = tnode_name( tnode );
        if( type_name ) {
            yyerrorf( "type '%s' is a non-null reference -- "
                      "please use array expressions to initialise array elements",
                      type_name );
        } else {
            yyerrorf( "array element is a non-null reference -- "
                      "please use array expressions to initialise array elements" );
        }
    }
}

static void compiler_check_type_contains_non_null_ref( TNODE *tnode )
{
    if( tnode_has_non_null_ref_field( tnode ) &&
        tnode_kind( tnode ) != TK_CLASS ) {
        char *type_name = tnode_name( tnode );
        if( type_name ) {
            yyerrorf( "type '%s' contains non-null fields -- "
                      "please use struct expressions to initialise them",
                      type_name );
        } else {
            yyerrorf( "structure contains non-null fields -- "
                      "please use structure expressions to initialise them" );
        }
    }
}

static void compiler_compile_type_descriptor_loader( COMPILER *cc,
                                                  TNODE *tnode,
                                                  cexception_t *ex )
{
    TNODE *type_descriptor_type;
    rtti_t type_descriptor;
    ssize_t offset;

    type_descriptor.size = tnode_size( tnode );
    type_descriptor.nref = tnode_number_of_references( tnode );

    compiler_assemble_static_alloc_hdr( cc, sizeof(type_descriptor),
                                        /* len */ -1, ex );

    offset = compiler_assemble_static_data( cc, &type_descriptor,
                                            sizeof(type_descriptor), ex );

    compiler_emit( cc, ex, "\tce\n", SLDC, &offset );

    type_descriptor_type = new_tnode_type_descriptor( ex );
    compiler_push_type( cc, type_descriptor_type, ex );
}

static COMPILER * volatile compiler_cc;

static cexception_t *px; /* parser exception */

%}

%union {
  long i;
  char *s;
  ANODE *anode;        /* type attribute description */
  TNODE *tnode;
  DNODE *dnode;
  ENODE *enode;
  TLIST *tlist;
  int token;           /* token value returned by lexer */
  int op;              /* type of the assign operator; for simple assignement
			  operator, contains '='; for operators like '+=' and
			  '*=' contains '+' and '*', correspondingly; for
			  operators like '**=' contains token for '**', in this
			  case __STAR_STAR */
  const_value_t c;     /* value of a constant being computed; strings
		          are allocated. */
}

%token _ADDRESSOF
%token _ARRAY
%token _ASSERT
%token _BLOB
%token _BREAK
%token _BYTECODE
%token _CATCH
%token _CLASS
%token _CLOSURE
%token _CONST
%token _CONSTRUCTOR
%token _CONTINUE
%token _DEBUG
%token _DO
%token _ELSE
%token _ELSIF
%token _ENDDO
%token _ENDIF
%token _ENUM
%token _EXCEPTION
%token _FOR
%token _FOREACH
%token _FORWARD
%token _FUNCTION
%token _IF
%token _IMPLEMENTS
%token _IMPORT
%token _IN
%token _INCLUDE
%token _INLINE
%token _INTERFACE
%token _LIKE
%token _LOAD
%token _METHOD
%token _MODULE
%token _NATIVE
%token _NEW
%token _NOT
%token _NULL
%token _OF
%token _OPERATOR
%token _PACK
%token _PACKAGE
%token _PRAGMA
%token _PROCEDURE
%token _PROGRAM
%token _RAISE
%token _READONLY
%token _REPEAT
%token _RERAISE
%token _RETURN
%token _SHL
%token _SHR
%token _SIZEOF
%token _STRUCT
%token _THEN
%token _TO
%token _TRY
%token _TYPE
%token _UNPACK
%token _USE
%token _VAR
%token _WHILE

%token __ASSIGN /* := */
%token __INC    /* ++ */
%token __DEC    /* -- */
%token __DOT_DOT /* .. */
%token __COLON_COLON /* :: */
%token __THREE_DOTS /* ... */
%token __ARROW  /* -> */
%token __THICK_ARROW /* => */
%token __STAR_STAR /* ** */
%token __LEFT_TO_RIGHT /* >> */
%token __RIGHT_TO_LEFT /* << */
%token __DOUBLE_PERCENT /* %% */

%token <s> __ARITHM_ASSIGN  /* +=, -=, *=, etc. */

%token __QQ /* ?? */

%token <s> __IDENTIFIER
%token <s> __INTEGER_CONST
%token <s> __REAL_CONST
%token <s> __STRING_CONST

%type <dnode> argument
%type <dnode> argument_list
%type <dnode> argument_identifier_list
%type <dnode> closure_header
%type <dnode> closure_var_declaration
%type <dnode> closure_var_list_declaration
%type <c>     constant_expression
%type <i>     constant_integer_expression
%type <dnode> constructor_header
%type <dnode> constructor_definition
%type <tnode> dimension_list
%type <dnode> enum_member
%type <tnode> enum_member_list
%type <i>     expression_list
%type <dnode> field_designator
%type <dnode> function_expression_header
%type <dnode> function_header
%type <dnode> method_header
%type <dnode> method_definition
%type <s>     module_list
%type <i>     multivalue_function_call
%type <i>     multivalue_expression_list
%type <s>     import_statement
%type <s>     include_statement
%type <i>     index_expression
%type <tlist> interface_identifier_list
%type <i>     lvalue_list
%type <i>     md_array_allocator
%type <dnode> operator_definition
%type <dnode> operator_header
%type <s>     opt_identifier
%type <dnode> opt_implements_method
%type <i>     function_attributes
%type <dnode> function_definition
%type <i>     function_or_procedure_keyword
%type <i>     function_or_procedure_type_keyword
%type <s>     opt_closure_initialisation_list
%type <i>     opt_null_type_designator
%type <tnode> opt_base_type
%type <i>     opt_function_attributes
%type <i>     opt_function_or_procedure_keyword
%type <tlist> opt_implemented_interfaces
%type <s>     opt_label
%type <i>     opt_readonly
%type <dnode> opt_retval_description_list
%type <i>     opt_variable_declaration_keyword
%type <dnode> package_name
%type <dnode> program_header
%type <dnode> raised_exception_identifier;
%type <dnode> retval_description_list
%type <i>     size_constant
%type <tnode> struct_description
%type <tnode> struct_or_class_declaration_body
%type <tnode> struct_or_class_description_body
%type <tnode> interface_declaration_body
%type <tnode> interface_type_placeholder
%type <tnode> class_description
%type <dnode> struct_field
%type <tnode> struct_declaration_field_list
%type <tnode> struct_description_field_list
%type <dnode> struct_operator
%type <tnode> struct_operator_list
%type <dnode> struct_var_declaration
%type <tnode> finish_fields
%type <dnode> interface_operator
%type <tnode> interface_operator_list
%type <tnode> compact_type_description
%type <s>     type_declaration_name
%type <tnode> type_identifier
%type <tnode> var_type_description
%type <tnode> undelimited_or_structure_description
%type <tnode> undelimited_type_description
%type <tnode> delimited_type_description
%type <anode> type_attribute
%type <s>     use_statement
%type <dnode> variable_access_identifier
%type <dnode> variable_access_for_indexing
%type <dnode> variable_identifier
%type <dnode> variable_identifier_list
%type <i>     variable_declaration_keyword
%type <dnode> variable_declarator_list
%type <dnode> uninitialised_var_declarator_list
%type <dnode> variable_declarator
%type <dnode> for_variable_declaration
%type <i>     exception_identifier_list

%left __ARROW
%right __ASSIGN '='

%left '?' ':'

%left _OR
%left _AND

%left  '<' '>' __EQ __NE __LE  __GE

%left  '_'
%left __DOUBLE_PERCENT
%left  '+' '-' '|' '^'
%left  '*' '/' '%' '&' _SHR _SHL __LEFT_TO_RIGHT  __RIGHT_TO_LEFT
%left  __STAR_STAR

%left '@'

%left __COLON_COLON /* :: */

/* %left _AS */

%right __UNARY

%%

Program
  :   {
        ssize_t zero = 0;
        assert( compiler_cc );
        compiler_insert_default_exceptions( compiler_cc, px );
        compiler_compile_function_thrcode( compiler_cc );
	compiler_push_absolute_fixup( compiler_cc, px );
	compiler_emit( compiler_cc, px, "\tce\n", ENTER, &zero );
	compiler_push_relative_fixup( compiler_cc, px );
	compiler_emit( compiler_cc, px, "\tce\n", JMP, &zero );
        compiler_compile_main_thrcode( compiler_cc );
      }
    statement_list
      {
	compiler_compile_function_thrcode( compiler_cc );
	compiler_fixup_here( compiler_cc );
	compiler_fixup( compiler_cc, -compiler_cc->local_offset );
	compiler_merge_functions_and_main( compiler_cc, px );
	compiler_check_forward_functions( compiler_cc );
	compiler_emit( compiler_cc, px, "\tc\n", NULL );
      }
  ;

statement_list
  : delimited_statement
  | statement_list ';' delimited_statement
  | undelimited_statement_list delimited_statement
  ;

undelimited_statement_list
  : undelimited_statement
  | statement_list ';' undelimited_statement
  | undelimited_statement_list undelimited_statement
  ;

statement
  : delimited_statement
  | undelimited_statement
  ;

delimited_statement
  : multivalue_function_call
    { compiler_emit_drop_returned_values( compiler_cc, $1, px ); }
  | assignment_statement
  | variable_declaration
  | constant_declaration
  | exception_declaration
  | function_prototype
  | delimited_type_declaration
  | return_statement
  | raise_statement
  | incdec_statement
  | io_statement
  | program_definition
  | delimited_control_statement
  | package_statement
  | break_or_continue_statement
  | pack_statement
  | assert_statement

  | /* empty statement */
  ;

assert_statement
  : _ASSERT boolean_expression
  {
    ssize_t current_line_no = compiler_flex_current_line_number();

    ssize_t file_name_offset = compiler_assemble_static_string
        ( compiler_cc, compiler_cc->filename, px );

    ssize_t current_line_offset = compiler_assemble_static_string
        ( compiler_cc, (char*)compiler_flex_current_line(), px );

    compiler_emit( compiler_cc, px, "\tceee\n", ASSERT,
                &current_line_no, &file_name_offset, &current_line_offset );
  }
  ;

/* pack a,    20,     4,    8;
   //-- blob, offset, size, value
*/
pack_statement
: _PACK expression ',' expression ',' expression ',' expression
{
    TNODE *type_to_pack = enode_type( compiler_cc->e_stack );

    if( type_to_pack ) {
	if( tnode_kind( type_to_pack ) == TK_ARRAY ) {
	    TNODE *element_type = tnode_element_type( type_to_pack );
	    if( element_type && tnode_kind( element_type ) == TK_ARRAY ) {
		key_value_t *fixup_values;
		int level = 1;
		do {
		    level ++;
		    element_type = tnode_element_type( element_type );
		} while( element_type && tnode_kind( element_type ) == TK_ARRAY );
		fixup_values =
		    make_mdalloc_key_value_list( element_type, level );
		compiler_check_and_compile_operator( compiler_cc, element_type,
						  "packmdarray", 4 /* arity */,
						  fixup_values, px );
	    } else {
		compiler_check_and_compile_operator( compiler_cc, element_type,
						  "packarray", 4 /* arity */,
						  NULL /* fixup_values */, px );
	    }
	} else {
	    compiler_check_and_compile_operator( compiler_cc, type_to_pack,
					      "pack", 4 /* arity */,
					  NULL /* fixup_values */, px );
	}
	compiler_emit( compiler_cc, px, "\n" );
    } else {
	yyerrorf( "top expression has no type???" );
    }
}
;

break_or_continue_statement
  : _BREAK
    { compiler_compile_break( compiler_cc, NULL, px ); }
  | _BREAK __IDENTIFIER
    { compiler_compile_break( compiler_cc, $2, px ); }
  | _CONTINUE
    { compiler_compile_continue( compiler_cc, NULL, px ); }
  | _CONTINUE __IDENTIFIER
    { compiler_compile_continue( compiler_cc, $2, px ); }
  ;

undelimited_simple_statement
  : include_statement
       { compiler_open_include_file( compiler_cc, $1, px ); }
  | import_statement
       { compiler_import_package( compiler_cc, $1, px ); }
  | use_statement
       { compiler_use_package( compiler_cc, $1, px ); }
  | load_library_statement
  | pragma_statement
  | bytecode_statement
  | function_definition
  | operator_definition
    {
#if 0
	TNODE *operator = dnode_type( $1 );
	DNODE *arg1 = tnode_args( operator );
	TNODE *arg1_type = dnode_type( arg1 );

	/* should probably check whether operator is declared in the
	   same module as the type. */
	tnode_insert_single_operator( arg1_type, $1 );
#else
        vartab_insert_named_operator( compiler_cc->operators, $1, px );
        if( compiler_cc->current_package && dnode_scope( $1 ) == 0 ) {
            dnode_optab_insert_named_operator( compiler_cc->current_package,
                                               share_dnode( $1 ), px );
        }

#endif
    }
  | compound_statement
  | undelimited_type_declaration
  | debug_statement
  ;

undelimited_statement
  : undelimited_simple_statement
  | control_statement
  ;

non_control_statement
  : delimited_statement
  | undelimited_simple_statement
  ;

debug_statement
  : _DEBUG
    {
	compiler_debug();
    }
  ;

do_prefix
  : _DO
    {
      compiler_push_thrcode( compiler_cc, px );
    }
  ;

repeat_prefix
  : _REPEAT
    {
      compiler_push_loop( compiler_cc, /* loop label = */ NULL,
                          /* ncounters = */ 0, px );
      compiler_push_current_address( compiler_cc, px );
    }
  ;

non_control_statement_list
  : non_control_statement
  | non_control_statement_list ';' non_control_statement
  ;

delimited_control_statement
  : do_prefix non_control_statement_list
      {
	compiler_swap_thrcodes( compiler_cc );
      }
    if_condition
      {
	compiler_merge_top_thrcodes( compiler_cc, px );
        compiler_fixup_here( compiler_cc );
      }

  | repeat_prefix non_control_statement_list _WHILE 
      {
	compiler_fixup_op_continue( compiler_cc, px );
      }
    expression
      {
	compiler_compile_jnz( compiler_cc, compiler_pop_offset( compiler_cc, px ), px );
	compiler_fixup_op_break( compiler_cc, px );
        compiler_pop_loop( compiler_cc );
      }
  ;

raised_exception_identifier
  : __IDENTIFIER
      {
          $$ = vartab_lookup( compiler_cc->vartab, $1 );
      }
  | module_list __COLON_COLON __IDENTIFIER
      {
          $$ = compiler_lookup_dnode( compiler_cc, $1, $3, "exception" );
      }
  ;

raise_statement
  : _RAISE
    {
	ssize_t zero = 0;
	ssize_t minus_one = -1;
	compiler_emit( compiler_cc, px, "\tce\n", LDC, &minus_one );
	compiler_emit( compiler_cc, px, "\tc\n", PLDZ );
	compiler_emit( compiler_cc, px, "\tcee\n", RAISE, &zero, &zero );
    }

  | _RAISE raised_exception_identifier
    {
	ssize_t zero = 0;
	ssize_t minus_one = -1;
	DNODE *exception = $2;
	ssize_t exception_val = exception ? dnode_ssize_value( exception ) : 0;

        if( exception ) {
            compiler_check_raise_expression( compiler_cc, dnode_name( exception ),
                                             px );
        }

	compiler_emit( compiler_cc, px, "\tce\n", LDC, &minus_one );
	compiler_emit( compiler_cc, px, "\tc\n", PLDZ );
	compiler_emit( compiler_cc, px, "\tcee\n", RAISE, &zero, &exception_val );
    }
  | _RAISE raised_exception_identifier '(' expression ')'
    {
	ssize_t zero = 0;
	DNODE *exception = $2;
	ssize_t exception_val = exception ? dnode_ssize_value( exception ) : 0;

        if( exception ) {
            compiler_check_raise_expression( compiler_cc, dnode_name(exception),
                                             px );
        }

        if( tnode_is_reference( enode_type( compiler_cc->e_stack ))) {
            compiler_emit( compiler_cc, px, "\tce\n", LLDC, &zero );
            compiler_emit( compiler_cc, px, "\tc\n", SWAP );            
        } else {
            compiler_emit( compiler_cc, px, "\tc\n", PLDZ );
        }
        compiler_emit( compiler_cc, px, "\tcee\n", RAISE, &zero, &exception_val );

	compiler_drop_top_expression( compiler_cc );
    }

  | _RAISE raised_exception_identifier '(' expression ','
    {
        DNODE *exception = $2;

        if( exception ) {
            compiler_check_raise_expression( compiler_cc, dnode_name(exception),
                                             px );
        }
	if( !compiler_stack_top_is_integer( compiler_cc )) {
	    yyerrorf( "The first expression in 'raise' operator "
		      "must be of integer type" );
	}
    }
    expression ')'
    {
	ssize_t zero = 0;
	DNODE *exception = $2;
	ssize_t exception_val = exception ? dnode_ssize_value( exception ) : 0;

	if( !compiler_stack_top_is_reference( compiler_cc )) {
	    yyerrorf( "The second expression in 'raise' operator "
		      "must be of string type" );
	}

	compiler_drop_top_expression( compiler_cc );
	compiler_drop_top_expression( compiler_cc );
	compiler_emit( compiler_cc, px, "\tcee\n", RAISE, &zero, &exception_val );
    }

  | _RERAISE
    {
	if( !compiler_cc->try_variable_stack || compiler_cc->try_block_level < 1 ) {
	    yyerror( "'reraise' operator can only be used after "
		     "a try block" );
	} else {
	    ssize_t try_var_offset = compiler_cc->try_variable_stack ?
		compiler_cc->try_variable_stack[compiler_cc->try_block_level-1] : 0;

	    compiler_emit( compiler_cc, px, "\tce\n", RERAISE, &try_var_offset );
	}
    }
;

exception_declaration
  : _EXCEPTION __IDENTIFIER
    { compiler_compile_next_exception( compiler_cc, $2, px ); }
  ;

/*--------------------------------------------------------------------------*/
/* package and import statements */

package_name
  : __IDENTIFIER
      {
	  DNODE *package_dnode = new_dnode_package( $1, px );
	  $$ = package_dnode;
      }
  ;

package_keyword : _PACKAGE | _MODULE;

package_statement
  : package_keyword package_name
      {
	  vartab_insert_named( compiler_cc->vartab, $2, px );
	  compiler_begin_package( compiler_cc, share_dnode( $2 ), px );
      }
    statement_list
    '}' package_keyword __IDENTIFIER
      {
	  char *name;
	  if( compiler_cc->current_package &&
	      (name = dnode_name( compiler_cc->current_package )) != NULL ) {
	      if( strcmp( $7, name ) != 0 ) {
		  yyerrorf( "package '%s' ends with 'end package %s'",
			    name, $7 );
	      }
	  }
	  compiler_end_package( compiler_cc, px );
      }
  ;

import_statement
   : _IMPORT __IDENTIFIER
       { $$ = $2; }
   ;

use_statement
   : _USE __IDENTIFIER
       { $$ = $2; }
   ;

load_library_statement
   : _LOAD __STRING_CONST
       {
	   compiler_load_library( compiler_cc, $2, "SL_OPCODES", px );
       }
   ;

include_statement
   : _INCLUDE __STRING_CONST
       { $$ = $2; }
   ;

pragma_statement
   : _PRAGMA type_identifier
   {
       TNODE *default_type = $2;

       if( default_type ) {
           typetab_override_suffix( compiler_cc->typetab, /*name*/ "",
                                    TS_INTEGER_SUFFIX,
                                    share_tnode( default_type ),
                                    px );

           typetab_override_suffix( compiler_cc->typetab, /*name*/ "",
                                    TS_FLOAT_SUFFIX, 
                                    share_tnode( default_type ),
                                    px );
       }
   }
   ;

opt_identifier
: __IDENTIFIER
| { $$ = ""; }
;

program_header
  :  _PROGRAM opt_identifier '(' argument_list ')' opt_retval_description_list
        {
	  cexception_t inner;
	  DNODE *volatile funct = NULL;
          DNODE *retvals = $6;
          TNODE *retval_type = retvals ? dnode_type( retvals ) : NULL;
          ssize_t program_addr;

    	  cexception_guard( inner ) {
	      $$ = funct = new_dnode_function( $2, $4, $6, &inner );
	      funct = $$ =
		  compiler_check_and_set_fn_proto( compiler_cc, funct, &inner );

              compiler_check_and_emit_program_arguments( compiler_cc, $4,
                                                         &inner );
              program_addr = thrcode_length( compiler_cc->function_thrcode );
              compiler_emit( compiler_cc, &inner, "\tce\n", CALL, &program_addr );
              /* Chech program return value; exit if the value is not zero: */
              if( retvals ) {
                  assert( retval_type );
                  compiler_emit( compiler_cc, px, "\tc\n", DUP );
                  compiler_compile_constant( compiler_cc, TS_INTEGER_SUFFIX,
                                          NULL, tnode_suffix( retval_type ), 
                                          "function return value", "0", px );
                  compiler_compile_operator( compiler_cc, retval_type, "==", 2, px );
                  compiler_emit( compiler_cc, px, "\n" );
                  compiler_emit( compiler_cc, px, "\tcI\n", BJNZ, 6 );
                  compiler_emit( compiler_cc, px, "\tcI\n", LDC, 0 );
                  compiler_compile_operator( compiler_cc, retval_type,
                                          "nth-byte", 2, px );
                  compiler_emit( compiler_cc, px, "\tc\n", EXIT );
                  compiler_emit( compiler_cc, px, "\tc\n", DROP );
              }
	  }
	  cexception_catch {
	      delete_dnode( $4 );
	      delete_dnode( $6 );
	      delete_dnode( funct );
	      $$ = NULL;
	      cexception_reraise( inner, px );
	  }
	}
;

program_definition
:   program_header
    function_or_operator_start
    function_or_operator_body
    function_or_operator_end
  ;

module_list
: __IDENTIFIER
| module_list __COLON_COLON __IDENTIFIER
;

variable_access_identifier
  : __IDENTIFIER
     {
	 $$ = compiler_lookup_dnode( compiler_cc, NULL, $1, "variable" );
     }
  | module_list __COLON_COLON __IDENTIFIER
     {
	 $$ = compiler_lookup_dnode( compiler_cc, $1, $3, "variable" );
     }
  ;

incdec_statement
  : variable_access_identifier __INC
      {
          if( dnode_has_flags( $1, DF_IS_READONLY )) {
              yyerrorf( "may not increment readonly variable '%s'",
                        dnode_name( $1 ));
          } else {
              if( compiler_variable_has_operator( compiler_cc, $1, "incvar", 0, px )) {
                  TNODE *var_type = dnode_type( $1 );
                  ssize_t var_offset = dnode_offset( $1 );

                  compiler_compile_operator( compiler_cc, var_type, "incvar", 0, px );
                  compiler_emit( compiler_cc, px, "eN\n", &var_offset, dnode_name( $1 ));
              } else {
                  compiler_compile_load_variable_value( compiler_cc, $1, px );
                  compiler_compile_unop( compiler_cc, "++", px );
                  compiler_compile_store_variable( compiler_cc, $1, px );
              }
          }
      }
  | variable_access_identifier __DEC
      {
          if( dnode_has_flags( $1, DF_IS_READONLY )) {
              yyerrorf( "may not decrement readonly variable '%s'",
                        dnode_name( $1 ));
          } else {
              if( compiler_variable_has_operator( compiler_cc, $1, "decvar", 0, px )) {
                  TNODE *var_type = dnode_type( $1 );
                  ssize_t var_offset = dnode_offset( $1 );

                  compiler_compile_operator( compiler_cc, var_type, "decvar", 0, px );
                  compiler_emit( compiler_cc, px, "eN\n", &var_offset, dnode_name( $1 ));
              } else {
                  compiler_compile_load_variable_value( compiler_cc, $1, px );
                  compiler_compile_unop( compiler_cc, "--", px );
                  compiler_compile_store_variable( compiler_cc, $1, px );
              }
          }
      }
  | lvalue __INC
      {
	  compiler_compile_dup( compiler_cc, px );
	  compiler_compile_ldi( compiler_cc, px );
	  compiler_compile_unop( compiler_cc, "++", px );
	  compiler_compile_sti( compiler_cc, px );
      }
  | lvalue __DEC
      {
	  compiler_compile_dup( compiler_cc, px );
	  compiler_compile_ldi( compiler_cc, px );
	  compiler_compile_unop( compiler_cc, "--", px );
	  compiler_compile_sti( compiler_cc, px );
      }
  ;

print_expression_list
  : expression
      {
	  compiler_compile_unop( compiler_cc, ".", px );
      }
  | print_expression_list ',' expression
      {
	  compiler_emit( compiler_cc, px, "\tc\n", SPACE );
	  compiler_compile_unop( compiler_cc, ".", px );
      }
; 

output_expression_list
  : expression
      {
	  compiler_compile_unop( compiler_cc, "<", px );
      }
  | output_expression_list ',' expression
      {
	  compiler_emit( compiler_cc, px, "\tc\n", SPACE );
	  compiler_compile_unop( compiler_cc, "<", px );
      }
; 

io_statement
  : '.' print_expression_list
     {
	 compiler_emit( compiler_cc, px, "\tc\n", NEWLINE );
     }

  | '<' output_expression_list

  | '>' lvariable
     {
	 compiler_compile_unop( compiler_cc, ">", px );
     }

  | __RIGHT_TO_LEFT expression
     {
	 compiler_compile_unop( compiler_cc, "<<", px );
     }

  | __LEFT_TO_RIGHT lvariable
     {
	 compiler_compile_unop( compiler_cc, ">>", px );
     }

  | file_io_statement
    {
	compiler_emit( compiler_cc, px, "\tc\n", PDROP );
	compiler_drop_top_expression( compiler_cc );
    }

  | stdread_io_statement
  ;

stdread_io_statement
: '<' '>' __LEFT_TO_RIGHT variable_access_identifier
      {
          cexception_t inner;
          TNODE *type_tnode = typetab_lookup( compiler_cc->typetab, "string" );

          cexception_guard( inner ) {
              compiler_push_type( compiler_cc, type_tnode, &inner );
              compiler_emit( compiler_cc, &inner, "\tc\n", STDREAD );
          }
          cexception_catch {
              delete_tnode( type_tnode );
              cexception_reraise( inner, px );
          }
          compiler_compile_store_variable( compiler_cc, $4, px );
      }

  | '<' '>' __LEFT_TO_RIGHT lvalue
      {
          cexception_t inner;
          TNODE *type_tnode = typetab_lookup( compiler_cc->typetab, "string" );

          cexception_guard( inner ) {
              compiler_push_type( compiler_cc, type_tnode, &inner );
              compiler_emit( compiler_cc, &inner, "\tc\n", STDREAD );
          }
          cexception_catch {
              delete_tnode( type_tnode );
              cexception_reraise( inner, px );
          }
          compiler_compile_sti( compiler_cc, px );
      }
;

file_io_statement

  : '<' expression '>' __RIGHT_TO_LEFT expression
      {
       compiler_check_and_compile_top_operator( compiler_cc, "<<", 2, px );
       compiler_emit( compiler_cc, px, "\n" );
      }

  | '<' expression '>'
      {
	  compiler_push_thrcode( compiler_cc, px );
      } 
    __LEFT_TO_RIGHT lvariable
      {
	  compiler_compile_file_input_operator( compiler_cc, px );
      }

  | file_io_statement __RIGHT_TO_LEFT expression
      {
        compiler_check_and_compile_top_operator( compiler_cc, "<<", 2, px );
        compiler_emit( compiler_cc, px, "\n" );
      }

  | file_io_statement __LEFT_TO_RIGHT
      {
        compiler_push_thrcode( compiler_cc, px );
      }
    lvariable
      {
	compiler_compile_file_input_operator( compiler_cc, px );
      }
  ;

variable_declaration_keyword
  : _VAR { $$ = 0; }
  | _READONLY { $$ = 1; }
  | _READONLY _VAR { $$ = 1; }
  ;

opt_variable_declaration_keyword
  : variable_declaration_keyword
  | /* empty */
      { $$ = 0; }
;

variable_declaration
  : variable_declaration_keyword variable_identifier ':' var_type_description
    {
     int readonly = $1;

     dnode_list_append_type( $2, $4 );
     dnode_list_assign_offsets( $2, &compiler_cc->local_offset );
     compiler_vartab_insert_named_vars( compiler_cc, $2, px );
     if( readonly ) {
	 dnode_list_set_flags( $2, DF_IS_READONLY );
     }
     if( compiler_cc->loops ) {
	 compiler_compile_zero_out_stackcells( compiler_cc, $2, px );
     }
     compiler_check_non_null_variables( $2 );
    }
  | variable_declaration_keyword 
    variable_identifier ',' variable_identifier_list ':' var_type_description
    {
     int readonly = $1;

     $2 = dnode_append( $2, $4 );
     dnode_list_append_type( $2, $6 );
     dnode_list_assign_offsets( $2, &compiler_cc->local_offset );
     compiler_vartab_insert_named_vars( compiler_cc, $2, px );
     if( readonly ) {
	 dnode_list_set_flags( $2, DF_IS_READONLY );
     }
     if( compiler_cc->loops ) {
	 compiler_compile_zero_out_stackcells( compiler_cc, $2, px );
     }
     compiler_check_non_null_variables( $2 );
    }
  | variable_declaration_keyword
    variable_identifier ':' var_type_description initialiser
    {
     int readonly = $1;
     DNODE *var = $2;

     dnode_list_append_type( var, $4 );
     dnode_list_assign_offsets( var, &compiler_cc->local_offset );
     compiler_vartab_insert_named_vars( compiler_cc, $2, px );
     if( readonly ) {
	 dnode_list_set_flags( var, DF_IS_READONLY );
     }
     compiler_compile_initialise_variable( compiler_cc, var, px );
    }

  | variable_declaration_keyword variable_identifier ','
    variable_identifier_list ':' var_type_description '=' multivalue_expression_list
    {
     int readonly = $1;
     int expr_nr = $8;

     $2 = dnode_list_invert( dnode_append( $2, $4 ));
     dnode_list_append_type( $2, $6 );
     dnode_list_assign_offsets( $2, &compiler_cc->local_offset );
     compiler_vartab_insert_named_vars( compiler_cc, $2, px );
     if( readonly ) {
	 dnode_list_set_flags( $2, DF_IS_READONLY );
     }
     {
	 DNODE *var;
	 DNODE *lst = $2;
	 int len = dnode_list_length( lst );         

         if( expr_nr < len ) {
             yyerrorf( "number of expressions (%d) is less "
                       "the number of variables (%d)", expr_nr, len );
         }

         if( expr_nr > len ) {
             if( expr_nr == len + 1 ) {
                 compiler_compile_drop( compiler_cc, px );
             } else {
                 compiler_compile_dropn( compiler_cc, expr_nr - len, px );
             }
         }

         len = 0;
         foreach_dnode( var, lst ) {
             len ++;
             if( len <= expr_nr )
                 compiler_compile_initialise_variable( compiler_cc, var, px );
         }
     }
    }

  | variable_declaration_keyword variable_identifier ','
    variable_identifier_list ':' var_type_description '=' simple_expression
    {
        yyerrorf( "need more than one expression to initialise %d variables",
                  dnode_list_length( $4 ) + 1 );

        $2 = dnode_list_invert( dnode_append( $2, $4 ));
        dnode_list_append_type( $2, $6 );
        dnode_list_assign_offsets( $2, &compiler_cc->local_offset );
        compiler_vartab_insert_named_vars( compiler_cc, $2, px );
    }

  | variable_declaration_keyword var_type_description variable_declarator_list
      {
        int readonly = $1;

	dnode_list_append_type( $3, $2 );
	dnode_list_assign_offsets( $3, &compiler_cc->local_offset );
	compiler_vartab_insert_named_vars( compiler_cc, $3, px );
	if( readonly ) {
	    dnode_list_set_flags( $3, DF_IS_READONLY );
	}
	if( compiler_cc->loops ) {
	    compiler_compile_zero_out_stackcells( compiler_cc, $3, px );
	}
	compiler_compile_variable_initialisations( compiler_cc, $3, px );
      }

  | variable_declaration_keyword 
    compact_type_description dimension_list variable_declarator_list
      {
        int readonly = $1;

	tnode_append_element_type( $3, $2 );
	dnode_list_append_type( $4, $3 );
	dnode_list_assign_offsets( $4, &compiler_cc->local_offset );
	compiler_vartab_insert_named_vars( compiler_cc, $4, px );
	if( readonly ) {
	    dnode_list_set_flags( $4, DF_IS_READONLY );
	}
	if( compiler_cc->loops ) {
	    compiler_compile_zero_out_stackcells( compiler_cc, $4, px );
	}
	compiler_compile_variable_initialisations( compiler_cc, $4, px );
      }

  | variable_declaration_keyword variable_identifier initialiser
    {
     TNODE *expr_type = compiler_cc->e_stack ?
	 share_tnode( enode_type( compiler_cc->e_stack )) : NULL;
     int readonly = $1;
     DNODE *var = $2;

     type_kind_t expr_type_kind = expr_type ?
         tnode_kind( expr_type ) : TK_NONE;

     if( expr_type_kind == TK_FUNCTION ||
         expr_type_kind == TK_OPERATOR ||
         expr_type_kind == TK_METHOD ) {
         TNODE *base_type = typetab_lookup( compiler_cc->typetab, "procedure" );
         expr_type = new_tnode_function_or_proc_ref
             ( share_dnode( tnode_args( expr_type )),
               share_dnode( tnode_retvals( expr_type )),
               share_tnode( base_type ),
               px );
     }

     dnode_list_append_type( var, expr_type );
     dnode_list_assign_offsets( var, &compiler_cc->local_offset );
     compiler_vartab_insert_named_vars( compiler_cc, var, px );
     if( readonly ) {
	 dnode_list_set_flags( var, DF_IS_READONLY );
     }
     compiler_compile_initialise_variable( compiler_cc, var, px );
    }
 
 | variable_declaration_keyword variable_identifier ','
    variable_identifier_list '=' multivalue_expression_list
    {
     int readonly = $1;

     $2 = dnode_list_invert( dnode_append( $2, $4 ));
     dnode_list_assign_offsets( $2, &compiler_cc->local_offset );
     compiler_vartab_insert_named_vars( compiler_cc, $2, px );
     if( readonly ) {
	 dnode_list_set_flags( $2, DF_IS_READONLY );
     }
     {
	 DNODE *var;
	 DNODE *lst = $2;
         ssize_t len = dnode_list_length( lst );
         ssize_t expr_nr = $6;

         if( expr_nr < len ) {
             yyerrorf( "number of expressions (%d) is less than "
                       "is needed to initialise %d variables",
                       expr_nr, len );
         }

         if( expr_nr > len ) {
             if( expr_nr == len + 1 ) {
                 compiler_compile_drop( compiler_cc, px );
             } else {
                 compiler_compile_dropn( compiler_cc, expr_nr - len, px );
             }
         }

         len = 0;
	 foreach_dnode( var, lst ) {
             len ++;
             TNODE *expr_type = compiler_cc->e_stack ?
                 share_tnode( enode_type( compiler_cc->e_stack )) : NULL;
             type_kind_t expr_type_kind = expr_type ?
                 tnode_kind( expr_type ) : TK_NONE;
             if( expr_type_kind == TK_FUNCTION ||
                 expr_type_kind == TK_OPERATOR ||
                 expr_type_kind == TK_METHOD ) {
                 TNODE *base_type = typetab_lookup( compiler_cc->typetab, "procedure" );
                 expr_type = new_tnode_function_or_proc_ref
                     ( share_dnode( tnode_args( expr_type )),
                       share_dnode( tnode_retvals( expr_type )),
                       share_tnode( base_type ),
                       px );
             }
             dnode_append_type( var, expr_type );
             if( len <= expr_nr )
                 compiler_compile_initialise_variable( compiler_cc, var, px );
	 }
     }
    }

  ;

variable_declarator_list
  : variable_declarator
  | variable_declarator '=' expression
      { $$ = dnode_set_flags( $1, DF_HAS_INITIALISER ); }
  | variable_declarator_list ',' variable_declarator
      { $$ = dnode_append( $3, $1 ); /* build list in the inverted order */ }
  | variable_declarator_list ',' variable_declarator '=' expression
      {
	dnode_set_flags( $3, DF_HAS_INITIALISER );
	$$ = dnode_append( $3, $1 ); /* build list in the inverted order */ 
      }
  ;

uninitialised_var_declarator_list
  : variable_declarator
  | uninitialised_var_declarator_list ',' variable_declarator
      { $$ = dnode_append( $1, $3 ); }
  ;

variable_declarator
  : variable_identifier
  | variable_identifier dimension_list
      { $$ = dnode_insert_type( $1, $2 ); }
  ;

variable_identifier_list
  : variable_identifier
    { $$ = $1; }
  | variable_identifier_list ',' variable_identifier
    { $$ = dnode_append( $1, $3 ); }
  ;

return_statement
  : _RETURN
      {
	compiler_push_guarding_retval( compiler_cc, px );
	compiler_compile_return( compiler_cc, 0, px );
      }
  | _RETURN 
      {
	if( compiler_cc->loops ) {
            char *name = dnode_name( compiler_cc->loops );
	    compiler_drop_loop_counters( compiler_cc, name, 0, px );
	}
        compiler_push_guarding_retval( compiler_cc, px );
      }
    expression_list
      { compiler_compile_return( compiler_cc, $3, px ); }
  ;

variable_identifier
  : __IDENTIFIER
     { $$ = new_dnode_name( $1, px ); }
  ;

/*--------------------------------------------------------------------------*/

opt_label
  : __IDENTIFIER ':'
      { $$ = $1; }
  |
      { $$ = NULL; }
  ;

if_condition
  : _IF /* expression */ {} condition
      {
        compiler_push_relative_fixup( compiler_cc, px );
	compiler_compile_jz( compiler_cc, 0, px );
      }
  ;

for_variable_declaration
  : variable_identifier ':' var_type_description
      {
	  dnode_append_type( $1, $3 );
	  dnode_assign_offset( $1, &compiler_cc->local_offset );
	  $$ = $1;
      }
  | var_type_description variable_identifier
      {
	  dnode_append_type( $2, $1 );
	  dnode_assign_offset( $2, &compiler_cc->local_offset );
	  $$ = $2;
      }
  | variable_identifier
      {
	  $$ = $1;
      }
  ;

elsif_condition
  : _ELSIF /* expression */ {} condition
      {
        compiler_push_relative_fixup( compiler_cc, px );
	compiler_compile_jz( compiler_cc, 0, px );
      }
  ;

elsif_statement
  : elsif_condition _THEN statement_list _ENDIF
    {
        compiler_fixup_here( compiler_cc );
    }

  | elsif_condition _THEN statement_list
    {
	ssize_t zero = 0;
        compiler_push_relative_fixup( compiler_cc, px );
        compiler_emit( compiler_cc, px, "\tce\n", JMP, &zero );
        compiler_swap_fixups( compiler_cc );
        compiler_fixup_here( compiler_cc );
    }
    elsif_statement
    {
        compiler_fixup_here( compiler_cc );
    }

  | elsif_condition _THEN statement_list
    {
	ssize_t zero = 0;
        compiler_push_relative_fixup( compiler_cc, px );
        compiler_emit( compiler_cc, px, "\tce\n", JMP, &zero );
        compiler_swap_fixups( compiler_cc );
        compiler_fixup_here( compiler_cc );
    }
    _ELSE statement_list _ENDIF
    {
        compiler_fixup_here( compiler_cc );
    }
;

control_statement
  : if_condition _THEN statement_list _ENDIF
      {
        compiler_fixup_here( compiler_cc );
      }

  | if_condition _THEN statement_list
      {
	ssize_t zero = 0;
        compiler_push_relative_fixup( compiler_cc, px );
        compiler_emit( compiler_cc, px, "\tce\n", JMP, &zero );
        compiler_swap_fixups( compiler_cc );
        compiler_fixup_here( compiler_cc );
      }
    _ELSE statement_list _ENDIF
      {
        compiler_fixup_here( compiler_cc );
      }

  | if_condition _THEN statement_list
      {
	ssize_t zero = 0;
        compiler_push_relative_fixup( compiler_cc, px );
        compiler_emit( compiler_cc, px, "\tce\n", JMP, &zero );
        compiler_swap_fixups( compiler_cc );
        compiler_fixup_here( compiler_cc );
      }
    elsif_statement
      {
        compiler_fixup_here( compiler_cc );
      }

  | if_condition compound_statement
      {
        compiler_fixup_here( compiler_cc );
      }

  | if_condition compound_statement _ELSE 
      {
	ssize_t zero = 0;
        compiler_push_relative_fixup( compiler_cc, px );
        compiler_emit( compiler_cc, px, "\tce\n", JMP, &zero );
        compiler_swap_fixups( compiler_cc );
        compiler_fixup_here( compiler_cc );
      }
    compound_statement
      {
        compiler_fixup_here( compiler_cc );
      }

  | opt_label _WHILE
      {
	  ssize_t zero = 0;
          compiler_begin_subscope( compiler_cc, px );
	  compiler_push_loop( compiler_cc, $1, 0, px );
          compiler_push_relative_fixup( compiler_cc, px );
	  compiler_emit( compiler_cc, px, "\tce\n", JMP, &zero );
	  compiler_push_current_address( compiler_cc, px );
	  compiler_push_thrcode( compiler_cc, px );
      }
    condition
      {
	compiler_swap_thrcodes( compiler_cc );
      }
    loop_body
      {
        compiler_fixup_here( compiler_cc );
	compiler_fixup_op_continue( compiler_cc, px );
	compiler_merge_top_thrcodes( compiler_cc, px );
	compiler_compile_jnz( compiler_cc, compiler_pop_offset( compiler_cc, px ), px );
	compiler_fixup_op_break( compiler_cc, px );
	compiler_pop_loop( compiler_cc );
        compiler_end_subscope( compiler_cc, px );
      }

  | opt_label _FOR
      {
	compiler_begin_subscope( compiler_cc, px );
      } 
    '(' statement ';'
      {
        compiler_push_loop( compiler_cc, $1, 0, px );
	compiler_push_thrcode( compiler_cc, px );
      }
    condition ';'
      {
	compiler_push_thrcode( compiler_cc, px );
      }
    statement ')'
      {
        ssize_t zero = 0;
	compiler_push_thrcode( compiler_cc, px );
        compiler_push_relative_fixup( compiler_cc, px );
	compiler_emit( compiler_cc, px, "\tce\n", JMP, &zero );
      }
    loop_body
      {
	compiler_fixup_op_continue( compiler_cc, px );
	compiler_merge_top_thrcodes( compiler_cc, px );

        compiler_fixup_here( compiler_cc );
	compiler_merge_top_thrcodes( compiler_cc, px );

	compiler_compile_jnz( compiler_cc, -compiler_code_length( compiler_cc ) + 2, px );

	compiler_swap_thrcodes( compiler_cc );
	compiler_merge_top_thrcodes( compiler_cc, px );
	compiler_fixup_op_break( compiler_cc, px );
	compiler_pop_loop( compiler_cc );
	compiler_end_subscope( compiler_cc, px );
      }

  | opt_label _FOR lvariable
      {
        compiler_push_loop( compiler_cc, $1, 2, px );
	dnode_set_flags( compiler_cc->loops, DF_LOOP_HAS_VAL );
	compiler_compile_dup( compiler_cc, px );
      }
    '=' expression
      {
        compiler_compile_sti( compiler_cc, px );
      }
    _TO expression
      {
	compiler_compile_over( compiler_cc, px );
	compiler_compile_ldi( compiler_cc, px );
	compiler_compile_over( compiler_cc, px );
	if( compiler_test_top_types_are_identical( compiler_cc, px )) {
	    compiler_compile_binop( compiler_cc, ">", px );
	    compiler_push_relative_fixup( compiler_cc, px );
	    compiler_compile_jnz( compiler_cc, 0, px );
	} else {
	    ssize_t zero = 0;
	    compiler_drop_top_expression( compiler_cc );
	    compiler_drop_top_expression( compiler_cc );
	    compiler_push_relative_fixup( compiler_cc, px );
	    compiler_emit( compiler_cc, px, "\tce\n", JMP, &zero );
	}

        compiler_push_current_address( compiler_cc, px );
      }
     loop_body
      {
	compiler_fixup_here( compiler_cc );
	compiler_fixup_op_continue( compiler_cc, px );
	compiler_compile_loop( compiler_cc, compiler_pop_offset( compiler_cc, px ), px );
	compiler_fixup_op_break( compiler_cc, px );
	compiler_pop_loop( compiler_cc );
      }

  | opt_label _FOR variable_declaration_keyword
      {
	compiler_begin_subscope( compiler_cc, px );
      }
    for_variable_declaration
      {
	int readonly = $3;
	if( readonly ) {
	    dnode_set_flags( $5, DF_IS_READONLY );
	}
	compiler_push_loop( compiler_cc, $1, 2, px );
	dnode_set_flags( compiler_cc->loops, DF_LOOP_HAS_VAL );
      }
    '=' expression
      {
	DNODE *loop_counter = $5;

	if( dnode_type( loop_counter ) == NULL ) {
	    dnode_append_type( loop_counter,
			       share_tnode( enode_type( compiler_cc->e_stack )));
	    dnode_assign_offset( loop_counter, &compiler_cc->local_offset );
	}
	compiler_vartab_insert_named_vars( compiler_cc, loop_counter, px );
        compiler_compile_store_variable( compiler_cc, loop_counter, px );
	compiler_compile_load_variable_address( compiler_cc, loop_counter, px );
      }
    _TO expression
      {
	compiler_compile_over( compiler_cc, px );
	compiler_compile_ldi( compiler_cc, px );
	compiler_compile_over( compiler_cc, px );
	if( compiler_test_top_types_are_identical( compiler_cc, px )) {
	    compiler_compile_binop( compiler_cc, ">", px );
	    compiler_push_relative_fixup( compiler_cc, px );
	    compiler_compile_jnz( compiler_cc, 0, px );
	} else {
	    ssize_t zero = 0;
	    compiler_drop_top_expression( compiler_cc );
	    compiler_drop_top_expression( compiler_cc );
	    compiler_push_relative_fixup( compiler_cc, px );
	    compiler_emit( compiler_cc, px, "\tce\n", JMP, &zero );
	}

        compiler_push_current_address( compiler_cc, px );
      }
     loop_body
      {
	compiler_fixup_here( compiler_cc );
	compiler_fixup_op_continue( compiler_cc, px );
	compiler_compile_loop( compiler_cc, compiler_pop_offset( compiler_cc, px ), px );
	compiler_fixup_op_break( compiler_cc, px );
	compiler_pop_loop( compiler_cc );
	compiler_end_subscope( compiler_cc, px );
      }

  | opt_label _FOREACH variable_declaration_keyword
      {
        compiler_begin_subscope( compiler_cc, px );
      }
    for_variable_declaration
      {
	int readonly = $3;
	if( readonly ) {
	    dnode_set_flags( $5, DF_IS_READONLY );
	}
	compiler_push_loop( compiler_cc, $1, 2, px );
	dnode_set_flags( compiler_cc->loops, DF_LOOP_HAS_VAL );
      }
    _IN expression
      {
	DNODE *loop_counter_var = $5;
        TNODE *aggregate_expression_type = enode_type( compiler_cc->e_stack );
        TNODE *element_type = 
            aggregate_expression_type ?
            tnode_element_type( aggregate_expression_type ) : NULL;

        if( element_type ) {
            if( dnode_type( loop_counter_var ) == NULL ) {
                dnode_append_type( loop_counter_var,
                                   share_tnode( element_type ));
            }
            dnode_assign_offset( loop_counter_var,
                                 &compiler_cc->local_offset );
        }

	compiler_vartab_insert_named_vars( compiler_cc, loop_counter_var, px );

        /* Load array limit onto the stack, for compiling the loop operator: */
        compiler_compile_dup( compiler_cc, px );
        compiler_compile_dup( compiler_cc, px );
        compiler_emit( compiler_cc, px, "\tc\n", LLENGTH );
        compiler_emit( compiler_cc, px, "\tc\n", LINDEX );
        compiler_drop_top_expression( compiler_cc );
        compiler_compile_swap( compiler_cc, px );

	if( compiler_test_top_types_are_identical( compiler_cc, px )) {
            cexception_t inner;
            TNODE *volatile bool_tnode =
                typetab_lookup( compiler_cc->typetab, "bool" );
            compiler_compile_over( compiler_cc, px );
            compiler_compile_over( compiler_cc, px );
            compiler_emit( compiler_cc, px, "\tc\n", PEQBOOL );
            compiler_drop_top_expression( compiler_cc );
            compiler_drop_top_expression( compiler_cc );
            cexception_guard( inner ) {
                compiler_push_type( compiler_cc, share_tnode( bool_tnode ),
                                    &inner );
            }
            cexception_catch {
                delete_tnode( bool_tnode );
                cexception_reraise( inner, px );
            }
	    compiler_push_relative_fixup( compiler_cc, px );
	    compiler_compile_jnz( compiler_cc, 0, px );
	} else {
	    ssize_t zero = 0;
	    compiler_push_relative_fixup( compiler_cc, px );
	    compiler_emit( compiler_cc, px, "\tce\n", JMP, &zero );
	}

        compiler_push_current_address( compiler_cc, px );

        /* Store the current array element into the loop variable: */
        compiler_compile_dup( compiler_cc, px );
        compiler_make_stack_top_element_type( compiler_cc );
        compiler_make_stack_top_addressof( compiler_cc, px );
        compiler_compile_ldi( compiler_cc, px );
        compiler_compile_variable_initialisation
            ( compiler_cc, loop_counter_var, px );
      }
     loop_body
      {
	int readonly = $3;
	DNODE *loop_counter_var = $5;
        /* Store the the loop variable back into the current array element: */
        if( !readonly ) {
            compiler_compile_dup( compiler_cc, px );
            compiler_make_stack_top_element_type( compiler_cc );
            compiler_make_stack_top_addressof( compiler_cc, px );
            compiler_compile_load_variable_value( compiler_cc,
                                                  loop_counter_var, px );
            compiler_compile_sti( compiler_cc, px );
        }

	compiler_fixup_op_continue( compiler_cc, px );
	compiler_compile_next( compiler_cc, px );

        compiler_fixup_here( compiler_cc );
	compiler_fixup_op_break( compiler_cc, px );
	compiler_pop_loop( compiler_cc );
	compiler_end_subscope( compiler_cc, px );
      }

  | opt_label _FOREACH lvariable
      {
        compiler_push_loop( compiler_cc, $1, 3, px );
	dnode_set_flags( compiler_cc->loops, DF_LOOP_HAS_VAL );
        /* stack now:
           ..., lvariable_address */
      }
    _IN expression
      {
        /* stack now:
           ..., lvariable_address, array_last_ptr */

        /* Load array limit onto the stack, for compiling the loop operator: */
        compiler_compile_dup( compiler_cc, px );
        compiler_compile_dup( compiler_cc, px );
        compiler_emit( compiler_cc, px, "\tc\n", LLENGTH );
        compiler_emit( compiler_cc, px, "\tc\n", LINDEX );
        compiler_drop_top_expression( compiler_cc );
        compiler_compile_swap( compiler_cc, px );
        /* stack now:
           ..., lvariable_address, array_last_ptr, array_current_ptr */

	if( compiler_test_top_types_are_identical( compiler_cc, px )) {
            cexception_t inner;
            TNODE *volatile bool_tnode =
                typetab_lookup( compiler_cc->typetab, "bool" );
            compiler_compile_over( compiler_cc, px );
            compiler_compile_over( compiler_cc, px );
            compiler_emit( compiler_cc, px, "\tc\n", PEQBOOL );
            compiler_drop_top_expression( compiler_cc );
            compiler_drop_top_expression( compiler_cc );
            cexception_guard( inner ) {
                compiler_push_type( compiler_cc, share_tnode( bool_tnode ),
                                    &inner );
            }
            cexception_catch {
                delete_tnode( bool_tnode );
                cexception_reraise( inner, px );
            }
	    compiler_push_relative_fixup( compiler_cc, px );
	    compiler_compile_jnz( compiler_cc, 0, px );
	} else {
	    ssize_t zero = 0;
	    compiler_push_relative_fixup( compiler_cc, px );
	    compiler_emit( compiler_cc, px, "\tce\n", JMP, &zero );
	}

        /* The execution flow should return here after each iteration: */
        compiler_push_current_address( compiler_cc, px );

        /* Store the current array element into the loop variable: */
        /* stack now:
           ..., lvariable_address, array_last_ptr, array_current_ptr */
        compiler_compile_swap( compiler_cc, px );
        compiler_emit( compiler_cc, px, "\tc\n", TOR );
        ENODE *top_enode = enode_list_pop( &compiler_cc->e_stack );
        /* stack now:
           ..., lvariable_address, array_current_ptr */
        compiler_compile_over( compiler_cc, px );
        compiler_compile_over( compiler_cc, px );
        compiler_make_stack_top_element_type( compiler_cc );
        compiler_make_stack_top_addressof( compiler_cc, px );
        compiler_compile_ldi( compiler_cc, px );
        compiler_compile_sti( compiler_cc, px );
        compiler_emit( compiler_cc, px, "\tc\n", FROMR );
        enode_list_push( &compiler_cc->e_stack, top_enode );
        compiler_compile_swap( compiler_cc, px );
        /* stack now:
           ..., lvariable_address, array_last_ptr, array_current_ptr */
      }
     loop_body
      {
        ENODE *loop_var = compiler_cc->e_stack; /* array_current_ptr */
        loop_var = loop_var ? enode_next( loop_var ) : NULL; /* array_last_ptr */
        loop_var = loop_var ? enode_next( loop_var ) : NULL; /* lvariable_address */
        
        if( loop_var && !enode_has_flags( loop_var, EF_IS_READONLY )) {
            /* Store the current array element into the loop variable: */
            /* stack now:
               ..., lvariable_address, array_last_ptr, array_current_ptr */
            compiler_compile_swap( compiler_cc, px );
            compiler_emit( compiler_cc, px, "\tc\n", TOR );
            ENODE *top_enode = enode_list_pop( &compiler_cc->e_stack );
            /* stack now:
               ..., lvariable_address, array_current_ptr */
            compiler_compile_over( compiler_cc, px );
            compiler_compile_over( compiler_cc, px );
            compiler_make_stack_top_element_type( compiler_cc );
            compiler_make_stack_top_addressof( compiler_cc, px );
            compiler_compile_swap( compiler_cc, px );
            compiler_compile_ldi( compiler_cc, px );
            compiler_compile_sti( compiler_cc, px );
            compiler_emit( compiler_cc, px, "\tc\n", FROMR );
            enode_list_push( &compiler_cc->e_stack, top_enode );
            compiler_compile_swap( compiler_cc, px );
            /* stack now:
               ..., lvariable_address, array_last_ptr, array_current_ptr */
        }

	compiler_fixup_here( compiler_cc );
	compiler_fixup_op_continue( compiler_cc, px );
	compiler_compile_next( compiler_cc, px );

	compiler_fixup_op_break( compiler_cc, px );
	compiler_pop_loop( compiler_cc );
      }

  | _TRY
      {
	cexception_t inner;
	ssize_t zero = 0;
	ssize_t try_var_offset = compiler_cc->local_offset--;

	push_ssize_t( &compiler_cc->try_variable_stack, &compiler_cc->try_block_level,
		      try_var_offset, px );

	push_ssize_t( &compiler_cc->catch_jumpover_stack,
		      &compiler_cc->catch_jumpover_stack_length,
		      compiler_cc->catch_jumpover_nr, px );

	compiler_cc->catch_jumpover_nr = 0;

	cexception_guard( inner ) {
	    compiler_push_relative_fixup( compiler_cc, &inner );
	    compiler_emit( compiler_cc, px, "\tcee\n", TRY, &zero, &try_var_offset );
	}
	cexception_catch {
	    cexception_reraise( inner, px );
	}
      }
    compound_statement
      {
	ssize_t zero = 0;
	compiler_emit( compiler_cc, px, "\tc\n", RESTORE );
	compiler_push_relative_fixup( compiler_cc, px );
	compiler_emit( compiler_cc, px, "\tce\n", JMP, &zero );
	compiler_swap_fixups( compiler_cc );
	compiler_fixup_here( compiler_cc );
      }
    opt_catch_list
      {
	int i;

	for( i = 0; i < compiler_cc->catch_jumpover_nr; i ++ ) { 
	    compiler_fixup_here( compiler_cc );
	}
	
	compiler_cc->catch_jumpover_nr = 
	    pop_ssize_t( &compiler_cc->catch_jumpover_stack, 
			 &compiler_cc->catch_jumpover_stack_length, px );

	compiler_fixup_here( compiler_cc );
	pop_ssize_t( &compiler_cc->try_variable_stack,
		     &compiler_cc->try_block_level, px );
      }

  ;

compound_statement
  : '{'
      {
	compiler_begin_subscope( compiler_cc, px );
      }
    statement_list '}'
      {
	compiler_end_subscope( compiler_cc, px );
      }
  ;

loop_body
  : _DO
      {
	compiler_begin_subscope( compiler_cc, px );
      }
    statement_list
      {
	compiler_end_subscope( compiler_cc, px );
      }
    _ENDDO
  | compound_statement
  ;

opt_catch_list
  : catch_list
  | /* empty */
  ; 

catch_list
  : catch_statement
  | catch_list catch_statement
  ;

catch_var_identifier
  : __IDENTIFIER
    {
     char *opname = "exceptionval";
     ssize_t try_var_offset = compiler_cc->try_variable_stack ?
	 compiler_cc->try_variable_stack[compiler_cc->try_block_level-1] : 0;
     DNODE *catch_var = vartab_lookup( compiler_cc->vartab, $1 );
     TNODE *catch_var_type = catch_var ? dnode_type( catch_var ) : NULL;

     if( !catch_var_type ||
         !compiler_lookup_operator( compiler_cc, catch_var_type, opname, 1, px )) {
	 yyerrorf( "type of variable in a 'catch' clause must "
		   "have unary '%s' operator", opname );
     } else {
	 compiler_emit( compiler_cc, px, "\n\tce\n", PLD, &try_var_offset );
	 compiler_push_type( compiler_cc, new_tnode_ref( px ), px );
	 compiler_check_and_compile_operator( compiler_cc, catch_var_type,
					   opname, /*arity:*/1,
					   /*fixup_values:*/ NULL,
					   px );
	 compiler_emit( compiler_cc, px, "\n" );
	 compiler_compile_variable_assignment( compiler_cc, catch_var, px );
     }
    }
  ;

catch_variable_declaration
  : _VAR variable_identifier_list ':' var_type_description
    {
     char *opname = "exceptionval";
     ssize_t try_var_offset = compiler_cc->try_variable_stack ?
	 compiler_cc->try_variable_stack[compiler_cc->try_block_level-1] : 0;

     dnode_list_append_type( $2, $4 );
     dnode_list_assign_offsets( $2, &compiler_cc->local_offset );     
     if( $2 && dnode_list_length( $2 ) > 1 ) {
	 yyerrorf( "only one variable may be declared in the 'catch' clause" );
     }
     if( !$4 || !compiler_lookup_operator( compiler_cc, $4, opname, 1, px )) {
	 yyerrorf( "type of variable declared in a 'catch' clause must "
		   "have unary '%s' operator", opname );
     } else {
	 compiler_emit( compiler_cc, px, "\n\tce\n", PLD, &try_var_offset );
	 compiler_push_type( compiler_cc, new_tnode_ref( px ), px );
	 compiler_check_and_compile_operator( compiler_cc, $4, opname,
					   /*arity:*/1,
					   /*fixup_values:*/ NULL, px );
	 compiler_emit( compiler_cc, px, "\n" );
	 compiler_compile_variable_assignment( compiler_cc, $2, px );	 
     }
     vartab_insert_named_vars( compiler_cc->vartab, $2, px );
    }
  ;

catch_variable_list
  : catch_var_identifier
  | catch_variable_declaration
  | catch_variable_list ';' catch_var_identifier
  | catch_variable_list ';' catch_variable_declaration
;

exception_identifier_list
  : __IDENTIFIER
    {
      compiler_emit_catch_comparison( compiler_cc, NULL, $1, px );
      $$ = 0;
    }
  | module_list __COLON_COLON __IDENTIFIER
    {
      compiler_emit_catch_comparison( compiler_cc, $1, $3, px );
      $$ = 0;
    }
  | exception_identifier_list ',' __IDENTIFIER
    {
      ssize_t zero = 0;
      compiler_push_relative_fixup( compiler_cc, px );
      compiler_emit( compiler_cc, px, "\tce\n", BJNZ, &zero );
      compiler_emit_catch_comparison( compiler_cc, NULL, $3, px );
      $$ = $1 + 1;
    }
  | exception_identifier_list ',' module_list __COLON_COLON __IDENTIFIER
    {
      ssize_t zero = 0;
      compiler_push_relative_fixup( compiler_cc, px );
      compiler_emit( compiler_cc, px, "\tce\n", BJNZ, &zero );
      compiler_emit_catch_comparison( compiler_cc, $3, $5, px );
      $$ = $1 + 1;
    }
  ;

catch_statement
  : _CATCH
    compound_statement
      {
	ssize_t zero = 0;
	compiler_cc->catch_jumpover_nr ++;
	compiler_push_relative_fixup( compiler_cc, px );
	compiler_emit( compiler_cc, px, "\tce\n", JMP, &zero );
      }

  | _CATCH
      {
	compiler_begin_subscope( compiler_cc,  px );
      }
    '(' catch_variable_list ')'
    compound_statement
      {
	ssize_t zero = 0;
	compiler_cc->catch_jumpover_nr ++;
	compiler_push_relative_fixup( compiler_cc, px );
	compiler_emit( compiler_cc, px, "\tce\n", JMP, &zero );
	compiler_end_subscope( compiler_cc, px );
      }

  | _CATCH exception_identifier_list
      {
	compiler_finish_catch_comparisons( compiler_cc, $2, px );
	compiler_begin_subscope( compiler_cc,  px );
      }
    '(' catch_variable_list ')'  
    compound_statement
      {
	compiler_end_subscope( compiler_cc, px );
	compiler_finish_catch_block( compiler_cc, px );
      }

  | _CATCH exception_identifier_list
      {
	compiler_finish_catch_comparisons( compiler_cc, $2, px );
      }
    compound_statement
      {
	compiler_finish_catch_block( compiler_cc, px );
      }

;

/*--------------------------------------------------------------------------*/

compact_type_description
  : delimited_type_description
  | undelimited_or_structure_description
  ;

var_type_description
  : delimited_type_description
  | undelimited_or_structure_description
  | _ARRAY
    { $$ = new_tnode_array_snail( NULL, compiler_cc->typetab, px ); }
  ;

undelimited_or_structure_description
  : struct_description
  | class_description
  | struct_or_class_description_body
  | undelimited_type_description
  ;

type_identifier
  : __IDENTIFIER
     {
	 $$ = compiler_lookup_tnode( compiler_cc, NULL, $1, "type" );
     }
  | module_list __COLON_COLON __IDENTIFIER
     {
	 $$ = compiler_lookup_tnode( compiler_cc, $1, $3, "type" );
     }
  ;

opt_null_type_designator
  : _NOT _NULL
      { $$ = 1; }
  | _NULL
      { $$ = 0; }
  | '*' /* synonim of 'not null' */
      { $$ = 1; }
  | '?' /* synonim of 'null' */
      { $$ = 0; }
  | /* default: 1 == not null, 0 == null */
      { $$ = 1; }
  ; 

delimited_type_description
  : type_identifier
    { 
       $$ = share_tnode( $1 );
    }

  | _LIKE type_identifier struct_or_class_description_body
    {
	$$ = new_tnode_synonim( share_tnode( $2 ), px );
	$$ = tnode_move_operators( $$, $3 );
	delete_tnode( $3 );
	$3 = NULL;
	assert( compiler_cc->current_type );
	tnode_set_suffix( $$, tnode_name( compiler_cc->current_type ), px );
    }

  | type_identifier _OF delimited_type_description
    {
      TNODE *composite = $1;
      $$ = new_tnode_synonim( composite, px );
      tnode_set_kind( $$, TK_COMPOSITE );
      tnode_insert_element_type( $$, $3 );
    }
  | _ADDRESSOF
    { $$ = new_tnode_addressof( NULL, px ); }

  | _ARRAY _OF delimited_type_description
    { $$ = new_tnode_array_snail( $3, compiler_cc->typetab, px ); }

  | _ARRAY dimension_list _OF delimited_type_description
    { $$ = tnode_append_element_type( $2, $4 ); }

  | _TYPE __IDENTIFIER
    {
	char *type_name = $2;
	TNODE *tnode = typetab_lookup( compiler_cc->typetab, type_name );
	if( !tnode ) {
	    tnode = new_tnode_placeholder( type_name, px );
	    tnode_set_size( tnode, 1 );
	    typetab_insert( compiler_cc->typetab, type_name, tnode, px );
	}
	$$ = share_tnode( tnode );
    }

  | function_or_procedure_type_keyword '(' argument_list ')'
    {
	int is_function = $1;
	TNODE *base_type = typetab_lookup( compiler_cc->typetab, "procedure" );

	share_tnode( base_type );
	$$ = new_tnode_function_or_proc_ref( $3, NULL, base_type, px );
	if( is_function ) {
	    compiler_set_function_arguments_readonly( $$ );
	}
    }
  | function_or_procedure_type_keyword '(' argument_list ')'
    __ARROW '(' retval_description_list ')'
    {
	int is_function = $1;
	TNODE *base_type = typetab_lookup( compiler_cc->typetab, "procedure" );

	share_tnode( base_type );
	$$ = new_tnode_function_or_proc_ref( $3, $7, base_type, px );
	if( is_function ) {
	    compiler_set_function_arguments_readonly( $$ );
	}
    }

  | _BLOB
    { $$ = new_tnode_blob_snail( compiler_cc->typetab, px ); }

  | _TYPE _OF _VAR
    { $$ = new_tnode_type_descriptor( px ); }
  ;


function_or_procedure_type_keyword
  : _FUNCTION
      { $$ = 1; }
  | _PROCEDURE
      { $$ = 0; }
  ;

opt_base_type
  : ':' type_identifier
      { $$ = $2; }
  | /* empty */
      { $$ = NULL; }
;

opt_implemented_interfaces
  : _IMPLEMENTS interface_identifier_list
  { $$ = $2; }
  | /* empty */
  { $$ = NULL; }
  ;

interface_identifier_list
  : type_identifier
  {
      TLIST *interfaces = NULL;
      if( $1 ) {
          share_tnode( $1 );
          tlist_push_tnode( &interfaces, &$1, px );
      }
      $$ = interfaces;
  }
  |  type_identifier ',' interface_identifier_list
  {
      if( $1 ) {
          share_tnode( $1 );
          tlist_push_tnode( &$3, &$1, px );
      }
      $$ = $3;
  }
  ;

struct_description
  : opt_null_type_designator _STRUCT struct_or_class_description_body
    {
        $$ = tnode_finish_struct( $3, px );
        if( $1 ) {
            tnode_set_flags( $$, TF_NON_NULL );
        }
    }
;

class_description
  : opt_null_type_designator _CLASS 
    {
        compiler_begin_subscope( compiler_cc, px );
    }
    struct_or_class_description_body
    {
        compiler_finish_virtual_method_table( compiler_cc, $4, px );
        $$ = tnode_finish_class( $4, px );
        if( $1 ) {
            tnode_set_flags( $$, TF_NON_NULL );
        }
        compiler_end_subscope( compiler_cc, px );
    }
;

undelimited_type_description
  : _ARRAY _OF undelimited_or_structure_description
    { $$ = new_tnode_array_snail( $3, compiler_cc->typetab, px ); }

  | _ARRAY dimension_list _OF undelimited_or_structure_description
    { $$ = tnode_append_element_type( $2, $4 ); }

  | type_identifier _OF undelimited_or_structure_description
    {
      TNODE *composite = $1;
      $$ = new_tnode_synonim( composite, px );
      tnode_insert_element_type( $$, $3 );
    }

  | '(' var_type_description ')'
    { $$ = $2; }

  | _ENUM __IDENTIFIER '(' enum_member_list ')'
    {
      TNODE *enum_implementing_type = typetab_lookup( compiler_cc->typetab, $2 );
      ssize_t tsize = enum_implementing_type ?
	  tnode_size( enum_implementing_type ) : 0;

      if( compiler_cc->current_type &&
	      tnode_is_forward( compiler_cc->current_type )) {
	  tnode_set_kind( compiler_cc->current_type, TK_ENUM );
	  tnode_set_size( compiler_cc->current_type, tsize );
      }
      $$ = tnode_finish_enum( $4, NULL, enum_implementing_type, px );
      compiler_check_enum_attributes( $$ );
    }

  | '(' __THREE_DOTS ',' enum_member_list ')'
    {
      if( !compiler_cc->current_type ||
	  tnode_is_forward( compiler_cc->current_type )) {
	  yyerror( "one can only extend previously defined enumeration types" );
	  tnode_set_size( $4, 1 );
      }
      $$ = $4;
    }
  ;

enum_member_list
  : enum_member
     {
       $$ = new_tnode( px );
       tnode_set_kind( $$, TK_ENUM );
       if( compiler_cc->current_type ) {
	   tnode_merge_field_lists( $$, compiler_cc->current_type );
       }
       tnode_insert_enum_value( $$, $1 );
     }

  | enum_member_list ',' enum_member
     { $$ = tnode_insert_enum_value( $1, $3 ); }
;

enum_member
  : __IDENTIFIER
    {
	$$ = new_dnode_name( $1, px );
    }
  | __IDENTIFIER '=' constant_integer_expression
    {
	$$ = new_dnode_name( $1, px );
	dnode_set_offset( $$, $3 );
    }
  | __THREE_DOTS
    {
	$$ = new_dnode_name( "...", px );
    }
  | /* empty */
    { $$ = NULL; }
  ;

struct_or_class_declaration_body
  : opt_base_type opt_implemented_interfaces
    '{' struct_declaration_field_list finish_fields '}'
    { $$ = $4; }
  | opt_base_type opt_implemented_interfaces
    '{' struct_declaration_field_list finish_fields 
    struct_operator_list '}'
    { $$ = $4; }
  | opt_base_type opt_implemented_interfaces
    '{' struct_declaration_field_list finish_fields 
    struct_operator_list ';' '}'
    { $$ = $4; }
  ;

finish_fields
  : 
  {
      TNODE *current_class = $<tnode>0;
      TLIST *interfaces = $<tlist>-2;
      TNODE *base_type = $<tnode>-3 ?
          $<tnode>-3 : typetab_lookup( compiler_cc->typetab, "struct" );

      if( current_class != base_type ) {
	  tnode_insert_base_type( current_class, share_tnode( base_type ));
          tnode_insert_interfaces( current_class, interfaces );
      }

      compiler_start_virtual_method_table( compiler_cc, current_class, px );

      $$ = current_class;
  }
;

struct_declaration_field_list
  : struct_field
     {
	 assert( compiler_cc->current_type );
	 $$ = share_tnode( compiler_cc->current_type );
         tnode_insert_type_member( $$, $1 );
     }
  | type_attribute
     {
       cexception_t inner;

       cexception_guard( inner ) {
	   assert( compiler_cc->current_type );
	   $$ = share_tnode( compiler_cc->current_type );
	   tnode_set_attribute( $$, $1, &inner );
       }
       cexception_catch {
	   delete_anode( $1 );
	   cexception_reraise( inner, px );
       }
       delete_anode( $1 );
     }
  | struct_declaration_field_list ';' struct_field
     {
         $$ = tnode_insert_type_member( $1, $3 );
     }
  | struct_declaration_field_list ';' type_attribute
     {
       cexception_t inner;

       cexception_guard( inner ) {
	   $$ = $1;
	   tnode_set_attribute( $$, $3, &inner );
       }
       cexception_catch {
	   delete_anode( $3 );
	   cexception_reraise( inner, px );
       }
       delete_anode( $3 );
     }
  ;

struct_or_class_description_body
  : opt_base_type opt_implemented_interfaces
    '{' struct_description_field_list finish_fields '}'
    { $$ = $4; }
  | opt_base_type opt_implemented_interfaces
    '{' struct_description_field_list finish_fields 
    struct_operator_list '}'
    { $$ = $4; }
  | opt_base_type opt_implemented_interfaces 
    '{' struct_description_field_list finish_fields
    struct_operator_list ';' '}'
    { $$ = $4; }
  ;

struct_description_field_list
  : struct_field
     {
	 $$ = new_tnode( px );
         tnode_insert_type_member( $$, $1 );
     }
  | type_attribute
     {
       cexception_t inner;

       cexception_guard( inner ) {
	   $$ = new_tnode( &inner );
	   tnode_set_attribute( $$, $1, &inner );
       }
       cexception_catch {
	   delete_anode( $1 );
	   cexception_reraise( inner, px );
       }
       delete_anode( $1 );
     }
  | struct_description_field_list ';' struct_field
     {
         $$ = tnode_insert_type_member( $1, $3 );
     }
  | struct_description_field_list ';' type_attribute
     {
       cexception_t inner;

       cexception_guard( inner ) {
	   $$ = $1;
	   tnode_set_attribute( $$, $3, &inner );
       }
       cexception_catch {
	   delete_anode( $3 );
	   cexception_reraise( inner, px );
       }
       delete_anode( $3 );
     }
  ;

struct_field
  : struct_var_declaration  { $$ = $1; }
  |                         { $$ = NULL; }
  ;

struct_operator_list
  : struct_operator
    {
	TNODE *struct_type = $<tnode>-1;
	tnode_insert_type_member( struct_type, $1 );
	$$ = struct_type;
    }
  | struct_operator_list struct_operator
    {
	tnode_insert_type_member( $1, $2 );
	$$ = $1;
    }
  | struct_operator_list ';' struct_operator
    {
	tnode_insert_type_member( $1, $3 );
	$$ = $1;
    }
;

struct_operator
  : operator_definition
  | method_definition
  | method_header
  | constructor_definition
  | constructor_header
  ;

interface_type_placeholder
  : /* empty */
     {
         assert( compiler_cc->current_type );
	 $$ = share_tnode( compiler_cc->current_type );
     }
  ;

interface_declaration_body
  : opt_base_type opt_implemented_interfaces '{'
    interface_type_placeholder finish_fields
    interface_operator_list '}'
    { $$ = $4; }
  | opt_base_type opt_implemented_interfaces '{'
    interface_type_placeholder finish_fields
    interface_operator_list ';' '}'
    { $$ = $4; }
  ;

interface_operator_list
  : interface_operator
    {
	TNODE *struct_type = compiler_cc->current_type;
	tnode_insert_type_member( struct_type, $1 );
	$$ = struct_type;
    }
  | interface_operator_list interface_operator
    {
	tnode_insert_type_member( $1, $2 );
	$$ = $1;
    }
  | interface_operator_list ';' interface_operator
    {
	tnode_insert_type_member( $1, $3 );
	$$ = $1;
    }
;

interface_operator
  : method_header
  ;

struct_var_declaration
  : variable_identifier_list ':' var_type_description
      {
       $$ = dnode_list_append_type( $1, $3 );
      }
  | _VAR variable_identifier_list ':' var_type_description
      {
       $$ = dnode_list_append_type( $2, $4 );
      }

  | _VAR var_type_description uninitialised_var_declarator_list
      {
        $$ = dnode_list_append_type( $3, $2 );
      }

  | var_type_description uninitialised_var_declarator_list
      {
        $$ = dnode_list_append_type( $2, $1 );
      }

  | _VAR compact_type_description dimension_list
    uninitialised_var_declarator_list
      {
	tnode_append_element_type( $3, $2 );
	$$ = dnode_list_append_type( $4, $3 );
      }

  | compact_type_description dimension_list uninitialised_var_declarator_list
      {
	tnode_append_element_type( $2, $1 );
	$$ = dnode_list_append_type( $3, $2 );
      }
  ;

size_constant
  : _SIZEOF type_identifier
    {
      TNODE *tnode = $2;

      if( tnode ) {
	  $$ = tnode_size( tnode );
      }
    }
  | _SIZEOF _NATIVE __STRING_CONST
    {
      $$ = compiler_native_type_size( $3 );
    }
  | _NATIVE __STRING_CONST /* _REF */ '*'
    {
      $$ = compiler_native_type_nreferences( $2 );
    }
  ;

type_attribute
  : __IDENTIFIER
    { $$ = new_anode_integer_attribute( $1, 1, px ); }
  | __IDENTIFIER '=' __INTEGER_CONST
    { $$ = new_anode_integer_attribute( $1, atol( $3 ), px ); }
  | __IDENTIFIER '=' size_constant
    { $$ = new_anode_integer_attribute( $1, $3, px ); }
  | __IDENTIFIER '=' __IDENTIFIER
    { $$ = new_anode_string_attribute( $1, $3, px ); }
  | __IDENTIFIER '=' __STRING_CONST
    { $$ = new_anode_string_attribute( $1, $3, px ); }
  ;

dimension_list
  : '[' ']'
    { $$ = new_tnode_array_snail( NULL, compiler_cc->typetab, px ); }
  | dimension_list '[' ']'
    {
      TNODE *array_type = new_tnode_array_snail( NULL, compiler_cc->typetab, px );
      $$ = tnode_append_element_type( $1, array_type );
    }
  ;

/*--------------------------------------------------------------------------*/

/* type_declaration */

type_declaration_name
  : __IDENTIFIER
    { $$ = $1; }

  | _STRUCT
    { $$ = "struct"; }

  | _ARRAY
    { $$ = "array"; }

  | _PROCEDURE
    { $$ = "procedure"; }

  | _BLOB
    { $$ = "blob"; }
;

type_declaration_start
  : _TYPE type_declaration_name
      {
	TNODE *old_tnode = typetab_lookup_silently( compiler_cc->typetab, $2 );
	TNODE *tnode = NULL;

	if( !old_tnode || !tnode_is_extendable_enum( old_tnode )) {
	    TNODE *tnode = new_tnode_forward( $2, px );
	    compiler_typetab_insert( compiler_cc, tnode, px );
	}
	tnode = typetab_lookup_silently( compiler_cc->typetab, $2 );
	assert( !compiler_cc->current_type );
	compiler_cc->current_type = tnode;
	compiler_begin_scope( compiler_cc, px );
      }
;

delimited_type_declaration
  : type_declaration_start '=' delimited_type_description
      {
	compiler_end_scope( compiler_cc, px );
	compiler_compile_type_declaration( compiler_cc, $3, px );
      }
  | type_declaration_start '=' delimited_type_description /*type_*/initialiser
      {
        compiler_compile_drop( compiler_cc, px );
	compiler_end_scope( compiler_cc, px );
	compiler_compile_type_declaration( compiler_cc, $3, px );
      }
  | type_declaration_start
      {
	compiler_end_scope( compiler_cc, px );
	compiler_cc->current_type = NULL;
      }
  | forward_struct_declaration
  | forward_class_declaration
  ;

undelimited_type_declaration
  : type_declaration_start '=' undelimited_type_description
      {
	compiler_end_scope( compiler_cc, px );
	compiler_compile_type_declaration( compiler_cc, $3, px );
	compiler_cc->current_type = NULL;
      }

  | type_declaration_start '=' undelimited_type_description type_initialiser
      {
	compiler_end_scope( compiler_cc, px );
	compiler_compile_type_declaration( compiler_cc, $3, px );
	compiler_cc->current_type = NULL;
      }

  | _TYPE __IDENTIFIER _OF __IDENTIFIER '='
      {
	TNODE * volatile base = NULL;
	TNODE * volatile tnode = NULL;
	cexception_t inner;

	// compiler_begin_scope( compiler_cc, px );

	cexception_guard( inner ) {
	    base = new_tnode_placeholder( $4, &inner );
	    tnode = new_tnode_composite( $2, base, &inner );
	    tnode_set_flags( tnode, TF_IS_FORWARD );
	    compiler_typetab_insert( compiler_cc, tnode, &inner );
	    tnode = typetab_lookup( compiler_cc->typetab, $2 );
	    compiler_cc->current_type = tnode;
	    compiler_typetab_insert( compiler_cc, share_tnode( base ), &inner );
	    compiler_begin_scope( compiler_cc, &inner );
	}
	cexception_catch {
	    delete_tnode( base );
	    delete_tnode( tnode );
	    cexception_reraise( inner, px );
	}
      }
    undelimited_type_description
      {
	compiler_end_scope( compiler_cc, px );
	compiler_compile_type_declaration( compiler_cc, $7, px );
	compiler_cc->current_type = NULL;
      }

  | struct_declaration
  | class_declaration
  | interface_declaration
  ;

struct_declaration
  : opt_null_type_designator _STRUCT __IDENTIFIER
    {
	TNODE *old_tnode = typetab_lookup( compiler_cc->typetab, $3 );
	TNODE *tnode = NULL;

	if( !old_tnode ) {
	    TNODE *tnode = new_tnode_forward_struct( $3, px );
            if( $1 ) {
                tnode_set_flags( tnode, TF_NON_NULL );
            }
	    compiler_typetab_insert( compiler_cc, tnode, px );
	} else {
            if( tnode_is_non_null_reference( old_tnode ) !=
                ($1 ? 1 : 0 )) {
                yyerrorf( "definition of forward structure '%s' "
                          "has different non-null flag", $3 );
            }
        }
	tnode = typetab_lookup( compiler_cc->typetab, $3 );
	assert( !compiler_cc->current_type );
	compiler_cc->current_type = tnode;
	compiler_begin_scope( compiler_cc, px );
    }
    struct_or_class_declaration_body
    {
	tnode_finish_struct( $5, px );
	compiler_end_scope( compiler_cc, px );
	compiler_typetab_insert( compiler_cc, $5, px );
        compiler_cc->current_type = NULL;
    }
  | type_declaration_start '=' opt_null_type_designator _STRUCT
    {
	assert( compiler_cc->current_type );
	tnode_set_flags( compiler_cc->current_type, TF_IS_REF );
        tnode_set_kind( compiler_cc->current_type, TK_STRUCT );
    }
    struct_or_class_declaration_body
    {
        if( $3 ) {
            tnode_set_flags( $6, TF_NON_NULL );
        }
	tnode_finish_struct( $6, px );
	compiler_end_scope( compiler_cc, px );
	compiler_compile_type_declaration( compiler_cc, $6, px );
        compiler_cc->current_type = NULL;
    }
  | type_declaration_start '=' opt_null_type_designator
    {
	assert( compiler_cc->current_type );
	// tnode_set_flags( compiler_cc->current_type, TF_IS_REF );
    }
    struct_or_class_declaration_body
    {
        if( $3 ) {
            tnode_set_flags( $5, TF_NON_NULL );
        }
	// tnode_finish_struct( $5, px );
	compiler_end_scope( compiler_cc, px );
	compiler_compile_type_declaration( compiler_cc, $5, px );
        compiler_cc->current_type = NULL;
    }
  | _TYPE __IDENTIFIER _OF __IDENTIFIER '=' opt_null_type_designator _STRUCT
      {
	TNODE * volatile base = NULL;
	TNODE * volatile tnode = NULL;
	cexception_t inner;

	// compiler_begin_scope( compiler_cc, px );

	cexception_guard( inner ) {
	    base = new_tnode_placeholder( $4, &inner );
	    tnode = new_tnode_composite( $2, base, &inner );
	    tnode_set_flags( tnode, TF_IS_FORWARD );
	    compiler_typetab_insert( compiler_cc, tnode, &inner );
	    tnode = typetab_lookup( compiler_cc->typetab, $2 );
	    compiler_cc->current_type = tnode;
	    compiler_typetab_insert( compiler_cc, share_tnode( base ), &inner );
	    compiler_begin_scope( compiler_cc, &inner );
	}
	cexception_catch {
	    delete_tnode( base );
	    delete_tnode( tnode );
	    cexception_reraise( inner, px );
	}
      }
      struct_or_class_declaration_body
      {
        if( $6 ) {
            tnode_set_flags( $9, TF_NON_NULL );
        }
	compiler_end_scope( compiler_cc, px );
	compiler_compile_type_declaration( compiler_cc, $9, px );
	compiler_cc->current_type = NULL;
      }

  | _TYPE __IDENTIFIER _OF __IDENTIFIER '=' opt_null_type_designator
      {
	TNODE * volatile base = NULL;
	TNODE * volatile tnode = NULL;
	cexception_t inner;

	// compiler_begin_scope( compiler_cc, px );

	cexception_guard( inner ) {
	    base = new_tnode_placeholder( $4, &inner );
	    tnode = new_tnode_composite( $2, base, &inner );
	    tnode_set_flags( tnode, TF_IS_FORWARD );
	    compiler_typetab_insert( compiler_cc, tnode, &inner );
	    tnode = typetab_lookup( compiler_cc->typetab, $2 );
	    compiler_cc->current_type = tnode;
	    compiler_typetab_insert( compiler_cc, share_tnode( base ), &inner );
	    compiler_begin_scope( compiler_cc, &inner );
	}
	cexception_catch {
	    delete_tnode( base );
	    delete_tnode( tnode );
	    cexception_reraise( inner, px );
	}
      }
    struct_or_class_declaration_body
      {
        if( $6 ) {
            tnode_set_flags( $8, TF_NON_NULL );
        }
	compiler_end_scope( compiler_cc, px );
	compiler_compile_type_declaration( compiler_cc, $8, px );
	compiler_cc->current_type = NULL;
      }

;

class_declaration
  : opt_null_type_designator _CLASS __IDENTIFIER
    {
	TNODE *old_tnode = typetab_lookup( compiler_cc->typetab, $3 );
	TNODE *tnode = NULL;

	if( !old_tnode ) {
	    TNODE *tnode = new_tnode_forward_class( $3, px );
            if( $1 ) {
                tnode_set_flags( tnode, TF_NON_NULL );
            }
	    compiler_typetab_insert( compiler_cc, tnode, px );
	}
	tnode = typetab_lookup( compiler_cc->typetab, $3 );
	assert( !compiler_cc->current_type );
	compiler_cc->current_type = tnode;
	compiler_begin_scope( compiler_cc, px );
    }
    struct_or_class_declaration_body
    {
 	tnode_finish_class( $5, px );
	compiler_finish_virtual_method_table( compiler_cc, $5, px );
	compiler_end_scope( compiler_cc, px );
	compiler_typetab_insert( compiler_cc, $5, px );
	compiler_cc->current_type = NULL;
    }
  | type_declaration_start '=' opt_null_type_designator _CLASS
    {
	assert( compiler_cc->current_type );
	tnode_set_flags( compiler_cc->current_type, TF_IS_REF );
        tnode_set_kind( compiler_cc->current_type, TK_CLASS );
    }
    struct_or_class_declaration_body
    {
        if( $3 ) {
            tnode_set_flags( $6, TF_NON_NULL );
        }
 	tnode_finish_class( $6, px );
	compiler_finish_virtual_method_table( compiler_cc, $6, px );
	compiler_end_scope( compiler_cc, px );
	compiler_compile_type_declaration( compiler_cc, $6, px );
	compiler_cc->current_type = NULL;
    }
;

interface_declaration
  : opt_null_type_designator _INTERFACE __IDENTIFIER
    {
	TNODE *old_tnode = typetab_lookup( compiler_cc->typetab, $3 );
	TNODE *tnode = NULL;

	if( !old_tnode ) {
	    TNODE *tnode = new_tnode_forward_interface( $3, px );
            if( $1 ) {
                tnode_set_flags( tnode, TF_NON_NULL );
            }
	    compiler_typetab_insert( compiler_cc, tnode, px );
	}
	tnode = typetab_lookup( compiler_cc->typetab, $3 );
	assert( !compiler_cc->current_type );
	compiler_cc->current_type = tnode;
	compiler_begin_scope( compiler_cc, px );
    }
    interface_declaration_body
    {
 	tnode_finish_interface( $5, ++compiler_cc->last_interface_number, px );
	compiler_end_scope( compiler_cc, px );
	compiler_typetab_insert( compiler_cc, $5, px );
	compiler_cc->current_type = NULL;
    }
;

forward_struct_declaration
  : opt_null_type_designator _STRUCT __IDENTIFIER
      {
	  TNODE *tnode = new_tnode_forward_struct( $3, px );
          if( $1 ) {
              tnode_set_flags( tnode, TF_NON_NULL );
          }
	  compiler_typetab_insert( compiler_cc, tnode, px );
      }
;

forward_class_declaration
  : opt_null_type_designator _CLASS __IDENTIFIER
      {
	  TNODE *tnode = new_tnode_forward_class( $3, px );
          if( $1 ) {
              tnode_set_flags( tnode, TF_NON_NULL );
          }
	  compiler_typetab_insert( compiler_cc, tnode, px );
      }
;


initialiser
  : '=' expression
  ;

type_initialiser
  : '=' '(' expression ')'
  ;

/*--------------------------------------------------------------------------*/

/*

1) compound assignment statements:
a[i] = b + c;

2) multiple assignments:
( a[i], b, c ) = b + c, d, f( x, y );
( a, b ) = f( x, y, z );
  a, b   = f( x, y, z );

*/

lvalue_list
: lvalue
      {
	  compiler_push_thrcode( compiler_cc, px );
	  $$ = 1;
      }
| __IDENTIFIER
      {
	  compiler_push_varaddr_expr( compiler_cc, $1, px );
	  compiler_push_thrcode( compiler_cc, px );
	  $$ = 1;
      }
| lvalue_list ',' lvalue
      {
	  compiler_push_thrcode( compiler_cc, px );
	  $$ = $1 + 1;
      }
| lvalue_list ',' __IDENTIFIER
      {
	  compiler_push_varaddr_expr( compiler_cc, $3, px );
	  compiler_push_thrcode( compiler_cc, px );
	  $$ = $1 + 1;
      }
;

assignment_statement
  : variable_access_identifier '=' expression
      {
	  compiler_compile_store_variable( compiler_cc, $1, px );
      }
  | lvalue '=' expression
      {
	  compiler_compile_sti( compiler_cc, px );
      }
  | '('
      {
	  /* Values must be emmitted first in the code. */
	  compiler_push_thrcode( compiler_cc, px );
      }
    lvalue_list ')' '=' multivalue_expression_list
      {
	  compiler_compile_multiple_assignment( compiler_cc, $3, $3, $6, px );
      }

  | lvalue ',' 
      {
	  compiler_push_thrcode( compiler_cc, px );
      }
    lvalue_list '=' multivalue_expression_list
      {
	  compiler_compile_multiple_assignment( compiler_cc, $4+1, $4, $6, px );
	  compiler_compile_sti( compiler_cc, px );
      }

  | __IDENTIFIER ',' 
      {
	  compiler_push_varaddr_expr( compiler_cc, $1, px );
	  compiler_push_thrcode( compiler_cc, px );
      }
    lvalue_list '=' multivalue_expression_list
      {
	  compiler_compile_multiple_assignment( compiler_cc, $4+1, $4, $6, px );

	  {
	      DNODE *var;

	      compiler_swap_top_expressions( compiler_cc );
	      var = enode_variable( compiler_cc->e_stack );

	      share_dnode( var );
	      compiler_drop_top_expression( compiler_cc );
	      compiler_compile_variable_assignment( compiler_cc, var, px );
	      delete_dnode( var );
	  }
      }

  | variable_access_identifier
      {
	  compiler_compile_load_variable_value( compiler_cc, $1, px );
      }
    __ARITHM_ASSIGN expression
      { 
	compiler_compile_binop( compiler_cc, $3, px );
	compiler_compile_store_variable( compiler_cc, $1, px );
      }
  | lvalue
      {
	  compiler_compile_dup( compiler_cc, px );
	  compiler_compile_ldi( compiler_cc, px );
      }
    __ARITHM_ASSIGN expression
      { 
	  compiler_compile_binop( compiler_cc, $3, px );
	  compiler_compile_sti( compiler_cc, px );
      }

  | lvalue
      {
	  compiler_compile_ldi( compiler_cc, px );
      }
     __ASSIGN expression
      {
	  int err = 0;
	  if( !compiler_test_top_types_are_assignment_compatible(
	           compiler_cc, px )) {
	      yyerrorf( "incopatible types for value-copy assignment ':='" );
	  }
	  compiler_emit( compiler_cc, px, "\tc\n", COPY );
	  if( !err && !compiler_stack_top_is_reference( compiler_cc )) {
	      yyerrorf( "value assignemnt := works only for references" );
	      err = 1;
	  }
	  if( !err &&
	      !compiler_test_top_types_are_readonly_compatible_for_copy(
	           compiler_cc, px )) {
	      yyerrorf( "can not copy into the readonly value "
                        "in the value-copy assignment ':='" );
	      err = 1;
	  }
	  compiler_drop_top_expression( compiler_cc );
	  if( !err && !compiler_stack_top_is_reference( compiler_cc )) {
	      yyerrorf( "value assignemnt := works only for references" );
	      err = 1;
	  }
	  compiler_drop_top_expression( compiler_cc );
      }

  | variable_access_identifier
      {
	  compiler_compile_load_variable_value( compiler_cc, $1, px );
      }
    __ASSIGN expression
      {
	  int err = 0;
	  if( !compiler_test_top_types_are_assignment_compatible(
	           compiler_cc, px )) {
	      yyerrorf( "incopatible types for value-copy assignment ':='" );
	      err = 1;
	  }
	  compiler_emit( compiler_cc, px, "\tc\n", COPY );
	  if( !err && !compiler_stack_top_is_reference( compiler_cc )) {
	      yyerrorf( "value assignemnt := works only for references" );
	      err = 1;
	  }
	  if( !err &&
	      !compiler_test_top_types_are_readonly_compatible_for_copy(
	           compiler_cc, px )) {
	      yyerrorf( "can not copy into the readonly value in "
                        "the value-copy assignment ':='" );
	      err = 1;
	  }
	  compiler_drop_top_expression( compiler_cc );
	  if( !err && !compiler_stack_top_is_reference( compiler_cc )) {
	      yyerrorf( "value assignemnt := works only for references" );
	      err = 1;
	  }
	  compiler_drop_top_expression( compiler_cc );
      }
  ;

bytecode_statement
  : _BYTECODE '{' bytecode_sequence '}'
  ;

bytecode_sequence
  : bytecode_item
  | bytecode_sequence bytecode_item
  ;

bytecode_item
  : opcode
  | variable_reference
  | bytecode_constant
  ;

opcode
  : __IDENTIFIER
      { compiler_emit( compiler_cc, px, "\tC\n", $1 ); }
  | module_list __COLON_COLON __IDENTIFIER
      { compiler_emit( compiler_cc, px, "\tMC\n", $1, $3 ); }
  ;

variable_reference
  : '%' __IDENTIFIER
      { 
         DNODE *varnode = vartab_lookup( compiler_cc->vartab, $2 );
	 if( varnode ) {
	     ssize_t var_offset = dnode_offset( varnode );
             compiler_emit( compiler_cc, px, "\teN\n", &var_offset, $2 );
	 } else {
	     yyerrorf( "name '%s' not declared in the current scope", $2 );
	 }
      }
  ;

bytecode_constant
  : __INTEGER_CONST
      {
	  ssize_t val = atol( $1 );
	  compiler_emit( compiler_cc, px, "\te\n", &val );
      }
  | '+' __INTEGER_CONST
      {
	  ssize_t val = atol( $2 );
	  compiler_emit( compiler_cc, px, "\te\n", &val );
      }
  | '-' __INTEGER_CONST
      {
	  ssize_t val = -atol( $2 );
	  compiler_emit( compiler_cc, px, "\te\n", &val );
      }
  | __REAL_CONST
      {
	double val;
	sscanf( $1, "%lf", &val );
        compiler_emit( compiler_cc, px, "\tf\n", val );
      }
  | __STRING_CONST
      {
	ssize_t string_offset;
	string_offset = compiler_assemble_static_string( compiler_cc, $1, px );
        compiler_emit( compiler_cc, px, "\te\n", &string_offset );
      }

  | __DOUBLE_PERCENT __IDENTIFIER
      {
	static const ssize_t zero = 0;
	if( !compiler_cc->current_function ) {
	    yyerrorf( "type attribute '%%%%%s' is not available here "
		      "(are you compiling a function or operator?)", $2 );
	} else {
            if( implementation_has_attribute( $2 )) {
                compiler_emit( compiler_cc, px, "\te\n", &zero );
                
                FIXUP *type_attribute_fixup =
                    new_fixup_absolute
                    ( $2, thrcode_length( compiler_cc->thrcode ) - 1,
                      NULL /* next */, px );

                dnode_insert_code_fixup( compiler_cc->current_function,
                                         type_attribute_fixup );
            }
	}
      }

  | _CONST '(' constant_expression ')'
      {
	  const_value_t const_expr = $3;

	  switch( const_expr.value_type ) {
	  case VT_INT: {
	      ssize_t val = const_expr.value.i;
	      compiler_emit( compiler_cc, px, "\te\n", &val );
	      }
	      break;
	  case VT_FLOAT: {
	      double val = const_expr.value.f;
	      compiler_emit( compiler_cc, px, "\tf\n", &val );
	      }
	      break;
	  default:
	      yyerrorf( "constant of type '%s' is not supported "
			"in bytecode", cvalue_type_name( const_expr ));
	      break;
	  }
      }     
  ;

function_identifier
  : __IDENTIFIER
	{
	    compiler_check_and_push_function_name( compiler_cc, NULL, $1, px );
	}
  | module_list __COLON_COLON __IDENTIFIER
	{
	    compiler_check_and_push_function_name( compiler_cc, $1, $3, px );
	}
  ;

multivalue_function_call
  : function_identifier 
        {
	  TNODE *fn_tnode;
          type_kind_t fn_kind;

	  fn_tnode = compiler_cc->current_call ?
	      dnode_type( compiler_cc->current_call ) : NULL;

	  compiler_cc->current_arg = fn_tnode ?
	      dnode_list_last( tnode_args( fn_tnode )) : NULL;

          fn_kind= fn_tnode ? tnode_kind( fn_tnode ) : TK_NONE;

          if( fn_kind == TK_FUNCTION_REF || fn_kind == TK_CLOSURE ) {
              compiler_push_type( compiler_cc, share_tnode(fn_tnode), px );
          }

	  compiler_push_guarding_arg( compiler_cc, px );
	}
    '(' opt_actual_argument_list ')'
        {
	    DNODE *function = compiler_cc->current_call;
	    TNODE *fn_tnode = function ? dnode_type( function ) : NULL;
            type_kind_t fn_kind = fn_tnode ?
                tnode_kind( fn_tnode ) : TK_NONE;

	    if( fn_kind == TK_FUNCTION_REF || fn_kind == TK_CLOSURE ) {
		char *fn_name = dnode_name( function );
		ssize_t offset = dnode_offset( function );
		compiler_emit( compiler_cc, px, "\tceN\n", PLD, &offset, fn_name );
	    }

	    $$ = compiler_compile_multivalue_function_call( compiler_cc, px );
	}
  | lvalue 
        {
	  TNODE *fn_tnode = NULL;

	  compiler_compile_ldi( compiler_cc, px );

	  compiler_emit( compiler_cc, px, "\tc\n", RTOR );

	  fn_tnode = compiler_cc->e_stack ?
	      enode_type( compiler_cc->e_stack ) : NULL;

	  dlist_push_dnode( &compiler_cc->current_call_stack,
			    &compiler_cc->current_call, px );

	  dlist_push_dnode( &compiler_cc->current_arg_stack,
			    &compiler_cc->current_arg, px );

	  compiler_cc->current_call = new_dnode( px );
	  if( fn_tnode ) {
	      dnode_insert_type( compiler_cc->current_call,
				 share_tnode( fn_tnode ));
	  }
	  if( fn_tnode && tnode_kind( fn_tnode ) != TK_FUNCTION_REF ) {
	      yyerrorf( "called object is not a function pointer" );
	  }

	  compiler_cc->current_arg = fn_tnode ?
	      dnode_list_last( tnode_args( fn_tnode )) : NULL;

	  compiler_push_guarding_arg( compiler_cc, px );
	}
    '(' opt_actual_argument_list ')'
        {
	    compiler_emit( compiler_cc, px, "\tc\n", RFROMR );
	    $$ = compiler_compile_multivalue_function_call( compiler_cc, px );
	}
  | variable_access_identifier
    __ARROW __IDENTIFIER
        {
            DNODE *object = $1;
            TNODE *object_type = dnode_type( object );
            DNODE *method = object_type ?
                tnode_lookup_field( object_type, $3 ) : NULL;
            DNODE *last_arg = NULL;

	    if( method ) {
		TNODE *fn_tnode = dnode_type( method );

                dlist_push_dnode( &compiler_cc->current_call_stack,
                                  &compiler_cc->current_call, px );

                dlist_push_dnode( &compiler_cc->current_arg_stack,
                                  &compiler_cc->current_arg, px );

		if( fn_tnode && tnode_kind( fn_tnode ) != TK_METHOD ) {
		    yyerrorf( "called field is not a method" );
                    compiler_cc->current_call = NULL;
		} else {
                    compiler_cc->current_call = share_dnode( method );
                }

                last_arg = fn_tnode ?
                    tnode_args( fn_tnode ) : NULL;

                last_arg = last_arg ?
                    dnode_list_last( last_arg ) : NULL;

		compiler_cc->current_arg = last_arg ?
		    dnode_prev( last_arg ) : NULL;
	    } else if( object ) {
		char *object_name = object ? dnode_name( object ) : NULL;
		char *method_name = $3;
		char *class_name =
		    object_type ? tnode_name( object_type ) : NULL;

		if( object_name && method_name ) {
		    yyerrorf( "object '%s' does not have method '%s'",
			      object_name, method_name );
		} else if ( class_name && method_name ) {
		    yyerrorf( "type/class '%s' does not have method '%s'",
			      class_name, method_name );
		} else {
		    yyerrorf( "can not locate method '%s'", method_name );
		}
	    }
	    compiler_push_guarding_arg( compiler_cc, px );
	    compiler_compile_load_variable_value( compiler_cc, object, px );
	}
    '(' opt_actual_argument_list ')'
        {
	    compiler_compile_load_variable_value( compiler_cc, $1, px );
	    compiler_drop_top_expression( compiler_cc );
	    $$ = compiler_compile_multivalue_function_call( compiler_cc, px );
	}

  | lvalue 
        {
	    compiler_compile_ldi( compiler_cc, px );
            compiler_compile_dup( compiler_cc, px );
            compiler_emit( compiler_cc, px, "\tc\n", RTOR );
	    compiler_drop_top_expression( compiler_cc );
	}
    __ARROW __IDENTIFIER
        {
            ENODE *object_expr = compiler_cc->e_stack;;
            TNODE *object_type =
		object_expr ? enode_type( object_expr ) : NULL;
            DNODE *method =
		object_type ? tnode_lookup_field( object_type, $4 ) : NULL;

	    if( method ) {
		TNODE *fn_tnode = dnode_type( method );

		dlist_push_dnode( &compiler_cc->current_call_stack,
				  &compiler_cc->current_call, px );

		dlist_push_dnode( &compiler_cc->current_arg_stack,
				  &compiler_cc->current_arg, px );

		compiler_cc->current_call = share_dnode( method );

		if( fn_tnode && tnode_kind( fn_tnode ) != TK_METHOD ) {
		    yyerrorf( "called field is not a method" );
		}

		compiler_cc->current_arg = fn_tnode ?
		    dnode_prev( dnode_list_last( tnode_args( fn_tnode ))) :
		    NULL;
	    }
            compiler_push_guarding_arg( compiler_cc, px );
            compiler_swap_top_expressions( compiler_cc );
	}
    '(' opt_actual_argument_list ')'
        {
	    compiler_emit( compiler_cc, px, "\tc\n", RFROMR );
	    $$ = compiler_compile_multivalue_function_call( compiler_cc, px );
	}

  ;

function_call
  : multivalue_function_call
    {
	if( $1 > 0 ) {
	    compiler_emit_drop_returned_values( compiler_cc, $1 - 1, px );
	} else {
	    yyerrorf( "functions called in exressions must return "
		      "at least one value" );
	    /* Push NULL value to maintain stack value balance and
	       avoid segfaults or asserts in the downstream code: */
	    compiler_push_type( compiler_cc, new_tnode_nullref( px ), px );
	}
    }
  ;

opt_actual_argument_list
  : actual_argument_list
  |
  ;

actual_argument_list
  : expression
      {
	compiler_convert_function_argument( compiler_cc, px );
      }
  | __IDENTIFIER 
      {
	  compiler_emit_default_arguments( compiler_cc, $1, px );
      }
   __THICK_ARROW expression
      {
	compiler_convert_function_argument( compiler_cc, px );
      }
  | actual_argument_list ',' expression
      {
	compiler_convert_function_argument( compiler_cc, px );
      }
  | actual_argument_list ',' __IDENTIFIER
      {
	  compiler_emit_default_arguments( compiler_cc, $3, px );
      }
    __THICK_ARROW expression
      {
	  compiler_convert_function_argument( compiler_cc, px );
      }
  ;

expression_list
  : expression
      { $$ = 1; }
  | expression_list ',' expression
      { $$ = $1 + 1; }
  ;

stdio_inpupt_condition
: '<' '>'
{
    cexception_t inner;
    TNODE *type_tnode = typetab_lookup( compiler_cc->typetab, "string" );
    DNODE *default_var = NULL;
    ssize_t default_var_offset = 0;

    cexception_guard( inner ) {
        default_var = new_dnode_typed( "$_", type_tnode, &inner );
        share_tnode( type_tnode );
        compiler_vartab_insert_named_vars( compiler_cc, default_var, &inner );
        default_var_offset = dnode_offset( default_var );

        compiler_cc->local_offset ++;
        default_var = new_dnode_typed( "$ARG", type_tnode, &inner );
        share_tnode( type_tnode );
        compiler_vartab_insert_named_vars( compiler_cc, default_var, &inner );

        compiler_push_type( compiler_cc, type_tnode, &inner );
        compiler_emit( compiler_cc, &inner, "\tc\n", STDREAD );
        compiler_emit( compiler_cc, &inner, "\tc\n", DUP );
        compiler_emit( compiler_cc, &inner, "\tce\n", PST, &default_var_offset );        
    }
    cexception_catch {
        delete_tnode( type_tnode );
        delete_dnode( default_var );
        cexception_reraise( inner, px );
    }
}
;

condition
  : function_call
  | simple_expression
  | '<' expression '>'
  {
      assert( "'<>' simple expression is not implemented yet" );
  }
  | stdio_inpupt_condition
  | '(' stdio_inpupt_condition ')'
/*
  | arithmetic_expression
*/
  | boolean_expression
  | '(' simple_expression ')'
  | '(' function_call ')'
  ;

multivalue_expression_list
  : multivalue_function_call
      { $$ = $1; }
  | expression ',' expression_list
      { $$ = $3 + 1; }
  ;

io_expression
  : '<' expression '>'
  {
      assert( "'<>' simple expression is not implemented yet" );
  }
  | '<' '>'
  {
    cexception_t inner;
    TNODE *type_tnode = typetab_lookup( compiler_cc->typetab, "string" );

    cexception_guard( inner ) {
        compiler_push_type( compiler_cc, type_tnode, &inner );
        compiler_emit( compiler_cc, &inner, "\tc\n", STDREAD );
    }
    cexception_catch {
        delete_tnode( type_tnode );
        cexception_reraise( inner, px );
    }
  }
;

expression
  : function_call
  | simple_expression
  | arithmetic_expression
  | boolean_expression
  | assignment_expression
  | null_expression
  | io_expression
  ;

null_expression
  : _NULL
      {
	  TNODE *tnode = new_tnode_nullref( px );
	  compiler_push_type( compiler_cc, tnode, px );
	  compiler_emit( compiler_cc, px, "\tc\n", PLDZ );
      }
  ;

opt_closure_initialisation_list
: __IDENTIFIER '{' closure_initialisation_list '}'
{
    $$ = $1;
}
| __IDENTIFIER '{' closure_initialisation_list ';' '}'
{
    $$ = $1;
}
| /* empty */
{
    $$ = NULL;
}
;

closure_initialisation_list
: closure_initialisation
| closure_initialisation_list ';' closure_initialisation
;

closure_var_declaration
  : opt_variable_declaration_keyword
    variable_identifier ':' var_type_description
      {
       int readonly = $1;
       if( readonly ) {
           dnode_list_set_flags( $2, DF_IS_READONLY );
       }
       $$ = dnode_list_append_type( $2, $4 );
      }

  | opt_variable_declaration_keyword
    var_type_description variable_declarator
      {
        int readonly = $1;
        if( readonly ) {
            dnode_list_set_flags( $3, DF_IS_READONLY );
        }
        $$ = dnode_list_append_type( $3, $2 );
      }

  | opt_variable_declaration_keyword
    compact_type_description dimension_list
    variable_declarator
      {
        int readonly = $1;
        if( readonly ) {
            dnode_list_set_flags( $4, DF_IS_READONLY );
        }
        tnode_append_element_type( $3, $2 );
        $$ = dnode_list_append_type( $4, $3 );
      }
  ;

closure_var_list_declaration
  : opt_variable_declaration_keyword
    variable_identifier ',' variable_identifier_list ':' var_type_description
      {
       int readonly = $1;
       DNODE *variables = dnode_append( $2, $4 );
       if( readonly ) {
           dnode_list_set_flags( variables, DF_IS_READONLY );
       }
       $$ = dnode_list_append_type( variables, $6 );
      }

  | opt_variable_declaration_keyword
    var_type_description
    variable_declarator ',' uninitialised_var_declarator_list
      {
        int readonly = $1;
        DNODE *variables = dnode_append( $3, $5 );
        if( readonly ) {
            dnode_list_set_flags( variables, DF_IS_READONLY );
        }
        $$ = dnode_list_append_type( variables, $2 );
      }

  | opt_variable_declaration_keyword
    compact_type_description dimension_list
    variable_declarator ',' uninitialised_var_declarator_list
      {
        int readonly = $1;
        DNODE *variables = dnode_append( $4, $6 );
        if( readonly ) {
            dnode_list_set_flags( variables, DF_IS_READONLY );
        }
        tnode_append_element_type( $3, $2 );
        $$ = dnode_list_append_type( variables, $3 );
      }
  ;

closure_initialisation
: closure_var_declaration
{
    ENODE *top_expr = compiler_cc->e_stack;
    TNODE *closure_tnode = top_expr ? enode_type( top_expr ) : NULL;
    DNODE *closure_var = $1;
    TNODE *var_type = closure_var ? dnode_type( closure_var ) : NULL;
    ssize_t offset = 0;

    assert( closure_tnode );
    assert( var_type );

    tnode_insert_fields( closure_tnode, closure_var );
    offset = dnode_offset( closure_var );
    compiler_emit( compiler_cc, px, "\tce\n", OFFSET, &offset );
    compiler_push_type( compiler_cc,
                     new_tnode_addressof( share_tnode( var_type ), px ), 
                     px );
}
 '=' expression
{
    compiler_compile_sti( compiler_cc, px );
    compiler_emit( compiler_cc, px, "\tc\n", DUP );
}

| closure_var_list_declaration
{
    ENODE *top_expr = compiler_cc->e_stack;
    TNODE *closure_tnode = top_expr ? enode_type( top_expr ) : NULL;
    DNODE *closure_var_list = $1;
    DNODE *closure_var;
    ssize_t offset = 0;
    int first_variable = 1;

    assert( closure_tnode );

    tnode_insert_fields( closure_tnode, closure_var_list );

    foreach_dnode( closure_var, closure_var_list ) {

        if( !first_variable ) {
            share_tnode( closure_tnode );
        }
        offset = dnode_offset( closure_var );
        compiler_emit( compiler_cc, px, "\tce\n", OFFSET, &offset );
        compiler_emit( compiler_cc, px, "\tc\n", RTOR );
        compiler_emit( compiler_cc, px, "\tc\n", DUP );
        first_variable = 0;
    }
}
 '=' multivalue_expression_list
{
    DNODE *var_list = $1;
    DNODE *var;
    ssize_t value_count = $4;
    ssize_t variable_count = dnode_list_length( var_list );

    if( variable_count > value_count ) {
        yyerrorf( "too little values (%d) to initialise "
                  "%d closure variables", value_count, variable_count );
    } else {
        if( variable_count < value_count ) {
            if( variable_count == value_count - 1 ) {
                compiler_compile_drop( compiler_cc, px );
            } else {
                compiler_compile_dropn( compiler_cc, value_count - variable_count,
                                     px );
            }
        }
    }

    variable_count = 0;
    foreach_dnode( var, var_list ) {
        variable_count ++;
        if( variable_count <= value_count ) {
            TNODE *var_type = var ? dnode_type( var ) : NULL;

            assert( var_type );

            compiler_emit( compiler_cc, px, "\tc\n", RFROMR );
            compiler_push_type( compiler_cc,
                             new_tnode_addressof( share_tnode( var_type ),
                                                  px ), 
                             px );
            compiler_compile_swap( compiler_cc, px );
            compiler_compile_sti( compiler_cc, px );
        }
    }
}

| opt_variable_declaration_keyword variable_identifier
{
    int readonly = $1;
    DNODE *closure_var = $2;

    if( readonly ) {
        dnode_list_set_flags( closure_var, DF_IS_READONLY );
    }
}
 '=' expression
{
    ENODE *top_expr = compiler_cc->e_stack;
    TNODE *top_type = top_expr ? enode_type( top_expr ) : NULL;
    ENODE *second_expr = enode_next( compiler_cc->e_stack );
    TNODE *closure_tnode = second_expr ? enode_type( second_expr ) : NULL;
    DNODE *closure_var = $2;
    ssize_t offset = 0;

    assert( closure_tnode );
    assert( top_type );

    dnode_insert_type( closure_var, share_tnode( top_type ));
    tnode_insert_fields( closure_tnode, closure_var );
    offset = dnode_offset( closure_var );
    compiler_emit( compiler_cc, px, "\tc\n", SWAP );
    compiler_emit( compiler_cc, px, "\tce\n", OFFSET, &offset );
    compiler_emit( compiler_cc, px, "\tc\n", SWAP );

    compiler_push_type( compiler_cc,
                     new_tnode_addressof( share_tnode( top_type ), px ), 
                     px );

    compiler_swap_top_expressions( compiler_cc );

    compiler_compile_sti( compiler_cc, px );
    compiler_emit( compiler_cc, px, "\tc\n", DUP );
}

| opt_variable_declaration_keyword variable_identifier ','
  variable_identifier_list
{
    int readonly = $1;
    DNODE *closure_var_list = dnode_append( $2, $4 );

    if( readonly ) {
        dnode_list_set_flags( closure_var_list, DF_IS_READONLY );
    }

    compiler_emit( compiler_cc, px, "\tc\n", RTOR );
}
 '=' multivalue_expression_list
{
    ENODE *top_expr = compiler_cc->e_stack;
    ENODE *current_expr, *closure_expr;
    TNODE *closure_tnode;
    DNODE *closure_var_list = $2;
    ssize_t len = dnode_list_length( closure_var_list );
    ssize_t expr_nr = $7;
    ssize_t offset = 0;
    int i, first_variable = 1;
    DNODE *var;

    closure_expr = top_expr;
    for( i = 0; i < expr_nr; i++ ) {
        closure_expr = enode_next( closure_expr );
    }

    closure_tnode = closure_expr ? enode_type( closure_expr ) : NULL;
    
    assert( closure_tnode );

    current_expr = top_expr;
    closure_var_list = dnode_list_invert( closure_var_list );
    foreach_dnode( var, closure_var_list ) {
        TNODE *expr_type = current_expr ?
            share_tnode( enode_type( current_expr )) : NULL;
        type_kind_t expr_type_kind = expr_type ?
            tnode_kind( expr_type ) : TK_NONE;
        if( expr_type_kind == TK_FUNCTION ||
            expr_type_kind == TK_OPERATOR ||
                 expr_type_kind == TK_METHOD ) {
            TNODE *base_type = typetab_lookup( compiler_cc->typetab, "procedure" );
            expr_type = new_tnode_function_or_proc_ref
                ( share_dnode( tnode_args( expr_type )),
                  share_dnode( tnode_retvals( expr_type )),
                  share_tnode( base_type ),
                  px );
        }
        dnode_append_type( var, expr_type );
        current_expr = current_expr ? enode_next( current_expr ) : NULL;
    }
    closure_var_list = dnode_list_invert( closure_var_list );

    tnode_insert_fields( closure_tnode, closure_var_list );

    if( expr_nr < len ) {
        yyerrorf( "number of expressions (%d) is less than "
                  "is needed to initialise %d variables",
                  expr_nr, len );
    }

    if( expr_nr > len ) {
        if( expr_nr == len + 1 ) {
            compiler_compile_drop( compiler_cc, px );
        } else {
            compiler_compile_dropn( compiler_cc, expr_nr - len, px );
        }
    }

    len = 0;
    closure_var_list = dnode_list_invert( closure_var_list );
    foreach_dnode( var, closure_var_list ) {
        len ++;
        if( len <= expr_nr ) {
            TNODE *var_type = var ? dnode_type( var ) : NULL;

            assert( var_type );

            compiler_push_type( compiler_cc,
                             new_tnode_addressof( share_tnode( var_type ),
                                                  px ), 
                             px );

            compiler_emit( compiler_cc, px, "\tc\n", RFROMR );
            compiler_emit( compiler_cc, px, "\tc\n", DUP );
            compiler_emit( compiler_cc, px, "\tc\n", RTOR );
            offset = dnode_offset( var );
            compiler_emit( compiler_cc, px, "\tce\n", OFFSET, &offset );
            compiler_compile_swap( compiler_cc, px );
            compiler_compile_sti( compiler_cc, px );
        }
    }
    closure_var_list = dnode_list_invert( closure_var_list );

    compiler_emit( compiler_cc, px, "\tc\n", RFROMR );
}

;

function_expression_header
:   function_or_procedure_keyword '(' argument_list ')'
         opt_retval_description_list
    {
        dlist_push_dnode( &compiler_cc->loop_stack, &compiler_cc->loops, px );
        $$ = new_dnode_function( /* name = */ NULL,
                                 /* parameters = */ $3,
                                 /* return_values = */ $5,
                                 px );
    }
;

opt_function_or_procedure_keyword
: function_or_procedure_keyword
| /* empty */
    { $$ = 1; }
;

closure_header
: _CLOSURE
  opt_function_or_procedure_keyword '(' argument_list ')'
      opt_retval_description_list
      {
          TNODE *closure_tnode = new_tnode_ref( px );
          DNODE *closure_fn_ref = NULL;
          ssize_t zero = 0;
          /* Allocate the closure structure: */
          compiler_push_absolute_fixup( compiler_cc, px );
          compiler_emit( compiler_cc, px, "\tc", ALLOC );
          compiler_push_absolute_fixup( compiler_cc, px );
          compiler_emit( compiler_cc, px, "ee\n", &zero, &zero );
          compiler_emit( compiler_cc, px, "\tc\n", DUP );
          tnode_set_kind( closure_tnode, TK_STRUCT );
          /* reserve one stackcell for a function pointer of the
             closure: */
          closure_fn_ref = new_dnode_typed( "",  new_tnode_ref( px ), px );
          tnode_insert_fields( closure_tnode, closure_fn_ref );
          compiler_push_type( compiler_cc, closure_tnode, px );
      }
      opt_closure_initialisation_list
      {
          DNODE *parameters = $4;
          DNODE *return_values = $6;
          DNODE *self_dnode = new_dnode_name( $8, px );
          ENODE *closure_expr = compiler_cc->e_stack;
          TNODE *closure_type = enode_type( closure_expr );

          ssize_t nref, size;

          nref = tnode_number_of_references( closure_type );
          size = tnode_size( closure_type );

          compiler_fixup( compiler_cc, nref );
          compiler_fixup( compiler_cc, size );

          dnode_insert_type( self_dnode, share_tnode( closure_type ));

          parameters = dnode_append( self_dnode, parameters );
          self_dnode = NULL;
        
          dlist_push_dnode( &compiler_cc->loop_stack, &compiler_cc->loops, px );

          $$ = new_dnode_function( /* name = */ NULL, 
                                   parameters, return_values, px );
          tnode_set_kind( dnode_type( $$ ), TK_CLOSURE );
    }
;

function_expression
:   function_expression_header
    function_or_operator_start
    function_or_operator_body
    function_or_operator_end
    {
        compiler_cc->loops = dlist_pop_data( &compiler_cc->loop_stack );
        compiler_compile_load_function_address( compiler_cc, $1, px );
    }

| closure_header
  function_or_operator_start
  function_or_operator_body
  function_or_operator_end
    {
        ENODE *closure_expr = enode_list_pop( &compiler_cc->e_stack );
        TNODE *closure_type = enode_type( closure_expr );
        DNODE *fields = tnode_fields( closure_type );
        ssize_t offs = dnode_offset( fields );

        /* assert( offs == -sizeof(alloccell_t)-sizeof(void*) ); */

        compiler_cc->loops = dlist_pop_data( &compiler_cc->loop_stack );
        compiler_emit( compiler_cc, px, "\tce\n", OFFSET, &offs );
        compiler_compile_load_function_address( compiler_cc, $1, px );
        compiler_emit( compiler_cc, px, "\tc\n", PSTI );
        delete_enode( closure_expr );
    }
;

simple_expression
  : constant
  | variable
  | field_access
      {
	compiler_compile_ldi( compiler_cc, px );
      }
  | indexed_rvalue
  | _BYTECODE ':' var_type_description '{' bytecode_sequence '}'
      {
	compiler_push_type( compiler_cc, $3, px );
      }
  | generator_new
  | array_expression
  | struct_expression
  | unpack_expression
  | function_expression
  | _TYPE type_identifier
      {
          TNODE *tnode = $2;
          compiler_compile_type_descriptor_loader( compiler_cc, tnode, px );
      }
  | _TYPE _OF variable_access_identifier
      {
          DNODE *var_dnode = $3;
          TNODE *var_type = dnode_type( var_dnode );
          compiler_compile_type_descriptor_loader( compiler_cc, var_type, px );
      }
  ;

opt_comma
  : ','
  |
  ;

/* unpack  int (  a,    20,     4  );
   //--    type,  blob, offset, size
*/
unpack_expression
  : _UNPACK compact_type_description
    '(' expression ',' expression ',' expression ')'
  {
      TNODE *type = $2;
      if( tnode_kind( type ) == TK_ARRAY ) {
	  compiler_check_and_compile_operator( compiler_cc,
					    tnode_element_type( type ),
					    "unpackarray", 3 /* arity */,
					    NULL /* fixup_values */, px );
      } else {
	  compiler_check_and_compile_operator( compiler_cc, type,
					    "unpack", 3 /* arity */,
					    NULL /* fixup_values */, px );
      }
      compiler_emit( compiler_cc, px, "\n" );
  }
  | _UNPACK compact_type_description '[' ']'
    '(' expression ',' expression ',' expression ')'
  {
      TNODE *element_type = $2;
      compiler_check_and_compile_operator( compiler_cc, element_type,
					"unpackarray", 3 /* arity */,
					NULL /* fixup_values */, px );

      compiler_emit( compiler_cc, px, "\n" );
  }
  | _UNPACK compact_type_description md_array_allocator '[' ']' 
    /*  blob,          offset,        format_and_size */
    /*  b,             123,           "i4x10" */
    '(' expression ',' expression ',' expression ')'
  {
      char *operator_name = "unpackmdarray";
      int arity = 3;
      int level = $3;
      TNODE *element_type = $2;
      TNODE *array_tnode =
	  new_tnode_array_snail( NULL, compiler_cc->typetab, px );

      if( compiler_lookup_operator( compiler_cc, element_type, operator_name,
                                    arity, px )) {
          key_value_t *fixup_values =
              make_mdalloc_key_value_list( element_type, level );
	  compiler_check_and_compile_operator( compiler_cc, element_type,
					    operator_name,
					    arity, fixup_values,
					    px );
	  /* Return value pushed by ..._compile_operator() function must
	     be dropped, since it only describes return value as having
	     type 'array'. The caller of the current function will push
	     a correct return value 'array of proper_element_type' */
	  compiler_drop_top_expression( compiler_cc );
	  if( compiler_stack_top_is_array( compiler_cc )) {
	      compiler_append_expression_type( compiler_cc, array_tnode );
	      compiler_append_expression_type( compiler_cc, share_tnode( element_type ));
	  }
      } else {
	  compiler_drop_top_expression( compiler_cc );
	  compiler_drop_top_expression( compiler_cc );
	  compiler_drop_top_expression( compiler_cc );
	  tnode_report_missing_operator( element_type, operator_name, arity );
      }
      compiler_emit( compiler_cc, px, "\n" );
  }
  ;

array_expression
  : '[' expression_list opt_comma ']'
     {
	 compiler_compile_array_expression( compiler_cc, $2, px );
     }
/*
  Expression never used and unnecessary duplication:
  | '{' expression_list opt_comma '}'
*/
  ;

struct_expression
  : opt_null_type_designator _STRUCT type_identifier
     {
	 compiler_compile_alloc( compiler_cc, share_tnode( $3 ), px );
         compiler_push_initialised_ref_tables( compiler_cc, px );
     }
    '{' field_initialiser_list opt_comma '}'
    {
        DNODE *field, *field_list;

        field_list = tnode_fields( $3 );
        foreach_dnode( field, field_list ) {
            TNODE *field_type = dnode_type( field );
            char * field_name = dnode_name( field );
            if( tnode_is_non_null_reference( field_type ) &&
                !vartab_lookup( compiler_cc->initialised_references,
                                field_name )) {
                char *field_type_name = $3 ? tnode_name( $3 ) : NULL;
                if( field_type_name ) {
                    yyerrorf( "non-null field '%s' of type '%s' "
                              "is not initialised",
                              field_name, field_type_name );
                } else {
                    yyerrorf( "non-null field '%s' is not initialised",
                              field_name );
                }
            }
        }

        compiler_pop_initialised_ref_tables( compiler_cc );
    }

  | _TYPE type_identifier _OF delimited_type_description
     {
	 TNODE *composite = new_tnode_synonim( $2, px );
	 tnode_set_kind( composite, TK_COMPOSITE );
	 tnode_insert_element_type( composite, $4 );

	 compiler_compile_alloc( compiler_cc, share_tnode( composite ), px );
         compiler_push_initialised_ref_tables( compiler_cc, px );
     }
    '{' field_initialiser_list opt_comma '}'
    {
        DNODE *field, *field_list;

        field_list = tnode_fields( $2 );
        foreach_dnode( field, field_list ) {
            TNODE *field_type = dnode_type( field );
            char * field_name = dnode_name( field );
            if( tnode_is_non_null_reference( field_type ) &&
                !vartab_lookup( compiler_cc->initialised_references,
                                field_name )) {
                char *field_type_name = $2 ? tnode_name( $2 ) : NULL;
                if( field_type_name ) {
                    yyerrorf( "non-null field '%s' of type '%s' "
                              "is not initialised",
                              field_name, field_type_name );
                } else {
                    yyerrorf( "non-null field '%s' is not initialised",
                              field_name );
                }
            }
        }

        compiler_pop_initialised_ref_tables( compiler_cc );
    }

  ;

field_initialiser_list
  : field_initialiser
  | field_initialiser_list ',' field_initialiser
  ;

field_initialiser_separator
: ':'
| __THICK_ARROW
;

field_initialiser
  : __IDENTIFIER
     {
	 DNODE *field;
         TNODE *field_type;

	 compiler_compile_dup( compiler_cc, px );
	 field = compiler_make_stack_top_field_type( compiler_cc, $1 );
         field_type = field ? dnode_type( field ) : NULL;
	 compiler_make_stack_top_addressof( compiler_cc, px );

         if( !vartab_lookup( compiler_cc->initialised_references, $1 ) &&
             field_type && tnode_is_non_null_reference( field_type )) {
             vartab_insert_named( compiler_cc->initialised_references,
                                  share_dnode( field ), px );
         }

	 if( field && dnode_offset( field ) != 0 ) {
	     ssize_t field_offset = dnode_offset( field );
	     compiler_emit( compiler_cc, px, "\tce\n", OFFSET, &field_offset );
	 }
     }
    field_initialiser_separator expression
     {
	 compiler_compile_sti( compiler_cc, px );
     }
  ;

arithmetic_expression
  : expression '+' expression
      {
       compiler_compile_binop( compiler_cc, "+", px );
      }
  | expression '-' expression
      {
       compiler_compile_binop( compiler_cc, "-", px );
      }
  | expression '*' expression
      {
       compiler_compile_binop( compiler_cc, "*", px );
      }
  | expression '/' expression
      {
       compiler_compile_binop( compiler_cc, "/", px );
      }
  | expression '&' expression
      {
       compiler_compile_binop( compiler_cc, "&", px );
      }
  | expression '|' expression
      {
       compiler_compile_binop( compiler_cc, "|", px );
      }
  | expression __RIGHT_TO_LEFT expression /* << */
      {
       compiler_compile_binop( compiler_cc, "shl", px );
      }
  | expression __LEFT_TO_RIGHT expression /* >> */
      {
       compiler_compile_binop( compiler_cc, "shr", px );
      }
  | expression _SHL expression
      {
       compiler_compile_binop( compiler_cc, "shl", px );
      }
  | expression _SHR expression
      {
       compiler_compile_binop( compiler_cc, "shr", px );
      }
  | expression '^' expression
      {
       compiler_compile_binop( compiler_cc, "^", px );
      }
  | expression '%' expression
      {
       compiler_compile_binop( compiler_cc, "%", px );
      }
  | expression __STAR_STAR expression
      {
       compiler_compile_binop( compiler_cc, "**", px );
      }
  | expression '_' expression
      {
       compiler_compile_binop( compiler_cc, "_", px );
      }

  | '+' expression %prec __UNARY
      {
       compiler_compile_unop( compiler_cc, "+", px );
      }
  | '-' expression %prec __UNARY
      {
       compiler_compile_unop( compiler_cc, "-", px );
      }
  | '~' expression %prec __UNARY
      {
       compiler_compile_unop( compiler_cc, "~", px );
      }

  | expression __DOUBLE_PERCENT expression
      {
       compiler_compile_binop( compiler_cc, "%%", px );
      }

/*
  | '<' __IDENTIFIER '>' expression %prec __UNARY
      {
       compiler_compile_type_conversion( compiler_cc, /*target_name* /$2, px );
      }
*/

  | expression '@' __IDENTIFIER
      {
       compiler_compile_type_conversion( compiler_cc, /*target_name*/$3, px );
      }

  | expression '@' '(' var_type_description ')'
      {
       compiler_compile_type_conversion( compiler_cc, NULL, px );
      }

  | expression '?'
      {
        compiler_push_relative_fixup( compiler_cc, px );
	compiler_compile_jz( compiler_cc, 0, px );
      }
    expression ':'
      {
	ssize_t zero = 0;
        compiler_push_relative_fixup( compiler_cc, px );
        compiler_emit( compiler_cc, px, "\tce\n", JMP, &zero );
        compiler_swap_fixups( compiler_cc );
        compiler_fixup_here( compiler_cc );
      }
    expression
      {
	compiler_check_top_2_expressions_and_drop( compiler_cc, "?:", px );
        compiler_fixup_here( compiler_cc );
      }
/*
  | expression _AS __IDENTIFIER
*/
  | '(' arithmetic_expression ')'
  | '(' simple_expression ')'

  | __QQ expression  %prec __UNARY
  {
      ENODE *top = compiler_cc->e_stack;
      TNODE *top_type = top ? enode_type( top ) : NULL;

      if( top && top_type &&
          tnode_is_reference( top_type ) &&
          !tnode_is_non_null_reference( top_type )) {
          TNODE *converted = copy_unnamed_tnode( top_type, px );
          tnode_set_flags( converted, TF_NON_NULL );
          enode_replace_type( top, converted );
          /* top_type no longer valid here! */
          compiler_emit( compiler_cc, px, "\tc\n", CHECKREF );
      }
  }

  ;

boolean_expression
  : expression '<' expression
      {
       compiler_compile_binop( compiler_cc, "<", px );
      }
  | expression '>' expression
      {
       compiler_compile_binop( compiler_cc, ">", px );
      }
  | expression __LE expression
      {
       compiler_compile_binop( compiler_cc, "<=", px );
      }
  | expression __GE expression
      {
       compiler_compile_binop( compiler_cc, ">=", px );
      }
  | expression __EQ expression
      {
       compiler_compile_binop( compiler_cc, "==", px );
      }
  | expression __NE expression
      {
       compiler_compile_binop( compiler_cc, "!=", px );
      }
  | expression _AND
      {
	compiler_compile_dup( compiler_cc, px );
        compiler_push_relative_fixup( compiler_cc, px );
	compiler_compile_jz( compiler_cc, 0, px );
	compiler_duplicate_top_expression( compiler_cc, px );
	compiler_compile_drop( compiler_cc, px );
      }
    expression
      {
	compiler_check_top_2_expressions_and_drop( compiler_cc, "and", px );
        compiler_fixup_here( compiler_cc );
      }
  | expression _OR
      {
	compiler_compile_dup( compiler_cc, px );
        compiler_push_relative_fixup( compiler_cc, px );
	compiler_compile_jnz( compiler_cc, 0, px );
	compiler_duplicate_top_expression( compiler_cc, px );
	compiler_compile_drop( compiler_cc, px );
      }
    expression
      {
	compiler_check_top_2_expressions_and_drop( compiler_cc, "or", px );
	compiler_fixup_here( compiler_cc );
      }
  | '!' expression %prec __UNARY
      {
       compiler_compile_unop( compiler_cc, "!", px );
      }

  | '(' boolean_expression ')'
  ;

generator_new
  : _NEW compact_type_description
      {
          compiler_check_type_contains_non_null_ref( $2 );
          compiler_compile_alloc( compiler_cc, $2, px );
      }

  | _NEW type_identifier
      {
	  DNODE *constructor_dnode;
          TNODE *constructor_tnode;
          TNODE *type_tnode = $2;

          compiler_check_type_contains_non_null_ref( type_tnode );
          compiler_compile_alloc( compiler_cc, type_tnode, px );

          /* --- function call generations starts here: */

          dlist_push_dnode( &compiler_cc->current_call_stack,
                            &compiler_cc->current_call, px );

          dlist_push_dnode( &compiler_cc->current_arg_stack,
                            &compiler_cc->current_arg, px );

          constructor_dnode = type_tnode ?
              tnode_constructor( type_tnode ) : NULL;

          constructor_tnode = constructor_dnode ?
              dnode_type( constructor_dnode ) : NULL;

          compiler_cc->current_call = share_dnode( constructor_dnode );
          
          compiler_cc->current_arg = constructor_tnode ?
              dnode_prev( dnode_list_last( tnode_args( constructor_tnode ))) :
              NULL;

          compiler_compile_dup( compiler_cc, px );
	  compiler_push_guarding_arg( compiler_cc, px );
          compiler_swap_top_expressions( compiler_cc );
	}
    '(' opt_actual_argument_list ')'
        {
	    DNODE *constructor_dnode = compiler_cc->current_call;
	    TNODE *constructor_tnode = constructor_dnode ?
                dnode_type( constructor_dnode ) : NULL;
            int nretvals;
            char *constructor_name = constructor_tnode ?
                tnode_name( constructor_tnode ) : NULL;

	    nretvals = compiler_compile_multivalue_function_call( compiler_cc, px );

            if( nretvals > 0 ) {
                yyerrorf( "constructor '%s()' should not return a value",
                          constructor_name ? constructor_name : "???" );
            }
	}

  | _NEW compact_type_description '[' expression ']'
      {
          compiler_check_array_component_is_not_null( $2 );
          compiler_compile_array_alloc( compiler_cc, $2, px );
      }
  | _NEW compact_type_description md_array_allocator '[' expression ']'
      {
          compiler_check_array_component_is_not_null( $2 );
          compiler_compile_mdalloc( compiler_cc, $2, $3, px );
      }
  | _NEW _ARRAY '[' expression ']' _OF var_type_description
      {
          compiler_check_array_component_is_not_null( $7 );
          compiler_compile_array_alloc( compiler_cc, $7, px );
      }
  | _NEW _ARRAY md_array_allocator '[' expression ']' _OF var_type_description
      {
          compiler_check_array_component_is_not_null( $8 );
          compiler_compile_mdalloc( compiler_cc, $8, $3, px );
      }
  | _NEW compact_type_description '[' expression ']' _OF var_type_description
      {
          compiler_check_array_component_is_not_null( $7 );
          compiler_compile_composite_alloc( compiler_cc, $2, $7, px );
      }
  | _NEW _BLOB '(' expression ')'
      {
	compiler_compile_blob_alloc( compiler_cc, px );
      }
  | expression '*' _NEW '[' expression ']'
      {
          ENODE *top_expr = compiler_cc->e_stack;
          ENODE *next_expr = top_expr ? enode_next( top_expr ) : NULL;
          TNODE *element_type =  next_expr ? enode_type( next_expr ) : NULL;
          compiler_compile_array_alloc( compiler_cc, element_type, px );
          compiler_emit( compiler_cc, px, "\tc\n", FILLARRAY );
      }
  | expression '*' _NEW md_array_allocator '[' expression ']'
      {
          ssize_t level = $4;
          ENODE *top_expr = compiler_cc->e_stack;
          ENODE *next_expr = top_expr ? enode_next( top_expr ) : NULL;
          ENODE *next2_expr = next_expr ? enode_next( next_expr ) : NULL;
          TNODE *element_type =  next_expr ? enode_type( next2_expr ) : NULL;
          compiler_compile_mdalloc( compiler_cc, element_type, level, px );
          compiler_emit( compiler_cc, px, "\tce\n", FILLMDARRAY, &level );
      }
  | _NEW type_identifier _OF '(' _TYPE type_identifier ',' opt_actual_argument_list ')'
  ;

md_array_allocator
  : '[' expression ']'
      {
	int level = 0;
	compiler_compile_mdalloc( compiler_cc, NULL, level, px );
	$$ = level + 1;
      }
  | md_array_allocator '[' expression ']'
      {
	int level = $1;
	compiler_compile_mdalloc( compiler_cc, NULL, level, px );
	$$ = level + 1;
      }
  ;

lvalue
  : function_call
  | field_access
  | indexed_lvalue
  ;

lvariable
  : variable_access_identifier
      { compiler_compile_load_variable_address( compiler_cc, $1, px ); }
  | lvalue
  ;

variable
  : variable_access_identifier
      {
	  DNODE *variable = $1;
	  TNODE *variable_type = variable ? dnode_type( variable ) : NULL; 

	  if( variable_type && tnode_kind( variable_type ) == TK_FUNCTION ) {
              if( variable && dnode_offset( variable ) == 0 ) {
                  thrcode_push_forward_function
                      ( compiler_cc->thrcode, dnode_name( variable ),
                        thrcode_length( compiler_cc->thrcode ) + 1, px );
              }
	      compiler_compile_load_function_address( compiler_cc, variable, px );
	  } else {
	      compiler_compile_load_variable_value( compiler_cc, variable, px );
	  }
      }
  ;

index_expression
  : expression
    { $$ = 1; }
  
  | expression __DOT_DOT expression
    { $$ = 2; }
  
  | expression __DOT_DOT 
    { $$ = -1; }
  
  | expression __THREE_DOTS 
    { $$ = -1; }
  
  | /* empty */
    { $$ = 0; }
;

variable_access_for_indexing
  : variable_access_identifier
      {
       if( compiler_dnode_is_reference( compiler_cc, $1 )) {
           compiler_compile_load_variable_value( compiler_cc, $1, px );
       } else {
           compiler_compile_load_variable_address( compiler_cc, $1, px );
       }
       $$ = $1;
      }
  ;

lvalue_for_indexing
  : lvalue
      {
       if( compiler_stack_top_base_is_reference( compiler_cc )) {
	   compiler_compile_ldi( compiler_cc, px );
       }
      }
  ;

indexed_rvalue
  : variable_access_for_indexing '[' index_expression ']'
      {
	  DNODE *var_dnode = $1;
	  TNODE *var_tnode = var_dnode ? dnode_type( var_dnode ) : NULL;
	  TNODE *element_type = var_tnode ?
	      tnode_element_type( var_tnode ) : NULL;
	  char *operator_name = "ldx";

	  if( element_type && tnode_is_reference( element_type )) {
	      operator_name = "pldx";
	  } else {
	      operator_name = "ldx";
	  }
	  if( compiler_stack_top_has_operator( compiler_cc, operator_name, 2, px ) ||
 	      compiler_nth_stack_value_has_operator( compiler_cc, 1,
						  operator_name, 2, px )) {
	      compiler_check_and_compile_top_2_operator( compiler_cc,
						      operator_name, 2, px );
	  } else {
	      if( compiler_dnode_is_reference( compiler_cc, var_dnode )) {
		  compiler_compile_indexing( compiler_cc, 1, $3, px );
	      } else {
		  compiler_compile_indexing( compiler_cc, 0, $3, px );
	      }
	      compiler_compile_ldi( compiler_cc, px );
	  }
      }
  | lvalue_for_indexing '[' index_expression ']'
      {
	  ENODE *top_expr = compiler_cc->e_stack;
	  ENODE *top2_expr = top_expr ? enode_next( top_expr ) : NULL;
	  TNODE *top2_tnode = top2_expr ? enode_type( top2_expr ) : NULL;
	  TNODE *element_type = top2_tnode ?
	      tnode_element_type( top2_tnode ) : NULL;
	  char *operator_name = "ldx";

	  if( element_type && tnode_is_reference( element_type )) {
	      operator_name = "pldx";
	  } else {
	      operator_name = "ldx";
	  }
	  if( compiler_stack_top_has_operator( compiler_cc, operator_name, 2, px ) ||
 	      compiler_nth_stack_value_has_operator( compiler_cc, 1,
                                                  operator_name, 2, px )) {
	      compiler_check_and_compile_top_2_operator( compiler_cc, operator_name,
                                                      2, px );
	  } else {
	      if( compiler_stack_top_is_reference( compiler_cc )) {
		  compiler_compile_indexing( compiler_cc, 1, $3, px );
	      } else {
		  compiler_compile_indexing( compiler_cc, 0, $3, px );
	      }
	      compiler_compile_ldi( compiler_cc, px );
	  }
      }
  ;

indexed_lvalue
  : variable_access_for_indexing '[' index_expression ']'
      {
	  if( compiler_dnode_is_reference( compiler_cc, $1 )) {
	      compiler_compile_indexing( compiler_cc, 1, $3, px );
	  } else {
	      compiler_compile_indexing( compiler_cc, 0, $3, px );
	  }
      }

  | lvalue_for_indexing '[' index_expression ']'
      {
	  if( compiler_stack_top_is_reference( compiler_cc )) {
	      compiler_compile_indexing( compiler_cc, 1, $3, px );
	  } else {
	      compiler_compile_indexing( compiler_cc, 0, $3, px );
	  }
      }
  ;

field_access
  : variable_access_identifier '.' __IDENTIFIER
      {
       DNODE *field;

       if( compiler_dnode_is_reference( compiler_cc, $1 )) {
	   compiler_compile_load_variable_value( compiler_cc, $1, px );
       } else {
           compiler_compile_load_variable_address( compiler_cc, $1, px );
       }
       field = compiler_make_stack_top_field_type( compiler_cc, $3 );
       compiler_make_stack_top_addressof( compiler_cc, px );
       if( field && dnode_offset( field ) != 0 ) {
	   ssize_t field_offset = dnode_offset( field );
	   compiler_emit( compiler_cc, px, "\tce\n", OFFSET, &field_offset );
       }
      }
  | lvalue '.' __IDENTIFIER
      {
       DNODE *field;

       if( compiler_stack_top_base_is_reference( compiler_cc )) {
	   compiler_compile_ldi( compiler_cc, px );
       }
       field = compiler_make_stack_top_field_type( compiler_cc, $3 );
       compiler_make_stack_top_addressof( compiler_cc, px );
       if( field && dnode_offset( field ) != 0 ) {
	   ssize_t field_offset = dnode_offset( field );
	   compiler_emit( compiler_cc, px, "\tce\n", OFFSET, &field_offset );
       }
      }
  ;

assignment_expression
  : lvalue '=' expression
      {
       compiler_compile_swap( compiler_cc, px );
       compiler_compile_over( compiler_cc, px );
       compiler_compile_sti( compiler_cc, px );
      }

  | variable_access_identifier '=' expression
      {
       compiler_compile_dup( compiler_cc, px );
       compiler_compile_store_variable( compiler_cc, $1, px );
      }

  | '(' assignment_expression ')'
  ;

constant
  : __INTEGER_CONST
      {
       compiler_compile_constant( compiler_cc, TS_INTEGER_SUFFIX,
			       NULL, NULL, "integer", $1, px );
      }
  | __INTEGER_CONST __IDENTIFIER
      {
       compiler_compile_constant( compiler_cc, TS_INTEGER_SUFFIX,
			       NULL, $2, "integer", $1, px );
      }
  | __INTEGER_CONST module_list __COLON_COLON __IDENTIFIER
      {
       compiler_compile_constant( compiler_cc, TS_INTEGER_SUFFIX,
			       $2, $4, "integer", $1, px );
      }
  | __REAL_CONST
      {
       compiler_compile_constant( compiler_cc, TS_FLOAT_SUFFIX,
			       NULL, NULL, "real", $1, px );
      }
  | __REAL_CONST __IDENTIFIER
      {
       compiler_compile_constant( compiler_cc, TS_FLOAT_SUFFIX,
			       NULL, $2, "real", $1, px );
      }
  | __REAL_CONST module_list __COLON_COLON __IDENTIFIER
      {
       compiler_compile_constant( compiler_cc, TS_FLOAT_SUFFIX,
			       $2, $4, "real", $1, px );
      }
  | __STRING_CONST
      {
       compiler_compile_constant( compiler_cc, TS_STRING_SUFFIX,
			       NULL, NULL, "string", $1, px );
      }
  | __STRING_CONST __IDENTIFIER
      {
       compiler_compile_constant( compiler_cc, TS_STRING_SUFFIX,
			       NULL, $2, "string", $1, px );
      }
  | __STRING_CONST module_list __COLON_COLON __IDENTIFIER
      {
       compiler_compile_constant( compiler_cc, TS_STRING_SUFFIX,
			       $2, $4, "string", $1, px );
      }
  | __IDENTIFIER  __IDENTIFIER
      {
       compiler_compile_enumeration_constant( compiler_cc, NULL, $1, $2, px );
      }

  | __IDENTIFIER module_list __COLON_COLON __IDENTIFIER
      {
       compiler_compile_enumeration_constant( compiler_cc, $2, $1, $4, px );
      }

  | _CONST __IDENTIFIER
      {
	DNODE *const_dnode = compiler_lookup_constant( compiler_cc, NULL, $2,
						    "constant" );
	if( const_dnode ) {
	    char pad[80];

	    snprintf( pad, sizeof(pad), "%ld",
		      (long)dnode_ssize_value( const_dnode ));
	    compiler_compile_constant( compiler_cc, TS_INTEGER_SUFFIX,
				    NULL, NULL, "integer", pad, px );
	}
      }

  | _CONST module_list __COLON_COLON __IDENTIFIER
      {
	DNODE *const_dnode = compiler_lookup_constant( compiler_cc, $2, $4,
						    "constant" );
	if( const_dnode ) {
	    char pad[80];

	    snprintf( pad, sizeof(pad), "%ld",
		      (long)dnode_ssize_value( const_dnode ));
	    compiler_compile_constant( compiler_cc, TS_INTEGER_SUFFIX,
				    NULL, NULL, "integer", pad, px );
	}
      }

  | _CONST '(' constant_expression ')'
      {
	  compiler_compile_multitype_const_value( compiler_cc, &$3, NULL, NULL, px );
      }

  | _CONST '(' constant_expression ')' __IDENTIFIER
      {
	  compiler_compile_multitype_const_value( compiler_cc, &$3, NULL, $5, px );
      }

  | _CONST '(' constant_expression ')'
    module_list __COLON_COLON __IDENTIFIER
      {
	  compiler_compile_multitype_const_value( compiler_cc, &$3, $5, $7, px );
      }

  ;

argument_list
  : argument
    { $$ = $1; }
  | argument_list ';' argument
    /* build a list of names in reverse order (opposite to the order which
       they appear in a programm text): */
    { $$ = dnode_append( $3, $1 ); }
  | /* empty */
    { $$ = NULL; }
  ;

opt_readonly
  : _READONLY
    { $$ = 1; }
  |
    { $$ = 0; }
  ;

argument
  : opt_readonly argument_identifier_list ':' var_type_description
    {
	$$ = dnode_list_append_type( $2, $4 );
	if( $1 ) {
	    dnode_list_set_flags( $2, DF_IS_READONLY );
	}
    }

  | opt_readonly argument_identifier_list ':' var_type_description
        '=' constant_expression
    {
	DNODE *arg;

	$$ = dnode_list_append_type( $2, $4 );
	foreach_dnode( arg, $2 ) {
	    const_value_t val = make_zero_const_value();
	    const_value_copy( &val, &$6, px );
	    compiler_check_default_value_compatibility( arg, &val );
	    dnode_set_value( arg, &val );
	    dnode_set_flags( arg, DF_HAS_INITIALISER );
	    if( $1 ) {
		dnode_set_flags( arg, DF_IS_READONLY );
	    }
	}
    }

  | opt_readonly var_type_description uninitialised_var_declarator_list
      {
	$$ = dnode_list_append_type( dnode_list_invert( $3 ), $2 );
	if( $1 ) {
	    dnode_list_set_flags( $3, DF_IS_READONLY );
	}
      }

  | opt_readonly var_type_description variable_declarator
        '=' constant_expression
      {
        $$ = dnode_list_append_type( $3, $2 );
	compiler_check_default_value_compatibility( $3, &$5 );
	dnode_set_value( $3, &$5 );
	dnode_set_flags( $3, DF_HAS_INITIALISER );
	if( $1 ) {
	    dnode_set_flags( $3, DF_IS_READONLY );
	}
      }

  | opt_readonly
    compact_type_description dimension_list uninitialised_var_declarator_list
      {
	tnode_append_element_type( $3, $2 );
	$$ = dnode_list_append_type( dnode_list_invert( $4 ), $3 );
	if( $1 ) {
	    dnode_list_set_flags( $4, DF_IS_READONLY );
	}
      }

  | opt_readonly compact_type_description dimension_list variable_declarator
    '=' constant_expression
      {
	tnode_append_element_type( $3, $2 );
	$$ = dnode_list_append_type( $4, $3 );
	compiler_check_default_value_compatibility( $4, &$6 );
	dnode_set_value( $4, &$6 );
	dnode_set_flags( $4, DF_HAS_INITIALISER );
	if( $1 ) {
	    dnode_set_flags( $4, DF_IS_READONLY );
	}
      }

  | opt_readonly __IDENTIFIER
      {
	  $$ = new_dnode_name( $2, px );
	  dnode_append_type( $$, new_tnode_ignored( px ));
	  if( $1 ) {
	      dnode_list_set_flags( $$, DF_IS_READONLY );
	  }
      }
  ;

argument_identifier_list
  : __IDENTIFIER
    { $$ = new_dnode_name( $1, px ); }
  | argument_identifier_list ',' __IDENTIFIER
    { $$ = dnode_append( new_dnode_name( $3, px ), $1 ); }
  ;

function_or_operator_start
  :
        {
	  cexception_t inner;
	  DNODE *volatile funct = $<dnode>0;
          TNODE *fn_tnode = funct ? dnode_type( funct ) : NULL;
	  int is_bytecode = dnode_has_flags( funct, DF_BYTECODE );

          dlist_push_dnode( &compiler_cc->current_function_stack,
                            &compiler_cc->current_function, px );

	  compiler_cc->current_function = funct;
	  dnode_reset_flags( funct, DF_FNPROTO );

          compiler_push_thrcode( compiler_cc, px );

    	  cexception_guard( inner ) {
	      compiler_push_current_address( compiler_cc, px );

	      if( !is_bytecode ) {
		  ssize_t zero = 0;
		  compiler_push_absolute_fixup( compiler_cc, px );
		  compiler_emit( compiler_cc, px, "\tce\n", ENTER, &zero );
	      }

              compiler_begin_scope( compiler_cc, &inner );
	  }
	  cexception_catch {
	      delete_dnode( funct );
	      compiler_cc->current_function =
                  dlist_pop_data( &compiler_cc->current_function_stack );
	      cexception_reraise( inner, px );
	  }
	  if( !is_bytecode ) {
	      compiler_emit_function_arguments( funct, compiler_cc, px );
	  }
          if( fn_tnode && tnode_kind( fn_tnode ) == TK_CLOSURE ) {
              tnode_drop_first_argument( fn_tnode );
          }
	}
;

function_or_operator_end
  :
        {
	  DNODE *funct = compiler_cc->current_function;
          TNODE *funct_tnode = funct ? dnode_type( funct ) : NULL;
	  int is_bytecode = dnode_has_flags( funct, DF_BYTECODE );
          ssize_t function_entry_address = thrcode_length( compiler_cc->function_thrcode );

	  if( !is_bytecode ) {
	      /* patch ENTER command: */
	      compiler_fixup( compiler_cc, -compiler_cc->local_offset );
	  }
          
          if( funct_tnode && tnode_kind( funct_tnode ) == TK_METHOD ) {
              dnode_set_ssize_value( funct, function_entry_address );
          } else {
              dnode_set_offset( funct, function_entry_address );
          }

	  compiler_get_inline_code( compiler_cc, funct, px );

	  if( thrcode_last_opcode( compiler_cc->thrcode ).fn != RET ) {
	      compiler_emit( compiler_cc, px, "\tc\n", RET );
	  }

          compiler_merge_functions_and_top( compiler_cc, px );
          if( !compiler_cc->thrcode ) {
              compiler_cc->thrcode = compiler_cc->main_thrcode;
          }
          compiler_fixup_function_calls( compiler_cc->function_thrcode, funct );
          compiler_fixup_function_calls( compiler_cc->main_thrcode, funct );
	  compiler_end_scope( compiler_cc, px );
	  compiler_cc->current_function = 
              dlist_pop_data( &compiler_cc->current_function_stack );
	}
;

method_definition
  : method_header
    function_or_operator_start
    function_or_operator_body
    function_or_operator_end
  ;

constructor_definition
  : constructor_header
    function_or_operator_start
    opt_base_class_initialisation
    function_or_operator_body
    function_or_operator_end
  ;

function_definition
  : function_header
    function_or_operator_start
    function_or_operator_body
    function_or_operator_end
  ;

operator_definition
  : operator_header
    function_or_operator_start
    function_or_operator_body
    function_or_operator_end
  ;

function_or_operator_body
  : '{' statement_list '}'
  | '{' bytecode_sequence '}'
  ;

retval_description_list
  : var_type_description 
      { $$ = new_dnode_return_value( $1, px ); }
  | retval_description_list ',' var_type_description
      { $$ = dnode_append( $1, new_dnode_return_value( $3, px )); }
  ;

opt_retval_description_list
  : ':' retval_description_list { $$ = $2; }
  | __ARROW retval_description_list { $$ = $2; }
  | { $$ = NULL; }
  ;

function_attributes
  : _INLINE
    { $$ = DF_INLINE; }
  | _BYTECODE
    { $$ = DF_BYTECODE; }
  | _BYTECODE _INLINE
    { $$ = DF_BYTECODE | DF_INLINE; }
  | _INLINE _BYTECODE
    { $$ = DF_INLINE | DF_BYTECODE; }
  ;

opt_function_attributes
  : function_attributes
    { $$ = $1; }
  |
    { $$ = 0; }
;

function_code_start
  :
    {
      if( thrcode_debug_is_on()) {
	  const char *currentLine = compiler_flex_current_line();
	  const char *first_nonblank = currentLine;
	  while( isspace( *first_nonblank )) first_nonblank++;
	  if( *first_nonblank == '#' ) {
              thrcode_printf( compiler_cc->function_thrcode, px,
                              "%s\n", currentLine );
	  } else {
              thrcode_printf( compiler_cc->function_thrcode, px,
                              "#\n# %s\n#\n", currentLine );
	  }
      }
    }
  ;

function_or_procedure_keyword
  : function_code_start _FUNCTION
      { $$ = 1; }
  | function_code_start _PROCEDURE
      { $$ = 0; }
 ;

function_header
  : opt_function_attributes function_or_procedure_keyword
        {
	    //compiler_begin_scope( compiler_cc, px );
        }
             __IDENTIFIER '(' argument_list ')'
            opt_retval_description_list
        {
	  cexception_t inner;
	  DNODE *volatile funct = NULL;
	  int is_function = $2;

    	  cexception_guard( inner ) {
	      $$ = funct = new_dnode_function( $4, $6, $8, &inner );
	      $6 = NULL;
	      $8 = NULL;
	      dnode_set_flags( funct, DF_FNPROTO );
	      if( $1 & DF_BYTECODE )
	          dnode_set_flags( funct, DF_BYTECODE );
	      if( $1 & DF_INLINE )
	          dnode_set_flags( funct, DF_INLINE );
	      funct = $$ =
		  compiler_check_and_set_fn_proto( compiler_cc, funct, px );
	      if( is_function ) {
		  compiler_set_function_arguments_readonly( dnode_type( funct ));
	      }
	  }
	  cexception_catch {
	      delete_dnode( $6 );
	      delete_dnode( $8 );
	      delete_dnode( funct );
	      $$ = NULL;
	      cexception_reraise( inner, px );
	  }
	}
  ;

opt_implements_method
  : _IMPLEMENTS __IDENTIFIER
  {
      char *method_name = $2;
      TNODE *containing_class_type = $<tnode>-6;
      TNODE *interface_type = tnode_first_interface( containing_class_type );
      DNODE *method_dnode = interface_type ?
          tnode_lookup_method( interface_type, method_name ) : NULL;

      /* printf( ">>> '%s'\n", tnode_name(containing_class_type) ); */
      assert( containing_class_type );
      if( !interface_type ) {
          char *containing_class_name = containing_class_type ?
              tnode_name( containing_class_type ) : NULL;
          if( containing_class_name ) {
              yyerrorf( "class '%s' does not implement any interfaces",
                        containing_class_name );
          } else {
              yyerrorf( "this class does not implement any interfaces" );
          }
      } else {
          if( !method_dnode ) {
              char *interface_name = tnode_name( interface_type );
              if( interface_name ) {
                  yyerrorf( "interface '%s' does not implement method "
                            "'%s'", interface_name, method_name );
              } else {
                  yyerrorf( "this interface does not declare method "
                            "'%s'", method_name );
              }
          }
      }
      $$ = method_dnode;
  }
  | _IMPLEMENTS __IDENTIFIER '.' __IDENTIFIER
  {
      char *interface_name = $2;
      char *method_name = $4;
      TNODE *containing_class_type = $<tnode>-6;
      TNODE *interface_type =
          tnode_lookup_interface( containing_class_type, interface_name );
      DNODE *method_dnode = interface_type ?
          tnode_lookup_method( interface_type, method_name ) : NULL;

      /* printf( ">>> '%s'\n", tnode_name(containing_class_type) ); */
      assert( containing_class_type );
      if( !interface_type ) {
          char *containing_class_name = containing_class_type ?
              tnode_name( containing_class_type ) : NULL;
          if( containing_class_name ) {
              yyerrorf( "class '%s' does not implement interface '%s'",
                        containing_class_name, interface_name );
          } else {
              yyerrorf( "this class does not implement interface '%s'",
                        interface_name );
          }
      } else {
          if( !method_dnode ) {
              yyerrorf( "interface '%s' does not declare method "
                        "'%s'", interface_name, method_name );
          }
      }
      $$ = method_dnode;
  }
  | _IMPLEMENTS module_list __COLON_COLON __IDENTIFIER '.' __IDENTIFIER
  {
      char *interface_name = $4;
      char *method_name = $6;
      TNODE *containing_class_type = $<tnode>-6;
      TNODE *interface_type =
          tnode_lookup_interface( containing_class_type, interface_name );
      DNODE *method_dnode = interface_type ?
          tnode_lookup_method( interface_type, method_name ) : NULL;

      /* printf( ">>> '%s'\n", tnode_name(containing_class_type) ); */
      assert( containing_class_type );
      if( !interface_type ) {
          char *containing_class_name = containing_class_type ?
              tnode_name( containing_class_type ) : NULL;
          if( containing_class_name ) {
              yyerrorf( "class '%s' does not implement interface '%s'",
                        containing_class_name, interface_name );
          } else {
              yyerrorf( "this class does not implement interface '%s'",
                        interface_name );
          }
      } else {
          if( !method_dnode ) {
              yyerrorf( "interface '%s' does not declare method "
                        "'%s'", interface_name, method_name );
          }
      }
      $$ = method_dnode;
  }
  | /* empty */
  { $$ = NULL; }
  ;

method_header
  : opt_function_attributes function_code_start _METHOD
        {
	    //compiler_begin_scope( compiler_cc, px );
	}
    __IDENTIFIER opt_implements_method '(' argument_list ')'
            opt_retval_description_list
        {
	  cexception_t inner;
	  DNODE *volatile funct = NULL;
          DNODE *volatile self_dnode = NULL;
          TNODE *current_class = $<tnode>-1;
          char *method_name = $5;
          DNODE *implements_method = $6;
          DNODE *parameter_list = $8;
          DNODE *return_values = $10;
	  int is_function = 0;

    	  cexception_guard( inner ) {
              self_dnode = new_dnode_name( "self", &inner );

              dnode_insert_type( self_dnode, share_tnode( current_class ));

              parameter_list = dnode_append( parameter_list, self_dnode );
              self_dnode = NULL;

	      $$ = funct = new_dnode_method( method_name, parameter_list,
                                             return_values, &inner );

              if( implements_method ) {
                  TNODE *method_type = dnode_type( funct );
                  TNODE *implements_type = dnode_type( implements_method );
                  char msg[300];

                  if( !tnode_function_prototypes_match_msg
                      ( implements_type, method_type, msg, sizeof( msg ))) {
                      yyerrorf( "method %s() does not match "
                                "method %s it should implement"
                                " - %s",
                                method_name,
                                dnode_name( implements_method ),
                                msg );
                  } else {
                      ssize_t method_offset = dnode_offset( implements_method );
                      TNODE *interface_method_type = dnode_type( implements_method );
                      TNODE *implemented_method_type = dnode_type( funct );
                      ssize_t interface_nr = interface_method_type ?
                          tnode_interface_number( interface_method_type ) : -1;

                      dnode_set_offset( funct, method_offset );
                      tnode_set_interface_nr( implemented_method_type, interface_nr );
                      /* printf( ">>> interface = %d, method = %d\n",
                         interface_nr, method_offset ); */
                  }
              }

	      $8 = NULL;
	      $10 = NULL;
	      dnode_set_flags( funct, DF_FNPROTO );
	      if( $1 & DF_BYTECODE )
	          dnode_set_flags( funct, DF_BYTECODE );
	      if( $1 & DF_INLINE )
	          dnode_set_flags( funct, DF_INLINE );
              dnode_set_scope( funct, compiler_current_scope( compiler_cc ));
	      funct = $$ =
		  compiler_check_and_set_fn_proto( compiler_cc, funct, px );
	      share_dnode( funct );
              tnode_insert_single_method( current_class, share_dnode( funct ));
	      if( is_function ) {
		  compiler_set_function_arguments_readonly( dnode_type( funct ));
	      }
	  }
	  cexception_catch {
	      delete_dnode( $8 );
	      delete_dnode( $10 );
	      delete_dnode( funct );
              delete_dnode( self_dnode );
	      $$ = NULL;
	      cexception_reraise( inner, px );
	  }
	}
  ;

opt_semicolon
  : ';'
  | /* empty */
  ;

opt_base_class_initialisation
: __IDENTIFIER 
    {
        TNODE *type_tnode = $<tnode>-3;
        TNODE *base_type_tnode = tnode_base_type( type_tnode );
        DNODE *constructor_dnode;
        TNODE *constructor_tnode;
        DNODE *self_dnode;

        compiler_emit( compiler_cc, px, "T\n", "# Initialising base class:" );

        dlist_push_dnode( &compiler_cc->current_call_stack,
                          &compiler_cc->current_call, px );

        dlist_push_dnode( &compiler_cc->current_arg_stack,
                          &compiler_cc->current_arg, px );

        constructor_dnode = base_type_tnode ?
            tnode_constructor( base_type_tnode ) : NULL;

        constructor_tnode = constructor_dnode ?
            dnode_type( constructor_dnode ) : NULL;

        compiler_cc->current_call = share_dnode( constructor_dnode );
          
        compiler_cc->current_arg = constructor_tnode ?
            dnode_prev( dnode_list_last( tnode_args( constructor_tnode ))) :
            NULL;

        self_dnode = compiler_lookup_dnode( compiler_cc, NULL, "self", "variable" );
        compiler_push_guarding_arg( compiler_cc, px );
        compiler_compile_load_variable_value( compiler_cc, self_dnode, px );
    }
'(' opt_actual_argument_list ')' opt_semicolon
    {
        ssize_t nretval;
        nretval = compiler_compile_multivalue_function_call( compiler_cc, px );
        assert( nretval == 0 );
    }
| /* empty */
;

constructor_header
  : opt_function_attributes function_code_start _CONSTRUCTOR
        {
	    //compiler_begin_scope( compiler_cc, px );
	}
    __IDENTIFIER '(' argument_list ')'
        {
	  cexception_t inner;
	  DNODE *volatile funct = NULL;
          DNODE *volatile self_dnode = NULL;
          
          int function_attributes = $1;
          char *constructor_name = $5;
          DNODE *parameter_list = $7;
          // DNODE *return_dnode = NULL;

    	  cexception_guard( inner ) {
              TNODE *class_tnode = $<tnode>-1;

              self_dnode = new_dnode_name( "self", &inner );
              dnode_insert_type( self_dnode, share_tnode( class_tnode ));

              parameter_list = dnode_append( parameter_list, self_dnode );
              self_dnode = NULL;

              // return_dnode = new_dnode( px );
              // dnode_insert_type( return_dnode, share_tnode( class_tnode ));

	      $$ = funct = new_dnode_constructor( constructor_name,
                                                  parameter_list,
                                                  /* return_dnode = */ NULL,
                                                  &inner );
	      parameter_list = NULL;
	      // return_dnode = NULL;

              dnode_set_scope( funct, compiler_current_scope( compiler_cc ));

              tnode_insert_constructor( class_tnode, share_dnode( funct ));
              
	      dnode_set_flags( funct, DF_FNPROTO );
	      if( function_attributes & DF_BYTECODE )
	          dnode_set_flags( funct, DF_BYTECODE );
	      if( function_attributes & DF_INLINE )
	          dnode_set_flags( funct, DF_INLINE );
	      funct = $$ =
		  compiler_check_and_set_fn_proto( compiler_cc, funct, px );
              share_dnode( funct );

              /* Constructors are always functions (?): */
              /* compiler_set_function_arguments_readonly( dnode_type( funct )); */
	  }
	  cexception_catch {
	      delete_dnode( parameter_list );
	      // delete_dnode( return_dnode );
	      delete_dnode( funct );
	      $$ = NULL;
	      cexception_reraise( inner, px );
	  }
	}
  ;

operator_keyword
: function_code_start _OPERATOR
;

operator_header
  : opt_function_attributes operator_keyword
        {
	    //compiler_begin_scope( compiler_cc, px );
	}
            __STRING_CONST '(' argument_list ')'
            opt_retval_description_list
        {
	  cexception_t inner;
	  DNODE *volatile funct = NULL;

    	  cexception_guard( inner ) {
	      $$ = funct = new_dnode_operator( $4, $6, $8, &inner );
	      $6 = NULL;
	      $8 = NULL;
	      if( $1 & DF_BYTECODE )
		dnode_set_flags( funct, DF_BYTECODE );
	      if( $1 & DF_INLINE )
	          dnode_set_flags( funct, DF_INLINE );
	      $$ = funct;
              compiler_set_function_arguments_readonly( dnode_type( funct ));
	  }
	  cexception_catch {
	      delete_dnode( $6 );
	      delete_dnode( $8 );
	      delete_dnode( funct );
	      $$ = NULL;
	      cexception_reraise( inner, px );
	  }
	}
  ;

function_prototype
  : function_header
  | _FORWARD function_header
  ;

/*---------------------------------------------------------------------------*/

constant_declaration
  : _CONST __IDENTIFIER '=' constant_expression
    {
      DNODE *const_dnode = new_dnode_constant( $2, &$4, px );
      compiler_consttab_insert_consts( compiler_cc, const_dnode, px );
    }
;

constant_integer_expression
  : constant_expression
    {
	if( const_value_type( &$1 ) == VT_INT ) {
	    $$ = const_value_integer( &$1 );
	} else {
	    yyerrorf( "constant integer value required" );
	}
    }
;

field_designator
  : __IDENTIFIER '.' __IDENTIFIER
    {
	$$ = compiler_lookup_type_field( compiler_cc, NULL, $1, $3 );
    }
  | '(' type_identifier _OF delimited_type_description ')' '.' __IDENTIFIER
    {
        TNODE *composite = $2;
        composite = new_tnode_synonim( composite, px );
        tnode_set_kind( composite, TK_COMPOSITE );
        tnode_insert_element_type( composite, $4 );
        
	$$ = compiler_lookup_tnode_field( compiler_cc, composite, $7 );
    }
  | module_list __COLON_COLON __IDENTIFIER  '.' __IDENTIFIER
    {
	$$ = compiler_lookup_type_field( compiler_cc, $1, $3, $5 );
    }
  | field_designator '.' __IDENTIFIER
    {
	DNODE *field = $1;
	TNODE *tnode = field ? dnode_type( field ) : NULL;
	$$ = tnode ? tnode_lookup_field( tnode, $3 ) : NULL;
    }
;

constant_expression
  : _NULL
      { $$ = make_const_value( px, VT_NULL ); }

  | __INTEGER_CONST
      {
	  $$ = make_const_value( px, VT_INT, atol( $1 ));
      }

  | __REAL_CONST
      {
	  $$ = make_const_value( px, VT_FLOAT, atof( $1 ));
      }

  | __STRING_CONST
      {
	  $$ = make_const_value( px, VT_STRING, $1 );
      }

  | __IDENTIFIER __IDENTIFIER
      {
	  $$ = make_const_value( px, VT_ENUM, $1, $2 );
      }

  | __IDENTIFIER
      {
	DNODE *const_dnode = compiler_lookup_constant( compiler_cc, NULL, $1,
						    "constant" );
	$$ = make_zero_const_value();
	if( const_dnode ) {
	    const_value_copy( &$$, dnode_value( const_dnode ), px );
	} else {
	    $$ = make_const_value( px, VT_INT, 0 );
	}
      }

  | module_list __COLON_COLON __IDENTIFIER
      {
	DNODE *const_dnode = compiler_lookup_constant( compiler_cc, $1, $3,
						    "constant" );
	$$ = make_zero_const_value();
	if( const_dnode ) {
	    const_value_copy( &$$, dnode_value( const_dnode ), px );
	} else {
	    $$ = make_const_value( px, VT_INT, 0 );
	}
      }

  | field_designator '.' __IDENTIFIER
      {
	  $$ = compiler_get_dnode_compile_time_attribute( $1, $3, px );
      }

  | __IDENTIFIER '.' __IDENTIFIER
      {
	  $$ = compiler_make_compile_time_value( compiler_cc, NULL, $1, $3, px );
      }

  | module_list __COLON_COLON __IDENTIFIER '.' __IDENTIFIER
      {
	  $$ = compiler_make_compile_time_value( compiler_cc, $1, $3, $5, px );
      }

  | '.' __IDENTIFIER
      {
	  $$ = compiler_make_compiler_attribute( $2, px );
      }

  | constant_expression '+' constant_expression
      { $$ = const_value_add( $1, $3 ); }
  | constant_expression '-' constant_expression
      { $$ = const_value_sub( $1, $3 ); }
  | constant_expression '*' constant_expression
      { $$ = const_value_mul( $1, $3 ); }
  | constant_expression '/' constant_expression
      { $$ = const_value_div( $1, $3 ); }
  | '(' constant_expression ')'
      { $$ = $2; }
  | '-' constant_expression %prec __UNARY
      { $$ = const_value_negate( $2 ); }
  ;

%%

static void compiler_compile_file( char *filename, cexception_t *ex )
{
    cexception_t inner;

    cexception_guard( inner ) {
        yyin = fopenx( filename, "r", ex );
	if( yyparse() != 0 ) {
	    int errcount = compiler_yy_error_number();
	    cexception_raise( &inner, COMPILER_UNRECOVERABLE_ERROR,
			      cxprintf( "compiler could not recover "
					"from errors, quitting now\n"
					"%d error(s) detected\n",
					errcount ));
	} else {
	    int errcount = compiler_yy_error_number();
	    if( errcount != 0 ) {
	        cexception_raise( &inner, COMPILER_COMPILATION_ERROR,
				  cxprintf( "%d error(s) detected\n",
					    errcount ));
	    }
	}
    }
    cexception_catch {
        if( yyin ) fclosex( yyin, ex );
	cexception_reraise( inner, ex );
    }
    fclosex( yyin, ex );
}

THRCODE *new_thrcode_from_file( char *filename, char **include_paths,
                                cexception_t *ex )
{
    THRCODE *code;

    assert( !compiler_cc );
    compiler_cc = new_compiler( filename, include_paths, ex );

    compiler_compile_file( filename, ex );

    thrcode_flush_lines( compiler_cc->thrcode );
    code = compiler_cc->thrcode;
    if( compiler_cc->thrcode == compiler_cc->function_thrcode ) {
	compiler_cc->function_thrcode = NULL;
    } else
    if( compiler_cc->thrcode == compiler_cc->main_thrcode ) {
	compiler_cc->main_thrcode = NULL;
    } else {
	assert( 0 );
    }
    compiler_cc->thrcode = NULL;

    thrcode_insert_static_data( code, compiler_cc->static_data,
				compiler_cc->static_data_size );
    compiler_cc->static_data = NULL;
    delete_compiler( compiler_cc );
    compiler_cc = NULL;

    return code;
}

void compiler_printf( cexception_t *ex, char *format, ... )
{
    cexception_t inner;
    va_list ap;

    va_start( ap, format );
    assert( format );
    assert( compiler_cc );
    assert( compiler_cc->thrcode );

    cexception_guard( inner ) {
	thrcode_printf_va( compiler_cc->thrcode, &inner, format, ap );
    }
    cexception_catch {
	va_end( ap );
	cexception_reraise( inner, ex );
    }
    va_end( ap );
}

static int errcount = 0;

int compiler_yy_error_number( void )
{
    return errcount;
}

void compiler_yy_reset_error_count( void )
{
    errcount = 0;
}

int yyerror( char *message )
{
    extern char *progname;
    /* if( YYRECOVERING ) return; */
    errcount++;
    fflush(NULL);
    if( strcmp( message, "syntax error" ) == 0 ) {
	message = "incorrect syntax";
    }
    fprintf(stderr, "%s: %s(%d,%d): ERROR, %s\n", 
	    progname, compiler_cc->filename,
	    compiler_flex_current_line_number(),
	    compiler_flex_current_position(),
	    message );
    fprintf(stderr, "%s\n", compiler_flex_current_line() );
    fprintf(stderr, "%*s\n", compiler_flex_current_position(), "^" );
    fflush(NULL);
    return 0;
}

int yywrap()
{
    if( compiler_cc->include_files ) {
	compiler_close_include_file( compiler_cc, px );
	return 0;
    } else {
	return 1;
    }
}

void compiler_yy_debug_on( void )
{
#ifdef YYDEBUG
    yydebug = 1;
#endif
}

void compiler_yy_debug_off( void )
{
#ifdef YYDEBUG
    yydebug = 0;
#endif
}
