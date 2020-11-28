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

our %CACHE_MSG_THREAD_ID;

signal_add_last 'complete word' => sub {
    my ($complist, $window, $word, $linestart, $want_space) = @_;

    my $wi = Irssi::active_win()->{active};
    return unless ref $wi and $wi->{type} eq 'CHANNEL';

    # Only message/thread IDs at the start.
    if ($word !~ /^@@/) {
        return;
    }
    $word =~ s/^@@//;

    if (not exists($CACHE_MSG_THREAD_ID{$wi->{name}})) {
        return;
    }

    foreach my $msgthread_id (@{$CACHE_MSG_THREAD_ID{$wi->{name}}}) {
        if ($msgthread_id =~ /^\Q$word\E/) {
            push(@$complist, "\@\@$msgthread_id");
        }
    }
};

signal_add_last 'message public' => sub {
    my($server, $msg, $nick, $address, $target) = @_;

    if ($msg !~ '@@([0-9a-z]{26})') {
        return;
    }
    my $msgid = $1;

    if (not exists($CACHE_MSG_THREAD_ID{$target})) {
        $CACHE_MSG_THREAD_ID{$target} = ();
        my $cache_ref = \@{$CACHE_MSG_THREAD_ID{$target}};
        unshift(@$cache_ref, $msgid);
        return;
    }

    my $cache_ref = \@{$CACHE_MSG_THREAD_ID{$target}};

    # We want to reduce duplicates by removing them currently in the
    # per-channel cache. But as a trade off in favor of
    # speed/performance, rather than traverse the entire per-channel
    # cache, we cap it at the first 5.
    my $max = ($#$cache_ref < 5)? $#$cache_ref : 5;
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
