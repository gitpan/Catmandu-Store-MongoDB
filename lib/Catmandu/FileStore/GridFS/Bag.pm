package Catmandu::FileStore::GridFS::Bag;

use Catmandu::Sane;
use Moo;
use MongoDB::GridFS;
use MongoDB::GridFS::File;
use File::Temp;

with 'Catmandu::Bag', 'Catmandu::FileBag';

has gridfs => (is => 'ro', lazy => 1, builder => '_build_gridfs');

sub _build_gridfs {
    my ($self) = @_;
    MongoDB::GridFS->new(_database => $self->store->database, prefix => $self->name);
}

sub generator {
    my ($self) = @_;
    sub {
        state $gridfs = $self->gridfs;
        state $cursor = $gridfs->files->query;
        my $data = $cursor->next // return;
        my $temp_file = File::Temp->new;
        my $grid_file = MongoDB::GridFS::File->new(_grid => $gridfs, info => $data);
        $grid_file->print($temp_file);
        $temp_file->seek(0, 0);
        $data->{_file} = $temp_file;
        $data;
    };
}

sub get {
    my ($self, $id) = @_;
    my $grid_file = $self->gridfs->get($id) // return;
    my $temp_file = File::Temp->new;
    $grid_file->print($temp_file);
    $temp_file->seek(0, 0);
    my $data = $grid_file->info;
    $data->{_file} = $temp_file;
    $data;
}

sub add {
    my ($self, $data) = @_;
    my $info = {%$data};
    my $file = delete $info->{_file};
    $self->gridfs->put($file, $info); # compares md5 hashes
    $data;
}

sub delete {
    my ($self, $id) = @_;
    $self->gridfs->delete($id);
}

sub delete_all {
    my ($self) = @_;
    for my $collection (qw(files chunks)) {
        $self->gridfs->$collection->remove({}, {safe => 1});
    }
}

sub count {
    my ($self) = @_;
    $self->gridfs->files->count;
}

1;
