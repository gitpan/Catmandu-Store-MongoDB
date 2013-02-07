package Catmandu::FileStore::GridFS;

use Catmandu::Sane;
use Moo;
use Catmandu::FileStore::GridFS::Bag;

extends 'Catmandu::Store::MongoDB';

with 'Catmandu::FileStore';

1;
