# Functions andn procedures in Starta

module Bubble;

use * from std;

procedure sort( m : array of int ): array of int
{
    var swapped = false;
    repeat {
        swapped = false;
        for var i = 0 to last(m) - 1 {
            if( m[i] < m[i+1] ) {
                m[i], m[i+1] = m[i+1], m[i];
                swapped = true;
            }
        }
    } while( swapped );
}

function sorted( int m[] ): int[]
{
    return sort( m[] );
}

end module Bubble;
