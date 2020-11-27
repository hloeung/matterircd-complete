use strict;

use Irssi qw(signal_add_last);

our $VERSION = '1.00';
our %IRSSI = (
    name        => 'Matterircd Message Thread Tab Complete',
    description => 'Adds tab complettion for Matterircd message threads',
    authors     => 'Haw Loeung',
    contact     => 'haw.loeung@canonical.com',
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

    # Message / thread IDs are added at the start of the array so most
    # recent would be first. We also want to avoid duplicates.
    if (@$cache_ref[0] ne $msgid) {
        unshift(@$cache_ref, $msgid);
    }

    # Maximum cache elements to store per channel.
    # XXX: Make this value configurable.
    if (scalar(@$cache_ref) > 20) {
        pop(@$cache_ref);
    }
};
