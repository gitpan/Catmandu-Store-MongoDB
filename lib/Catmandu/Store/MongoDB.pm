package Catmandu::Store::MongoDB;

use Catmandu::Sane;
use Moo;
use Catmandu::Store::MongoDB::Bag;
use MongoDB;

with 'Catmandu::Store';

=head1 NAME

Catmandu::Store::MongoDB - A searchable store backed by MongoDB

=head1 VERSION

Version 0.0302

=cut

our $VERSION = '0.0303';

=head1 SYNOPSIS

    use Catmandu::Store::MongoDB;

    my $store = Catmandu::Store::MongoDB->new(database_name => 'test');

    my $obj1 = $store->bag->add({ name => 'Patrick' });

    printf "obj1 stored as %s\n" , $obj1->{_id};

    # Force an id in the store
    my $obj2 = $store->bag->add({ _id => 'test123' , name => 'Nicolas' });

    my $obj3 = $store->bag->get('test123');

    $store->bag->delete('test123');

    $store->bag->delete_all;

    # All bags are iterators
    $store->bag->each(sub { ... });
    $store->bag->take(10)->each(sub { ... });

    # Search
    my $hits = $store->bag->search(query => '{"name":"Patrick"}');
    my $hits = $store->bag->search(query => '{"name":"Patrick"}' , sort => { age => -1} );
    my $hits = $store->bag->search(query => {name => "Patrick"} , start => 0 , limit => 100);
    
    my $next_page = $hits->next_page;
    my $hits = $store->bag->search(query => '{"name":"Patrick"}' , page => $next_page);

    my $iterator = $store->bag->searcher(query => {name => "Patrick"});



=head1 DESCRIPTION

A Catmandu::Store::MongoDB is a Perl package that can store data into
MongoDB databases. The database as a whole is called a 'store'.
Databases also have compartments (e.g. tables) called Catmandu::Bag-s.

=head1 METHODS

=head2 new(database_name => $name , %opts )

Create a new Catmandu::Store::MongoDB store with name $name. Optionally provide
connection parameters (see MongoDB::MongoClient for possible options).

This module support to additional connection parameters:
    
    - connect_retry => NUM : connection's should be retried NUM times for success
    - connect_retry_sleep => NUM : sleep NUM seconds after any connection failure

=head2 bag($name)

Create or retieve a bag with name $name. Returns a Catmandu::Bag.

=head2 client

Return the MongoDB::MongoClient instance.

=head2 database

Return a MongoDB::Database instance.

=cut

my $CLIENT_ARGS = [qw(
    host
    w
    wtimeout
    j
    auto_reconnect
    auto_connect
    timeout
    username
    password
    db_name
    query_timeout
    max_bson_size
    find_master
    ssl
    dt_type
    inflate_dbrefs
)];

has connect_retry        => (is => 'ro', default => sub { 0 } );
has connect_retry_sleep  => (is => 'ro', default => sub { 1 } );
has client        => (is => 'ro', lazy => 1, builder => '_build_client');
has database_name => (is => 'ro', required => 1);
has database      => (is => 'ro', lazy => 1, builder => '_build_database');

sub _build_client {
    my $self  = shift;
    my $retry = $self->connect_retry;
    my $args  = delete $self->{_args};
    my $host  = $self->{_args}->{host} // 'mongodb://localhost:27017';

    do {
        $self->log->debug("Connecting to $host");
        my $client = eval { MongoDB::MongoClient->new($args) };
        if ($@) {
            die $@ unless $self->connect_retry;
            $self->log->info("Can't connect to $host. Sleeping : " .
                             $self->connect_retry_sleep .
                             " seconds ($retry retries left)");
            sleep $self->connect_retry_sleep;
        }
        else {
           return $client;
        }
    } while (--$retry > 0);

    Catmandu::Error->throw("Can't connect to $host");
}

sub _build_database {
    my $self = $_[0]; $self->client->get_database($self->database_name);
}

sub BUILD {
    my ($self, $args) = @_;
    $self->{_args} = {};
    for my $key (@$CLIENT_ARGS) {
        $self->{_args}{$key} = $args->{$key} if exists $args->{$key};
    }
}

=head1 SEE ALSO

L<Catmandu::Bag>, L<Catmandu::Searchable> , L<MongoDB::MongoClient>

=head1 AUTHOR

Nicolas Steenlant, C<< <nicolas.steenlant at ugent.be> >>

=head1 LICENSE AND COPYRIGHT

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut

1;
