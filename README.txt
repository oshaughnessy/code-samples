This directory includes samples of software written by O'Shaughnessy Evans.

Samples include:

  atactl                  A front-end script and supporting libraries written
                          in Perl, useful for provisioning VoIP ATAs for
                          ser accounts.

  autorespond             A plugin for the web email software Squirrelmail
                          (www.squirrelmail.org) written in PHP that gives
                          users a way to forward their email elsewhere,
                          run it through filters, or manage a "vacation"
                          autoresponder. See also:
                          http://www.squirrelmail.org/plugin_view.php?id=172

  enum-audit              A simple Perl script that compares phone numbers
                          in a database with ENUM DNS records and reports
                          discrepancies.

  ksh-template            A template useful for writing new shell scripts.
                          Includes help and usage messages and argument
                          processing. Intended to help standardize the
                          way a shop's shell scripts are written.
                          Easily adapted for sh/bash.

  magilla                 A brief Python script, written on top of scapy
                          (see http://www.secdev.org/projects/scapy/), to
                          communicate with a VoIP phone switch over MGCP.

  voicemail-reaper        A brief Perl script that compares an Asterisk
                          voicemail spool with mailboxes in a database
                          and archives the spools of those that are no
                          longer active.

All of these applications require supporting libraries or databases.


### See also

My repository in GitHub: https://github.com/oshaughnessy

* https://github.com/oshaughnessy/mailmate-scripts
  Scripts I've found handy to have when using MailMate

* https://github.com/oshaughnessy/mailmate-macvim
  The MacVim bundle for MailMate (http://freron.com)

* https://github.com/oshaughnessy/squirrelmail-autorespond
  A SquirrelMail plugin to manage .forward and .vacation files over FTP

* https://github.com/oshaughnessy/trash-monkey
  A pair of scripts to cleaning up mbox and Maildir-format mailboxes

* https://github.com/oshaughnessy/sip-notify
  Notify Asterisk SIP users when they have new voicemail
