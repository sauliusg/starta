
use std;

function ff( float x, y ): float, float // a||b, (a+b)/2
{
    pragma float;
    return x*y/(x+y), (x+y)/2;
}

function sff( float x, y ): struct { float apb; float aab }
{
    var ret = new struct { float x; float y };
    ret.x, ret.y = ff( x, y );
    return ret;
}

## . ff( 2.0, 3.0 );
## 
## var apb, aab = ff( 2.0, 3.0 );
## 
## . apb, aab;

var value = sff( 2, 3 );

. value.apb, value.aab;
