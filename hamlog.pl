#!/usr/bin/env morbo

use Mojolicious::Lite;
use DBI;
use POSIX 'strftime';
use Digest::SHA qw(sha256_hex);
use Ham::Locator;
use Text::CSV;
use Mojo::JSON;
use PDF::API2;

# Enable sessions
app->secrets(['Password123']);	# change to a strong secret in production

# DB setup
my $dbfile = 'hamlog.db';
my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", '', '', { RaiseError => 1, AutoCommit => 1 });

# Create tables if they don't exist
$dbh->do(<<'SQL');
CREATE TABLE IF NOT EXISTS users (
	id INTEGER PRIMARY KEY,
	username TEXT UNIQUE NOT NULL,
	password TEXT NOT NULL
)
SQL

# If the log table doesn't have user_id column, create table from scratch
my $log_columns = $dbh->selectall_arrayref('PRAGMA table_info(log)');
my $has_user_id = 0;
for my $col (@$log_columns) {
	$has_user_id = 1 if $col->[1] eq 'user_id';
}
unless ($has_user_id) {
  $dbh->do("DROP TABLE IF EXISTS log");
  $dbh->do(<<'SQL');
CREATE TABLE log (
  id         INTEGER PRIMARY KEY,
  call       TEXT,
  date       TEXT,
  time       TEXT,
  frequency  TEXT,
  mode       TEXT,
  power	TEXT,
  rst_sent   TEXT,
  rst_recv   TEXT,
  grid       TEXT,
  qsl_sent   TEXT,
  qsl_recv   TEXT,
  dxcc		TEXT,
  notes      TEXT,
  user_id    INTEGER,
  FOREIGN KEY(user_id) REFERENCES users(id)
)
SQL
}

$dbh->do(<<'SQL');
CREATE TABLE IF NOT EXISTS deleted_log (
  id         INTEGER,
  call       TEXT,
  date       TEXT,
  time       TEXT,
  frequency  TEXT,
  mode       TEXT,
  power	TEXT,
  rst_sent   TEXT,
  rst_recv   TEXT,
  grid       TEXT,
  qsl_sent   TEXT,
  qsl_recv   TEXT,
  notes      TEXT,
  deleted_at TEXT
)
SQL

helper db => sub { $dbh };

# JSON helper for templates
helper json => sub {
  my ($c, $data) = @_;
  return Mojo::JSON::to_json($data);
};

# Password hashing
sub hash_password {
  my ($password) = @_;
  return sha256_hex($password);
}

# Before dispatch hook to require login for certain routes
under sub {
  my $c = shift;
  # Allow public access to register and login
  return 1 if $c->req->url->path->to_string =~ m{^/(login|register)$};
  # Check if user is logged in
  return $c->redirect_to('/login') unless $c->session('user_id');
  return 1;
};

# Registration routes
get '/register' => sub {
  my $c = shift;
  $c->render(template => 'register');
};

post '/register' => sub {
  my $c = shift;
  my $username = $c->param('username') || '';
  my $password = $c->param('password') || '';

  $username =~ s/^\s+|\s+$//g;
  return $c->render(text => 'Username and password required', status => 400)
    unless length $username && length $password;

  my $hashed = hash_password($password);

  eval {
    $c->db->do("INSERT INTO users (username, password) VALUES (?, ?)", undef, $username, $hashed);
  };
  if ($@) {
    return $c->render(text => 'Username already exists', status => 400);
  }

  $c->redirect_to('/login');
};

# Login routes
get '/login' => sub {
  my $c = shift;
  $c->render(template => 'login');
};

post '/login' => sub {
  my $c = shift;
  my $username = $c->param('username') || '';
  my $password = $c->param('password') || '';

  return $c->render(text => 'Missing username or password', status => 400)
    unless length $username && length $password;

  my $user = $c->db->selectrow_hashref("SELECT * FROM users WHERE username = ?", undef, $username);
  return $c->render(text => 'Invalid username or password', status => 401)
    unless $user && $user->{password} eq hash_password($password);

  $c->session(user_id => $user->{id});
  $c->session(user_name => $user->{username});
  $c->redirect_to('/');
};

# Logout route
get '/logout' => sub {
  my $c = shift;
  $c->session(expires => 1);  # expire session
  $c->redirect_to('/login');
};

# Main log listing, filtered by logged-in user
get '/' => sub {
  my $c = shift;
  my $user_id = $c->session('user_id');
  my $p = $c->req->query_params;

  my @where = ("user_id = ?");
  my @bind = ($user_id);

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

  my $sql = "SELECT * FROM log WHERE " . join(" AND ", @where) . " ORDER BY date DESC, time DESC";

  my $rows = $c->db->selectall_arrayref($sql, { Slice => {} }, @bind);
  $c->stash(log => $rows);
  $c->stash(
  log     => $rows,
  filters => {
    call      => $p->param('call'),
    mode      => $p->param('mode'),
    from_date => $p->param('from_date'),
    to_date   => $p->param('to_date'),
  }
);
  $c->render(template => 'index');
};

get '/export' => sub {
  my $c = shift;
  $c->render(template => 'export');
};

get '/export/csv' => sub {
  my $c = shift;
  my $rows = $c->db->selectall_arrayref("SELECT * FROM log ORDER BY date DESC, time DESC", { Slice => {} });

  my $csv = Text::CSV->new({ binary => 1 });
  my $output = '';
  open my $fh, '>', \$output;

  $csv->print($fh, [qw/date time call frequency mode power rst_sent rst_recv grid qsl_sent qsl_recv notes/]);
  print $fh "\n";

  for my $row (@$rows) {
    $csv->print($fh, [ @{$row}{qw/date time call frequency mode power rst_sent rst_recv grid qsl_sent qsl_recv notes/} ]);
    print $fh "\n";
  }
  close $fh;

  $c->res->headers->content_disposition('attachment; filename="hamlog.csv"');
  $c->render(data => $output, format => 'txt');
};

get '/export/adif' => sub {
	my $c = shift;
	my $rows = $c->db->selectall_arrayref("SELECT * FROM log ORDER BY date DESC, time DESC", { Slice => {} });
	my $output = '';

  $output .= "Generated by Ham Log App\n";
  $output .= "<EOH>\n";
	for my $row (@$rows) {
	  $output .= sprintf(
	    "<QSO_DATE:%d>%s"
	  . "<TIME_ON:%d>%s"
	  . "<CALL:%d>%s"
	  . "<FREQ:%d>%s"
	  . "<MODE:%d>%s"
	  . "<TX_PWR:%d>%s"
	  . "<RST_SENT:%d>%s"
	  . "<RST_RCVD:%d>%s"
	  . "<GRIDSQUARE:%d>%s"
	  . "<QSL_SENT:%d>%s"
	  . "<QSL_RCVD:%d>%s"
	  . "<COMMENT:%d>%s<EOR>\n",

	    length($row->{date}),        $row->{date},
	    length($row->{time}),        $row->{time},
	    length($row->{call}),        $row->{call},
	    length($row->{frequency}),   $row->{frequency},
	    length($row->{mode}),        $row->{mode},
	    length($row->{power} // ''), $row->{power} // '',
	    length($row->{rst_sent}),    $row->{rst_sent},
	    length($row->{rst_recv}),    $row->{rst_recv},
	    length($row->{grid} // ''),  $row->{grid} // '',
	    length($row->{qsl_sent} // ''), $row->{qsl_sent} // '',
	    length($row->{qsl_recv} // ''), $row->{qsl_recv} // '',
	    length($row->{notes} // ''),    $row->{notes} // '',
	  );
	}

	$c->res->headers->content_disposition('attachment; filename="hamlog.adi"');
	$c->render(data => $output, format => 'txt');
};

# Map route filtered by logged-in user
get '/map' => sub {
  my $c = shift;
  my $user_id = $c->session('user_id');
  my $rows = $c->db->selectall_arrayref("SELECT call, grid FROM log WHERE user_id = ? AND grid IS NOT NULL AND grid != ''", { Slice => {} }, $user_id);

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

# Stats route filtered by logged-in user
get '/stats' => sub {
  my $c = shift;
  my $user_id = $c->session('user_id');

  my $summary = $c->db->selectall_arrayref(
    "SELECT mode, COUNT(*) AS count FROM log WHERE user_id = ? GROUP BY mode ORDER BY count DESC",
    { Slice => {} },
    $user_id
  );

  my $bands = $c->db->selectall_arrayref(
    "SELECT frequency, COUNT(*) AS count FROM log WHERE user_id = ? GROUP BY frequency ORDER BY count DESC",
    { Slice => {} },
    $user_id
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

# GET new
get '/new' => sub {
  my $c = shift;
  my $now = strftime("%Y-%m-%d", localtime);
  my $time = strftime("%H:%M", localtime);
  $c->stash(now_date => $now, now_time => $time, is_edit => 0, entry => {});
  $c->render(template => 'new');
};

# POST new
post '/new' => sub {
  my $c = shift;
  my $p = $c->req->params;
  my $user_id = $c->session('user_id');

  $c->db->do("INSERT INTO log (call, date, time, frequency, mode, power, rst_sent, rst_recv, grid, qsl_sent, qsl_recv, notes, user_id)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    undef,
    $p->param('call'), $p->param('date'), $p->param('time'), $p->param('frequency'), $p->param('mode'),
    $p->param('power') // '', $p->param('rst_sent'), $p->param('rst_recv'), $p->param('grid'),
    $p->param('qsl_sent'), $p->param('qsl_recv'), $p->param('notes'), $user_id
  );

  $c->redirect_to('/');
};

# GET edit
get '/edit/:id' => sub {
  my $c  = shift;
  my $id = $c->param('id');
  my $user_id = $c->session('user_id');

  my $entry = $c->db->selectrow_hashref(
    'SELECT * FROM log WHERE id = ? AND user_id = ?',
    undef,
    $id, $user_id
  ) or return $c->reply->not_found;

  $c->stash(entry => $entry, is_edit => 1);
  $c->render(template => 'new');
};

# POST edit
post '/edit/:id' => sub {
  my $c  = shift;
  my $id = $c->param('id');
  my $p  = $c->req->params;
  my $user_id = $c->session('user_id');

  $c->db->do(
    q{
      UPDATE log SET
        call = ?, date = ?, time = ?, frequency = ?, mode = ?, power = ?,
        rst_sent = ?, rst_recv = ?, grid = ?, qsl_sent = ?, qsl_recv = ?, notes = ?
      WHERE id = ? AND user_id = ?
    },
    undef,
    $p->param('call'), $p->param('date'), $p->param('time'), $p->param('frequency'), $p->param('mode'),
    $p->param('power') // '', $p->param('rst_sent'), $p->param('rst_recv'), $p->param('grid'),
    $p->param('qsl_sent'), $p->param('qsl_recv'), $p->param('notes'),
    $id, $user_id
  );

  $c->flash(message => 'QSO updated');
  $c->redirect_to('/');
};

post '/delete/:id' => sub {
  my $c = shift;
  my $id = $c->stash('id');

  my $entry = $c->db->selectrow_hashref("SELECT * FROM log WHERE id = ?", undef, $id);
  if ($entry) {
    $c->db->do("INSERT INTO deleted_log (id, call, date, time, frequency, mode, power, rst_sent, rst_recv, grid, qsl_sent, qsl_recv, notes, deleted_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
      undef, @$entry{qw/id call date time frequency mode power rst_sent rst_recv grid qsl_sent qsl_recv notes/}, strftime('%Y-%m-%d %H:%M:%S', localtime));
    $c->db->do("DELETE FROM log WHERE id = ?", undef, $id);
  }
  $c->redirect_to('/');
};

get '/undo/:id' => sub {
  my $c = shift;
  my $id = $c->stash('id');

  my $entry = $c->db->selectrow_hashref("SELECT * FROM deleted_log WHERE id = ? ORDER BY deleted_at DESC LIMIT 1", undef, $id);
  if ($entry) {
    $c->db->do("INSERT INTO log (id, call, date, time, frequency, mode, power, rst_sent, rst_recv, grid, qsl_sent, qsl_recv, notes)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
      undef, @$entry{qw/id call date time frequency mode power rst_sent rst_recv grid qsl_sent qsl_recv notes/});
    $c->db->do("DELETE FROM deleted_log WHERE id = ? AND deleted_at = ?", undef, $id, $entry->{deleted_at});
  }
  $c->redirect_to('/');
};


get '/import' => sub {
  my $c = shift;
  $c->render(template => 'import');
};

post '/import/csv' => sub {
  my $c = shift;
  my $upload = $c->req->upload('file');
  return $c->render(text => 'No file uploaded') unless $upload;

  my $csv = Text::CSV->new({ binary => 1, auto_diag => 1 });
  open my $fh, '<', $upload->asset->path or return $c->render(text => "Failed to read file");

  my $header = $csv->getline($fh);
  while (my $row = $csv->getline($fh)) {
    my %data;
    @data{@$header} = @$row;

    $c->db->do("INSERT INTO log (date, time, call, frequency, mode, power, rst_sent, rst_recv, grid, qsl_sent, qsl_recv, notes) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
      undef,
      @data{qw/date time call frequency mode power rst_sent rst_recv grid qsl_sent qsl_recv notes/}
    );
  }
  close $fh;
  $c->redirect_to('/');
};

post '/import/adif' => sub {
  my $c = shift;
  my $upload = $c->req->upload('file');
  return $c->render(text => 'No file uploaded') unless $upload;

  open my $fh, '<', $upload->asset->path or return $c->render(text => "Failed to read file");
  local $/ = "<EOR>";

  while (my $record = <$fh>) {
    my %qso;
    while ($record =~ /<(\w+):\d+>([^<]*)/g) {
      $qso{uc $1} = $2;
    }
    $c->db->do("INSERT INTO log (date, time, call, frequency, mode, power, rst_sent, rst_recv, grid, qsl_sent, qsl_recv, notes) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
      undef,
      $qso{QSO_DATE}, $qso{TIME_ON}, $qso{CALL}, $qso{FREQ}, $qso{MODE}, $qso{RST_SENT}, $qso{RST_RCVD}, $qso{GRIDSQUARE}, $qso{QSL_SENT}, $qso{QSL_RCVD}, $qso{COMMENT}
    );
  }
  close $fh;
  $c->redirect_to('/');
};

get '/qsl_cards' => sub {
  my $c = shift;

  my $log = $c->db->selectall_arrayref('SELECT * FROM log ORDER BY date DESC', { Slice => {} });

  $c->stash(log => $log);
  $c->render(template => 'qsl_cards');
};

post '/generate_qsl_pdf' => sub {
  my $c = shift;
  my $ids = $c->every_param('ids');

  return $c->render(text => 'No QSO IDs provided', status => 400) unless @$ids;

  my $placeholders = join(",", ("?") x @$ids);
  my $qsos = $c->db->selectall_arrayref(
    "SELECT * FROM log WHERE id IN ($placeholders)", { Slice => {} }, @$ids
  );

  my $pdf  = PDF::API2->new();
  my $font = $pdf->corefont('Helvetica-Bold');

  foreach my $qso (@$qsos) {
    my $page = $pdf->page;
    $page->mediabox(252, 180); # 3.5x5 inches approx (in points)

    my $text = $page->text;
    $text->font($font, 10);

    my $y = 160;

    $text->translate(20, $y); $text->text("QSL Card for $qso->{call}");
    $text->translate(20, $y -= 15); $text->text("Date: $qso->{date}  Time: $qso->{time}");
    $text->translate(20, $y -= 15); $text->text("Freq: $qso->{frequency}  Power: $qso->{power} Mode: $qso->{mode}");
    $text->translate(20, $y -= 15); $text->text("RST Sent: $qso->{rst_sent}  Rcvd: $qso->{rst_recv}");
    $text->translate(20, $y -= 15); $text->text("Grid: $qso->{grid}  DXCC: $qso->{dxcc}");
    $text->translate(20, $y -= 15); $text->text("Notes: $qso->{notes}");
  }

  # Add logo to each page if available
  my $logo_path = 'public/uploads/logo.jpg';
  if (-r $logo_path) {
    my $img = eval { $pdf->image_jpeg($logo_path) };
    if ($img) {
      foreach my $page ($pdf->pages) {
        my $gfx = $page->gfx;
        $gfx->image($img, 180, 110, 60, 60);  # bottom right corner
      }
    }
  }

  $c->res->headers->content_type('application/pdf');
  $c->res->headers->content_disposition('inline; filename="qsl_cards.pdf"');
  $c->res->body($pdf->stringify);
};


get '/qso_map' => sub {
  my $c = shift;

  # Optional filtering parameters from query string
  my $band = $c->param('band');
  my $mode = $c->param('mode');
  my $from = $c->param('from');
  my $to   = $c->param('to');

  # Build SQL query with optional filters
  my @conditions;
  my @params;

  push @conditions, 'band = ?'   if $band;
  push @params,     $band        if $band;

  push @conditions, 'mode = ?'   if $mode;
  push @params,     $mode        if $mode;

  push @conditions, 'date >= ?'  if $from;
  push @params,     $from        if $from;

  push @conditions, 'date <= ?'  if $to;
  push @params,     $to          if $to;

  my $where = @conditions ? 'WHERE ' . join(' AND ', @conditions) : '';

  my $log = $c->db->selectall_arrayref(
    "SELECT call, grid, dxcc, date FROM log $where",
    { Slice => {} },
    @params
  );

  # Build grid data (dummy location generation for example)
  my %grids;
  for my $entry (@$log) {
    next unless $entry->{grid};
    my ($lat, $lon) = _maidenhead_to_latlon($entry->{grid});
    $grids{"$lat,$lon"} = { lat => $lat, lon => $lon, worked => 1 };
  }

  my @grid_data = values %grids;

  # Build DXCC data (dummy confirmed status logic)
  my %dxcc;
  for my $entry (@$log) {
    next unless $entry->{dxcc};
    my $name = $entry->{dxcc};
    $dxcc{$name} ||= {
      name => $name,
      lat  => 0 + int(rand(140)) - 70,
      lon  => 0 + int(rand(360)) - 180,
      confirmed => int(rand(2)),
    };
  }

  my @dxcc_data = values %dxcc;

  $c->stash(grid_data => \@grid_data, dxcc_data => \@dxcc_data);
  $c->render(template => 'qso_map');
};

# Convert Maidenhead grid square to approximate lat/lon
sub _maidenhead_to_latlon {
  my $grid = shift;
  return (0, 0) unless $grid =~ /^[A-R]{2}\d{2}/i;

  my $A = ord('A');
  my $a = ord('a');

  my $lon = (ord(uc(substr($grid, 0, 1))) - $A) * 20 - 180;
  my $lat = (ord(uc(substr($grid, 1, 1))) - $A) * 10 - 90;
  $lon += substr($grid, 2, 1) * 2;
  $lat += substr($grid, 3, 1) * 1;
  return ($lat, $lon);
};

get '/calendar' => sub {
  my $c = shift;

  my $log_entries = $c->db->selectall_arrayref(
    'SELECT date, COUNT(*) as count FROM log GROUP BY date ORDER BY date',
    { Slice => {} }
  );

  my @events = map {
    {
      title => "$_->{count} QSOs",
      start => $_->{date}
    }
  } @$log_entries;

$c->stash(include_fullcalendar => 1);
  $c->stash(events => \@events);
  $c->render(template => 'calendar');
};

# Route to render the logo upload form
get '/upload_logo' => sub {
  my $c = shift;
  $c->render(template => 'upload_logo');
};

# Route to handle the logo upload POST
post '/upload_logo' => sub {
  my $c = shift;
  my $upload = $c->param('logo');

  if ($upload && $upload->filename =~ /\.(png|jpe?g|gif)$/i) {
    my $path = $c->app->home->rel_file("public/uploads/logo.png");
    $upload->move_to($path);
    $c->flash(message => 'Logo uploaded successfully.');
  } else {
    $c->flash(message => 'Please upload a valid image.');
  }

	$c->redirect_to('/upload_logo');
};

app->start();
