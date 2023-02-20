package MetaCPIN::Reader::JSON v0.1.1;
use strict;
use warnings;

use Path::Tiny;
use JSON::MaybeXS;

use Moo;
use experimental qw(signatures);

use namespace::clean;

sub parse ($file) {
  decode_json(path($file)->slurp_raw);
}

1;

