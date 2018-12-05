#
# Snail compiler tests
#
#
# Generic lists.
#

use * from std;

type list of T = ?{
    next : list of T;
    value : T;

    operator "+" ( l1, l2 : list of T ) : list of T
    {
	if( l1 && l2 ) {
	    var r = l1[];
	    var q = r;
	    var p = l1.next;
	    while( p != null ) {
		q.next = p[];
		q = q.next;
		p = p.next;
	    }
	    q.next = l2;
	    return r
	} else {
	    if( l1 ) {
		return l1
	    } else {
		return l2
	    }
	}
    }; // operator "+"

    inline bytecode operator "new" () : list of T
    { ALLOC %%element_size %%element_nref };

    inline bytecode operator "@list" ( i : int ) : list of int
    {
      ALLOC %%element_size %%element_nref
      OFFSET const((list of T).value.offset)
      SWAP STI
    };

    inline bytecode operator "next"( l : list of T )
    { NEXT const((list of T).next.offset) const((list of T).value.offset) }

} // type "list of T"

procedure cons( s : list of type T; l : list of type T = null ) : list of type T
{
    s.next = l;
    return s;
}

procedure cat( l1, l2 : list of T ) : list of T
{
    l1.next = l2;
    return l1
}

exception NullPointerException;

procedure tail( l : list of type T ) : list of type T
{
    if( l ) {
        return l.next
    } else {
        return null;
    }
}

// Need:

# operator 'new' : -> list of T
# operator '[]' : list of T -> address of T
# Operator 'cat': +, _
# Operator 'cons': ::
# Operator 'head': @
# Operator 'tail': _ (unary)

var l, p : list of int;

var s : list of int = new list of int;

s = 1@(list of int);

l = s + p;
l = s + cons( 2@(list of int) );
l = l + cons( 11@(list of int),
              cons( 22@(list of int) ) ) +
        cons( 3@(list of int),
              cons( 4@(list of int) );

< "( ";
foreach var i in l do
    < i, ""
enddo
. ")"
