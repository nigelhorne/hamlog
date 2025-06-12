#!/usr/bin/env perl

use Mojo::JSON;
use Mojolicious::Lite;
use DBI;
use POSIX 'strftime';
use Text::CSV;
use JSON;

# SQLite DB file
my $dbfile = "hamlog.db";
my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", { RaiseError => 1, AutoCommit => 1 });

# Create log table if not exists
$dbh->do(<<'SQL');
CREATE TABLE IF NOT EXISTS log (
  id         INTEGER PRIMARY KEY,
  call       TEXT,
  date       TEXT,
  time       TEXT,
  frequency  TEXT,
  mode       TEXT,
  rst_sent   TEXT,
  rst_recv   TEXT,
  grid       TEXT,
  qsl_sent   TEXT,
  qsl_recv   TEXT,
  notes      TEXT
)
SQL

helper db => sub { $dbh };

# Home route with optional filters
get '/' => sub {
  my $c = shift;
  my $p = $c->req->query_params;
  my @where;
  my @bind;

  # Filter by call sign substring
  if (my $call = $p->param('call')) {
    push @where, "call LIKE ?";
    push @bind, "%$call%";
  }
  # Filter by mode
  if (my $mode = $p->param('mode')) {
    push @where, "mode = ?";
    push @bind, $mode;
  }
  # Date range filters
  if (my $from = $p->param('from_date')) {
    push @where, "date >= ?";
    push @bind, $from;
  }
  if (my $to = $p->param('to_date')) {
    push @where, "date <= ?";
    push @bind, $to;
  }

  my $sql = "SELECT * FROM log";
  $sql .= " WHERE " . join(" AND ", @where) if @where;
  $sql .= " ORDER BY date DESC, time DESC";

  my $rows = $c->db->selectall_arrayref($sql, { Slice => {} }, @bind);
  $c->stash(log => $rows);
  $c->render(template => 'index');
};

# New QSO form route
get '/new' => sub {
  my $c = shift;
  my $now_date = strftime("%Y-%m-%d", localtime);
  my $now_time = strftime("%H:%M", localtime);
  $c->stash(now_date => $now_date, now_time => $now_time);
  $c->render(template => 'new');
};

# Process new QSO form submission
post '/new' => sub {
  my $c = shift;
  my $p = $c->req->body_params;

  my $call = uc($p->param('call') // '');
  $call =~ s/^\s+|\s+$//g;

  $c->db->do(
    "INSERT INTO log (call, date, time, frequency, mode, rst_sent, rst_recv, grid, qsl_sent, qsl_recv, notes)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    undef,
    $call, $p->param('date'), $p->param('time'), $p->param('frequency'), $p->param('mode'),
    $p->param('rst_sent'), $p->param('rst_recv'), $p->param('grid'),
    $p->param('qsl_sent'), $p->param('qsl_recv'), $p->param('notes')
  );

  $c->redirect_to('/');
};

# Map route - shows QSO locations on map
get '/map' => sub {
  my $c = shift;
  my $rows = $c->db->selectall_arrayref("SELECT call, grid FROM log WHERE grid IS NOT NULL AND grid != ''", { Slice => {} });

  my @features;
  for my $r (@$rows) {
    my $grid = $r->{grid};
    my ($lat, $lon) = grid_to_latlon($grid);
    next unless defined $lat;
    push @features, {
      type => "Feature",
      geometry => { type => "Point", coordinates => [ $lon, $lat ] },
      properties => { call => $r->{call}, grid => $grid },
    };
  }

  $c->stash(features => \@features);
  $c->render(template => 'map');
};

# Stats route
get '/stats' => sub {
  my $c = shift;

  # QSOs by mode
  my $modes = $c->db->selectall_arrayref(
    "SELECT mode, COUNT(*) AS count FROM log GROUP BY mode ORDER BY count DESC",
    { Slice => {} }
  );

  # QSOs by band (frequency)
  my $bands = $c->db->selectall_arrayref(
    "SELECT frequency AS band, COUNT(*) AS count FROM log GROUP BY frequency ORDER BY count DESC",
    { Slice => {} }
  );

  # QSOs per month over time
  my $dates = $c->db->selectall_arrayref(
    "SELECT strftime('%Y-%m', date) AS month, COUNT(*) AS count FROM log GROUP BY month ORDER BY month",
    { Slice => {} }
  );

  $c->stash(
    stats_modes => $modes,
    stats_bands => $bands,
    stats_dates => $dates
  );

  $c->render(template => 'stats');
};

# CSV export of entire log
get '/export.csv' => sub {
  my $c = shift;
  my $rows = $c->db->selectall_arrayref("SELECT * FROM log ORDER BY date DESC, time DESC", { Slice => {} });

  my $csv = Text::CSV->new({ binary => 1, eol => "\n" });
  my $fh = IO::File->new_tmpfile;

  # Header row
  $csv->print($fh, [qw/id call date time frequency mode rst_sent rst_recv grid qsl_sent qsl_recv notes/]);

  # Data rows
  for my $r (@$rows) {
    $csv->print($fh, [ @$r{qw/id call date time frequency mode rst_sent rst_recv grid qsl_sent qsl_recv notes/} ]);
  }

  seek $fh, 0, 0;
  my $content = do { local $/; <$fh> };

  $c->res->headers->content_type('text/csv');
  $c->res->headers->content_disposition('attachment; filename=hamlog_export.csv');
  $c->render(data => $content);
};

# Helper to convert Maidenhead grid to lat/lon (center of grid square)
sub grid_to_latlon {
  my ($grid) = @_;
  return unless $grid =~ /^[A-R]{2}[0-9]{2}(?:[A-X]{2})?/;

  my ($A,$B,$C,$D,$E,$F) = split(//, uc($grid));
  my $lon = (ord($A)-ord('A'))*20 - 180 + (ord($C)-ord('0'))*2 + ((defined $E ? ord($E) - ord('A') : 0) + 0.5)/12;
  my $lat = (ord($B)-ord('A'))*10 - 90 + (ord($D)-ord('0'))*1 + ((defined $F ? ord($F) - ord('A') : 0) + 0.5)/24;
  return ($lat, $lon);
}

helper json => sub {
  my ($c, $data) = @_;
  return Mojo::JSON::to_json($data);
};


app->start;
