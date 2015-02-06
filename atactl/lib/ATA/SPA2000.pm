# $Id: SPA2000.pm,v 1.2 2005/07/25 21:32:07 root Exp $

package ATA::SPA2000;
use base qw(ATA);

require 5;
use DBI;
use Carp;
use FileHandle;
use XML::Smart;
use strict;

# ATA model ID as listed in the ata_models table
use constant MODEL_ID     => 2;
# Path to all config files for this model of ATA
use constant CFG_DIR      => '/usr/local/www/ata/spa2000';
# Path to an individual ATA's text config.  %s will be replaced w/the MAC
use constant TEXT_CFG     => '/usr/local/www/ata/spa2000/spa%s.xml';
# Template text file for a Sipura SPA2000
use constant CFG_TEMPLATE => 'TEMPLATE.xml';
# How to rebuild the ATA binary config.  Each %s matches the MAC addr.
use constant BIN_CMD      => '/usr/bin/gzip -f -c '.
                             '/usr/local/www/ata/spa2000/spa%s.xml >'.
                             '/usr/local/www/ata/spa2000/spa%s.xml.gz';
# How to reset the ATA.  1st %s is phone, 2nd is config pass, 3rd is MAC.
#use constant RESET_CMD    => '/usr/local/grandstream/bin/reset.sh %s %s %s';


# what codecs do the Sipura SPA-2000 ATAs support, and what code do they
# map to in the config?
# Available codecs:  G711u G711a G726-16 G726-24 G726-32 G726-40 G729a G723
my %CODEC_CODES = (
    'G.711' => 'G711u',
    'G.723' => 'G723',
    'G.726' => 'G726-16',
    'G.729' => 'G729a',
);


# map some logical tags to field names in the Sipura ATA template config
# for replacement in the init_text function
my %CFG_TAGS = (
    ADMIN_PASS  => 'Admin_Passwd',
    AUTH_ID     => 'User_ID_1_',
    AUTH_PASS   => 'Password_1_',
    CALLER_ID   => 'Display_Name_1_',
    CODEC1      => 'Preferred_Codec_1_',
);


##
# new():
# Create, initialize, and return a new ATA::Grandstream object.
# 
##
sub new
{
    my $class = shift;
    my %params = @_;

    if ($params{phone2}) {
        croak("Sorry, but this type of ATA doesn't support multiple lines.\n");
        return undef;
    }
    else {
        my $self = ATA->new(@_, model_id => MODEL_ID);
        
        bless $self, $class;

        $self->_dprint(2, "Initializing a new ". __PACKAGE__. " object.");
        return $self;
    }
}


# init():  save the info to the DB and generate all new config files 
# for the ATA
sub init
{
    my $self = shift;

    # commit the cached data
    $self->commit;

    # generate a fresh text config
    $self->init_text;

    # generate a fresh binary config
    $self->init_bin;
}


# update():  save the info to the DB and modify the existing config files
# for the ATA
sub update
{
    my $self = shift;

    # commit the cached data
    $self->commit;

    # modify the existing text config
    $self->update_text;

    # generate a fresh binary config
    $self->init_bin;
}


# init_text():  create a new text config for the ATA by customizing the
# template file with the object's unique data
sub init_text
{
    my $self = shift;
    my ($xml, $cfg);

    unless (chdir(CFG_DIR)) {
        print STDERR 'Couldn\'t chdir to '. CFG_DIR. ": $!\n";
        return 0;
    }

    unless (-f CFG_TEMPLATE) {
        print STDERR 'ATA config template '. CFG_TEMPLATE. " does not exist!\n";
        return 0;
    }

    # read in the XML template, adjust according to the object data, and save
    $xml = XML::Smart->new(CFG_TEMPLATE) or do {
        print STDERR "Couldn't load new XML config from ". CFG_TEMPLATE. "\n";
        return 0;
    };
    $xml->{'flat-profile'}->{$CFG_TAGS{ADMIN_PASS}} = $self->adminpass if $self->adminpass;
    $xml->{'flat-profile'}->{$CFG_TAGS{AUTH_ID}} = $self->phone if $self->phone;
    $xml->{'flat-profile'}->{$CFG_TAGS{AUTH_PASS}} = $self->sippass if $self->sippass;
    $xml->{'flat-profile'}->{$CFG_TAGS{CALLER_ID}} = $self->callerid if $self->callerid;
    $xml->{'flat-profile'}->{$CFG_TAGS{CODEC1}} = $self->codec if $self->codec;

    # figure out the path to the new config file (derived from the MAC addr)
    $cfg = sprintf TEXT_CFG, $self->mac;

    # if it already exists, delete it
    if (-f $cfg) {
        unlink $cfg or do { 
            print STDERR "Couldn't remove old config file: $!\n";
            return 0;
        }
    };

    # now save the data
    $xml->save($cfg) or do {
        print STDERR "Couldn't save new XML config $cfg: $!\n";
        return 0;
    };
    chmod 0440, $cfg;

    return 1;
}


# update_text():  similar to init_text(), but modifies the text file in place
# with current data rather than starting from scratch with the TEMPLATE.
# If the object doesn't know a bit of data, it won't be changed in the text
# file.
sub update_text
{
    my $self = shift;
    my ($cfg, $xml);
    my $codec_code = $CODEC_CODES{$self->codec};

    unless (chdir(CFG_DIR)) {
        print STDERR 'Couldn\'t chdir to '. CFG_DIR. ": $!\n";
        return 0;
    }

    $cfg = sprintf TEXT_CFG, $self->mac;
    $self->_dprint(3, "Updating config file $cfg\n");
    if (not -f $cfg) {
        print STDERR "ATA config $cfg does not exist.\n";
        return 0;
    }

    # read in the XML template, adjust according to the object data, and save
    $xml = XML::Smart->new($cfg);
    $xml->{'flat-profile'}->{$CFG_TAGS{ADMIN_PASS}} = $self->adminpass if $self->adminpass;
    $xml->{'flat-profile'}->{$CFG_TAGS{AUTH_ID}} = $self->phone if $self->phone;
    $xml->{'flat-profile'}->{$CFG_TAGS{AUTH_PASS}} = $self->sippass if $self->sippass;
    $xml->{'flat-profile'}->{$CFG_TAGS{CALLER_ID}} = $self->callerid if $self->callerid;
    $xml->{'flat-profile'}->{$CFG_TAGS{CODEC1}} = $self->codec if $self->codec;

    # now save the data
    $xml->save($cfg) or do {
        print STDERR "Could not save $cfg:  $!.\n";
        return 0;
    };
    chmod 0644, $cfg;

    return 1;
}


# init_bin():  generate the ATA's binary TFTP config using the text cfg and
# place it in the TFTP download directory
sub init_bin
{
    my $self = shift;
    my ($cmd, $out);
    my $mac = $self->mac;

    $cmd = sprintf BIN_CMD, $mac, $mac;
    $self->_dprint(1, "(Generating binary config... ");
    $out = `$cmd`;
    if ($? != 0) {
        print STDERR "ERROR:  $out\n";
        return 0;
    }
    $self->_dprint(1, "done.)");
    $self->_dprint(3, "Command output:\n$cmd\n") if $out;

    return 1;
}


# delete():  delete all files associated with the ATA
sub delete
{
    my $self = shift;
    my ($txtcfg, $bincfg, $ok);

    # remove the text config file
    unless (chdir(CFG_DIR)) {
        print STDERR 'Couldn\'t chdir to '. CFG_DIR. ": $!\n";
        return 0;
    }

    $txtcfg = sprintf TEXT_CFG, $self->mac;
    $self->_dprint(2, "(Removing text config $txtcfg... ");
    if (-f $txtcfg) {
    unlink $txtcfg or print STDERR "ERROR:  could not remove $txtcfg\n";
        $self->_dprint(2, "done.)\n");
    }

    # run the superclass's delete to get rid of DB data.
    $self->SUPER::delete();

    return 1;
}


# reset():  tell the ATA to reboot itself
##
# sub reset
# {
#     my $self = shift;
#     my ($cmd, $out);
# 
#     $cmd = sprintf RESET_CMD, $self->phone, $self->adminpass, $self->mac;
#     $self->_dprint(2, "Issuing reset command...\n");
#     $self->_dprint(2, "Command:  $cmd\n");
#     $out = `$cmd`;
#     if ($? != 0) {
#     print STDERR "ERROR:  $out\n";
#     return 0;
#     }
#     $self->_dprint(2, "Command output:\n$cmd\n") if $out;
# 
#     return 1;
# }
##

1;


##
# Revision history
# ================
# 
# $Log: SPA2000.pm,v $
# Revision 1.2  2005/07/25 21:32:07  root
# keep model ID in a constant
# error out if a 2nd line is requested
#
# Revision 1.1  2005/07/07 00:09:40  root
# Initial revision
#
##
