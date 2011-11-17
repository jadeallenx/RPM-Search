package RPM::Search;

use strict;
use warnings;

use File::Find;
use DBI;
use Try::Tiny;

our $VERSION = '0.01';

=head1 NAME

RPM::Search

=head1 SYNOPSIS

  # On (recent) RPM based systems
  my $db = RPM::Search->new();

  my $aref = $db->search(qr/perl-Mo\.se/);
  # or
  $aref = $db->search('perl-CGI-*');
  # or
  $aref = $db->search('cpanminus');

  if ( $aref ) {
    my $pkgs = join ", ", @{ $aref };
    `/usr/bin/yum -y install $pkgs`;
  }
  else {
      print "No matching packages\n";
  }

=head1 ATTRIBUTES

=over

=item *

cache_base - base location of the yum data (default: none)

=item *

yum_primary_db - fully qualified path to the primary SQLite database 
(default: none)

=item *

dbh - DBI handle to the yum SQLite database

=back

=head1 METHODS

=over

=item new()

Make a new L<RPM::Search|RPM::Search> object.  Will automatically search 
for an appropriate yum database and open a handle to the data set 
unless you pass valid arguments to the F<dbh> and/or F<yum_primary_db>
attributes at construction time.

Returns a new L<RPM::Search|RPM::Search> object.

=back

=cut

sub new {

    try {
        require DBD::SQLite;
    }
    catch {
        die "This module requires DBD::SQLite. Try:\n\tsudo yum -y install perl-DBD-SQLite\n";
    };

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
        return unless -d $param;
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

sub dbh {
    my $self = shift;
    my $param = shift;

    if ( $param ) {
        return unless ref($param) =~ /DBI/i;
        $self->{'dbh'} = $param;
    }

    return $self->{'dbh'};
}

=over

=item find_yum_db()

This method searches for an appropriate yum database starting at the 
location passed as a parameter. If no parameter is given, the method
will use F<cache_base>. If F<cache_base> is not set, the method will 
use F</var/cache/yum>.

This call populates F<yum_primary_db>.

The return value is boolean: true for success, false for failure.

=back

=cut

sub find_yum_db {
    my $self = shift;
    my $base = shift || $self->cache_base() || "/var/cache/yum";


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
        warn "Couldn't find any yum primary SQLite databases in $base\n";
        return 0;
    }
}

=over

=item open_db()

This method opens a connection to the yum SQLite database.  The DSN
is constructed from the passed in parameter.  If no parameter is
passed in, the method will use F<yum_primary_db>.

This method populates F<dbh>.

This method causes a fatal error on any failure.

=back

=cut

sub open_db {
    my $self = shift;
    my $dbname = shift || $self->yum_primary_db;

    try {
        my $dbh = DBI->connect("dbi:SQLite:dbname=$dbname", undef, undef, {
                        RaiseError => 1,
                    sqlite_unicode => 1, 
                } ) or die $DBI::err;
        $self->dbh($dbh);
    }
    catch {
        die "Couldn't open db $dbname: $_\n";
    };
}

=over

=item search()

This method searches the RPM database using a 

=back

=cut

sub search {
    my $self = shift;
    my $pattern = shift;

    unless ( $pattern ) {
        warn "You must pass a pattern.\n";
        return undef;
    }

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

    try {
        return $self->dbh->selectcol_arrayref($sql, undef, $pattern) or die $DBI::err;
    }
    catch {
        warn "Couldn't execute query $sql: $_\n";
        return undef;
    }
}

1;
