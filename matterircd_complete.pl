# /bind ^G /message_thread_id_search
# Use Ctrl+g to insert latest thread/message ID.

use strict;
use warnings;

use Irssi::TextUI;
use Irssi qw(command_bind gui_input_set gui_input_set_pos settings_add_int settings_get_int signal_add_last);


our $VERSION = '1.00';
our %IRSSI = (
    name        => 'Matterircd Message Thread Tab Complete',
    description => 'Adds tab complettion for Matterircd message threads',
    authors     => 'Haw Loeung',
    contact     => 'hloeung/Freenode',
    license     => 'GPL',
);


sub cache_store {
    my ($cache_ref, $item, $cache_size) = @_;

    # We want to reduce duplicates by removing them currently in the
    # per-channel cache. But as a trade off in favor of
    # speed/performance, rather than traverse the entire per-channel
    # cache, we cap/limit it.
    my $limit = 8;
    my $max = ($#$cache_ref < $limit)? $#$cache_ref : $limit;
    for my $i (0 .. $max) {
        if (@$cache_ref[$i] eq $item) {
            splice(@$cache_ref, $i, 1);
        }
    }

    unshift(@$cache_ref, $item);
    if (scalar(@$cache_ref) > $cache_size) {
        pop(@$cache_ref);
    }
}


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

    my $msgid = '';
    # Mattermost message/thread IDs.
    if ($msg =~ /(?:^\[@@([0-9a-z]{26})\])|(?:\[@@([0-9a-z]{26})\]$)/) {
        $msgid = $1 ? $1 : $2;
    }
    # matterircd generated 3-letter hexadecimal.
    elsif ($msg =~ /(?:^\[([0-9a-f]{3})\])|(?:\[([0-9a-f]{3})\]$)/) {
        $msgid = $1 ? $1 : $2;
    }
    # matterircd generated 3-letter hexadecimal replying to threads.
    elsif ($msg =~ /(?:^\[[0-9a-f]{3}->([0-9a-f]{3})\])|(?:\[[0-9a-f]{3}->([0-9a-f]{3})\]$)/) {
        $msgid = $1 ? $1 : $2;
    }
    else {
        return;
    }

    my $cache_size = settings_get_int('matterircd_complete_message_thread_id_cache_size');
    cache_store(\@{$MSGTHREADID_CACHE{$target}}, $msgid, $cache_size);
};

signal_add_last 'message own_public' => sub {
    my($server, $msg, $target) = @_;

    if ($msg !~ /^@@((?:[0-9a-z]{26})|(?:[0-9a-f]{3}))/) {
        return;
    }
    my $msgid = $1;

    my $cache_size = settings_get_int('matterircd_complete_message_thread_id_cache_size');
    cache_store(\@{$MSGTHREADID_CACHE{$target}}, $msgid, $cache_size);
};

settings_add_int('matterircd_complete', 'matterircd_complete_message_thread_id_cache_size', 20);


my %NICKNAMES_CACHE;

signal_add_last 'complete word' => sub {
    my ($complist, $window, $word, $linestart, $want_space) = @_;

    my $wi = Irssi::active_win()->{active};
    return unless ref $wi and $wi->{type} eq 'CHANNEL';

    if (substr($word, 0, 1) ne '@') {
        return;
    }
    $word = substr($word, 1);

    foreach my $nick (@{$NICKNAMES_CACHE{$wi->{name}}}) {
        if ($nick =~ /^\Q$word\E/) {
            push(@$complist, "\@${nick}");
        }
    }

    # We need to store the results in a temporary array so we can sort.
    my @tmp;
    foreach my $nick ($wi->nicks()) {
        if ($nick->{nick} =~ /^\Q$word\E/i) {
            push(@tmp, "$nick->{nick}");
        }
    }
    @tmp = sort @tmp;
    foreach my $nick (@tmp) {
        push(@$complist, "\@${nick}");
    }
};

signal_add_last 'message public' => sub {
    my($server, $msg, $nick, $address, $target) = @_;

    my $cache_size = settings_get_int('matterircd_complete_nick_cache_size');
    cache_store(\@{$NICKNAMES_CACHE{$target}}, $nick, $cache_size);
};

signal_add_last 'message own_public' => sub {
    my($server, $msg, $target) = @_;

    if ($msg !~ /^@([^@ \t:,\)]+)/) {
        return;
    }
    my $nick = $1;

    my $cache_size = settings_get_int('matterircd_complete_nick_cache_size');
    cache_store(\@{$NICKNAMES_CACHE{$target}}, $nick, $cache_size);
};

settings_add_int('matterircd_complete', 'matterircd_complete_nick_cache_size', 20);
