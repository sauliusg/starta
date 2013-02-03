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
    void **base, **e;
    // void *s;
    ssize_t k, i;
    int debug = thrcode_heapdebug_is_on();

    if( !root ) return;

    p = q = root;
    for(;;) {
	assert( p != NULL );
	assert( p[-1].magic == BC_MAGIC );
        if( p[-1].nref > 0  ) {
            if( p[-1].length > 0 &&
                p[-1].element_size == sizeof(stackcell_t) ) {
                base = (void**)&(((stackcell_t*)p)->ptr);
            } else {
                // base = (void**)p;
                base = (void**)&(((stackcell_t*)p)->ptr);
            }
        } else {
            base = (void**)(&p[-1]) - 1;
        }
	k = p[-1].rcount;
        i = p[-1].nref >= 0 ? k : -k;
        e = i > 0 ? 
            (void**)(((char*)base) + 
                     /* p[-1].element_size */sizeof(stackcell_t) * i) :
            base + i;
        if( debug ) {
	    printf( "%10p (%10p) (up: %10p) nref = %4d length = %8d, k = %d\n",
		    p-1, p, q, p[-1].nref, p[-1].length, k );
	}
	p[-1].flags |= AF_USED;
	p[-1].rcount ++;
	if( k < abs( p[-1].nref )) {
	    r = *e;
	    if( r != NULL && 
                ( (char*)r <  (char*)istate.code ||
		  (char*)r >= (char*)(istate.code + istate.code_length) ) &&
                (r[-1].flags & AF_USED) == 0 ) {
		*e = q;
		q = p;
		p = r;
	    }
	} else if( p == q ) {
	    break;
	} else {
            if( q[-1].nref > 0  ) {
                if( q[-1].length > 0 &&
                    q[-1].element_size == sizeof(stackcell_t) ) {
                    base = (void**)&(((stackcell_t*)q)->ptr);
                } else {
                    // base = (void**)q;
                    base = (void**)&(((stackcell_t*)q)->ptr);
                }
            } else {
                base = (void**)(&q[-1]) - 1;
            }
	    k = q[-1].rcount - 1;
            i = q[-1].nref > 0 ? k : -k;
            e = i > 0 ?
                (void**)(((char*)base) + 
                         /* p[-1].element_size */sizeof(stackcell_t) * i) :
                base + i;
	    r = *e; *e = p;
	    p = q; q = r;
	}
    }
    if( debug ) {
	printf( "\n" );
    }
}
