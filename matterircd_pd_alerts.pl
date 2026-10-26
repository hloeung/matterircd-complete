#
# Compacts the table-style PagerDuty bot messages relayed by matterircd
# into single lines, and re-joins URLs that matterircd split over several
# lines.
#
# Add it to ~/.irssi/scripts/autorun, or:
#
#   /script load ~/.irssi/scripts/matterircd_pd_alerts.pl
#
# A bot message such as:
#
#   [↪@@abc,@@def] some alert description (https://pagerduty/incidents/Q1)
#   🮇 Alert ID    Status        Assignee
#   🮇 Q1          ✅ RESOLVED   usernickname
#   🮇 Actions
#   🮇  ➥ View Source (https://example.com/source)
#
# is displayed as:
#
#   [↪@@abc,@@def] ✅ RESOLVED Q1 some alert description @ usernickname
#   ➥ PagerDuty: https://pagerduty/incidents/Q1
#   ➥ View Source: https://example.com/source
#
# Any status is handled as it is taken verbatim from the table. The
# timestamp BIP replays between the nick and the thread ID tag is ignored
# when parsing, and kept in the output.
#
# Settings:
#
#   /set matterircd_pd_alerts_nicks is-pd-bot
#   /set matterircd_pd_alerts_networks *
#   /set matterircd_pd_alerts_channels #is-pagerduty #is-outage
#   /set matterircd_pd_alerts_ignore_channel_links ON
#   /set matterircd_pd_alerts_flush_timeout 750
#   /set matterircd_pd_alerts_strip_reply_suffix ON
#
# matterircd_pd_alerts_channels restricts the script to the listed channels,
# empty (the default) means all channels.
#
# matterircd_pd_alerts_strip_reply_suffix removes the "(re @nick: ...)" suffix
# matterircd adds to the bot's messages.
#
# matterircd_pd_alerts_ignore_channel_links drops the links between the
# channels ("Internal Discussion" and "View ~channel Announcement").
#
# Should be loaded alongside matterircd_complete.pl; the compacted lines are
# re-emitted as regular 'message public' signals so its thread ID handling
# keeps working.

use strict;
use warnings;

require Irssi;

our $VERSION = '0.01';
our %IRSSI = (
    name        => 'Matterircd PagerDuty Alerts',
    description => 'Compacts table-style PagerDuty bot messages into single lines',
    authors     => 'Loïc Gomez',
    contact     => 'kotodama/Libera.chat',
    license     => 'GPL',
);

Irssi::settings_add_str('matterircd_pd_alerts', 'matterircd_pd_alerts_nicks', 'is-pd-bot');
Irssi::settings_add_str('matterircd_pd_alerts', 'matterircd_pd_alerts_networks', '*');
Irssi::settings_add_str('matterircd_pd_alerts', 'matterircd_pd_alerts_channels', '');
Irssi::settings_add_bool('matterircd_pd_alerts', 'matterircd_pd_alerts_ignore_channel_links', 1);
Irssi::settings_add_int('matterircd_pd_alerts', 'matterircd_pd_alerts_flush_timeout', 750);
Irssi::settings_add_bool('matterircd_pd_alerts', 'matterircd_pd_alerts_strip_reply_suffix', 1);

# Strings are handled as UTF-8 bytes, like matterircd_complete.pl.
my $FMT_RE          = qr/(?:[\x02\x0f\x16\x1d\x1f]|\x03(?:\d{1,2}(?:,\d{1,2})?)?)*/;
my $BLOCK_PREFIX_RE = qr/^$FMT_RE\xF0\x9F\xAE\x87$FMT_RE ?/;
my $TIMESTAMP_RE    = qr/^($FMT_RE(?:\[\d{1,2}:\d{2}(?::\d{2})?\]|\d{1,2}:\d{2}(?::\d{2})?>)$FMT_RE\s*)/;
my $SUFFIX_RE       = qr/\s*(\(re\s*\@.*\))\s*$/s;
my $LINK_LINE_RE    = qr/^\s*(?:\xE2\x9E\xA5\s*)*(.*?)\s*\((https?:\/\/[^\s()]+)\)\s*$/;
my $MAX_LINES       = 100;

# Pending messages per server/channel/nick, only alive until flushed.
my %STATE;
our $EMITTING = 0;

my ($NICKS_RAW, %NICKS, $NETS_RAW, %NETS, $CHANS_RAW, %CHANS);

sub bot_nick {
    my ($nick) = @_;

    my $raw = Irssi::settings_get_str('matterircd_pd_alerts_nicks');
    if (!defined($NICKS_RAW) || $NICKS_RAW ne $raw) {
        $NICKS_RAW = $raw;
        %NICKS = map { lc($_) => 1 } split(/\s+/, $raw);
    }
    return exists $NICKS{lc($nick)};
}

sub channel_enabled {
    my ($target) = @_;

    my $raw = Irssi::settings_get_str('matterircd_pd_alerts_channels');
    if (!defined($CHANS_RAW) || $CHANS_RAW ne $raw) {
        $CHANS_RAW = $raw;
        %CHANS = map { lc($_) => 1 } split(/\s+/, $raw);
    }
    return 1 unless %CHANS;
    return exists $CHANS{lc($target)};
}

sub chatnet_enabled {
    my ($server) = @_;

    my $raw = Irssi::settings_get_str('matterircd_pd_alerts_networks');
    if (!defined($NETS_RAW) || $NETS_RAW ne $raw) {
        $NETS_RAW = $raw;
        %NETS = map { lc($_) => 1 } split(/\s+/, $raw);
    }
    return 1 if exists $NETS{'*'};
    return 1 if defined $server->{chatnet} && exists $NETS{lc($server->{chatnet})};
    return 1 if defined $server->{tag}     && exists $NETS{lc($server->{tag})};
    return 0;
}

# Mattermost pads tables with non-ASCII spaces which \s does not match on
# byte strings.
sub normalize_spaces {
    my ($s) = @_;

    $s =~ s/\xC2\xA0|\xE2\x80[\x80-\x8B\xAF]|\xE2\x81\x9F|\xE2\xA0\x80|\xE3\x80\x80|\xE3\x85\xA4/ /g;
    return $s;
}

sub strip_codes {
    my ($s) = @_;

    $s =~ s/\x03(?:\d{1,2}(?:,\d{1,2})?)?//g;
    $s =~ s/[\x02\x04\x0f\x11\x16\x1d\x1e\x1f]//g;
    return $s;
}

sub split_line {
    my ($msg) = @_;

    my $ts = '';
    $ts = $1 if $msg =~ s/$TIMESTAMP_RE//;
    my $bar = ($msg =~ s/($BLOCK_PREFIX_RE)//) ? $1 : '';
    return { ts => $ts, block => ($bar ne '' ? 1 : 0), bar => $bar, body => $msg };
}

# matterircd splits long lines, leaving a URL unterminated.
sub line_open {
    my ($line) = @_;

    my $text = strip_codes($line->{body});
    return 1 if $text =~ /\(https?:\/\/[^\s)]*$/;
    return 1 if $text =~ /\(re(?:\s[^)]*)?$/;
    return 1 if $text =~ /\(\s*$/;
    return 1 if $line->{block} && $text =~ /\xE2\x9E\xA5[^()]*$/ && $text !~ /https?:\/\//;
    return 1 if length($text) >= 200 && $text =~ /(?:^|\s)https?:\/\/\S+$/;
    return 0;
}

sub looks_like_continuation {
    my ($st, $line) = @_;

    my $last = $st->{lines}[-1];
    return 0 unless $last;
    my $text = strip_codes($last->{body});
    return 1 if $text =~ /\(https?:\/\/[^\s)]*$/;
    return 1 if $text =~ /\(re(?:\s[^)]*)?$/;
    return 1 if $text =~ /\(\s*$/;
    return !$line->{block} ? 1 : 0
        if $last->{block} && $text =~ /\xE2\x9E\xA5[^()]*$/ && $text !~ /https?:\/\//;
    # matterircd wraps at roughly 500 bytes; the remainder has no thread tag or bar.
    return 1 if !$last->{block} && !$line->{block} && length($text) >= 400 && $line->{body} !~ /^\[/;
    return 0 unless length($text) >= 200 && $text =~ /(?:^|\s)https?:\/\/\S+$/;
    return strip_codes($line->{body}) =~ /^\S+$/ ? 1 : 0;
}

sub emit_line {
    my ($st, $text) = @_;

    return unless defined $st->{server};
    local $EMITTING = 1;
    Irssi::signal_emit('message public', $st->{server}, $text, $st->{nick}, $st->{address}, $st->{target});
}

sub parse_table {
    my ($lines) = @_;

    my (%res, @header);
    $res{links}  = [];
    $res{extra}  = [];
    my $section = '';
    foreach my $line (@$lines) {
        my $text = strip_codes($line->{body});
        $text =~ s/^\s+//;
        $text =~ s/\s+$//;
        next if $text eq '';

        # Lines may have lost their bold codes.
        my $title;
        if ($line->{body} =~ /^\s*\x02([^\x02]+)\x02?\s*$/) {
            $title = strip_codes($1);
            $title =~ s/\s+$//;
        } elsif ($text =~ /^(?:Actions|Internal Discussion|Alert ID\s{2,}\S.*)$/) {
            $title = $text;
        }
        if (defined $title) {
            if ($title =~ /\S\s{2,}\S/) {
                @header = split(/\s{2,}/, $title);
                $section = 'row';
            } else {
                $section = $title;
            }
            next;
        }
        if ($section eq 'row') {
            my @vals = split(/\s{2,}/, $text);
            for my $i (0 .. $#vals) {
                my $name = $header[$i] // "field$i";
                $res{lc $name} = $vals[$i];
            }
            $section = '';
        } elsif ($text =~ $LINK_LINE_RE) {
            push @{$res{links}}, { section => $section, label => $1, url => $2 };
        } else {
            push @{$res{extra}}, ($section ne '' ? "$section: " : '') . $text;
        }
    }
    return \%res;
}

sub flush_state {
    my ($key) = @_;

    my $st = delete $STATE{$key} or return;
    Irssi::timeout_remove($st->{timer}) if defined $st->{timer};
    my @lines = @{$st->{lines}};
    return unless @lines;

    my $strip = Irssi::settings_get_bool('matterircd_pd_alerts_strip_reply_suffix');
    if (!grep { $_->{block} } @lines) {
        foreach my $line (@lines) {
            $line->{body} =~ s/$SUFFIX_RE// if $strip;
            emit_line($st, $line->{ts} . $line->{body}) if $line->{body} ne '';
        }
        return;
    }

    my $main;
    my @block_lines;
    foreach my $line (@lines) {
        if (!$line->{block} && !$main && !@block_lines) {
            $main = $line;
        } else {
            push @block_lines, $line;
        }
    }

    my $suffix = '';
    foreach my $line (@block_lines) {
        if ($line->{body} =~ s/$SUFFIX_RE//) {
            $suffix = strip_codes($1);
        }
    }

    my $tbl = parse_table(\@block_lines);
    my $ignore_links = Irssi::settings_get_bool('matterircd_pd_alerts_ignore_channel_links');
    my @links = grep {
        !($ignore_links && ($_->{section} eq 'Internal Discussion' || $_->{label} =~ /^View ~\S+ Announcement$/))
    } @{$tbl->{links}};

    my ($ts, $tag, $text, $pd_url) = ('', '', '');
    if ($main) {
        $ts = $main->{ts};
        $text = $main->{body};
        if ($text =~ s/^(\[[^\]]*\])\s*//) {
            $tag = $1;
        }
        if ($text =~ s/\s*\((https?:\/\/[^\s()]+)\)\s*$//) {
            $pd_url = $1;
        }
    }
    my $assignee = $tbl->{assignee};
    my @unknown = map { "$_: $tbl->{$_}" } grep {
        my $k = $_; $k ne 'links' && $k ne 'extra' && !grep { $_ eq $k } ('alert id', 'status', 'assignee')
    } sort keys %$tbl;

    my $status = defined $tbl->{status} && $tbl->{status} ne '' ? "\x02$tbl->{status}\x02" : '';
    my @parts = grep { defined($_) && $_ ne '' } ($tag, $status, $tbl->{'alert id'}, $text);
    my @out;
    my $first = join(' ', @parts);
    $first .= " @ $assignee" if defined $assignee && $assignee ne '';
    $first .= ' [' . join('; ', @unknown) . ']' if @unknown;
    $first .= " ($pd_url)" if defined $pd_url;
    push @out, $first if $first ne '';
    # Keep the coloured bar of the table lines on the link/extra lines.
    my $bar = (grep { $_->{block} } @block_lines)[0]{bar};
    push @out, "$bar\xE2\x9E\xA5 $_->{label}: $_->{url}" foreach @links;
    push @out, map { "$bar$_" } @{$tbl->{extra}};

    if ($suffix ne '' && @out && !$strip) {
        $out[-1] .= " $suffix";
    }
    emit_line($st, $ts . $_) foreach @out;
}

sub timer_flush {
    my ($key) = @_;

    my $st = $STATE{$key} or return;
    # The timer has fired, nothing to remove.
    $st->{timer} = undef;
    flush_state($key);
}

sub arm_timer {
    my ($key, $st) = @_;

    Irssi::timeout_remove($st->{timer}) if defined $st->{timer};
    my $ms = Irssi::settings_get_int('matterircd_pd_alerts_flush_timeout');
    $ms = 10 if $ms < 10;
    $st->{timer} = Irssi::timeout_add_once($ms, 'timer_flush', $key);
}

sub signal_message_public_pd_alerts {
    my ($server, $msg, $nick, $address, $target) = @_;

    return if $EMITTING;
    return unless defined $server && defined $msg && defined $nick && defined $target;
    return unless bot_nick($nick) && chatnet_enabled($server) && channel_enabled($target);

    utf8::encode($msg) if utf8::is_utf8($msg);
    $msg = normalize_spaces($msg);
    Irssi::signal_stop();

    my $key = join("\0", $server->{tag} // '', lc($target), lc($nick));
    my $line = split_line($msg);
    my $st = $STATE{$key};

    if ($st && looks_like_continuation($st, $line)) {
        # matterircd splits on spaces too, dropping them; only URL fragments join directly.
        $st->{lines}[-1]{body} .= ' ' unless strip_codes($st->{lines}[-1]{body}) =~ /(?:\(|(?:^|\s))https?:\/\/[^\s)]*$/;
        $st->{lines}[-1]{body} .= $line->{body};
    } elsif ($st && $line->{block}) {
        push @{$st->{lines}}, $line;
    } else {
        flush_state($key) if $st;
        $st = $STATE{$key} = {
            server  => $server,
            nick    => $nick,
            address => $address,
            target  => $target,
            lines   => [$line],
        };
    }

    if (@{$st->{lines}} >= $MAX_LINES) {
        flush_state($key);
        return;
    }

    my $last = $st->{lines}[-1];
    if (!line_open($last) && strip_codes($last->{body}) =~ /\(re\s*\@.*\)\s*$/s) {
        flush_state($key);
        return;
    }
    arm_timer($key, $st);
}

sub signal_server_disconnected_pd_alerts {
    my ($server) = @_;

    return unless $server;
    my $prefix = ($server->{tag} // '') . "\0";
    foreach my $key (grep { index($_, $prefix) == 0 } keys %STATE) {
        my $st = delete $STATE{$key};
        Irssi::timeout_remove($st->{timer}) if defined $st->{timer};
    }
}

Irssi::signal_add_first('message public', 'signal_message_public_pd_alerts');
Irssi::signal_add('server disconnected', 'signal_server_disconnected_pd_alerts');
