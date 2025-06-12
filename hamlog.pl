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

get '/edit/:id' => sub {
  my $c = shift;
  my $row = $c->db->selectrow_hashref("SELECT * FROM log WHERE id = ?", undef, $c->param('id'))
    or return $c->reply->not_found;
  $c->stash(entry => $row);
  $c->render(template => 'edit');
};

post '/edit/:id' => sub {
  my $c = shift;
  my $p = $c->req->body_params;

  my $call = uc($p->param('call') // '');
  $call =~ s/^\s+|\s+$//g;

  $c->db->do("UPDATE log SET call=?, date=?, time=?, frequency=?, mode=?, rst_sent=?, rst_recv=?, grid=?, qsl_sent=?, qsl_recv=?, notes=? WHERE id=?",
    undef,
    $call, $p->param('date'), $p->param('time'), $p->param('frequency'), $p->param('mode'),
    $p->param('rst_sent'), $p->param('rst_recv'), $p->param('grid'),
    $p->param('qsl_sent'), $p->param('qsl_recv'), $p->param('notes'), $c->param('id')
  );
  $c->redirect_to('/');
};

post '/delete/:id' => sub {
  my $c = shift;
  $c->db->do("DELETE FROM log WHERE id = ?", undef, $c->param('id'));
  $c->redirect_to('/');
};

get '/export.csv' => sub {
  my $c = shift;
  my $rows = $c->db->selectall_arrayref("SELECT * FROM log ORDER BY date DESC, time DESC", { Slice => {} });
  my $csv = "id,call,date,time,frequency,mode,rst_sent,rst_recv,grid,qsl_sent,qsl_recv,notes\n";
  for my $r (@$rows) {
    $csv .= join(",", map { my $v = $_ // ''; $v =~ s/"/""/g; $v =~ s/\R/ /g; '"' . $v . '"' } @$r{qw(id call date time frequency mode rst_sent rst_recv grid qsl_sent qsl_recv notes)}) . "\n";
  }
  $c->res->headers->content_type('text/csv');
  $c->render(data => $csv);
};

get '/export.adif' => sub {
  my $c = shift;
  my $rows = $c->db->selectall_arrayref("SELECT * FROM log ORDER BY date DESC, time DESC", { Slice => {} });
  my $adif = "<ADIF_VER:5>3.1.0\n<EOR>\n";
  for my $r (@$rows) {
    $adif .= sprintf("<CALL:%d>%s<DATE:%d>%s<TIME:%d>%s<FREQ:%d>%s<MODE:%d>%s<RSTS:%d>%s<RSTR:%d>%s<GRIDSQUARE:%d>%s<QSL_SENT:%d>%s<QSL_RCVD:%d>%s<COMMENT:%d>%s<EOR>\n",
      length($r->{call} // ''), $r->{call} // '',
      length($r->{date} // ''), $r->{date} // '',
      length($r->{time} // ''), $r->{time} // '',
      length($r->{frequency} // ''), $r->{frequency} // '',
      length($r->{mode} // ''), $r->{mode} // '',
      length($r->{rst_sent} // ''), $r->{rst_sent} // '',
      length($r->{rst_recv} // ''), $r->{rst_recv} // '',
      length($r->{grid} // ''), $r->{grid} // '',
      length($r->{qsl_sent} // ''), $r->{qsl_sent} // '',
      length($r->{qsl_recv} // ''), $r->{qsl_recv} // '',
      length($r->{notes} // ''), $r->{notes} // '');
  }
  $c->res->headers->content_type('application/text');
  $c->res->headers->content_disposition('attachment; filename=logbook.adi');
  $c->render(data => $adif);
};

post '/import.csv' => sub {
  my $c = shift;
  my $upload = $c->req->upload('csv_file');
  return $c->render(text => 'No file uploaded') unless $upload;

  my $csv = Text::CSV->new({ binary => 1 }) or die "Cannot use CSV: " . Text::CSV->error_diag();
  my $fh = $upload->asset->handle;

  # Skip header
  <$fh>;

  while (my $row = $csv->getline($fh)) {
    my ($id, $call, $date, $time, $frequency, $mode, $rst_sent, $rst_recv, $grid, $qsl_sent, $qsl_recv, $notes) = @$row;
    $call = uc($call // '');
    $call =~ s/^\s+|\s+$//g;
    $c->db->do("INSERT INTO log (call, date, time, frequency, mode, rst_sent, rst_recv, grid, qsl_sent, qsl_recv, notes)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
      undef,
      $call, $date, $time, $frequency, $mode, $rst_sent, $rst_recv, $grid, $qsl_sent, $qsl_recv, $notes);
  }
  $c->redirect_to('/');
};

app->start;