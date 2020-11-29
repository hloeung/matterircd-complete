# /bind ^G /message_thread_id_search
# Use Ctrl+g to insert latest thread/message ID.

use strict;
use warnings;

use Irssi qw(command_bind gui_input_set gui_input_set_pos signal_add_last);
use Irssi::TextUI;


our $VERSION = '1.00';
our %IRSSI = (
    name        => 'Matterircd Message Thread Tab Complete',
    description => 'Adds tab complettion for Matterircd message threads',
    authors     => 'Haw Loeung',
    contact     => 'hloeung/Freenode',
    license     => 'GPL',
);

my %MSGTHREADID_CACHE;

command_bind 'message_thread_id_search' => sub {
    my ($data, $server, $wi) = @_;

    return unless ref $wi and $wi->{type} eq 'CHANNEL';
    if (not exists($MSGTHREADID_CACHE{$wi->{name}})) {
        return;
    }

    # XXX: Maybe add it so re-running the search command each time
    # cycles through. For now, just add the most recent.
    gui_input_set_pos(0);
    gui_input_set('@@' . $MSGTHREADID_CACHE{$wi->{name}}[0] . ' ');
};

signal_add_last 'complete word' => sub {
    my ($complist, $window, $word, $linestart, $want_space) = @_;

    my $wi = Irssi::active_win()->{active};
    return unless ref $wi and $wi->{type} eq 'CHANNEL';
    if (not exists($MSGTHREADID_CACHE{$wi->{name}})) {
        return;
    }

    # Only message/thread IDs at the start.
    if (substr($word, 0, 2) ne '@@') {
        return;
    }
    $word = substr($word, 2);

    foreach my $msgthread_id (@{$MSGTHREADID_CACHE{$wi->{name}}}) {
        if ($msgthread_id =~ /^\Q$word\E/) {
            push(@$complist, "\@\@${msgthread_id}");
        }
    }
};

signal_add_last 'message public' => sub {
    my($server, $msg, $nick, $address, $target) = @_;

    if ($msg !~ /\[@@([0-9a-z]{26})\]/) {
        return;
    }
    my $msgid = $1;
    my $cache_ref = \@{$MSGTHREADID_CACHE{$target}};

    # We want to reduce duplicates by removing them currently in the
    # per-channel cache. But as a trade off in favor of
    # speed/performance, rather than traverse the entire per-channel
    # cache, we cap/limit it.
    my $limit = 5;
    my $max = ($#$cache_ref < $limit)? $#$cache_ref : $limit;
    for my $i (0 .. $max) {
        if (@$cache_ref[$i] eq $msgid) {
            splice(@$cache_ref, $i, 1);
        }
    }

    # Message / thread IDs are added at the start of the array so most
    # recent would be first.
    unshift(@$cache_ref, $msgid);

    # Maximum cache elements to store per channel.
    # XXX: Make this value configurable.
    if (scalar(@$cache_ref) > 20) {
        pop(@$cache_ref);
    }
};

signal_add_last 'message own_public' => sub {
    my($server, $msg, $target) = @_;

    if ($msg !~ /^@@([0-9a-z]{26})/) {
        return;
    }
    my $msgid = $1;
    my $cache_ref = \@{$MSGTHREADID_CACHE{$target}};

    if ((not @$cache_ref) || (@$cache_ref[0] ne $msgid)) {
        unshift(@$cache_ref, $msgid);
    }
};
