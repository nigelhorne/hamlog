requires 'Mojolicious', '9.0';             # Mojolicious web framework
requires 'DBD::SQLite';                    # SQLite database backend
requires 'DBI';                            # Database interface
requires 'PDF::API2';                      # For generating QSL PDF cards
requires 'File::Basename';                # To extract filename parts (used in uploads)
requires 'File::Path';                    # Directory creation
requires 'File::Spec';                    # Platform-agnostic file paths
requires 'JSON::MaybeXS';                 # JSON encoding for stash -> json
requires 'DateTime';                      # For date parsing and formatting
requires 'Text::CSV';                     # CSV import/export if needed
requires 'Geo::Coordinates::UTM';         # For potential Maidenhead/grid calc
requires 'Geo::Calc';                     # Optional: DXCC location math

on 'test' => sub {
  requires 'Test::More';
  requires 'Test::Mojo';                  # Mojolicious-specific testing
};
