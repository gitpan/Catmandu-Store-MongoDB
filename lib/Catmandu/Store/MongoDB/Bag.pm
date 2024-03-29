package Catmandu::Store::MongoDB::Bag;

use Catmandu::Sane;
use Catmandu::Util qw(:is);
use Carp qw(confess);
use Catmandu::Store::MongoDB::Searcher;
use Catmandu::Hits;
use JSON qw(decode_json);
use Moo;

with 'Catmandu::Bag';
with 'Catmandu::Searchable';

has collection => (
    is => 'ro',
    init_arg => undef,
    lazy => 1,
    builder => '_build_collection',
);

sub _build_collection {
    my ($self) = @_;
    $self->store->database->get_collection($self->name);
}

sub generator {
    my ($self) = @_;
    sub {
        state $cursor = do {
            my $c = $self->collection->find;
            $c->immortal(1);
            $c;
        };
        $cursor->next;
    };
}

sub to_array {
    my ($self) = @_;
    my @all = $self->collection->find->all;
    \@all;
}

sub each {
    my ($self, $sub) = @_;
    my $cursor = $self->collection->find;
    my $n = 0;
    while (my $data = $cursor->next) {
        $sub->($data);
        $n++;
    }
    $n;
}

sub count {
    $_[0]->collection->count;
}

# efficiently handle:
# $bag->detect('foo' => 'bar')
# $bag->detect('foo' => /bar/)
# $bag->detect('foo' => ['bar', 'baz'])
around detect => sub {
    my ($orig, $self, $arg1, $arg2) = @_;
    if (is_string($arg1)) {
        if (is_value($arg2) || is_regex_ref($arg2)) {
            return $self->collection->find_one({$arg1 => $arg2});
        }
        if (is_array_ref($arg2)) {
            return $self->collection->find_one({$arg1 => {'$in' => $arg2}});
        }
    }
    $self->$orig($arg1, $arg2);
};

# efficiently handle:
# $bag->select('foo' => 'bar')
# $bag->select('foo' => /bar/)
# $bag->select('foo' => ['bar', 'baz'])
around select => sub {
    my ($orig, $self, $arg1, $arg2) = @_;
    if (is_string($arg1)) {
        if (is_value($arg2) || is_regex_ref($arg2)) {
            return Catmandu::Iterator->new(sub { sub {
                state $cursor = $self->collection->find({$arg1 => $arg2});
                $cursor->next;
            }});
        }
        if (is_array_ref($arg2)) {
            return Catmandu::Iterator->new(sub { sub {
                state $cursor = $self->collection->find({$arg1 => {'$in' => $arg2}});
                $cursor->next;
            }});
        }
    }
    $self->$orig($arg1, $arg2);
};

# efficiently handle:
# $bag->reject('foo' => 'bar')
# $bag->reject('foo' => ['bar', 'baz'])
around reject => sub {
    my ($orig, $self, $arg1, $arg2) = @_;
    if (is_string($arg1)) {
        if (is_value($arg2)) {
            return Catmandu::Iterator->new(sub { sub {
                state $cursor = $self->collection->find({$arg1 => {'$ne' => $arg2}});
                $cursor->next;
            }});
        }
        if (is_array_ref($arg2)) {
            return Catmandu::Iterator->new(sub { sub {
                state $cursor = $self->collection->find({$arg1 => {'$nin' => $arg2}});
                $cursor->next;
            }});
        }
    }
    $self->$orig($arg1, $arg2);
};

sub pluck {
    my ($self, $key) = @_;
    Catmandu::Iterator->new(sub { sub {
        state $cursor = $self->collection->find->fields({$key => 1});
        ($cursor->next || return)->{$key};
    }});
}

sub get {
    my ($self, $id) = @_;
    $self->collection->find_one({_id => $id});
}

sub add {
    my ($self, $data) = @_;
    $self->collection->save($data, {safe => 1});
}

sub delete {
    my ($self, $id) = @_;
    $self->collection->remove({_id => $id}, {safe => 1});
}

sub delete_all {
    my ($self) = @_;
    $self->collection->remove({}, {safe => 1});
}

sub delete_by_query {
    my ($self, %args) = @_;
    $self->collection->remove($args{query}, {safe => 1});
}

sub search {
    my ($self, %args) = @_;

    my $query = $args{query};
    my $start = $args{start};
    my $limit = $args{limit};
    my $bag   = $args{reify};

    my $cursor = $self->collection->find($query)->skip($start)->limit($limit);
    if ($bag) { # only retrieve _id
        $cursor->fields({})
    }
    if (my $sort =  $args{sort}) {
        $cursor->sort($sort);
    }

    my @hits = $cursor->all;
    if ($bag) {
        @hits = map { $bag->get($_->{_id}) } @hits;
    }

    Catmandu::Hits->new({
        start => $start,
        limit => $limit,
        total => $cursor->count,
        hits  => \@hits,
    });
}

sub searcher {
    my ($self, %args) = @_;
    Catmandu::Store::MongoDB::Searcher->new(%args, bag => $self);
}

sub translate_sru_sortkeys {
    confess "Not Implemented";
}

sub translate_cql_query {
    confess "Not Implemented";
}

# assume a string query is a JSON encoded MongoDB query
sub normalize_query {
    my ($self, $query) = @_;
    return $query if ref $query;
    return {} if !$query;
    decode_json($query);
}

1;
