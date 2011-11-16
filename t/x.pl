use RPM::Search;
use Data::Printer;

my $rpm = RPM::Search->new();

p $rpm;

p $rpm->search(qr/perl-Mo.se/);

p $rpm->search('perl-CG%');

p $rpm->search('perl-CG*');

p $rpm->search('perl-CGI');
