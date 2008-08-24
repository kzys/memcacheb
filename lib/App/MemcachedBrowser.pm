package App::MemcachedBrowser;

use strict;
use warnings;

use POE::Component::Server::HTTP;
use Cache::Memcached;
use HTML::Template;
use YAML;
use URI::Escape;

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

    my $template = HTML::Template->new(filename => "tmpl/$paths[0].html",
                                       die_on_bad_params => 0);

    shift @paths;
    my ($code, %params) = $self->$method(@paths);
    if ($code == 200) {
        $template->param(%params);
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

    $key = uri_unescape($key);

    if ($action && $action eq 'delete') {
        $self->{client}->delete($key);
        return $self->redirect('/');
    }
    my $value = YAML::Dump($self->{client}->get($key));

    return 200,
        title => "Key: $key",
        key => $key,
        value => $value;
}

sub handle_slab {
    my ($self, $slab_id) = @_;

    return 200,
        title => "All keys on Slab #$slab_id",
        keys => [ map { { key => $_} } sort $self->slab_keys($slab_id) ];
}

sub handle_index {
    my $self = shift;

    my %slabs;
    my @lines = split /\n/, ($self->stats('slabs') || '');
    for my $line (@lines) {
        if ($line =~/^STAT (\d+):/) {
            $slabs{ $1 } = 1;
        }
    }

    return 200,
        title => 'Server: ' . $self->{server},
        slabs => [ map { { number => $_} } sort { $a <=> $b } keys %slabs ];
}

sub handle_stats {
    my $self = shift;
    my %stats = %{ $self->stats('misc') };

    return 200,
        title => 'Status',
        stats => [ map {
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
