use strict;
use warnings;

use MetaCPIN::App;
use Plack::Builder;

builder {
  enable 'XSendfile';
  MetaCPIN::App->new->to_app;
},
