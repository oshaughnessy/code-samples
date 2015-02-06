##
# 
# sh/ksh/bash library
# 
##

MY_CNF=/etc/my.cnf
MY_CNF_ROOT=/root/.my.cnf


## Exit code definitions:
##
## successful completion of the request
##

EX_OK=0
export EX_OK

## All other exit values indicate a failure of some type
##

# bogus syntax (e.g., wrong number of args, etc)
EX_USAGE=64

# bogus input data
EX_DATAERR=65

# the requested service does not exist
EX_UNAVAILABLE=69

# a system error occurred
EX_OSERR=71

# error connecting to server
EX_CONNECT=74

# IP or user not authorized to run script or connect to server
EX_NOPERM=77

# target user/address/condition does not exist
EX_NOEXISTS=79

# target user/address/condition already exists
EX_EXISTS=80

# the target user/address/service is protected
EX_PROTECTED=81

# an unexpected, as-yet-undefined error
EX_MISCERR=99

export EX_USAGE EX_DATAERR EX_PROTECTED EX_EXISTS EX_NOEXISTS EX_OSERR
export EX_MISCERR EX_UNAVAILABLE EX_NOPERM EX_CONNECT 



## Useful utility functions
##

# die - Fatal exit with diagnostic info
# arg 1: exit code
# arg n: all other arguments are messages to be printed out
function die
{
    typeset code="$1"; shift
    #for msg in "$@"; do print "$ME: $msg"; done;
    for msg in "$@"; do echo $msg |sed "s/^/$ME: /g"; done;
    exit $code
}


# warn - Print a message
# args: each arg is printed to stdout, prefixed with the name of the program
function warn
{
    for msg in "$@"; do echo "$ME: $msg"; done;
}


# sigdie - Signal handler that reports the cause of death (barely)
function sigdie
{
    die $EX_OSERR "killed"
}


# find_caller - Simple to() try and identify who's running the program
function find_caller
{
    typeset real_user=`whoami`
    #real_user=${SUDO_USER:-`who am i | cut -d' ' -f1`}
    remote_host=${REMOTE_HOST:-${REMOTE_ADDR:-localhost}}
    remote_user=${REMOTE_USER:-$real_user}
    export real_user remote_host remote_user
}


# check_out - wrapper around RCS check-out
# arg 1: name of file to check out and lock
function check_out
{
    typeset file="$1"

    for d in 3 2 1; do
        co -q -l $file >/dev/null 2>&1 && return 0
        sleep 1
    done

    #warn "$file could not be locked."
    return $EX_OSERR
}


# check_in - wrapper around RCS check-in
# arg 1: name of file to check in and unlock
# arg 2: message to record in the RCS history
function check_in
{
    typeset file="$1"
    typeset note="$2"

    for d in 3 2 1; do
        ci -q -u "-m$note" $file >/dev/null 2>&1 && return 0
        sleep 1
    done

    #warn "$file could not be unlocked."
    return $EX_OSERR
}


# copy_dir - move all files from one directory to another
# arg 1:  source dir
# arg 2:  dest dir
# arg 3:  account or uid of dest dir owner
# arg 4:  group or gid of dest dir owner
#
# If the dest dir already exists, the script will fail.
# If the source dir doesn't exist, the script will do nothing and succeed.
function copy_dir
{
    typeset src="$1"
    typeset dest="$2"
    typeset user="$3"
    typeset group="$4"

    # return success if the source dir doesn't exist
    test -d $src || return 0

    # create the dest dir if it doesn't exist; return failure if we can't
    test -d $dest || mkdir -p $dest || return 1

    # copy the data
    #(cd $src && tar cf - . | (cd $dest && tar xfBp -) ) || return 1
    rsync -aq --delete $src/ $dest

    # make sure it's owned by the right account
    chown -R $user:$group $dest >/dev/null 2>&1

    return 0
}


function mysql_query
{
    typeset _db=r3system

    mysql --defaults-extra-file=$MY_CNF --batch --skip-column-names "$_db" -e "$*"
}

function mysql_root_query
{
    sudo mysql --defaults-extra-file=$MY_CNF_ROOT --batch --skip-column-names -e "$*"
}


function mysql_dump
{
    typeset _dbs="$@"

    sudo mysqldump --defaults-extra-file=$MY_CNF_ROOT --routines --databases $_dbs
}


function mysql_dump_tables
{
    typeset _db="$1"; shift
    typeset _tables="$@"

    sudo mysqldump --defaults-extra-file=$MY_CNF_ROOT $_db $_tables
}


function mysql_dump_table_where
{
    typeset _db="$1"; shift
    typeset _table="$1"; shift
    typeset _where="$@"
    typeset _dump_args="--compact --skip-extended-insert --complete-insert --no-create-info"

    sudo mysqldump --defaults-extra-file=$MY_CNF_ROOT $_dump_args --where="$_where" $_db $_table
}
