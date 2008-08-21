package App::MemcachedBrowser;

use strict;
use warnings;

use POE::Component::Server::HTTP;
use Cache::Memcached;
use HTML::Template;
use Data::Dumper;

sub new {
    my ($class, $server) = @_;
    my $self = bless {}, $class;

    $self->{server} = $server;
    $self->{client} = Cache::Memcached->new(servers => [ $self->{server} ]);
    return $self;
}

sub redirect {
    my ($self, $path) = @_;
    return 302, Location => $path;
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
        return RC_OK;
    }

    my $template = HTML::Template->new(filename => "tmpl/$paths[0].html");

    shift @paths;
    my ($code, %params) = $self->$method(@paths);
    if ($code == 200) {
        $template->param(server => $self->{server}, %params);
        $resp->content($template->output);
    } elsif ($code == 302) {
        my $uri = $req->uri;
        $uri->path($params{Location});
        $resp->header(Location => $uri);
    }
    $resp->code($code);
    return RC_OK;
}

sub handle_key {
    my ($self, $key, $action) = @_;

    if ($action && $action eq 'delete') {
        $self->{client}->delete($key);
        return $self->redirect('/');
    }
    my $value = Dumper($self->{client}->get($key));
    $value =~ s/^\$VAR1 = //;
    $value =~ s/;$//;
    return 200, key => $key, value => $value;
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

    return 200, keys => [ map { { key => $_} } @keys ];
}

sub handle_stats {
    my $self = shift;
    my %stats = %{ $self->stats('misc') };

    return 200, stats => [ map {
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
