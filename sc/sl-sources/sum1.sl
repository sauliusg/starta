include "stdtypes.slib";

var a : llong = 1;
var i : long;

. a;

for i = 1 to 10000000L do
    a +=  i @llong
enddo

. a;
