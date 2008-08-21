package App::MemcachedBrowser;

use strict;
use warnings;

use HTTP::Status;
use Cache::Memcached;
use HTML::Template;

sub new {
    my $class = shift;
    my $self = bless {}, $class;

    $self->{server} = 'localhost:11211';
    $self->{client} = Cache::Memcached->new(servers => [ $self->{server} ]);
    return $self;
}

sub handler {
    my ($self, $req, $resp) = @_;

    my @paths = split '/', $req->uri->path;
    shift @paths;

    if (! @paths) {
        @paths = qw(index);
    }

    my $method = "handle_$paths[0]";
    if (! $self->can($method)) {
        return RC_NOT_FOUND;
    }

    my $template = HTML::Template->new(filename => "tmpl/$paths[0].html");

    shift @paths;
    my ($code, %params) = $self->$method(@paths);

    $template->param(server => $self->{server}, %params);
    $resp->content($template->output);
    return RC_OK;
}

sub handle_key {
    my ($self, $key) = @_;

    my $value = $self->{client}->get($key);
    return RC_OK, key => $key, value => $value;
}

sub handle_index {
    my $self = shift;

    my %slabs;
    my @lines = split /\n/, $self->stats('slabs');
    for my $line (@lines) {
        if ($line =~/^STAT (\d+):/) {
            $slabs{ $1 } = 1;
        }
    }

    my @keys;
    for my $slab_id (keys %slabs) {
        push @keys, $self->slab_keys($slab_id);
    }

    return RC_OK, keys => [ map { { key => $_} } @keys ];
}

sub handle_stats {
    my $self = shift;
    my %stats = %{ $self->stats('misc') };

    return RC_OK, stats => [ map {
        { key => $_, value => $stats{$_} }
    } keys %stats ];
}

sub slab_keys {
    my ($self, $slab_id) = @_;
    my @lines = split /\n/, $self->stats("cachedump $slab_id 0");

    my @result;
    for my $line (@lines) {
        if ($line =~/^ITEM ([^ ]+)/) {
            push @result, $1;
        }
    }
    @result;
}

sub stats {
    my ($self, $str) = @_;
    my $stats = $self->{client}->stats($str);
    return $stats->{hosts}->{ $self->{server} }->{ $str };
}

1;
