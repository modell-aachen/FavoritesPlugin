#!/usr/bin/perl

use strict;
use warnings;

BEGIN {
    if (-e './setlib.cfg') {
        unshift @INC, '.';
    } elsif (-e '../bin/setlib.cfg') {
        unshift @INC, '../bin';
    }
    require 'setlib.cfg';
}

use Foswiki;
use Foswiki::Func;
use Foswiki::Meta;
use Getopt::Long;

my %cfg=(
    web         => 'Main',
    debug       => 0,
    help        => 0, 
    nodry       => 0,
);

Getopt::Long::GetOptions(
    'help|h'    => \$cfg{help},
    'nodry|n'   => \$cfg{nodry},
    'debug|d'   => \$cfg{debug},
);

if($cfg{help}){
    printHelp();
    exit 0;
}

sub printHelp {
    my $help = <<'HELP';
    -h      --help      Prints this help message.

    -n      --nodry     Actually do the conversion, only simulate otherwise

    -d      --debug     Prints debug messages.
HELP


    print $help;
    return;
}


if($ENV{ LOGNAME } ne "www-data"){
    print "logname = " .$ENV{LOGNAME}. "=> has to be www-data.\n";
    exit 0;
}

process();

sub process {
    Foswiki->new('admin');
    my $web = $cfg{web};
    debug("Starting");
    my @users = getListOfUsers();
    for my $topic (@users){
        handleTopic($web,$topic);
    }
    print "DRY RUN: No files changed!\n" unless $cfg{nodry};
    print "Done\n";
    return;
}

sub getListOfUsers{
    my @users;
    my $iterate = Foswiki::Func::eachUser();
    while($iterate->hasNext()){
        push(@users, $iterate->next());
    }
    return @users;
}

sub handleTopic{

    my ($web,$topic) = @_;
    return unless Foswiki::Func::topicExists($web,$topic);
    my ($meta, $text) = Foswiki::Func::readTopic($web, $topic);
    foreach my $favorite ($meta->find('FAVORITE')){
        my $favoriteweb = $favorite->{'web'};
        my $favoritetopic = $favorite->{'topic'};
        my $favoritename = $favorite->{'name'};
        if($favoritename=~/$favoriteweb\/$favoritetopic/gx){
            debug("Found match in $web.$topic => $favoritename");
            if($cfg{nodry}){
                $favoritename =~ s/$favoriteweb\/$favoritetopic/$favoriteweb\.$favoritetopic/gx;
                $favorite->{'name'}=$favoritename;
                $meta->putKeyed('FAVORITE', $favorite);
                debug("Changed it => $favoritename");
            }
        }
        
    }


    Foswiki::Func::saveTopic($web,$topic, $meta, $text);
    return;
}

sub debug{
    if($cfg{debug}){
        print "@_\n";
    }
    return;
}
1;

