/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* exports: */
#include <bctraverse.h>

/* uses: */
#include <stdio.h>
#include <alloccell.h>
#include <run.h>
#include <thrcode.h> /* for thr_heapdebug_is_on() */
#include <assert.h>

/*
node = record
   m, n : integer;
   dsc : array n of ptr;
end;

p.dsc[0], ..., p.dsc[n-1]

procedure Traverse( root : ptr )
   var k : integer; p, q, r : ptr;
begin
   p := q := root;
   loop { p != nil }
      k := p.m; p.m++; (* mark *)
      if k < p.n then
         r := p.dsc[k];
         if r != nil then
            p.dsc[k] := q; q := p; p := r;
         end if
      elsif p = q then
         exit
      else
         k := q.m - 1;
         r := q.dsc[k]; q.dsc[k] := p;
         p := q; q := r;
      end if
   end loop
end
*/

void bctraverse( void *root )
{
    alloccell_t *p, *q, *r;
    stackcell_t *s;
    ssize_t k;
    int debug = thrcode_heapdebug_is_on();

    if( !root ) return;

    p = q = root;
    for(;;) {
	assert( p != NULL );
	assert( p[-1].magic == BC_MAGIC );
	k = p[-1].rcount;
	s = (stackcell_t*)p + k;
	if( debug ) {
	    printf( "%10p (%10p) (up: %10p) nref = %4"SSIZE_FMT"d "
                    "length = %8"SSIZE_FMT"d, "
                    "k = %"SSIZE_FMT"d\n",
		    p-1, p, q, p[-1].nref, p[-1].length, k );
	}
	p[-1].flags |= AF_USED;
	p[-1].rcount ++;
	if( k < p[-1].nref ) {
	    r = s->ptr;
	    if( r != NULL && 
                ( (char*)r <  (char*)istate.code ||
		  (char*)r >= (char*)(istate.code + istate.code_length) ) &&
                (r[-1].flags & AF_USED) == 0 ) {
		s->ptr = q;
		q = p;
		p = r;
	    }
	} else if( p == q ) {
	    break;
	} else {
	    k = q[-1].rcount - 1;
            s = (stackcell_t*)q + k;
	    r = s->ptr; s->ptr = p;
	    p = q; q = r;
	}
    }
    if( debug ) {
	printf( "\n" );
    }
}
