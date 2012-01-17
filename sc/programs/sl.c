/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* The main program of the compiler and interpreter. Compiles and runs
   programs written in SL/SC languages.
 */

/* uses: */

#include <stdio.h>
#include <stdlib.h> /* for getenv() */
#include <string.h>
#include <getoptions.h>
#include <thrcode.h>
#include <snail_y.h>
#include <snail_flex.h>
#include <run.h>
#include <bcalloc.h>
#include <allocx.h>
#include <stringx.h>
#include <cxprintf.h>

static char **include_paths = NULL;

static ssize_t string_count( char **strings )
{
    ssize_t len = 0;

    if( strings )
      while( strings[len] )
	len ++;

    return len;
}

static void push_string( char ***array, char *string, cexception_t *ex )
{
    ssize_t len = string_count( *array );

    *array = reallocx( *array, sizeof((*array)[0]) * (len + 2), ex );
    (*array)[len+1] = NULL;
    (*array)[len] = string;
}

static void push_path( int argc, char *argv[], int *i,
		       option_t *opt, cexception_t *ex )
{
    if( *i < argc - 1 ) {
	/* printf( "Pushing '%s'\n", argv[*i+1] ); */
	push_string( &include_paths, argv[*i+1], ex );
	(*i) ++;
    } else {
	cexception_raise( ex, SL_EXCEPTION_MISSING_INCLUDE_PATH,
			  cxprintf( "missing include path after option '%s'",
				    argv[*i] ));
    }
}

static void push_environment_paths( char ***include_paths,
                                    char *env_varname,
                                    cexception_t *ex )
{
    char *env_value;

    env_value = getenv( env_varname );

    while( env_value && *env_value ) {
        char *value = strdupx( env_value, ex );
        char *end = strchr( value, ':' );

        if( end && *end == ':' )
            *end = '\0';

        push_string( include_paths, value, ex );

        env_value = strchr( env_value, ':' );
        if( env_value && *env_value == ':' ) env_value++;
    }
}

static void gc_collect_on_hit( int argc, char *argv[], int *i,
			       option_t *opt, cexception_t *ex)
{
    bcalloc_set_gc_collector_policy( GC_ON_LIMIT_HIT );
}

static void gc_collect_always( int argc, char *argv[], int *i,
			       option_t *opt, cexception_t *ex)
{
    bcalloc_set_gc_collector_policy( GC_ALWAYS );
}

static void gc_collect_never( int argc, char *argv[], int *i,
			      option_t *opt, cexception_t *ex)
{
    bcalloc_set_gc_collector_policy( GC_NEVER );
}

static option_value_t verbose;
static option_value_t debug;
static option_value_t only_compile;
static option_value_t use_environment;

static option_t options[] = {
  { "-d", "--debug",        OT_STRING,        &debug },
  { "-c", "--compile-only", OT_BOOLEAN_TRUE,  &only_compile },
  { "-q", "--quiet",        OT_BOOLEAN_FALSE, &verbose },
  { "-q-","--no-quiet",     OT_BOOLEAN_TRUE,  &verbose },
  { NULL, "--vebose",       OT_BOOLEAN_TRUE,  &verbose },
  { "-I", "--include-path", OT_FUNCTION,      NULL, push_path },
  { "-G", "--gc-always",    OT_FUNCTION, NULL, gc_collect_always },
  { "-g", "--gc-on-hit",    OT_FUNCTION, NULL, gc_collect_on_hit },
  { "-g-","--gc-never",     OT_FUNCTION, NULL, gc_collect_never },
  { NULL, "--garbage-collect-always", OT_FUNCTION, NULL, gc_collect_always },
  { NULL, "--garbage-collect-on-hit", OT_FUNCTION, NULL, gc_collect_on_hit },
  { NULL, "--garbage-collect-never",  OT_FUNCTION, NULL, gc_collect_never },
  { NULL, "--use-environment",      OT_BOOLEAN_TRUE,  &use_environment },
  { NULL, "--dont-use-environment", OT_BOOLEAN_FALSE, &use_environment },
  { NULL, "--no-use-environment",   OT_BOOLEAN_FALSE, &use_environment },
  { NULL }
};

static int argv_has_dashes( int argc, char *argv[] )
{
    int i;

    for( i = 0; i < argc; i++ ) {
	if( argv[i] &&
	    argv[i][0] == '-' &&
	    argv[i][1] == '-' &&
	    argv[i][2] == '\0' ) {
	    return 1;
	}
    }
    return 0;
}

char *progname;

int main( int argc, char *argv[], char *env[] )
{
  cexception_t inner;
  char ** volatile files = NULL;
  THRCODE * volatile code = NULL;
  int i;

  progname = argv[0];

  cexception_guard( inner ) {
      files = get_optionsx( argc, argv, options, &inner );
  }
  cexception_catch {
      fprintf( stderr, "%s: %s\n", argv[0], cexception_message( &inner ));
      exit(1);
  }

  if( files[0] == NULL ) {
      fprintf( stderr, "%s: Usage: %s program.snl\n", argv[0], argv[0] );
      exit(2);
  }

  snail_yy_debug_off();    
  snail_flex_debug_off();    
  thrcode_debug_off();
  thrcode_trace_off();
  thrcode_stackdebug_off();
  thrcode_heapdebug_off();
  if( debug.present ) {
      if( strstr(debug.value.s, "lex") != NULL ) snail_flex_debug_yyflex();
      if( strstr(debug.value.s, "yylval") != NULL ) snail_flex_debug_yylval();
      if( strstr(debug.value.s, "text") != NULL ) snail_flex_debug_yytext();
      if( strstr(debug.value.s, "trace") != NULL ) thrcode_trace_on();
      if( strstr(debug.value.s, "yacc") != NULL ) snail_yy_debug_on();
      if( strstr(debug.value.s, "stack") != NULL ) thrcode_stackdebug_on();
      if( strstr(debug.value.s, "heap") != NULL ) thrcode_heapdebug_on();
      if( strstr(debug.value.s, "gc") != NULL ) thrcode_gc_debug_on();
      if( strstr(debug.value.s, "code") != NULL ) {
	  snail_flex_debug_lines();
	  thrcode_debug_on();
      }
  }

  cexception_guard( inner ) {
      if( !use_environment.present || use_environment.value.bool == 1 ) {
          push_environment_paths( &include_paths, "SL_INCLUDE_PATHS", &inner );
      }

      if( argv_has_dashes( argc, argv )) {
	  for( i = 0; files[i] != NULL; ) {
	      i++;
	  }
	  code = new_thrcode_from_snail_file( files[0], include_paths, &inner );

	  if( debug.present && strstr(debug.value.s, "dump") != NULL ) {
	      thrcode_dump( code );
	  }
	  if( !only_compile.value.bool ) {
	      interpret( code, i - 1, files, env, &inner );
	  }
      } else {
	  for( i = 0; files[i] != NULL; i++ ) {
	      code = new_thrcode_from_snail_file( files[i], include_paths,
						  &inner );

	      if( debug.present && strstr(debug.value.s, "dump") != NULL ) {
		  thrcode_dump( code );
	      }
	      if( !only_compile.value.bool ) {
		  interpret( code, 0/*argc*/, files, env, &inner );
	      }
	      delete_thrcode( code );
	      code = NULL;
	  }
      }
  }
  cexception_catch {
      fprintf( stderr, "%s: %s\n", argv[0], cexception_message( &inner ));
      delete_thrcode( code );
      exit(3);
  }
  delete_thrcode( code );

  return 0;
}
