#!/usr/bin/env perl
# coverage-summary.pl: print one coverage table for the three tools.
# test/run.sh --coverage runs this from the root of the repository, after
# the tools wrote their data:
#
#   luacov.report.out        luacov, lines of Lua
#   cover_db/cover.json      Devel::Cover, statements of Perl
#   kcov/.../coverage.json   kcov, lines of bash
#
# Colors show only on a terminal, and not when NO_COLOR is set.
use strict;
use warnings;
use utf8;
use JSON::PP;

binmode STDOUT, ':encoding(UTF-8)';

my $color = -t STDOUT && !$ENV{NO_COLOR};
sub paint { my ($code, $s) = @_; $color ? "\e[${code}m$s\e[0m" : $s }

sub slurp {
    my ($path) = @_;
    open my $f, '<', $path or return undef;
    local $/;
    return scalar <$f>;
}

my @rows;    # [file, tool, covered, total]

# luacov: the Summary table at the end of the text report.
if (defined(my $text = slurp('luacov.report.out'))) {
    my ($summary) = $text =~ /^Summary\n(.*)/ms;
    for (split /\n/, $summary // '') {
        my ($file, $hits, $missed) = /^(\S+)\s+(\d+)\s+(\d+)\s+[\d.]+%$/ or next;
        next if $file eq 'Total';
        $file =~ s{^(?:\w+/)?\.\./}{};
        push @rows, [$file, 'luacov', $hits, $hits + $missed];
    }
}

# Devel::Cover: statements, from its JSON report.
if (defined(my $json = slurp('cover_db/cover.json'))) {
    my $summary = decode_json($json)->{summary};
    for my $file (sort grep { $_ ne 'Total' } keys %$summary) {
        my $s = $summary->{$file}{statement};
        push @rows, [$file, 'Devel::Cover', $s->{covered}, $s->{total}];
    }
}

# kcov: the merged result of all the bash tests, or the result of one.
my ($kcov) = grep { -f } 'kcov/kcov-merged/coverage.json', glob('kcov/*/coverage.json');
if ($kcov) {
    for my $f (sort { $a->{file} cmp $b->{file} } @{ decode_json(slurp($kcov))->{files} }) {
        (my $file = $f->{file}) =~ s{.*/(bin/)}{$1};
        push @rows, [$file, 'kcov', $f->{covered_lines}, $f->{total_lines}];
    }
}

die "coverage-summary.pl: no coverage data found\n" unless @rows;

# The percentage, rounded down, so that a file with a missed line never
# shows 100.0%.
sub percent { my ($c, $t) = @_; $t ? int($c / $t * 1000) / 10 : 100 }

sub level { my ($p) = @_; $p >= 100 ? 32 : $p >= 75 ? 33 : 31 }  # green, yellow, red

sub bar {
    my ($p) = @_;
    my $full = int($p / 10);
    return paint(level($p), '█' x $full) . paint(90, '░' x (10 - $full));
}

sub row {
    my ($file, $tool, $covered, $total) = @_;
    my $p = percent($covered, $total);
    my $name = sprintf '%-22s', $file;
    $name = paint(1, $name) if $file eq 'Total';
    printf "  %s %-13s %9s    %s %s\n", $name, $tool, "$covered/$total", bar($p),
        paint(level($p), sprintf '%5.1f%%', $p);
}

print paint(1, 'Coverage'), "\n";
print paint(90, sprintf "  %-22s %-13s %9s    %s\n", 'File', 'Tool', 'Covered', 'Coverage');
my ($covered, $total) = (0, 0);
for (@rows) {
    row(@$_);
    $covered += $_->[2];
    $total += $_->[3];
}
row('Total', '', $covered, $total);
