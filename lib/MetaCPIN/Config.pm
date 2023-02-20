package MetaCPIN::Config v0.1.1;
use strict;
use warnings;

use Config::ZOMG;

use Moo;

my $config;
sub config {
  $config //= Config::ZOMG->new(name => 'MetaCPIN')->load;
}

1;
