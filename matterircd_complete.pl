# '/bind ^G /message_thread_id_search'
# Use Ctrl+g to insert latest thread/message ID (ESC to abort).
#
# @@+TAB to tab auto-complete message/thread ID.
# @ +TAB to tab auto-complete IRC nick.

use strict;
use warnings;
use experimental 'smartmatch';

use Irssi::TextUI;
use Irssi qw(command_bind gui_input_set gui_input_set_pos settings_add_int settings_get_int signal_add_last);


our $VERSION = '1.00';
our %IRSSI = (
    name        => 'Matterircd Tab Auto Complete',
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
        if ((@$cache_ref[$i]) && (@$cache_ref[$i] eq $item)) {
            splice(@$cache_ref, $i, 1);
        }
    }

    unshift(@$cache_ref, $item);
    if (scalar(@$cache_ref) > $cache_size) {
        pop(@$cache_ref);
    }
}


my %MSGTHREADID_CACHE;
settings_add_int('matterircd_complete', 'matterircd_complete_message_thread_id_cache_size', 20);
command_bind 'matterircd_complete_msgthreadid_cache_dump' => sub {
    my ($data, $server, $wi) = @_;

    if (not $data) {
        return unless ref $wi and $wi->{type} eq 'CHANNEL';
    }

    my $channel = $data ? $data : $wi->{name};
    # Remove leading and trailing whitespace.
    $channel =~ s/^\s+|\s+$//g;

    if (not exists($MSGTHREADID_CACHE{$channel})) {
        Irssi::print("${channel}: Empty cache");
        return;
    }

    foreach my $msgthread_id (@{$MSGTHREADID_CACHE{$channel}}) {
        Irssi::print("${channel}: ${msgthread_id}");
    }
};

my $MSGTHREADID_CACHE_SEARCH_ENABLED = 0;
my $MSGTHREADID_CACHE_INDEX = 0;
command_bind 'message_thread_id_search' => sub {
    my ($data, $server, $wi) = @_;

    return unless ref $wi and $wi->{type} eq 'CHANNEL';
    if (not exists($MSGTHREADID_CACHE{$wi->{name}})) {
        return;
    }

    $MSGTHREADID_CACHE_SEARCH_ENABLED = 1;
    my $msgthreadid = $MSGTHREADID_CACHE{$wi->{name}}[$MSGTHREADID_CACHE_INDEX];
    $MSGTHREADID_CACHE_INDEX += 1;
    if ($MSGTHREADID_CACHE_INDEX > $#{$MSGTHREADID_CACHE{$wi->{name}}}) {
        # Cycle back to the start.
        $MSGTHREADID_CACHE_INDEX = 0;
    }

    # Save input text.
    my $input = Irssi::parse_special('$L');
    # Remove existing thread.
    $input =~ s/^@@(?:[0-9a-z]{26}|[0-9a-f]{3}) //;
    # Insert message/thread ID from cache.
    gui_input_set_pos(0);
    gui_input_set("\@\@${msgthreadid} ${input}");
};

my $KEY_ESC = 27;
my $KEY_RET = 13;
my $KEY_SPC = 32;

signal_add_last 'gui key pressed' => sub {
    my ($key) = @_;

    if (not $MSGTHREADID_CACHE_SEARCH_ENABLED) {
        return;
    }

    if ($key == $KEY_RET) {
        $MSGTHREADID_CACHE_INDEX = 0;
        $MSGTHREADID_CACHE_SEARCH_ENABLED = 0;
    }

    elsif ($key == $KEY_ESC) {
        # Cancel/abort, so remove thread stuff.
        my $input = Irssi::parse_special('$L');
        $input =~ s/^@@(?:[0-9a-z]{26}|[0-9a-f]{3}) //;
        gui_input_set_pos(0);
        gui_input_set($input);

        $MSGTHREADID_CACHE_INDEX = 0;
        $MSGTHREADID_CACHE_SEARCH_ENABLED = 0;
    }
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


my %NICKNAMES_CACHE;
settings_add_int('matterircd_complete', 'matterircd_complete_nick_cache_size', 20);
command_bind 'matterircd_complete_nicknames_cache_dump' => sub {
    my ($data, $server, $wi) = @_;

    if (not $data) {
        return unless ref $wi and $wi->{type} eq 'CHANNEL';
    }

    my $channel = $data ? $data : $wi->{name};
    # Remove leading and trailing whitespace.
    $channel =~ s/^\s+|\s+$//g;

    if (not exists($NICKNAMES_CACHE{$channel})) {
        Irssi::print("${channel}: Empty cache");
        return;
    }

    foreach my $nick (@{$NICKNAMES_CACHE{$channel}}) {
        Irssi::print("${channel}: ${nick}");
    }
};

signal_add_last 'complete word' => sub {
    my ($complist, $window, $word, $linestart, $want_space) = @_;

    my $wi = Irssi::active_win()->{active};
    return unless ref $wi and $wi->{type} eq 'CHANNEL';
    my $server = Irssi::active_server();

    if (substr($word, 0, 1) ne '@') {
        return;
    }
    $word = substr($word, 1);

    my $compl_char = Irssi::settings_get_str('completion_char');

    # We need to store the results in a temporary array so we can sort.
    my @tmp;
    foreach my $nick ($wi->nicks()) {
        if ($nick->{nick} =~ /^\Q$word\E/i) {
            push(@tmp, "$nick->{nick}");
        }
    }
    @tmp = sort @tmp;
    foreach my $nick (@tmp) {
        # Ignore our own nick.
        if ($nick eq $server->{nick}) {
            next;
        }
        push(@$complist, "\@${nick}${compl_char}");
    }

    if (not exists($NICKNAMES_CACHE{$wi->{name}})) {
        return;
    }
    # We use the populated cache so frequent and active users in
    # channel come before those idling there. e.g. In a channel where
    # @barryp talks more often, it will come before @barry-m.
    # We want to make sure users are still in channel for those still in the cache.
    foreach my $nick (reverse @{$NICKNAMES_CACHE{$wi->{name}}}) {
        if ("\@${nick}${compl_char}" ~~ @$complist) {
            unshift(@$complist, "\@${nick}${compl_char}");
        }
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
