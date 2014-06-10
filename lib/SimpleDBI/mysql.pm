#ABSTRACT: some function on mysql, base DBI
package SimpleDBI::mysql;
use base qw/SimpleDBI/;
use DBD::mysql;
use DBI;
use File::Temp qw/tempfile/;
use SimpleR::Reshape;

our $DEFAULT_SEP = ',';
sub new {
    my ($self, %opt) = @_;

    my $dbh = connect_db(%opt);

    bless { %opt, dbh => $dbh }, __PACKAGE__;
}

sub connect_db {
    my (%opt) = @_;

    my %default_opt = (
        mysql_local_infile    => 1,
        mysql_connect_timeout => 14400,
        port                  => $opt{port} || 3306,
        host                  => $opt{host} || 'localhost',
        database              => $opt{db},
    );
    my $conn_str =
      join( ";", map { "$_=$default_opt{$_}" } keys(%default_opt) );

    my $dbh = DBI->connect( "DBI:mysql:$conn_str", $opt{usr}, $opt{passwd},
        { 'RaiseError' => 0, PrintError => 1, mysql_enable_utf8=> $opt{enable_utf8} // 1,  } ), 
          or die $DBI::errstr;


    return $dbh;
}

sub query_db {
    my ( $self, $sql, %opt ) = @_;
    $opt{sep} ||= $DEFAULT_SEP;
    $opt{attr} ||= undef, 
    $opt{bind_values} ||= [];
    $opt{result_type} ||=
        $opt{hash_key} ? 'hashref'
      : $opt{file}     ? 'file'
      :                  'arrayref';

    my $sth = $self->{dbh}->prepare( $sql, $opt{attr} );
    $sth->execute( @{ $opt{bind_values} } );

    return $sth->fetchall_arrayref if ( $opt{result_type} eq 'arrayref' );

    if ( $opt{result_type} eq 'hashref' ) {
        $opt{hash_key} ||= [];
        return $sth->fetchall_hashref( @{ $opt{hash_key} } );
    }

    if ( $opt{result_type} eq 'file' ) {
        open my $fh, ">:utf8", $opt{file};
        while ( my @row = $sth->fetchrow_array ) {
            print $fh join( $opt{sep}, @row ), "\n";
        }
        close $fh;
        return $opt{file};
    }

    return;
}

sub load_table {
    my ( $self, $data, %opt ) = @_;
    $opt{sep} ||= $DEFAULT_SEP;
    $opt{db} ||= $self->{db};
    $opt{charset} ||= $self->{charset};

    my ( $file, $temp_fh ) = ( $data, undef );
    if ( !-f $data ) {
        ( $temp_fh, $file ) = tempfile( 'tmpXXXXXXXXXXXXX', TMPDIR => 1 );
        write_table(
            $data,
            sep     => $opt{sep},
            file    => $file,
            charset => $opt{charset},
        );
    }
    $file = quotemeta($file);

    my $replace_flag = $opt{replace} ? 'REPLACE' : '';
    my $set_charset =
      ( $opt{charset} eq 'utf8' ) ? 'character set UTF8' : '';
    my $field_str = join( ", ", @{ $opt{field} } );

    my $load_sql = qq[load data local infile '$file' 
    $replace_flag into table $opt{db}.$opt{table}
    $set_charset
    fields terminated by '$opt{sep}'
    lines terminated by '\\n'
    ($field_str);];

    $self->{dbh}->do($load_sql);
}

1;
