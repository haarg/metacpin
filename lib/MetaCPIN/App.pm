package MetaCPIN::App v0.1.1;
use strict;
use warnings;

use Path::Tiny;
use Plack::App::File;
use Plack::App::DirectoryIndex;
use Plack::App::Cascade;
use Plack::Builder;
use Types::Path::Tiny qw(AbsPath);
use MetaCPIN;

use Moo;
use experimental qw(signatures);

use namespace::clean;

has mpin => (
  is => 'ro',
  default => sub {
    MetaCPIN->new_from_config,
  },
);

has cpan_root => (
  is => 'lazy',
  isa => AbsPath,
  coerce => 1,
  default => sub ($self) { $self->mpin->cpan_root },
);

has pins_root => (
  is => 'ro',
  isa => AbsPath,
  coerce => 1,
  default => sub ($self) { $self->mpin->pins_root },
);

has public_root => (
  is => 'lazy',
  isa => AbsPath,
  coerce => 1,
  default => sub ($self) {
    my $root = $self->mpin->config->{public_root} // path(__FILE__)->parent(3)->child('root');
  },
);

# XXX these all need cache headers
has static_app => (
  is => 'lazy',
  default => sub ($self) {
    my $root = $self->public_root->stringify;
    Plack::App::DirectoryIndex->new(root => $root);
  },
);

# XXX redirect?
has cpan_app => (
  is => 'lazy',
  default => sub ($self) {
    my $root = $self->public_root->stringify;
    Plack::App::DirectoryIndex->new(root => $root);
  },
);

has pins_app => (
  is => 'lazy',
  default => sub ($self) {
    my $root = $self->pins_root->stringify;
    Plack::App::File->new(root => $root);
  },
);

has cpan_middleware => (
  is => 'lazy',
  default => sub ($self) {
    my $cpan_app = $self->cpan_app;
    my $pins_root = $self->pins_root;

    sub ($app) {
      sub ($env) {
        my $path_info = $env->{PATH_INFO} || '';
        $path_info =~ s{\A[\/\\]}{};
        my ($author, $pin, @parts) = split /[\/\\]/, $path_info, -1;
        if (
          !defined $author
          || $author =~ /\A\./
          || !defined $pin
          || $pin =~ /\A./
          || !-d $pins_root->child($author, $pin)
        ) {
          return $cpan_app->return_404;
        }
        $path_info = join '/', '', @parts;
        local $env->{PATH_INFO} = $path_info;
        $app->($env);
      };
    };
  },
);

has app => (
  is => 'lazy',
  default => sub ($self) {
    Plack::App::Cascade->new(apps => [
      $self->static_app->to_app,
      $self->pins_app->to_app,
      builder {
        enable $self->cpan_middleware;
        $self->cpan_app->to_app;
      },
    ]);
  },
);

sub to_app ($self) {
  my $app = $self->app;
}

1;
