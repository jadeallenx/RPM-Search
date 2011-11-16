package RPM::Search;

use strict;
use warnings;

use File::Find;
use DBI;
use Try::Tiny;

our $VERSION = '0.01';

try {
    require DBD::SQLite;
}
catch {
    die "This module requires DBD::SQLite. Try
        yum -y install perl-DBD-SQLite";
};

sub new {
    my $class = shift;
    my $proto = ref $class || $class;
    
    my $self = bless { @_ }, $proto;

    $self->find_yum_db unless $self->yum_primary_db; 
    $self->open_db unless $self->dbh;

    return $self;
}

sub cache_base {
    my $self = shift;
    my $param = shift;

    if ( $param ) {
        $self->{'cache_base'} = $param;
    }

    return $self->{'cache_base'};
}

sub yum_primary_db {
    my $self = shift;
    my $param = shift;

    if ( $param ) {
        return unless -e $param;
        $self->{'yum_primary_db'} = $param;
    }

    return $self->{'yum_primary_db'};
}

sub find_yum_db {
    my $self = shift;

    my $base = $self->cache_base() || "/var/cache/yum";


    my $path;
    find( sub {
            $path = $File::Find::name if /primary\.sqlite\z/ &&
                $File::Find::dir !~ /update/ 
          }, 
    $base);

    if ( $path ) {
        $self->yum_primary_db($path);
        return 1;
    }
    else {
        warn "Couldn't find any yum primary SQLite databases in $base";
        return 0;
    }
}

sub dbh {
    my $self = shift;
    my $param = shift;

    if ( $param ) {
        return unless ref($param) =~ /DBI/i;
        $self->{'dbh'} = $param;
    }

    return $self->{'dbh'};
}

sub open_db {
    my $self = shift;

    my $dsn = sprintf('dbi:SQLite:dbname=%s', $self->yum_primary_db);

    try {
        my $dbh = DBI->connect($dsn, undef, undef, {
                        RaiseError => 1,
                    sqlite_unicode => 1, 
                } ) or die $DBI::err;
        $self->dbh($dbh);
    }
    catch {
        die "Couldn't open db " . $self->yum_primary_db . ": $_";
    };
}

sub search {
    my $self = shift;
    my $pattern = shift;

    my $sql = "SELECT name FROM packages WHERE name ";

    if ( ref($pattern) =~ /regexp/i ) {
        $sql .= "REGEXP ?";
    }
    elsif ( $pattern =~ /[%_]/ ) {
        $sql .= "LIKE ?";
    }
    elsif ( $pattern =~ /[\?\*]/ ) {
        $sql .= "GLOB ?";
    }
    else {
        $sql .= "=?";
    }

    return $self->dbh->selectcol_arrayref($sql, undef, $pattern);
}

1;
