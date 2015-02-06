package ATA::Sipura2000;
use base qw(ATA);

require 5;
use DBI;
use Carp;
use FileHandle;
use XML::Smart;
use strict;

use constant CFG_DIR      => '/usr/local/www/ata/%s';
use constant TEXT_CFG     => '/usr/local/www/ata/%s/spa%s.xml';
use constant CFG_TEMPLATE => 'spam2000.xml';
# How to rebuild the ATA binary config.  Each %s matches the MAC addr.
use constant BIN_CMD      => '/usr/bin/gzip %s';

# How to reset the ATA.  1st %s is phone, 2nd is config pass, 3rd is MAC.
use constant RESET_CMD    => '/usr/local/grandstream/bin/reset.sh %s %s %s';


# what codecs do the Grandstream ATAs support, and what code do they
# map to in the HandyTone TFTP config?
my %CODEC_CODES = (
    'G.711' => 0,
    'G.723' => 4,
    'G.726' => 2,
    'G.728' => 15,
    'G.729' => 18,
    'ILBC'  => 98,
    'PCMU'  => 0,
    'PCMA'  => 8,
);


# map some logical tags to field names in the Grandstream ATA config file
my %CFG_FIELDS = (
    ADMIN_PASS  => 'P2',
    USER_ID     => 'P35',
    AUTH_ID     => 'P36',
    AUTH_PASS   => 'P34',
    CALLER_ID   => 'P3',
    CODEC1      => 'P57',
    CODEC2      => 'P58',
    CODEC3      => 'P59',
    CODEC4      => 'P60',
    CODEC5      => 'P61',
    CODEC6      => 'P62',
    CODEC7      => 'P46',
    ANON_CID    => 'P65',
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
    my $self = ATA->new(@_);
    
    bless $self, $class;

    $self->_dprint(2, "Initializing a new ". __PACKAGE__. " object.");
    return $self;
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
    my ($cfg, $newcfg, $fh);

    unless (chdir(CFG_DIR)) {
        print STDERR 'Couldn\'t chdir to '. CFG_DIR. ": $!\n";
        return 0;
    }

    unless (-f CFG_TEMPLATE) {
        print STDERR 'ATA config template '. CFG_TEMPLATE. " does not exist!\n";
        return 0;
    }

    # erase any old config file and generate a new one by reading in the
    # template, replacing values, and writing it out as <mac_address>.cfg
    $cfg = XML::Smart->new(CFG_TEMPLATE);

    foreach (@tmpl) {
        $_ =~ s,\${SIP_USER},$self->phone,eg;
        $_ =~ s,\${ADMIN_PASS},$self->adminpass,eg;
        $_ =~ s,\${SIP_PASS},$self->sippass,eg;
        $_ =~ s,\${CALLER_ID},$self->callerid,eg;
        $_ =~ s,\${CODEC},$self->codec,eg;
    }

    $cfg = sprintf TEXT_CFG, $self->mac;
    $fh = new FileHandle ">$cfg";
    print $fh @tmpl;
    close $fh;
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
    my ($cfg, @cfg, $fh);
    my $codec_code = $CODEC_CODES{$self->codec};
    my $phone = $self->phone;
    my $adminpass = $self->adminpass;
    my $sippass = $self->sippass;
    my $codec = $self->codec;
    my $callerid = $self->callerid;

    unless (chdir(CFG_DIR)) {
        print STDERR 'Couldn\'t chdir to '. CFG_DIR. ": $!\n";
        return 0;
    }

    $cfg = sprintf TEXT_CFG, $self->mac;
    if (not -f $cfg) {
        print STDERR "ATA config $cfg does not exist.\n";
        return 0;
    }

    # FIX:  we should lock the config file while we read and overwrite it.
    $fh = new FileHandle "<$cfg";
    seek $fh, 0, 0;
    @cfg = <$fh>;
    $fh->close;

    foreach my $line (@cfg) {
        $line =~ s/(^$CFG_FIELDS{USER_ID})\s*=.*/$1 = $phone/o if $phone;
        $line =~ s/(^$CFG_FIELDS{AUTH_ID})\s*=.*/$1 = $phone/o if $phone;
        $line =~ s/(^$CFG_FIELDS{AUTH_PASS})\s*=.*/$1 = $sippass/o if $sippass;
        $line =~ s/(^$CFG_FIELDS{ADMIN_PASS})\s*=.*/$1 = $adminpass/o
         if $adminpass;
        $line =~ s/(^$CFG_FIELDS{CALLER_ID})\s*=.*/$1 = $callerid/o if $callerid;
        if ($codec) {
            $line =~ s/(^$CFG_FIELDS{CODEC1})\s*=.*/$1 = $codec_code/o;
            $line =~ s/(^$CFG_FIELDS{CODEC2})\s*=.*/$1 = $codec_code/o;
            $line =~ s/(^$CFG_FIELDS{CODEC3})\s*=.*/$1 = $codec_code/o;
            $line =~ s/(^$CFG_FIELDS{CODEC4})\s*=.*/$1 = $codec_code/o;
            $line =~ s/(^$CFG_FIELDS{CODEC5})\s*=.*/$1 = $codec_code/o;
            $line =~ s/(^$CFG_FIELDS{CODEC6})\s*=.*/$1 = $codec_code/o;
        }
    }

    # create a new copy of the config
    unless ($fh = new FileHandle ">$cfg.$$") {
        print STDERR "Couldn't create new config file: $!\n";
        return 0;
    }
    print $fh @cfg;
    close $fh;
    chmod 0440, "$cfg.$$";

    # now remove the old and rename the new
    unlink $cfg or do { 
        print STDERR "Couldn't remove old config file: $!\n";
        return 0;
    };
    rename("$cfg.$$", $cfg) or do {
        print STDERR "Couldn't replace old config with new: $!\n";
        return 0;
    };

    return 1;
}


# init_bin():  generate the ATA's binary TFTP config using the text cfg and
# place it in the TFTP download directory
sub init_bin
{
    my $self = shift;
    my ($cmd, $out);
    my $mac = $self->mac;

    $cmd = sprintf BIN_CMD, $mac;
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
sub reset
{
    my $self = shift;
    my ($cmd, $out);

    $cmd = sprintf RESET_CMD, $self->phone, $self->adminpass, $self->mac;
    $self->_dprint(2, "Issuing reset command...\n");
    $self->_dprint(2, "Command:  $cmd\n");
    $out = `$cmd`;
    if ($? != 0) {
    print STDERR "ERROR:  $out\n";
    return 0;
    }
    $self->_dprint(2, "Command output:\n$cmd\n") if $out;

    return 1;
}

1;
