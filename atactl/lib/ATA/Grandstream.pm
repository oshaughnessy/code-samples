package ATA::Grandstream;
use base qw(ATA);

require 5;
use DBI;
use Carp;
use FileHandle;
use POSIX qw(tmpnam);
use strict;

# ATA model ID as listed in the ata_models table
use constant MODEL_ID     => 1;
# Path to all config files for this model of ATA
use constant CFG_DIR      => '/usr/local/grandstream/ataconfig';
# Path to an individual ATA's text config.  %s will be replaced w/the MAC
use constant TEXT_CFG     => '/usr/local/grandstream/ataconfig/%s.cfg';
# Template text file for this class of ATA
use constant CFG_TEMPLATE => 'TEMPLATE.cfg';
use constant BIN_CFG      => '/tftpboot/cfg%s';
# How to rebuild the ATA binary config.  Each %s matches the MAC addr.
use constant BIN_CMD      => '/usr/local/grandstream/bin/encode.sh %s '.
                             '/usr/local/grandstream/ataconfig/%s.cfg '.
                             '/tftpboot/cfg%s';
# How to reset the ATA.  1st %s is phone, 2nd is config pass, 3rd is MAC.
use constant RESET_CMD    => '/usr/local/grandstream/bin/reset.sh %s %s %s';

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
    my ($cfg, $tmpl, @tmpl, $newcfg, $fh);

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
    $tmpl = new FileHandle CFG_TEMPLATE;
    @tmpl = <$tmpl>;
    $tmpl->close;

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

    umask(0022);
    $cmd = sprintf BIN_CMD, $mac, $mac, $mac;
    $self->_dprint(1, "(Generating binary TFTP config... ");
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

    # remove the binary config file
    $bincfg = sprintf BIN_CFG, $self->mac;
    $self->_dprint(2, "(Removing binary config $bincfg... ");
    if (-f $bincfg) {
	unlink $bincfg or print STDERR "ERROR:  could not remove $bincfg\n";
        $self->_dprint(2, "done.)\n");
    }

    # run the superclass's delete to get rid of DB data.
    $self->SUPER::delete();

    return 1;
}


## reset():  tell the ATA to reboot itself
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
##

## reset():  tell the ATA to reboot itself
# sub reset
# {
#     my $self = shift;
#     my ($out, $sipmsg, $tmpnam, $pass);
#     my $cmd = RESET_CMD;
#     my $sipdata = RESET_DATA;
#     my $addr = 'sip:'. $self->phone. '@'. ATA::SIP_DOMAIN;
# 
#     # add verbosity to the command if we're debugging
#     $cmd .= ' -v' x ATA->Debug;
#     #for (my $i = 0; $i < ATA->Debug; $i++) {
# 
#     # create a new temporary file for the SIP message that we're going to send
#     do { $tmpnam = tmpnam() }
#     until $sipmsg = IO::File->new($tmpnam, O_RDWR|O_CREAT|O_EXCL);
#     seek($sipmsg, 0, 0);
#     print $sipmsg $sipdata;
# 
#     # add the sip message filename and sending addr to the reset cmd
#     $cmd .= ' -f '. $tmpnam. ' -s '. $addr;
# 
#     # add auth info to the reset command
#     #$cmd .= ' -u '. $self->phone;
#     $cmd .= ' -a '. $self->adminpass;
# 
#     $self->_dprint(2, "Issuing reset command...\n");
#     $self->_dprint(2, "Command:  $cmd\n");
#     if (ATA->Debug > 2) {
#         print "\nSIP message:\n====================\n";
#         system('cat', $tmpnam);                               
#         print "end of SIP message\n====================\n";
#     }
#     print "$cmd\n" if ATA->Debug > 2;
#     $out = `$cmd`;
#     if ($? != 0) {
# 	print STDERR "ERROR:  $out\n";
# 	return 0;
#     }
#     $self->_dprint(2, "Command output:\n$out\n") if $out;
# 
#     $sipmsg->close();
# 
#     -f $tmpnam and unlink($tmpnam)
#      || $self->_dprint(1, "couldn't unlink $tmpnam: $!\n");
# 
#     return 1;
# }
##


1;
