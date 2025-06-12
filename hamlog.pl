#!/usr/bin/env perl
use Mojolicious::Lite;
use DBI;
use POSIX 'strftime';
use Text::CSV;
use IO::File;

# DB setup
my $dbfile = "hamlog.db";
my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", { RaiseError => 1, AutoCommit => 1 });

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

# Routes
get '/' => sub {
  my $c = shift;
  my $p = $c->req->query_params;
  my @where;
  my @bind;

  if (my $call = $p->param('call')) {
    push @where, "call LIKE ?";
    push @bind, "%$call%";
  }
  if (my $mode = $p->param('mode')) {
    push @where, "mode = ?";
    push @bind, $mode;
  }
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

get '/stats' => sub {
  my $c = shift;
  my $summary = $c->db->selectall_arrayref(
    "SELECT mode, COUNT(*) AS count FROM log GROUP BY mode ORDER BY count DESC",
    { Slice => {} }
  );
  my $bands = $c->db->selectall_arrayref(
    "SELECT frequency, COUNT(*) AS count FROM log GROUP BY frequency ORDER BY count DESC",
    { Slice => {} }
  );
  $c->stash(stats_modes => $summary, stats_bands => $bands);
  $c->render(template => 'stats');
};

sub grid_to_latlon {
  my ($grid) = @_;
  return unless $grid =~ /^[A-R]{2}[0-9]{2}(?:[A-X]{2})?/;

  my ($A,$B,$C,$D,$E,$F) = split(//, uc($grid));
  my $lon = (ord($A)-ord('A'))*20 - 180 + (ord($C)-ord('0'))*2 + ((ord($E)//0)-ord('A'))/12 + 1/24;
  my $lat = (ord($B)-ord('A'))*10 - 90 + (ord($D)-ord('0'))*1 + ((ord($F)//0)-ord('A'))/24 + 0.5/24;
  return ($lat, $lon);
}

get '/new' => sub {
  my $c = shift;
  my $now = strftime("%Y-%m-%d", localtime);
  my $time = strftime("%H:%M", localtime);
  $c->stash(now_date => $now, now_time => $time);
  $c->render(template => 'new');
};

post '/new' => sub {
  my $c = shift;
  my $p = $c->req->body_params;

  my $call = uc($p->param('call') // '');
  $call =~ s/^\s+|\s+$//g;

  $c->db->do("INSERT INTO log (call, date, time, frequency, mode, rst_sent, rst_recv, grid, qsl_sent, qsl_recv, notes)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    undef,
    $call, $p->param('date'), $p->param('time'), $p->param('frequency'), $p->param('mode'),
    $p->param('rst_sent'), $p->param('rst_recv'), $p->param('grid'),
    $p->param('qsl_sent'), $p->param('qsl_recv'), $p->param('notes')
  );
  $c->redirect_to('/');
};

# ... rest of the routes remain unchanged ...

app->start;
