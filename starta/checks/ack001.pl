#
# Ackermann functon
#

sub ack
{
    my ( $m, $n ) = @_;
    if( $m == 0 ) { return $n + 1 }
    if( $n == 0 ) { return ack( $m - 1, 1 ) }
    return ack( $m - 1, ack( $m, $n - 1 ));
}

$\ = "\n";

print ack(0,0);
print ack(1,1);
print ack(2,2);
print ack(3,3);
