#
# For the full matterircd_complete experience, your matterircd.toml
# should have SuffixContext=true and ThreadContext="mattermost".
#
# Add it to ~/.irssi/scripts/autorun, or:
#
#   /script load ~/.irssi/scripts/matterircd_complete.pl
#   /set matterircd_complete_networks <...>
#
# NOTE: It is important to set which networks to enable plugin for per
# above ^.
#
# Bind message/thread ID completion to a key to make it easier to
# reply to threads:
#
#   /bind ^G /message_thread_id_search'
#
# Also bind to insert nicknames:
#
#   /bind ^F /nicknames_search
#
# (Or pick your own shortcut keys to bind to).
#
# Then:
#
#   Ctrl+g - Insert latest message/thread ID.
#   Ctrl+c - Abort inserting message/thread ID. Also clears existing.
#
#   @@+TAB to tab auto-complete message/thread ID.
#   @ +TAB to tab auto-complete IRC nick. Active users appear first.
#
# By default, message/thread IDs are shortened from 26 characters to
# first few (default 4). It is also grayed out to try reduce noise and
# make it easier to read conversations. To disable this use:
#
#   /set matterircd_complete_shorten_message_thread_id 0
#
# Use the dump commands to show the contents of the cache:
#
#   /matterircd_complete_msgthreadid_cache_dump
#   /matterircd_complete_nicknames_cache_dump
#
# (You can bind these to keys).
#
# To increase or decrease the size of the cache, use:
#
#   /set matterircd_complete_message_thread_id_cache_size 50
#   /set matterircd_complete_nick_cache_size 20
#

use strict;
use warnings;
use experimental 'smartmatch';

use Irssi::TextUI;
use Irssi qw(command_bind gui_input_set gui_input_get_pos gui_input_set_pos parse_special settings_add_bool settings_add_int settings_get_bool settings_get_int settings_get_str settings_add_str signal_add signal_add_last signal_continue);

# Enable for debugging purposes only.
# use Data::Dumper;

our $VERSION = '1.00';
our %IRSSI = (
    name        => 'Matterircd Tab Auto Complete',
    description => 'Adds tab completion for Matterircd message threads',
    authors     => 'Haw Loeung',
    contact     => 'hloeung/Freenode',
    license     => 'GPL',
);

my $KEY_CTRL_C = 3;
my $KEY_ESC    = 27;
my $KEY_RET    = 13;
my $KEY_SPC    = 32;

settings_add_str('matterircd_complete', 'matterircd_complete_networks', '');

# Rely on message/thread IDs stored in message cache so we can shorten
# to save on screen real-estate.
settings_add_int('matterircd_complete', 'matterircd_complete_shorten_message_thread_id', 4);
sub update_msgthreadid {
    my($server, $msg, $nick, $address, $target) = @_;

    my %chatnets = map { $_ => 1 } split(/\s+/, settings_get_str('matterircd_complete_networks'));
    return unless exists $chatnets{'*'} || exists $chatnets{$server->{chatnet}};

    # For '/me' actions, it has trailing space so we need to use
    # \s* here.
    $msg =~ s/\[\@\@([0-9a-z]{26})\]\s*$/\@\@PLACEHOLDER\@\@/;
    my $msgthreadid = $1;
    return unless $msgthreadid;

    my $len = settings_get_int('matterircd_complete_shorten_message_thread_id');
    if ($len) {
        # Shorten to length configured. We use unicode ellipsis (...)
        # here to both allow word selection to just select parts of
        # the message/thread ID when copying & pasting and save on
        # screen real estate.
        $msgthreadid = substr($msgthreadid, 0, $len) . '…';
    }
    $msg =~ s/\@\@PLACEHOLDER\@\@/\x0314[\@\@${msgthreadid}]/;

    signal_continue($server, $msg, $nick, $address, $target);
}
signal_add_last('message irc action', 'update_msgthreadid');
signal_add_last('message irc notice', 'update_msgthreadid');
signal_add_last('message private', 'update_msgthreadid');
signal_add_last('message public', 'update_msgthreadid');

sub cache_store {
    my ($cache_ref, $item, $cache_size) = @_;

    return unless $item ne '';

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
    if (($cache_size > 0) && (scalar(@$cache_ref) > $cache_size)) {
        pop(@$cache_ref);
    }
}


my %MSGTHREADID_CACHE;
settings_add_int('matterircd_complete', 'matterircd_complete_message_thread_id_cache_size', 50);
command_bind 'matterircd_complete_msgthreadid_cache_dump' => sub {
    my ($data, $server, $wi) = @_;

    if (not $data) {
        return unless ref $wi and ($wi->{type} eq 'CHANNEL' or $wi->{type} eq 'QUERY');
    }

    my %chatnets = map { $_ => 1 } split(/\s+/, settings_get_str('matterircd_complete_networks'));
    return unless exists $chatnets{'*'} || exists $chatnets{$server->{chatnet}};

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

    return unless ref $wi and ($wi->{type} eq 'CHANNEL' or $wi->{type} eq 'QUERY');
    return unless exists($MSGTHREADID_CACHE{$wi->{name}});

    my %chatnets = map { $_ => 1 } split(/\s+/, settings_get_str('matterircd_complete_networks'));
    return unless exists $chatnets{'*'} || exists $chatnets{$server->{chatnet}};

    $MSGTHREADID_CACHE_SEARCH_ENABLED = 1;
    my $msgthreadid = $MSGTHREADID_CACHE{$wi->{name}}[$MSGTHREADID_CACHE_INDEX];
    $MSGTHREADID_CACHE_INDEX += 1;
    if ($MSGTHREADID_CACHE_INDEX > $#{$MSGTHREADID_CACHE{$wi->{name}}}) {
        # Cycle back to the start.
        $MSGTHREADID_CACHE_INDEX = 0;
    }

    if ($msgthreadid) {
        # Save input text.
        my $input = parse_special('$L');
        # Remove existing thread.
        $input =~ s/^@@(?:[0-9a-z]{26}|[0-9a-f]{3}) //;
        # Insert message/thread ID from cache.
        gui_input_set_pos(0);
        gui_input_set("\@\@${msgthreadid} ${input}");
    }
};

signal_add_last 'gui key pressed' => sub {
    my ($key) = @_;

    return unless $MSGTHREADID_CACHE_SEARCH_ENABLED;

    my $server = Irssi::active_server();
    my %chatnets = map { $_ => 1 } split(/\s+/, settings_get_str('matterircd_complete_networks'));
    return unless exists $chatnets{'*'} || exists $chatnets{$server->{chatnet}};

    if ($key == $KEY_RET) {
        $MSGTHREADID_CACHE_INDEX = 0;
        $MSGTHREADID_CACHE_SEARCH_ENABLED = 0;
    }

    elsif ($key == $KEY_CTRL_C) {
        # Cancel/abort, so remove thread stuff.
        my $input = parse_special('$L');
        my $pos = 0;
        if ($input =~ s/^(@@(?:[0-9a-z]{26}|[0-9a-f]{3}) )//) {
            $pos = gui_input_get_pos() - length($1);
        }
        # Remove the Ctrl+C character.
        my $keychr = chr($key);
        $input =~ s/$keychr//;
        # We also want to move the input position back one for Ctrl+C
        # char.
        $pos -= 1;

        # Replace the text in the input box with our modified version,
        # then move cursor positon to where it was without the
        # message/thread ID.
        gui_input_set($input);
        gui_input_set_pos($pos);

        $MSGTHREADID_CACHE_INDEX = 0;
        $MSGTHREADID_CACHE_SEARCH_ENABLED = 0;
    }
};

signal_add_last 'complete word' => sub {
    my ($complist, $window, $word, $linestart, $want_space) = @_;

    return unless substr($word, 0, 2) eq '@@';
    return unless $window->{active} and ($window->{active}->{type} eq 'CHANNEL' || $window->{active}->{type} eq 'QUERY');
    return unless exists($MSGTHREADID_CACHE{$window->{active}->{name}});

    my %chatnets = map { $_ => 1 } split(/\s+/, settings_get_str('matterircd_complete_networks'));
    return unless exists $chatnets{'*'} || exists $chatnets{$window->{active_server}->{chatnet}};

    $word = substr($word, 2);

    foreach my $msgthread_id (@{$MSGTHREADID_CACHE{$window->{active}->{name}}}) {
        if ($msgthread_id =~ /^\Q$word\E/) {
            push(@$complist, "\@\@${msgthread_id}");
        }
    }
};

sub cache_msgthreadid {
    my($server, $msg, $nick, $address, $target) = @_;

    my %chatnets = map { $_ => 1 } split(/\s+/, settings_get_str('matterircd_complete_networks'));
    return unless exists $chatnets{'*'} || exists $chatnets{$server->{chatnet}};

    my $msgid = '';

    # For '/me' actions, it has trailing space so we need to use \s*
    # here. We use unicode ellipsis (...) here to both allow
    # Mattermost message/thread IDs.
    if ($msg =~ /(?:^\[@@([0-9a-z]{26})\])|(?:\[@@([0-9a-z]{26})\]\s*$)/) {
        $msgid = $1 ? $1 : $2;
    }
    # matterircd generated 3-letter hexadecimal.
    elsif ($msg =~ /(?:^\[([0-9a-f]{3})\])|(?:\[([0-9a-f]{3})\]\s*$)/) {
        $msgid = $1 ? $1 : $2;
    }
    # matterircd generated 3-letter hexadecimal replying to threads.
    elsif ($msg =~ /(?:^\[[0-9a-f]{3}->([0-9a-f]{3})\])|(?:\[[0-9a-f]{3}->([0-9a-f]{3})\]\s*$)/) {
        $msgid = $1 ? $1 : $2;
    }
    else {
        return;
    }

    my $cache_size = settings_get_int('matterircd_complete_message_thread_id_cache_size');
    cache_store(\@{$MSGTHREADID_CACHE{$target}}, $msgid, $cache_size);
}
signal_add('message irc action', 'cache_msgthreadid');
signal_add('message irc notice', 'cache_msgthreadid');
signal_add('message private', 'cache_msgthreadid');
signal_add('message public', 'cache_msgthreadid');

signal_add 'message own_public' => sub {
    my($server, $msg, $target) = @_;

    my %chatnets = map { $_ => 1 } split(/\s+/, settings_get_str('matterircd_complete_networks'));
    return unless exists $chatnets{'*'} || exists $chatnets{$server->{chatnet}};

    if ($msg !~ /^@@((?:[0-9a-z]{26})|(?:[0-9a-f]{3}))/) {
        return;
    }
    my $msgid = $1;

    my $cache_size = settings_get_int('matterircd_complete_message_thread_id_cache_size');
    cache_store(\@{$MSGTHREADID_CACHE{$target}}, $msgid, $cache_size);
};

signal_add 'message own_private' => sub {
    my($server, $msg, $target, $orig_target) = @_;

    my %chatnets = map { $_ => 1 } split(/\s+/, settings_get_str('matterircd_complete_networks'));
    return unless exists $chatnets{'*'} || exists $chatnets{$server->{chatnet}};

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

    my %chatnets = map { $_ => 1 } split(/\s+/, settings_get_str('matterircd_complete_networks'));
    return unless exists $chatnets{'*'} || exists $chatnets{$server->{chatnet}};

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

    return unless substr($word, 0, 1) eq '@';
    return unless $window->{active} and $window->{active}->{type} eq 'CHANNEL';

    my %chatnets = map { $_ => 1 } split(/\s+/, settings_get_str('matterircd_complete_networks'));
    return unless exists $chatnets{'*'} || exists $chatnets{$window->{active_server}->{chatnet}};

    $word = substr($word, 1);
    my $compl_char = settings_get_str('completion_char');

    # We need to store the results in a temporary array so we can sort.
    my @tmp;
    foreach my $nick ($window->{active}->nicks()) {
        if ($nick->{nick} =~ /^\Q$word\E/i) {
            push(@tmp, "$nick->{nick}");
        }
    }
    @tmp = sort @tmp;
    foreach my $nick (@tmp) {
        # Ignore our own nick.
        if ($nick eq $window->{active_server}->{nick}) {
            next;
        }
        push(@$complist, "\@${nick}${compl_char}");
    }

    return unless exists($NICKNAMES_CACHE{$window->{active}->{name}});

    # We use the populated cache so frequent and active users in
    # channel come before those idling there. e.g. In a channel where
    # @barryp talks more often, it will come before @barry-m.
    # We want to make sure users are still in channel for those still in the cache.
    foreach my $nick (reverse @{$NICKNAMES_CACHE{$window->{active}->{name}}}) {
        my $nick_compl = "\@${nick}${compl_char}";
        # Skip over if nick is already first in completion list.
        if ((scalar(@{$complist}) > 0) and ($nick_compl eq @{$complist}[0])) {
            next;
        }
        # Only add to completion list if user/nick is online and in channel.
        elsif ("\@${nick}${compl_char}" ~~ @$complist) {
            unshift(@$complist, "\@${nick}${compl_char}");
        }
    }
};

sub cache_ircnick {
    my($server, $msg, $nick, $address, $target) = @_;

    my %chatnets = map { $_ => 1 } split(/\s+/, settings_get_str('matterircd_complete_networks'));
    return unless exists $chatnets{'*'} || exists $chatnets{$server->{chatnet}};

    my $cache_size = settings_get_int('matterircd_complete_nick_cache_size');
    cache_store(\@{$NICKNAMES_CACHE{$target}}, $nick, $cache_size);
}
signal_add('message irc action', 'cache_ircnick');
signal_add('message irc notice', 'cache_ircnick');
signal_add('message public', 'cache_ircnick');

signal_add_last 'message own_public' => sub {
    my($server, $msg, $target) = @_;

    my %chatnets = map { $_ => 1 } split(/\s+/, settings_get_str('matterircd_complete_networks'));
    return unless exists $chatnets{'*'} || exists $chatnets{$server->{chatnet}};

    if ($msg !~ /^@([^@ \t:,\)]+)/) {
        return;
    }
    my $nick = $1;

    my $cache_size = settings_get_int('matterircd_complete_nick_cache_size');
    # We want to make sure that the nick or user is still online and
    # in the channel.
    my $wi = Irssi::active_win()->{active};
    if (not defined $wi) {
        return;
    }
    foreach my $cur ($wi->nicks()) {
        if ($nick eq $cur->{nick}) {
            cache_store(\@{$NICKNAMES_CACHE{$target}}, $nick, $cache_size);
            return;
        }
    }
};

my $NICKNAMES_CACHE_SEARCH_ENABLED = 0;
my $NICKNAMES_CACHE_INDEX = 0;
command_bind 'nicknames_search' => sub {
    my ($data, $server, $wi) = @_;

    return unless ref $wi and ($wi->{type} eq 'CHANNEL' or $wi->{type} eq 'QUERY');
    return unless exists($NICKNAMES_CACHE{$wi->{name}});

    my %chatnets = map { $_ => 1 } split(/\s+/, settings_get_str('matterircd_complete_networks'));
    return unless exists $chatnets{'*'} || exists $chatnets{$server->{chatnet}};

    $NICKNAMES_CACHE_SEARCH_ENABLED = 1;
    my $nickname = $NICKNAMES_CACHE{$wi->{name}}[$NICKNAMES_CACHE_INDEX];
    $NICKNAMES_CACHE_INDEX += 1;
    if ($NICKNAMES_CACHE_INDEX > $#{$NICKNAMES_CACHE{$wi->{name}}}) {
        # Cycle back to the start.
        $NICKNAMES_CACHE_INDEX = 0;
    }

    if ($nickname) {
        # Save input text.
        my $input = parse_special('$L');
        my $compl_char = settings_get_str('completion_char');
        # Remove any existing nickname and insert one from the cache.
        my $msgid = "";
        if ($input =~ s/^(\@\@(?:[0-9a-z]{26}|[0-9a-f]{3}) )//) {
            $msgid = $1;
        }
        $input =~ s/^\@[^${compl_char}]+$compl_char //;
        gui_input_set_pos(0);
        gui_input_set("${msgid}\@${nickname}${compl_char} ${input}");
    }
};

signal_add_last 'gui key pressed' => sub {
    my ($key) = @_;

    return unless $NICKNAMES_CACHE_SEARCH_ENABLED;

    my $server = Irssi::active_server();
    my %chatnets = map { $_ => 1 } split(/\s+/, settings_get_str('matterircd_complete_networks'));
    return unless exists $chatnets{'*'} || exists $chatnets{$server->{chatnet}};

    if ($key == $KEY_RET) {
        $NICKNAMES_CACHE_INDEX = 0;
        $NICKNAMES_CACHE_SEARCH_ENABLED = 0;
    }

    elsif ($key == $KEY_CTRL_C) {
        # Cancel/abort, so remove current nickname.
        my $input = parse_special('$L');
        my $compl_char = settings_get_str('completion_char');
        my $pos = 0;
        if ($input =~ s/^(\@[^${compl_char}]+$compl_char )//) {
            $pos = gui_input_get_pos() - length($1);
        }
        # Remove the Ctrl+C character.
        my $keychr = chr($key);
        $input =~ s/$keychr//;
        # We also want to move the input position back one for Ctrl+C
        # char.
        $pos -= 1;

        # Replace the text in the input box with our modified version,
        # then move cursor positon to where it was without the
        # current nickname.
        gui_input_set($input);
        gui_input_set_pos($pos);

        $NICKNAMES_CACHE_INDEX = 0;
        $NICKNAMES_CACHE_SEARCH_ENABLED = 0;
    }
};
