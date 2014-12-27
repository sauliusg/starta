include "stdtypes.slib";

var a : llong = 1;
var i : llong;

. a;

for i = 1 to 10000000LL do
    // a += i
    bytecode { LLADD2 %a %i }
enddo

. a;
