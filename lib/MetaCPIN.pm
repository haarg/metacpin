package MetaCPIN v0.1.1;
use strict;
use warnings;

use MetaCPIN::Config;
use Types::Path::Tiny qw(AbsPath);
use Types::URI qw(Uri);
use IO::Compress::Gzip qw(gzip);
use List::Util qw(max);
use MetaCPIN::Reader::02Packages;
use MetaCPIN::Reader::JSON;

use Moo;
use experimental qw(signatures);

use namespace::clean;

has config => (
  is => 'ro',
);

has host_root => (
  is => 'lazy',
  isa => Uri,
  coerce => 1,
  default => sub ($self) { $self->config->{host_root} },
);

has cpan_root => (
  is => 'lazy',
  isa => AbsPath,
  coerce => 1,
  default => sub ($self) { $self->config->{cpan_root} },
);

has pins_root => (
  is => 'lazy',
  isa => AbsPath,
  coerce => 1,
  default => sub ($self) { $self->config->{pins_root} },
);

has source_packages => (
  is => 'lazy',
  isa => AbsPath,
  coerce => 1,
  default => sub ($self) { $self->cpan_root->child('modules/02packages.details.txt.gz') },
);

has parsed_source => (
  is => 'lazy',
  default => sub ($self) {
    my $source_packages = $self->source_packages;
    MetaCPIN::Reader::02Packages->new->parse($source_packages);
  },
);

has parsers => (
  is => 'lazy',
  default => sub ($self) {
    {
      packages  => MetaCPIN::Reader::02Packages->new,
      json      => MetaCPIN::Reader::JSON->new,
    };
  },
);

sub new_from_config ($class) {
  $class->new(config => MetaCPIN::Config->new->config);
}

sub update_pins ($self) {
  my $cpan_root = $self->cpan_root;
  my $pins_root = $self->pins_root;

  my $source_packages = $self->source_packages;
  my $source_mtime = (stat($source_packages))[9];

  my %old_pins = map {
    my ($author, $pin) = m{/([^/]+)/([^/]+)/modules/02packages\.details\.txt\.gz\z};
    defined $pin ? ("$author/$pin" => $_) : ();
  } glob "$pins_root/*/*/modules/02packages.details.txt.gz";
  my %seen_pins;
  for my $pin (sort grep -f, glob "$cpan_root/authors/id/*/*/*/pins/*") {
    my ($author, $pin, $type) = $pin =~ m{/([^/]+)/pins/([^/]+)\.([^/.]+)};
    next
      unless defined $type;
    next
      if $seen_pins{"$author/$pin"}++;

    my $out_file = "$pins_root/$author/$pin/modules/02packages.details.txt.gz";

    if (-f $out_file) {
      my $out_mtime = (stat(_))[9];
      if ($out_mtime > $source_packages && $out_mtime > (stat($pin))[9]) {
        delete $old_pins{"$author/$pin"};
        next;
      }
    }

    my $parser = $self->parsers->{$type};
    next
      if !$parser;

    eval {
      my $parsed = $parser->parse($pin);
      my $merged = $self->merge_pin($parsed);

      $merged->{header}{URL} = $self->host_root . "$author/$pin/modules/02packages.details.txt";
      $merged->{header}{'Written-By'} = __PACKAGE__ . ' version ' . __PACKAGE__->VERSION;
      $merged->{header}{'Last-Updated'} = '...';

      $self->write_packages($merged, $out_file);
      delete $old_pins{"$author/$pin"};
      1;
    } or do {
      warn $@;
    };
  }

  for my $old_pin (values %old_pins) {
    unlink $old_pin;
    if ($old_pin =~ s{\.gz\z}{}) {
      unlink $old_pin;
    }
    # we don't care if these fail
    rmdir path($old_pin)->parent;
    rmdir path($old_pin)->parent(2);
    rmdir path($old_pin)->parent(3);
  }

  return 1;
}

sub merge_pin ($self, $pin_data) {
  my $parsed_source = $self->parsed_source;

  my $clone = clone $parsed_source;
  my $lines;

  for my $package (keys $pin_data->{packages}->%*) {
    my ($version, $path) = $pin_data->{packages}->{$package}->@{qw(version path)};
    if (defined $path) {
      $clone->{packages}->{$package} = {
        version => $version,
        path    => $path,
      };
    }
    else {
      delete $clone->{packages}->{$package};
    }
  }

  my $headers = $clone->{headers};
  $headers->{'Line-Count'} = 0+scalar $clone->{packages}->%*;

  return $clone;
}

my @header_order = qw(
  File
  URL
  Description
  Columns
  Intended-For
  Written-Bo
  Line-Count
  Last-Updated
);
my %header_index = do {
  my $i = 0;
  map +($_ => $i++), @header_order;
};

sub write_packages ($self, $pin_data, $file) {
  my $compress_to;
  if ($file =~ s/\.gz\z//) {
    $compress_to = "$file.gz";
  }

  open my $fh, '>:raw', $file
    or die "can't write to $file: $!";

  my @headers = sort {
    $header_index{$a}//999 <=> $header_index{$b}//999 || $a cmp $b
  } keys $pin_data->{headers}->%*;

  my $length = 1 + max map length, @headers;

  for my $header (@headers) {
    print { $fh } sprintf "%-${length}s %s\n", "$header:", $pin_data->{headers}{$header};
  }
  print { $fh } "\n";

  my $packages = $pin_data->{packages};

  for my $package (sort {
    fc $a cmp fc $b || $a cmp $b
  } keys $packages->%*) {
    my ($version, $path) = $packages->{$package}->@{qw(version path)};

    my $plen = 30;
    my $vlen = 8;
    if (length($package) > $vlen) {
      $plen += 8 - length($version);
      $vlen = length($version);
    }
    print { $fh } sprintf "%-${plen}s %${vlen}s  %s\n", $package, $version, $path;
  }

  close $fh;

  if ($compress_to) {
    gzip $file, $compress_to;
  }
}

1;
