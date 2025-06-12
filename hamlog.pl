#!/usr/bin/env perl

use Mojolicious::Lite;
use DBI;

# DB setup
my $dbfile = 'hamlog.db';
my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", '', '', { RaiseError => 1, AutoCommit => 1 });

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
  my $rows = $c->db->selectall_arrayref("SELECT * FROM log ORDER BY date DESC, time DESC", { Slice => {} });
  $c->stash(log => $rows);
  $c->render(template => 'index');
};

get '/new' => sub {
  shift->render(template => 'new');
};

post '/new' => sub {
  my $c = shift;
  my $p = $c->req->body_params;
  $c->db->do("INSERT INTO log (call, date, time, frequency, mode, rst_sent, rst_recv, grid, qsl_sent, qsl_recv, notes)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    undef,
    $p->param('call'), $p->param('date'), $p->param('time'), $p->param('frequency'), $p->param('mode'),
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
  $c->db->do("UPDATE log SET call=?, date=?, time=?, frequency=?, mode=?, rst_sent=?, rst_recv=?, grid=?, qsl_sent=?, qsl_recv=?, notes=? WHERE id=?",
    undef,
    $p->param('call'), $p->param('date'), $p->param('time'), $p->param('frequency'), $p->param('mode'),
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
    $csv .= join(",", map { my $v = $_ // ''; $v =~ s/"/''/g; $v =~ s/\R/ /g; '"' . $v . '"' } @$r{qw(id call date time frequency mode rst_sent rst_recv grid qsl_sent qsl_recv notes)}) . "\n";
  }
  $c->res->headers->content_type('text/csv');
  $c->render(data => $csv);
};

app->start;
