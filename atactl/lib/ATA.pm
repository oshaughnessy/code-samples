# $Id: ATA.pm,v 1.9 2007/07/17 18:29:54 root Exp root $

package ATA;
use base qw(Class::Data::Inheritable);

##
# This includes maintaining the our_atas table in the ser database,
# modifying an ATA's config settings, and generating a new TFTP config.
# 
# We're expecting the ser our_atas table to look something like this:
# 
#     CREATE TABLE `our_atas` (
#       `macaddr` varchar(12) NOT NULL default '',
#       `line` smallint(6) NOT NULL default '1',
#       `username` varchar(64) NOT NULL default '',
#       `config_password` varchar(25) NOT NULL default '',
#       `codec` varchar(8) default NULL,
#       `model_id` smallint(6) default NULL,
#       PRIMARY KEY  (`macaddr`,`line`),
#       KEY `username` (`username`)
#     ) ENGINE=MyISAM;
# 
##

require 5;
use DBI;
use Carp;


# class variables
# - Module version
ATA->mk_classdata('Version');
ATA->Version('0.1');
# - DBI data source name (see 'perldoc DBI' for more info).
#   This will be used to store data about the ATA.
ATA->mk_classdata('DSN');
# - DBI connection handle.
ATA->mk_classdata('DBH');
# - Debugging level; affects verbosity
ATA->mk_classdata('Debug');
ATA->Debug(0);
# - track the number of ATA objects so we know when to disconnect from the DB
ATA->mk_classdata('count');

##
## class variables
##
# our %ATA = (
#     # - module version
#     Version => '0.1',
# 
#     # - DBI data source name (see 'perldoc DBI' for more info).
#     #   This will be used to store data about the ATA.
#     DSN => undef,
#     # - DBI connection handle.
#     DBH => undef,
# 
#     # - Debugging level; affects verbosity
#     Debug => 0,
# );
# 
# # tri-natured: function, class method, or object method
# # (see http://perldoc.perl.org/perltooc.html#The-Eponymous-Meta-Object)
# sub _classobj {
#     my $obclass = shift || __PACKAGE__;
#     my $class   = ref($obclass) || $obclass;
#     no strict "refs";   # to convert sym ref to real one
#     return \%$class;
# }
# 
# # create access functions for each class data variable
# # (see http://perldoc.perl.org/perltooc.html)
# for my $datum (keys %{ _classobj() }) {
#     # turn off strict refs so that we can
#     # register a method in the symbol table
#     no strict "refs";
#     *$datum = sub {
#         use strict "refs";
#         my $self = shift->_classobj();
#         $self->{$datum} = shift if @_;
#         return $self->{$datum};
#     } 
# } 
##


##
## private variables
##


# Maker MAC address prefixes:  each one of these should be able to uniquely
# identify the maker of a particular type of ATA.
my %MAKER_MACS = (
    '000b82' => 'Grandstream',
    '000e08' => 'Sipura-SPA2000',
    '001310' => 'Linksys-WRT54GP2',
    '001217' => 'Linksys-WRT54GP2',
    #'000e08' => 'Linksys',
);

# default audio codec
use constant DEF_CODEC => 'G.711';

# SIP domain shared by all phone accounts
use constant SIP_DOMAIN => 'example.org';

# - SQL info for working with the ATA information tables
my %ATA_DB = (
    CREATE   => 'INSERT into our_atas (macaddr, line, username, '.
                'config_password, codec, model_id) VALUES (?, ?, ?, ?, ?, ?)',
    DELETE   => 'DELETE from our_atas where username = ? and macaddr = ?',
    GET_ALL  => 'SELECT * from our_atas where username = ? and macaddr = ?',

    CHECK_PHONE  => 'SELECT username from our_atas where username = ?',
    GET_PHONES   => 'SELECT username from our_atas where macaddr = ? '.
                    'ORDER BY line',

    GET_LINE     => 'SELECT line from our_atas where username = ?',

    GET_MACS     => 'SELECT macaddr from our_atas where username = ?',
    CHANGE_MAC   => 'UPDATE our_atas set macaddr = ? '.
                    'where username = ? and macaddr = ?',

    GET_PASS     => 'SELECT config_password from our_atas '.
                    'where username = ? and macaddr = ?',
    CHANGE_PASS  => 'UPDATE our_atas set config_password = ? '.
                    'where username = ? and macaddr = ?',

    GET_CODEC    => 'SELECT codec from our_atas '.
                    'where username = ? and macaddr = ?',
    CHANGE_CODEC => 'UPDATE our_atas set codec = ? '.
                    'where username = ? and macaddr = ?',

    GET_CALLERID => 'SELECT first_name, last_name from subscriber '.
                    'where username = ?',

    GET_SIPPASS  => 'SELECT password from subscriber where username = ?',

    GET_MAKERS   => 'SELECT distinct vendor from ata_models '.
                    'ORDER BY vendor ASC',
    GET_MODELS   => 'SELECT vendor,model from ata_models '.
                    'ORDER BY vendor ASC',
    GET_MAKER_MODELS   => 'SELECT model from ata_models where vendor = ?',
    GET_MAKER_MODEL_ID => 'SELECT id from ata_models '.
                         'where vendor = ? and model = ?',
    GET_MODEL_ID      => 'SELECT id from ata_models '.
                         'where id = ?',
    GET_MODEL_INFO    => 'SELECT vendor,model from ata_models '.
                         'where id = ?',
    GET_ATA_MODEL_ID  => 'SELECT model_id from our_atas '.
                         'where username = ? and macaddr = ?',
    CHANGE_MODEL_ID   => 'UPDATE our_atas set model_id = ? '.
                         'where username = ? and macaddr = ?',
);


##
# new():
# Create, initialize, and return a new ATA object.
# 
##
sub new
{
    my $class = shift;
    my %params = @_;
    my $self = {};
    my $count = ATA->count + 1;

    $class = ref $class if ref $class;
    bless $self, $class;

    #
    # class data
    #
    ATA->Debug($params{debug}) if exists $params{debug};
    $self->_dprint(2, "Initializing a new ". __PACKAGE__.
                      " object (#$count).\n");
    if ($params{dsn}) {
        # only update the DSN if it has changed
        if (!ATA->DSN or ATA->DSN && $params{dsn} != ATA->DSN) {
            $self->_dprint(3, "Initializing DB DSN for all ATAs.\n");
            ATA->DSN($params{dsn}) 
        }
    }
    ATA->DSN or croak("$class needs a database DSN");

    # only update the class DB handle if we have a new DSN or don't
    # already have a handle
    $self->_dprint(3, "Initializing new DB handle for all ATAs.\n");
    ATA->DBH(DBI->connect_cached(ATA->DSN, '', '',
                          { RaiseError => 1, AutoCommit => 0 }));


    #
    # public data
    #

    # the MAC address is the primary key upon which all other data is stored
    $self->{MAC} = $params{mac} || undef;

    # fill in the rest of the data from the db if we can.
    if ($self->{MAC}) {
        my @phones = $self->get_phones();
        $self->_dprint(2, "Loading ATA info from db; found phones:  @phones\n");

        if ($phones[0]) {
            $self->{PHONE} = $phones[0];
            $self->{SIP_PASS}   = $self->_do_sql($ATA_DB{GET_SIPPASS}, 1,
                                  $phones[0]);
            $self->{CODEC}      = $self->_do_sql($ATA_DB{GET_CODEC}, 1,
                                  $phones[0], $self->{MAC}) || DEF_CODEC;
            $self->{CALLER_ID}  = join(' ',
                                  $self->_do_sql($ATA_DB{GET_CALLERID}, 1,
                                  $phones[0]));
            $self->{ADMIN_PASS} = $self->_do_sql($ATA_DB{GET_PASS}, 1,
                                  $phones[0], $self->{MAC});
            $self->{MODEL_ID}   = $self->_do_sql($ATA_DB{GET_ATA_MODEL_ID}, 1,
                                  $phones[0], $self->{MAC});
        }

        if ($phones[1]) {
            $self->{PHONE2} = $phones[1];
            $self->{SIP_PASS2}   = $self->_do_sql($ATA_DB{GET_SIPPASS}, 1,
                                   $phones[1]);
            $self->{CODEC2}      = $self->_do_sql($ATA_DB{GET_CODEC}, 1,
                                   $phones[1], $self->{MAC}) || DEF_CODEC;
            $self->{CALLER_ID2} = join(' ',
                                  $self->_do_sql($ATA_DB{GET_CALLERID}, 1,
                                  $phones[1]));
        }

        # read the maker and model (for use later) if we know the model ID
        if ($self->{MODEL_ID}) {
            unless ($self->{MAKER} and $self->{MODEL}) {
                my ($v, $m) = $self->_do_sql($ATA_DB{GET_MODEL_INFO}, 1,
                                             $self->{MODEL_ID});
                if (!$v or !$m) {
                    $self->_dprint(1, "Warning:  ATA model ID ".
                                   $self->{MODEL_ID}.  " wasn't recognized.\n");
                }
                $self->{MAKER} = $v if $v;
                $self->{MODEL}  = $m if $m;
            }
        }
        # no model ID; try to derive it from the maker and model.
        elsif ($self->{MAKER} and $self->{MODEL}) {
            $self->{MODEL_ID} = $self->_do_sql($ATA_DB{GET_MAKER_MODEL_ID},
                                1, $self->{MAKER}, $self->{MODEL});
            $self->_dprint(2, "Discovered model ID from db (".
                           $self->{MODEL_ID}. ") using ". $self->{MAKER}.
                           "/".$self->{MODEL}. "\n");
        }
        else {
            $self->_dprint(2, "Couldn't derive model ID.\n");
        }
    }

    # now that we've loaded all the data we can from the db, check to see any
    # of it was overridden with parameters passed to new().  first off, we need
    # to check the phones that were named in case lines 1 & 2 were reversed.

    if (exists $self->{PHONE2} or exists $params{phone2}) {     # 2-line ATA?
        # was the line 2 phone given to us as line 1?
        # if so, we need to swap the phone params and read the opposite names
        if (exists $params{phone} and $params{phone} eq $self->{PHONE2}) {
            $self->_dprint(2, "Recognized a 2-line phone; phone param is for ".
                           "line 2.\n");

            delete $params{phone};

            # if phone and phone2 were given, swap them.
            # otherwise, just move phone to phone2 and delete phone
            if (exists $params{phone2}) {
                $params{phone} = $params{phone2};
                $self->_dprint(2, "Swapping params for lines 1 ".
                                  "($params{phone}) & 2 ($params{phone2}).\n");
            }

            $params{phone2} = $self->{PHONE2};

            $self->callerid2($params{callerid}) if exists $params{callerid};
            $self->codec2($params{codec})       if exists $params{codec};
            $self->sippass2($params{sip_pass})  if exists $params{sip_pass};
        }
        else {
            $self->_dprint(2, "Recognized a 2-line phone.\n");
            # if it was given correctly, update any line 2 params we were given
            $self->phone2($params{phone2}) if exists $params{phone2} and
                                           $params{phone2} != $self->{PHONE2};
            $self->callerid2($params{callerid2}) if exists $params{callerid2};
            $self->codec2($params{codec2})       if exists $params{codec2};
            $self->sippass2($params{sip_pass2})  if exists $params{sip_pass2};
        }
    }

    # update line 1 data
    $self->phone($params{phone})       if exists $params{phone};
    $self->codec($params{codec})       if exists $params{codec};
    $self->callerid($params{callerid}) if exists $params{callerid};
    $self->sippass($params{sip_pass})  if exists $params{sip_pass};

    # update the non-line-dependent data if given
    $self->adminpass($params{admin_pass}) if defined $params{admin_pass};
    $self->model_id($params{model_id})    if defined $params{model_id};
    $self->maker($params{maker})        if $params{maker};
    $self->model($params{model})          if $params{model};

    ATA->count($count);
    $self->_dprint(3, "ATA number ". ATA->count. " initialized.\n");
    return $self;
}


sub version
{
    my $self = shift;
    return $self->Version;
}


# debug(level):  set class debugging
sub debug {
    my $class = shift;
    if (ref $class)  { confess "Class method called as object method" }
    unless (@_ == 1) { confess "usage:  CLASSNAME->debug(level)" }
    $class->Debug(shift);
}


# phone($string):  set the ATA's phone number (aka user account).  always
# return the phone string.
sub phone
{
    my ($self, $phone) = @_;

    $self->_dprint(4, "Reading line 1 phone...\n");
    if ($phone and $self->{PHONE} ne $phone) {
        $self->_dprint(3, "Setting line 1 phone number to $phone.\n");
        $self->{PHONE} = $phone;
        $self->{_cache} |= 1;
    }
    return $self->{PHONE};
}


# phone2($string):  set the ATA's second line phone number.
# always return the phone string.
sub phone2
{
    my ($self, $phone) = @_;

    $self->_dprint(4, "Reading line 2 phone...\n");
    if ($phone and $self->{PHONE2} ne $phone) {
        $self->_dprint(3, "Setting line 2 phone number to $phone.\n");
        $self->{PHONE2} = $phone;
        $self->{_cache} |= 2;
    }
    return $self->{PHONE2};
}


# mac($string):  set the ATA's ethernet MAC address if given.  always return
# the MAC string.
sub mac
{
    my $self = shift;
    my $newmac = shift;

    if ($newmac) {
        # the if MAC is being changed, we need to remember it so we can
        # update the DB later.
        $self->_dprint(3, "Setting ATA MAC address to $newmac.\n");
        $self->{_oldmac} = $self->{MAC} if $self->{MAC};

        $self->{MAC} = $newmac;
        $self->{_cache} |= 4;
    }

    return $self->{MAC};
}


# get_macs([$phone])):  look in the ATA database and return all MAC addrs that
# match the ATA's phone number (or the given phone # if specified)
sub get_macs
{
    my ($self, $phone, @found);

    if (@_ == 1) {
        if (ref $_[0]) {
            $self = shift;
            $phone = $self->phone;
        }
        else {
            $phone = shift;
        }
    }
    else {
        ($self, $phone) = @_;
    }

    @found = $self->_do_sql($ATA_DB{GET_MACS}, 1, $phone);
    $self->_dprint(2, 'Found '. scalar @found. ' ATAs listed in the db for '.
                   '$phone:  '. join(' ', @found)."\n");
    return @found;
}


# get_phones([$mac])):  look in the ATA database and return all phone numbers
# that match the ATA's MAC address (or the given MAC if specified)
sub get_phones
{
    my ($self, $mac, @found);

    if (@_ == 1) {
        if (ref $_[0]) {
            $self = shift;
            $mac = $self->mac;
        }
        else {
            $mac = shift;
        }
    }
    else {
        ($self, $mac) = @_;
    }

    @found = $self->_do_sql($ATA_DB{GET_PHONES}, 1, $mac);
    $self->_dprint(2, 'Found '. scalar @found. ' ATA entries in the db for '.
                   "$mac:  ". join(' ', @found)."\n");
    return @found;
}


# line($phone):  read the line for the given phone number from the db.
# returns an int indicating the line.  if no phone is given, returns -1.
# if not found, returns 0.
sub line
{
    my ($self, $phone) = @_;
    if ($phone) {
        return $self->_do_sql($ATA_DB{GET_LINE}, 1, $self->{PHONE});
    }
    else {
        return -1;
    }
}


# codec($string):  set the ATA codec if given.  always returns the string
# identifying the codec.
sub codec
{
    my ($self, $codec) = @_;

    if ($codec and $self->{CODEC} ne $codec) {
        $self->_dprint(3, "Setting line 1 codec to $codec.\n");
        $self->{CODEC} = $codec;
        $self->{_cache} |= 1;
    }
    elsif (not $self->{CODEC}) {
        $self->{CODEC} = $self->_do_sql($ATA_DB{GET_CODEC}, 1,
                              $self->phone, $self->mac) || DEF_CODEC;
    }

    return $self->{CODEC};
}


# codec2($string):  set the ATA codec for line 2 if given.
# always returns the string identifying the codec.
sub codec2
{
    my ($self, $codec) = @_;

    if ($codec and $self->{CODEC2} ne $codec) {
        $self->_dprint(3, "Setting line 2 codec to $codec.\n");
        $self->{CODEC2} = $codec;
        $self->{_cache} |= 2;
    }
    elsif (not $self->phone2) {
        $self->{CODEC2} = DEF_CODEC;
    }
    elsif (not $self->{CODEC2}) {
        $self->{CODEC2} = $self->_do_sql($ATA_DB{GET_CODEC}, 1,
                              $self->phone2, $self->mac) || DEF_CODEC;
    }

    return $self->{CODEC2};
}


# adminpass($string):  set the administrator's password if one is passed.
# always returns the password string.
sub adminpass
{
    my ($self, $pass) = @_;

    if ($pass and $self->{ADMIN_PASS} ne $pass) {
        $self->_dprint(3, "Setting ATA admin password to $pass.\n");
        $self->{ADMIN_PASS} = $pass;
        $self->{_cache} |= 4;
    }
    elsif (not $self->{ADMIN_PASS}) {
        $self->{ADMIN_PASS} = $self->_do_sql($ATA_DB{GET_PASS}, 1,
                              $self->phone, $self->mac);
    }

    return $self->{ADMIN_PASS};
}


# sippass($string):  set the sip account password if one is passed.
# always returns the password string.
sub sippass
{
    my ($self, $pass) = @_;

    if ($pass and $self->{SIP_PASS} ne $pass) {
        $self->_dprint(3, "Setting line 1 sip password to $pass.\n");
        $self->{SIP_PASS} = $pass;
        $self->{_cache} |= 1;
    }
    elsif (not $self->{SIP_PASS}) {
        $self->{SIP_PASS} = $self->_do_sql($ATA_DB{GET_SIPPASS}, 1,
                            $self->phone);
    }

    return $self->{SIP_PASS};
}


# sippass2($string):  set the sip account password for line2 if one is passed.
# always returns the password string.
sub sippass2
{
    my ($self, $pass) = @_;

    if ($pass and $self->{SIP_PASS2} ne $pass) {
        $self->_dprint(3, "Setting line 2 sip password to $pass.\n");
        $self->{SIP_PASS2} = $pass;
        $self->{_cache} |= 2;
    }
    elsif ($self->phone2 and not $self->{SIP_PASS2}) {
        $self->{SIP_PASS2} = $self->_do_sql($ATA_DB{GET_SIPPASS}, 1,
                            $self->phone2);
    }

    return $self->{SIP_PASS2};
}


# callerid($string):  set the caller ID info if given.
# always returns the caller ID info, or the phone number if it wasn't set.
sub callerid
{
    my ($self, $cid) = @_;

    if ($cid and $self->{CALLER_ID} ne $cid) {
        $self->_dprint(3, "Setting line 1 caller ID to $cid.\n");
        $self->{CALLER_ID} = $cid;
        $self->{_cache} |= 1;
    }
    elsif (not $self->{CALLER_ID}) {
        $self->{CALLER_ID} = join(' ', $self->_do_sql($ATA_DB{GET_CALLERID}, 1,
                             $self->phone)) or $self->phone;
    }

    return $self->{CALLER_ID};
}


# callerid2($string):  set the caller ID info for line2 if given.
# always returns the caller ID info or the phone number if it wasn't set.
sub callerid2
{
    my ($self, $cid) = @_;

    if ($cid and $self->{CALLER_ID2} ne $cid) {
        $self->_dprint(3, "Setting line 2 caller ID to $cid.\n");
        $self->{CALLER_ID2} = $cid;
        $self->{_cache} |= 2;
    }
    elsif ($self->phone2 and not $self->{CALLER_ID2}) {
        $self->{CALLER_ID2} = join(' ', $self->_do_sql($ATA_DB{GET_CALLERID}, 1,
                              $self->phone2)) or $self->phone2;
    }

    return $self->{CALLER_ID2};
}



# model_id($string):  read or set the ATA model id number.
# if a string is given, remembers it as the model ID.
# always returns the number of this model.
sub model_id
{
    my ($self, $id) = @_;

    # has the maker or model changed?
    if ($self->{_cache} & 4) {
        my $id = $self->_do_sql($ATA_DB{GET_MAKER_MODEL_ID}, 1, $self->maker,
                                $self->model);
        if ($id) {
            $self->{MODEL_ID} = $sane_id;
            $self->{_cache} |= 4;
        }
    }

    if (defined $id) {
        $self->_dprint(2, "Attempting to set model ID attribute to $id.\n");
        my $sane_id = $self->_do_sql($ATA_DB{GET_MODEL_ID}, 1, $id);
        if ($sane_id) {
            $self->{MODEL_ID} = $sane_id;
            $self->{_cache} |= 4;
        }
    }

    if (not $self->{MODEL_ID}) {
        $self->_dprint(3, "Attempting to figure out model ID from maker and ".
                          "model names.\n");
        my $v = $self->maker;
        my $m = $self->model;
        if ($v and $m) {
            my $id = $self->_do_sql($ATA_DB{GET_MAKER_MODEL_ID}, 1, $v, $m);
            if ($id) {
                $self->{MODEL_ID} = $id;
                $self->{_cache} |= 4;
            }
            else {
                $self->_dprint(3, "No model ID found for $v/$m.\n");
            }
        }
    }

    if (not $self->{MODEL_ID}) {
        $self->_dprint(3, "Attempting to read model ID for this ATA ".
                          "from db.\n");
        my $p = $self->phone;
        my $m = $self->mac;
        if ($p and $m) {
            my $id = $self->_do_sql($ATA_DB{GET_ATA_MODEL_ID}, 1, $p, $m);
            if ($id) {
                $self->{MODEL_ID} = $id;
                $self->{_cache} |= 4;
            }
            else {
                $self->_dprint(3, "No model ID found for $p [$m].\n");
            }
        }
    }

    $self->_dprint(3, "Model ID is $self->{MODEL_ID}\n");
    return $self->{MODEL_ID};
}


# guess_maker([$mac]):  return a string identifying the name of the ATA's
# maker.  This can be discerned by matching the first 6 characters of the
# MAC address to the %MAKER_MACS hash defined above.  If a MAC is given,
# use that; otherwise use the object's own MAC addr.
# WARNING:  This may very well not be accurate.
sub guess_maker
{
    my ($self, $mac);

    if (@_ == 1) {
        if (ref $_[0]) {
            $self = shift;
            $mac = $self->mac;
        }
        else {
            $mac = shift;
        }
    }
    else {
        ($self, $mac) = @_;
    }

    if ($mac) {
        my $vend_macid = substr($mac, 0, 6);
        return $MAKER_MACS{$vend_macid} || 'unidentified';
    }
    else {
        return '';
    }
}


# maker($string):  read or set the ATA model's maker name.
# if a string is given, remembers it as the maker name.
# always returns the string identifying the maker.
sub maker
{
    my ($self, $maker) = @_;
    my $sane_maker;

    if (defined $maker) {
        $self->_dprint(2, "Attempting to set maker attribute to $maker.\n");
        my ($sane_maker) = grep(/^$maker$/i, $self->makers);
        if ($sane_maker) {
            $self->{MAKER} = $sane_maker;
            $self->{_cache} |= 4;
            $self->_dprint(3, "Maker attribute set to $sane_maker.\n");
        }
        else {
            $self->_dprint(2, "Maker $maker not recognized.\n");
            return 0;
        }
    }

    if (not $self->{MAKER}) {
        if (not $self->{MODEL_ID}) {
            $self->{MODEL_ID} = $self->_do_sql($ATA_DB{GET_ATA_MODEL_ID}, 1,
                                $self->{PHONE}, $self->{MAC});
            $self->{_cache} |= 4;
        }
        if ($self->{MODEL_ID}) {
            $self->_dprint(2, "Found model ID $self->{MODEL_ID} in db.\n");
            $self->_dprint(2, "Attempting to read maker for model ".
                           $self->{MODEL_ID}. " from db.\n");
            my ($v, $m) = $self->_do_sql($ATA_DB{GET_MODEL_INFO}, 1,
                                         $self->{MODEL_ID});
            if (!$v or !$m) {
                $self->_dprint(1, "Warning:  ATA model ID $self->{MODEL_ID} ".
                               " wasn't recognized.\n");
            }
            $self->_dprint(2, "Found maker '$v' and model '$m'.\n");
            if ($v) {
                $self->{MAKER} = $v;
                $self->{_cache} |= 4;
            }
            if (!$self->{MODEL} and $m) {
                $self->{MODEL} = $m;
                $self->{_cache} |= 4;
            }
        }
        else {
            $self->_dprint(2, "Couldn't derive model ID to figure out ".
                           "maker.\n");
        }
    }

    return $self->{MAKER};
}


# model($string):  read or set the ATA model name.
# if a string is given, remembers it as the model name.
# always returns the string identifying the model.
sub model
{
    my ($self, $model) = @_;

    if (defined $model) {
        $self->_dprint(2, "Attempting to set model attribute to $model.\n");
        my ($sane_model) = grep(/^$model$/i, $self->models($self->maker));
        if ($sane_model) {
            $self->{MODEL} = $sane_model;
            $self->{_cache} |= 4;
            $self->_dprint(3, "Model attribute set to $sane_model.\n");
        }
        else {
            $self->_dprint(2, "Model $model not recognized.\n");
            return 0;
        }
    }

    if (not $self->{MODEL}) {
        if (not $self->{MODEL_ID}) {
            $self->{MODEL_ID} = $self->_do_sql($ATA_DB{GET_ATA_MODEL_ID}, 1,
                                $self->{PHONE}, $self->{MAC});
            $self->{_cache} |= 4;
        }

        if ($self->{MODEL_ID}) {
            $self->_dprint(2, "Found model ID $self->{MODEL_ID} in db.\n");
            $self->_dprint(2, "Attempting to read model for model ID ".
                           $self->{MODEL_ID}. " from db.\n");
            my ($v, $m) = $self->_do_sql($ATA_DB{GET_MODEL_INFO}, 1,
                                         $self->{MODEL_ID});
            if (!$v or !$m) {
                $self->_dprint(1, "Warning:  ATA model ID ". $self->{MODEL_ID}.
                               " wasn't recognized.\n");
            }
            if ($v) {
                $self->{MAKER} = $v;
                $self->{_cache} |= 4;
            }
            if ($m) {
                $self->{MODEL} = $m;
                $self->{_cache} |= 4;
            }
        }
        else {
            $self->_dprint(2, "Couldn't derive model ID to figure out ".
                           "maker.\n");
        }
    }

    return $self->{MODEL};
}




# makers():  return a string identifying the list of recognized ATA makers
sub makers
{
    my $self = shift;
    my @found;

    @found = $self->_do_sql($ATA_DB{GET_MAKERS}, 1);
    return @found;
}


# models([$maker]):  return a string identifying the list of recognized
# ATA models.
#
# If a maker string is given, only those models associated with that maker
# are returned.  If not given, a flat array of (maker, model) pairs is
# returned, e.g. ('Grandstream', 'HandyTone-486', 'Sipura', 'SPA-2000',
# 'Sipura', 'SPA-2100').
sub models
{
    my ($self, $maker) = @_;
    my @found;

    if ($maker) {
        @found = $self->_do_sql($ATA_DB{GET_MAKER_MODELS}, 1, $maker);
    }
    else {
        @found = $self->_do_sql($ATA_DB{GET_MODELS}, 1);
    }
    return @found;
}


# commit():  save cached ATA data to the database
sub commit
{
    my $self = shift;
    my $ok;

    unless ($self->{_cache}) {
        $self->_dprint(1, "No changes to ATA in cache.\n");
        return 1;
    }

    # if the ATA is already listed, then we have to update the record.
    # otherwise we need to do a new INSERT.

    # line 1:
    if ($self->{_cache} & 1) {
        if ($self->exists(line => 1)) {
            $self->_dprint(1, "Updating existing DB record for line 1:  ".
                              $self->phone. " [". $self->mac. "]...\n");

            if ($self->codec) {
                $self->_dprint(1, "Changing line 1 codec to ". $self->codec.
                                  " for ". $self->phone. " [". $self->mac.
                                  "]...\n");
                $ok = $self->_do_sql($ATA_DB{CHANGE_CODEC}, 0, $self->codec,
                             $self->phone, $self->mac);
                $self->_dprint(3, "Status = $ok\n");
                return 0 unless $ok;
            }
            if ($self->adminpass) {
                $self->_dprint(1, "Changing admin config password to ".
                               $self->adminpass. " for ". $self->phone. " [".
                               $self->mac. "]...\n");
                $ok = $self->_do_sql($ATA_DB{CHANGE_PASS}, 0, $self->adminpass,
                                     $self->phone, $self->mac);
                $self->_dprint(3, "Status = $ok\n");
                return 0 unless $ok;
            }

            # we changed the MAC address earlier.
            if ($self->{_oldmac}) {
                $self->_dprint(1, "Changing MAC address to [". $self->mac. 
                                  "]...\n");
                $ok = $self->_do_sql($ATA_DB{CHANGE_MAC}, 0, $self->mac,
                                     $self->phone, $self->{_oldmac});
                $self->_dprint(3, "Status = $ok\n");
                return 0 unless $ok;
            }
        }
        else {
            $self->_dprint(1, "Inserting new entry for line 1:  ".
                              $self->phone. " [". $self->mac. "]...\n");
            $ok = $self->_do_sql($ATA_DB{CREATE}, 0, $self->mac, 1,
                                 $self->phone, $self->adminpass, $self->codec,
                                 $self->model_id);
            $self->_dprint(3, "Status = $ok\n");
            return 0 unless $ok;
        }
    }

    # line 2:
    if ($self->{_cache} & 2) {
        if ($self->exists(line => 2)) {
            $self->_dprint(1, "Updating existing DB record for line 2:  ".
                              $self->phone2. " [". $self->mac. "]...\n");

            if ($self->codec2) {
                $self->_dprint(1, "Changing line 2 codec to ". $self->codec2.
                                  " for ". $self->phone2. " [". $self->mac.
                                  "]...\n");
                $ok = $self->_do_sql($ATA_DB{CHANGE_CODEC}, 0, $self->codec2,
                             $self->phone2, $self->mac);
                $self->_dprint(3, "Status = $ok\n");
                return 0 unless $ok;
            }
            if ($self->adminpass) {
                $self->_dprint(1, "Changing admin config password to ".
                               $self->adminpass. " for ". $self->phone2. " [".
                               $self->mac. "]...\n");
                $ok = $self->_do_sql($ATA_DB{CHANGE_PASS}, 0, $self->adminpass,
                                     $self->phone2, $self->mac);
                $self->_dprint(3, "Status = $ok\n");
                return 0 unless $ok;
            }

            # we changed the MAC address earlier.
            if ($self->{_oldmac}) {
                $self->_dprint(1, "Changing line 2 MAC address to [".
                               $self->mac. "]...\n");
                $ok = $self->_do_sql($ATA_DB{CHANGE_MAC}, 0, $self->mac,
                                     $self->phone2, $self->{_oldmac});
                $self->_dprint(3, "Status = $ok\n");
                return 0 unless $ok;
            }
        }
        else {
            $self->_dprint(1, "Inserting new entry for line 2:  ".
                               $self->phone2. " [".  $self->mac. "]...\n");
            $ok = $self->_do_sql($ATA_DB{CREATE}, 0, $self->mac, 2,
                                 $self->phone2, $self->adminpass, $self->codec2,
                                 $self->model_id);
            $self->_dprint(3, "Status = $ok\n");
            return 0 unless $ok;
        }
    }

    if ($self->{_cache} & 4) {
        if ($self->phone) {
            $self->_dprint(1, "Changing line 1 model ID to ". $self->model_id.
                              "...\n");
            $ok = $self->_do_sql($ATA_DB{CHANGE_MODEL_ID}, 0, $self->model_id,
                                 $self->phone, $self->mac);
            $self->_dprint(3, "Status = $ok\n");
        }
        if ($self->phone2) {
            $self->_dprint(1, "Changing line 2 model ID to ". $self->model_id.
                              "...\n");
            $ok = $self->_do_sql($ATA_DB{CHANGE_MODEL_ID}, 0, $self->model_id,
                                 $self->phone2, $self->mac);
            $self->_dprint(3, "Status = $ok\n");
        }
        return 0 unless $ok;
    }

    return 1;
}


# delete($line or $phone):  remove myself from the database
# NOTE:  subclasses may want to call this and then remove their own unique
# config files as well
# if a phone number is given, only remove that number.  otherwise remove
# all numbers.
sub delete
{
    my ($self, @phones) = @_;
    my ($ok);

    $self->_dprint(0, "ATA DB data...");
    unless (@phones) {
       @phones = $self->get_phones;
    }

    foreach my $p (@phones) {
        $self->_dprint(2, "Removing $p [". $self->mac. "] from the db.\n");
        $ok = $self->_do_sql($ATA_DB{DELETE}, 0, $p, $self->mac);
    }

    # now remove the phones from our memory
    if (grep($_ eq $self->phone, @phones)) {
        $self->_dprint(2, "Forgetting line 1 (". $self->phone. ").\n");
        delete $self->{PHONE};
        delete $self->{CODEC};
        delete $self->{CALLER_ID};
    }
    if (grep($_ eq $self->phone2, @phones)) {
        $self->_dprint(2, "Forgetting line 2 (". $self->phone2. ").\n");
        delete $self->{PHONE2};
        delete $self->{CODEC2};
        delete $self->{CALLER_ID2};
    }

    #_dprint(0, "ATA config files...");
    #$ok = del_ata_config($curinfo{mac});

    return $ok;
}


# exists([line => N | phone => #]):  return non-zero if a DB entry for this
# unique ATA exists in the our_atas table.
# an optional phone line can be given:  line => <N>, etc, or phone => <number>
sub exists
{
    my $self = shift;
    my %which = @_;
    my (@phones, @found, $result);

    if (exists $which{line}) {
        if ($which{line} == 1) {
            @phones = ($self->phone);
        }
        elsif ($which{line} == 2) {
            @phones = ($self->phone2);
        }
    }
    elsif (exists $which{phone}) {
        @phones = ($which{phone});
    }
    else {
        push @phones, $self->phone, $self->phone2;
    }

    @found = $self->get_phones;
    $result = 0;
    foreach my $p (@phones) {
        $result += grep(/^$p$/, @found);
    }

    return $result;
}


sub reset
{
    my $self = shift;
    _dprint(1, "Reset unimplemented for this type of ATA");
    return 0;
}


sub init
{
    my $self = shift;
    return $self->commit;
}


sub update
{
    my $self = shift;
    return $self->commit;
}


sub print
{
    my $self = shift;
    my ($sql, $found);

    $sql = ATA->DBH->prepare($ATA_DB{GET_ALL})
     or die("ERROR:  ATA DB select is misconfigured:  ".  $sql->errstr. "\n");
    $sql->execute($self->phone, $self->mac);
    if ($sql->err) {
        print STDERR "ERROR:  ". $sql->errstr. "\n";
        return 0;
    }

    while (defined($found = $sql->fetchrow_hashref())) {
        foreach my $key (reverse sort keys %$found) {
            print "$key:  ". $found->{$key}. "\n";
        }
        print 'Maker:  '. $self->maker. "\n";
        print 'model:  '. $self->model. "\n";
        print "\n";
    }

    return 1;
}


sub printcache
{
    my $self = shift;
    my ($sql, $found);

    $self->_dprint(1, "Cached ATA data (not read from DB)...\n");

    print 'MAC addr:  '. $self->mac. "\n";
    print 'Maker:  '. $self->maker. "\n";
    print 'Model:  '. $self->model. "\n";
    print 'Admin password:  '. $self->adminpass. "\n";

    print "\n";
    print 'Line 1 Username:  '. $self->phone. "\n";
    print 'Line 1 Caller ID:  '. $self->callerid. "\n";
    print 'Line 1 SIP password:  '. $self->sippass. "\n";
    print 'Line 1 Codec:  '. $self->codec. "\n";

    if ($self->phone2) {
        print "\n";
        print 'Line 2 Username:  '. $self->phone2. "\n";
        print 'Line 2 Caller ID:  '. $self->callerid2. "\n";
        print 'Line 2 SIP password:  '. $self->sippass2. "\n";
        print 'Line 2 Codec:  '. $self->codec2. "\n";
    }

    return 1;
}


##
# _dprint($level, $mesg):
# 
# Print the given message if the object's verbosity level is above $level.
##
sub _dprint
{
    my ($self, $level, $mesg);

    if (ref $_[0]) {
        $self = shift;
    }
    ($level, $mesg) = @_;

    #print "dprint:  Debug ". ATA->Debug. ", level $level\n";
    return unless ATA->Debug >= $level;

    if ($level == 0) {
        print "$mesg";
    }
    else {
        print '['. __PACKAGE__. ' D'. $level. '] '. $mesg;
    }

    return undef;
}


##
# _do_sql($template, $want_data, @data):
# 
# Execute the SQL statement in $template with @data as the values.
# 
# returns:  if want_data is nonzero, returns the 1st array of data on success.
#   otherwise, returns 1 on success.  returns 0 on failure.
##
sub _do_sql
{
    my ($self, $template, $want_data, @data) = @_;
    my ($sql, @fetched);

    $sql = ATA->DBH->prepare($template)
     or die("ERROR:  SQL statement is misconfigured:  ". $sql->errstr);
    $self->_dprint(4, "SQL status:  ". ATA->DBH->state. "\n");
    $self->_dprint(4, "SQL:  $template\n");
    $self->_dprint(4, "Data:  ". join(', ', @data). "\n");
    $sql->execute(@data);
    if ($sql->err) {
        print STDERR "ERROR:  ". $sql->errstr. "\n";
        return 0;
    }

    # if we got more than one row of data, unpack it all into an array
    # and return that array
    if ($want_data) {
        $self->_dprint(4, "Returning data...\n");
        foreach my $aref (@{ $sql->fetchall_arrayref() }) {
            push @fetched, @{ $aref };
        }

        $self->_dprint(4, "Fetched:  @fetched\n");
        return wantarray ? @fetched : $fetched[0];

    }
    else {
        $self->_dprint(4, "Returning 1...\n");
        return 1;
    }
}


# class destructor
sub DESTROY {
    my $self = shift;

    ATA::_dprint(2, "Done with ". ($self->phone || $self->mac).
                    "; destroying\n");

    # drop the number in the pool
    ATA->count(ATA->count - 1);

    if (ATA->count == 0 and ATA->DBH) {
        ATA::_dprint(2, "Last ATA object destroyed.  Disconnecting from db.\n");
        ATA->DBH->disconnect;
    }
}

1;


##
# Revision history
# ================
# 
# $Log: ATA.pm,v $
# Revision 1.9  2007/07/17 18:29:54  root
# fixed level 2 debugging statement where '$mac' was being printed
# instead of "$mac", so the actual value of the var wasn't being shown
#
# Revision 1.8  2007/07/12 23:38:31  root
# updated our_atas table description with 'line' field
#
# Revision 1.7  2006/09/28 19:44:52  root
# fixed bug in codec2() -- $self->{CODEC} was being returned instead of
# $self-{CODEC2} (line1's codec instead of line2's)
#
# Revision 1.6  2005/07/25 21:34:11  root
# added support for a second line
# added support for tracking ATA make and model
#
# Revision 1.2  2005/06/30 18:40:24  root
# added 001217 as another prefix for a Linksys-WRT54GP2
#
# Revision 1.1  2005/06/30 18:39:14  root
# Initial revision
#
##
