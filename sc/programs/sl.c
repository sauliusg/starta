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
#include <grammar_y.h>
#include <lexer_flex.h>
#include <run.h>
#include <bcalloc.h>
#include <allocx.h>
#include <stringx.h>
#include <cxprintf.h>

static char *source_URL = "$URL$";

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
    cexception_t inner;
    if( *i < argc - 1 ) {
        char * volatile path = strdupx( argv[*i+1], ex );
        cexception_guard( inner ) {
            push_string( &include_paths, path, &inner );
        }
        cexception_catch {
            freex( path );
            cexception_reraise( inner, ex );
        }
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
    cexception_t inner;

    env_value = getenv( env_varname );

    while( env_value && *env_value ) {
        char *value = strdupx( env_value, ex );
        char *end = strchr( value, ':' );

        if( end && *end == ':' )
            *end = '\0';

        cexception_guard( inner ) {
            push_string( include_paths, value, &inner );
        }
        cexception_catch {
            freex( value );
            cexception_reraise( inner, ex );
        }

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

static char *usage_text[2] = {

"Compile and run an SLC program\n",

"Options:\n"

"  -c, --compile-only  Only compile a program, do not run it.\n"
"  -e, --execute '. 1' Execute a Starta program.\n"
"  -q, --quiet         Do not print file name on successful compilation.\n"
"  -q-,--verbose       Print file name and 'OK' on successful compilation.\n"
"\n"

"  -S, --stack-length  2000\n"
"      Set return (function call) stack length.\n"
"  -E, --evaluation-stack-length  2000\n"
"      Set evaluation (expression evaluation) stack length.\n"
"  -D, --stack-delta  1000\n"
"      Set stack length increment for reallocation for all stacks.\n"
"      Value 0 prevents stack reallocation.\n"
"\n"

"  -G, --gc-always\n"
"      Invoke garbage collector (GC) before every allocation\n"
"      (slow, for debugging).\n"

"  -g, --gc-on-hit\n"
"      Invoke GC when a pre-set memory limit is hit (default).\n"

"  -g-,--gc-never\n"
"      Never invoke GC (leaks memory! For debugging).\n"
"\n"

"  "
"--garbage-collect-always, "
"--garbage-collect-on-hit, "
"--garbage-collect-never\n"
"      Synonims for -G, -g and -g-, respectively.\n"
"\n"

"  -d, --debug code,flex\n"
"      Debug the compiler. Possible (comma-separated) debug flags are:\n"
"      flex  - print FLEX debug output\n"
"      yacc  - print YACC/Bison debug output\n"
"      code  - print the generated code in a bytecode assembler notation\n"
"      dump  - dump the generated code after patching addresses\n"
"      trace - print opcode names and stack top during program execution\n"
"\n"

"  -I, --include-path path/to/modules\n"
"      Add a directory for module and library (*.so*) search.\n\n"

"  --use-environment\n"
"      Use environment variable SL_INCLUDE_PATHS to search for modules\n"
"      and libraries (default). -I supplied values take precedence over\n"
"      the SL_INCLUDE_PATHS variable.\n"
"\n"

"  "
"--dont-use-environment, "
"--no-use-environment, "
"--no-environment\n"
"      Ignore the SL_INCLUDE_PATHS value, use only -I options\n"
"\n"

"  --version  print program version (SVN Id) and exit\n"

"  --help     print short usage message (this message) and exit\n"
};

static void usage( int argc, char *argv[], int *i, option_t *option,
		   cexception_t * ex )
{
    puts( usage_text[0] );
    puts( "Usage:" );
    printf( "   %s --options programs*.snl\n", argv[0] );
    printf( "   %s --options programs*.snl -- "
            "--program-options program-args\n", argv[0] );
    printf( "   %s --options -- program.snl "
            "--program-options program-args\n\n", argv[0] );
    puts( usage_text[1] );
    exit( 0 );
};

static void version( int argc, char *argv[], int *i, option_t *option,
                     cexception_t * ex )
{
    char url_keyword[6] = ".URL.";
    url_keyword[0] = '$';
    url_keyword[4] = '$';
    printf( "%s %s\n", argv[0], SVN_VERSION );
    if( strcmp( source_URL, url_keyword ) != 0 ) {
        printf( "%s\n", source_URL );
    }
    exit( 0 );
}

static option_value_t verbose;
static option_value_t debug;
static option_value_t only_compile;
static option_value_t use_environment;
static option_value_t rstack_length;
static option_value_t estack_length;
static option_value_t stack_delta;
static option_value_t program_line;

static option_t options[] = {
  { "-S", "--stack-length",            OT_INT, &rstack_length },
  { "-E", "--evaluation-stack-length", OT_INT, &estack_length },
  { "-D", "--stack-delta",  OT_INT,           &stack_delta },
  { "-d", "--debug",        OT_STRING,        &debug },
  { "-e", "--execute",      OT_STRING,        &program_line },
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
  { NULL, "--no-environment",       OT_BOOLEAN_FALSE, &use_environment },
  { NULL, "--help",         OT_FUNCTION,      NULL, &usage },
  { NULL, "--options",      OT_FUNCTION,      NULL, &usage },
  { NULL, "--version",      OT_FUNCTION,      NULL, &version },
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

extern char *progname;
char *progtail;

int main( int argc, char *argv[], char *env[] )
{
  cexception_t inner;
  char ** volatile files = NULL;
  THRCODE * volatile code = NULL;
  int i, called_as_starta = 0;

  progname = argv[0];

  progtail = progname + strlen( progname );
  while( *progtail != '/' && progtail >= progname )
      progtail --;
  progtail ++;

  /* If the compiler is called as 'starta', only options up to the
     first file name will be considered as compiler options, the rest
     will be passed to the executed program: */
  if( strcmp( progtail, "starta" ) == 0 ) {
      called_as_starta = 1;
  }

  cexception_guard( inner ) {
      if( called_as_starta ) {
          files = get_optionsx_until_first_file( argc, argv, options, &inner );
      } else {
          files = get_optionsx( argc, argv, options, &inner );
      }
  }
  cexception_catch {
      fprintf( stderr, "%s: %s\n", progname, cexception_message( &inner ));
      exit(1);
  }

  if( only_compile.value.bool && !verbose.present ) {
      verbose.value.bool = 1;
  }

#if 0
  if( files[0] == NULL ) {
      fprintf( stderr, "%s: Usage: %s program.snl\n", progname, progname );
      fprintf( stderr, "%s: please try '%s --help' for more options\n",
               progname, progname );
      exit(2);
  }
#endif
  
  compiler_yy_debug_off();    
  compiler_flex_debug_off();    
  thrcode_debug_off();
  thrcode_trace_off();
  thrcode_stackdebug_off();
  thrcode_heapdebug_off();
  if( debug.present ) {
      if( strstr(debug.value.s, "lex") != NULL ) compiler_flex_debug_yyflex();
      if( strstr(debug.value.s, "yylval") != NULL ) compiler_flex_debug_yylval();
      if( strstr(debug.value.s, "text") != NULL ) compiler_flex_debug_yytext();
      if( strstr(debug.value.s, "trace") != NULL ) thrcode_trace_on();
      if( strstr(debug.value.s, "yacc") != NULL ) compiler_yy_debug_on();
      if( strstr(debug.value.s, "stack") != NULL ) thrcode_stackdebug_on();
      if( strstr(debug.value.s, "heap") != NULL ) thrcode_heapdebug_on();
      if( strstr(debug.value.s, "gc") != NULL ) thrcode_gc_debug_on();
      if( strstr(debug.value.s, "code") != NULL ) {
	  compiler_flex_debug_lines();
	  thrcode_debug_on();
      }
  }

  cexception_guard( inner ) {
      if( !use_environment.present || use_environment.value.bool == 1 ) {
          push_environment_paths( &include_paths, "SL_INCLUDE_PATHS", &inner );
      }

      if( program_line.present ) {
          char * program = program_line.value.s;
          code = new_thrcode_from_string( program, include_paths, &inner );
          if( rstack_length.present ) {
              interpret_rstack_length( rstack_length.value.i );
          }

          if( estack_length.present ) {
              interpret_estack_length( estack_length.value.i );
          }

          if( stack_delta.present ) {
              interpret_stack_delta( stack_delta.value.i );
          }

	  if( debug.present && strstr(debug.value.s, "dump") != NULL ) {
	      thrcode_dump( code );
	  }
	  if( !only_compile.value.bool ) {
	      interpret( code, i - 1, files, env, &inner );
          } else {
              if( verbose.value.bool ) {
                  printf( "%s: '%s' -- OK\n", progname, files[0] );
              }
          }
          return 0;
      }
      
      if( argv_has_dashes( argc, argv ) || called_as_starta ) {
	  for( i = 0; files[i] != NULL; ) {
	      i++;
	  }
	  code = new_thrcode_from_file( files[0], include_paths, &inner );

          if( rstack_length.present ) {
              interpret_rstack_length( rstack_length.value.i );
          }

          if( estack_length.present ) {
              interpret_estack_length( estack_length.value.i );
          }

          if( stack_delta.present ) {
              interpret_stack_delta( stack_delta.value.i );
          }

	  if( debug.present && strstr(debug.value.s, "dump") != NULL ) {
	      thrcode_dump( code );
	  }
	  if( !only_compile.value.bool ) {
	      interpret( code, i - 1, files, env, &inner );
          } else {
              if( verbose.value.bool ) {
                  printf( "%s: '%s' -- OK\n", progname, files[0] );
              }
          }
      } else {
	  for( i = 0; files[i] != NULL; i++ ) {
	      code = new_thrcode_from_file( files[i], include_paths,
                                            &inner );

              if( rstack_length.present ) {
                  interpret_rstack_length( rstack_length.value.i );
              }

              if( estack_length.present ) {
                  interpret_estack_length( estack_length.value.i );
              }

              if( stack_delta.present ) {
                  interpret_stack_delta( stack_delta.value.i );
              }

	      if( debug.present && strstr(debug.value.s, "dump") != NULL ) {
		  thrcode_dump( code );
	      }
	      if( !only_compile.value.bool ) {
		  interpret( code, 0/*argc*/, files, env, &inner );
	      } else {
                  if( verbose.value.bool ) {
                      printf( "%s: '%s' syntax OK\n", progname, files[i] );
                  }
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
