use strict;

use Irssi qw(signal_add_last);

our $VERSION = '1.00';
our %IRSSI = (
    name        => 'Matterircd Message Thread Tab Complete',
    description => 'Adds tab complettion for Matterircd message threads',
    authors     => 'Haw Loeung',
    contact     => 'hloeung/Freenode',
    license     => 'GPL',
);

my %MSGTHREADID_CACHE;

signal_add_last 'complete word' => sub {
    my ($complist, $window, $word, $linestart, $want_space) = @_;

    my $wi = Irssi::active_win()->{active};
    return unless ref $wi and $wi->{type} eq 'CHANNEL';

    # Only message/thread IDs at the start.
    if (substr($word, 0, 2) ne '@@') {
        return;
    }
    $word = substr($word, 2);

    if (not exists($MSGTHREADID_CACHE{$wi->{name}})) {
        return;
    }

    foreach my $msgthread_id (@{$MSGTHREADID_CACHE{$wi->{name}}}) {
        if ($msgthread_id =~ /^\Q$word\E/) {
            push(@$complist, "\@\@$msgthread_id");
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

    if (@$cache_ref[0] ne $msgid) {
        unshift(@$cache_ref, $msgid);
    }
};
