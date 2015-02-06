# $Id: SPA2102.pm,v 1.1 2007/12/20 23:58:01 shaug Exp shaug $

package ATA::SPA2102;
use base qw(ATA);

require 5;
use DBI;
use Carp;
use XML::Smart;
use IO::File;
use POSIX qw(tmpnam);
use strict;

# ATA model ID as listed in the ata_models table
use constant MODEL_ID     => 5;
# Path to all config files for this model of ATA
use constant CFG_DIR      => '/usr/local/www/ata/spa2102';
# Path to an individual ATA's text config.  %s will be replaced w/the MAC
use constant TEXT_CFG     => '/usr/local/www/ata/spa2102/%s.xml';
# Template text file for this class of ATA
use constant CFG_TEMPLATE => 'TEMPLATE.xml';
# How to rebuild the ATA binary config.  Each %s matches the MAC addr.
use constant BIN_CMD      => '/usr/bin/gzip -f -c '.
                             '/usr/local/www/ata/spa2102/%s.xml >'.
                             '/usr/local/www/ata/spa2102/%s.xml.gz';
# How to reset the ATA.  1st %s is phone, 2nd is config pass, 3rd is MAC.
#use constant RESET_CMD    => '/usr/local/grandstream/bin/reset.sh %s %s %s';
use constant RESET_CMD    => 'sipsak -p sip.example.org -r 5060 -G';

# What's the SIP packet look like that will be sent to reset an ATA?
use constant RESET_DATA   => <<EOdata;
NOTIFY sip:\$user\$@\$dsthost\$ SIP/2.0\r
From: <sip:provisioning@\$srchost\$>\r
To: <sip:\$user\$@\$dsthost\$>\r
Contact: <sip:\$user\$@\$dsthost\$>\r
Call-ID: abcd01234567abcdef01234567abcdef@\$srchost\$\r
CSeq: 1 NOTIFY\r
User-Agent: sipsak\r
Event: resync\r
Content-Type: text/plain\r
Content-Length: 0\r
\r
EOdata


# what codecs do these ATAs support and what label do they map to in the config?
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

    LINE_1      => 'Line_Enable_1_',
    AUTH_ID     => 'User_ID_1_',
    AUTH_PASS   => 'Password_1_',
    CALLER_ID   => 'Display_Name_1_',
    CODEC1      => 'Preferred_Codec_1_',

    LINE_2      => 'Line_Enable_2_',
    AUTH_ID2    => 'User_ID_2_',
    AUTH_PASS2  => 'Password_2_',
    CALLER_ID2  => 'Display_Name_2_',
    CODEC2      => 'Preferred_Codec_2_',
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
    my $self = ATA->new(@_, model_id => MODEL_ID);
    
    bless $self, $class;

    $self->_dprint(2, "Initializing a new ". __PACKAGE__. " object.\n");
    return $self;
}


# init():  save the info to the DB and generate all new config files 
# for the ATA
sub init
{
    my $self = shift;

    # run the super-class's update
    $self->SUPER::update;

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

    # run the super-class's update
    $self->SUPER::update;

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

    $self->_dprint(1, "(Generating text config... ");

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
    $self->_xml_update($xml);

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
    $xml->save($cfg, noheader => 1, nometagen => 1) or do {
        print STDERR "Couldn't save new XML config $cfg: $!\n";
        return 0;
    };
    chmod 0440, $cfg;

    $self->_dprint(1, "done.)");

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

    $self->_dprint(1, "(Updating text config... ");

    unless (chdir(CFG_DIR)) {
        print STDERR 'Couldn\'t chdir to '. CFG_DIR. ": $!\n";
        return 0;
    }

    $cfg = sprintf TEXT_CFG, $self->mac;
    $self->_dprint(3, "Updating config file $cfg\n");
    if (not -f $cfg) {
        return $self->init_text;
	#print STDERR "ATA config $cfg does not exist.\n";
        #return 0;
    }

    # read in the XML template, adjust according to the object data, and save
    $xml = XML::Smart->new($cfg);
    $self->_xml_update($xml);

    # now save the data
    $xml->save($cfg, noheader => 1, nometagen => 1) or do {
        print STDERR "Could not save $cfg:  $!.\n";
        return 0;
    };
    chmod 0644, $cfg;

    $self->_dprint(1, "done.)");

    return 1;
}


# _xml_update():  internal function that modifies an XML::Smart object
# based on what the ATA knows about itself
sub _xml_update
{
    my ($self, $xml) = @_;
    my ($codec_code, $codec_code2);
    
    if ($self->codec) {
        $codec_code = exists $CODEC_CODES{$self->codec}
                      ? $CODEC_CODES{$self->codec} : $self->codec;
    }
    if ($self->codec2) {
        $codec_code2 = exists $CODEC_CODES{$self->codec2}
                       ? $CODEC_CODES{$self->codec2} : $self->codec2;
    }

    $xml->{'flat-profile'}->{$CFG_TAGS{ADMIN_PASS}} = $self->adminpass
     if $self->adminpass;

    if ($self->phone) {
        $xml->{'flat-profile'}->{$CFG_TAGS{LINE_1}} = 'Yes';
        $xml->{'flat-profile'}->{$CFG_TAGS{AUTH_ID}} = $self->phone;
        $xml->{'flat-profile'}->{$CFG_TAGS{AUTH_PASS}} = $self->sippass
         if $self->sippass;
        $xml->{'flat-profile'}->{$CFG_TAGS{CALLER_ID}} = $self->callerid
         if $self->callerid;
        $xml->{'flat-profile'}->{$CFG_TAGS{CODEC1}} = $codec_code
         if $codec_code;
    }
    else {
        $xml->{'flat-profile'}->{$CFG_TAGS{LINE_1}} = 'No';
    }

    if ($self->phone2) {
        my $sippass = $self->sippass2 or $self->sippass;

        $xml->{'flat-profile'}->{$CFG_TAGS{LINE_2}} = 'Yes';
        $xml->{'flat-profile'}->{$CFG_TAGS{AUTH_ID2}} = $self->phone2;
        $xml->{'flat-profile'}->{$CFG_TAGS{AUTH_PASS2}} = $sippass
         if defined $sippass;
        $xml->{'flat-profile'}->{$CFG_TAGS{CALLER_ID2}} = $self->callerid2
         if $self->callerid2;
        $xml->{'flat-profile'}->{$CFG_TAGS{CODEC2}} = $codec_code2
         if $codec_code2;
    }
    else {
        $xml->{'flat-profile'}->{$CFG_TAGS{LINE_2}} = 'No';
    }
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
# if all lines are being removed, remove the text config.  otherwise
# we have to regenerate the text config after running the superclass delete.
sub delete
{
    my ($self, @phones) = @_;
    my ($txtcfg, $bincfg, $ok);

    # run the superclass's delete to get rid of DB data.
    $self->SUPER::delete(@phones);

    # check to see if there's anything left of this ATA
    # if so, regenerate the configs.
    # if not, remove them.
    if ($self->exists) {
        $self->update;
    }
    else {
        unless (chdir(CFG_DIR)) {
            print STDERR 'Couldn\'t chdir to '. CFG_DIR. ": $!\n";
            return 0;
        }

        $txtcfg = sprintf TEXT_CFG, $self->mac;
        $self->_dprint(2, "(Removing text config $txtcfg... ");
        if (-f $txtcfg) {
            unlink $txtcfg
             or print STDERR "ERROR:  could not remove $txtcfg\n";
        }
        if (-f "$txtcfg.gz") {
            unlink "$txtcfg.gz"
             or print STDERR "ERROR:  could not remove $txtcfg.gz\n";
        }
        $self->_dprint(2, "done.)\n");
    }

    return 1;
}


# reset():  tell the ATA to reboot itself
sub reset
{
    my $self = shift;
    my ($out, $sipmsg, $tmpnam, $pass);
    my $cmd = RESET_CMD;
    my $sipdata = RESET_DATA;
    my $addr = 'sip:'. $self->phone. '@'. ATA::SIP_DOMAIN;

    # add verbosity to the command if we're debugging
    $cmd .= ' -v' x ATA->Debug;
    #for (my $i = 0; $i < ATA->Debug; $i++) {

    # create a new temporary file for the SIP message that we're going to send
    do { $tmpnam = tmpnam() }
    until $sipmsg = IO::File->new($tmpnam, O_RDWR|O_CREAT|O_EXCL);
    seek($sipmsg, 0, 0);
    print $sipmsg $sipdata;

    # add the sip message filename and sending addr to the reset cmd
    $cmd .= ' -f '. $tmpnam. ' -s '. $addr;

    # add auth info to the reset command
    #$cmd .= ' -u '. $self->phone;
    $cmd .= ' -a '. $self->adminpass;

    $self->_dprint(2, "Issuing reset command...\n");
    $self->_dprint(2, "Command:  $cmd\n");
    if (ATA->Debug > 2) {
        print "\nSIP message:\n====================\n";
        system('cat', $tmpnam);                               
        print "end of SIP message\n====================\n";
    }
    print "$cmd\n" if ATA->Debug > 2;
    $out = `$cmd`;
    if ($? != 0) {
	print STDERR "ERROR:  $out\n";
	return 0;
    }
    $self->_dprint(2, "Command output:\n$out\n") if $out;

    $sipmsg->close();

    -f $tmpnam and unlink($tmpnam)
     || $self->_dprint(1, "couldn't unlink $tmpnam: $!\n");

    return 1;
}

1;


##
# Revision history
# ================
# 
# $Log: SPA2102.pm,v $
# Revision 1.1  2007/12/20 23:58:01  shaug
# Initial revision
#
# Revision 1.4  2006/07/25 22:43:43  root
# fixed codec updates.  strings in %CODEC_CODES are used instead of the
# names passed to the update function if the given name exists.  if it
# doesn't, the string as given is used.
#
# Revision 1.3  2005/07/25 21:33:34  root
# added 2nd-line support
# added tentative support for reset()
#
# Revision 1.1  2005/07/07 00:09:40  root
# Initial revision
#
##
