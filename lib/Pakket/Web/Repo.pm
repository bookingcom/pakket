package Pakket::Web::Repo;
# ABSTRACT: A web repository app

use Dancer2 'appname' => 'Pakket::Web';
use Dancer2::Plugin::Pakket::ParamTypes;

use Carp qw< croak >;
use Log::Any qw< $log >;
use Pakket::Repository::Spec;
use Pakket::Repository::Parcel;
use Pakket::Repository::Source;

## no critic qw(Modules::RequireExplicitInclusion)

my %repo_types = (
    'spec'   => sub { return Pakket::Repository::Spec->new(@_);   },
    'source' => sub { return Pakket::Repository::Source->new(@_); },
    'parcel' => sub { return Pakket::Repository::Parcel->new(@_); },
);

sub create {
    my ( $class, $args ) = @_;

    my $repo_type    = $args->{'type'}    or croak(q{Missing 'type'});
    my $repo_path    = $args->{'path'}    or croak(q{Missing 'path'});
    my $repo_backend = $args->{'backend'} or croak(q{Missing 'backend'});

    my $repo = $repo_types{$repo_type}->( 'backend' => $repo_backend );

    prefix $repo_path => sub {
        get '/info' => sub {
            return encode_json({
                'version' => $Pakket::Web::Repo::VERSION,
                'objects' => scalar @{$repo->all_object_ids},
            });
        };

        get '/has_object' => with_types [
            [ 'query', 'id', 'Str', 'MissingID' ],
        ] => sub {
            my $id = query_parameters->get('id');

            return encode_json({
                'has_object' => $repo->has_object($id),
            });
        };

        get '/all_object_ids' => sub {
            return encode_json({
                'object_ids' => $repo->all_object_ids,
            });
        };

        get '/all_object_ids_by_name' => with_types [
            [ 'query', 'name',     'Str', 'MissingName' ],
            [ 'query', 'category', 'Str', 'MissingCategory' ],
        ] => sub {
            my $name     = query_parameters->get('name');
            my $category = query_parameters->get('category');
            return encode_json({
                'object_ids' => $repo->all_object_ids_by_name($name, $category),
            });
        };

        prefix '/retrieve' => sub {
            get '/content' => with_types [
                [ 'query', 'id', 'Str', 'MissingID' ],
            ] => sub {
                my $id = query_parameters->get('id');

                return encode_json( {
                    'id'      => $id,
                    'content' => $repo->retrieve_content($id),
                } );
            };

            get '/location' => with_types [
                [ 'query', 'id', 'Str', 'MissingID' ],
            ] => sub {
                my $id   = query_parameters->get('id');
                my $file = $repo->retrieve_location($id);

                # This is already anchored to the repo
                # (And no user input can change the path it will reach)
                send_file( $file, 'system_path' => 1 );
            };
        };

        if (!$args->{'read_only'}) {
            prefix '/store' => sub {
                # There is no body to check, because the body is JSON content
                # So we manually decode and check
                post '/content' => sub {
                    my $data    = decode_json( request->body );
                    my $id      = $data->{'id'};
                    my $content = $data->{'content'};

                    defined && length
                        or send_error( 'Bad input', 400 )
                        for $id, $content;

                    $repo->store_content( $id, $content );
                    return encode_json( { 'success' => 1 } );
                };

                post '/location' => with_types [
                    [ 'query', 'id', 'Str',  'MissingID' ],
                ] => sub {
                    my $id   = query_parameters->get('id');
                    my $file = Path::Tiny->tempfile;
                    $file->spew_raw( request->body );
                    $repo->store_location( $id, $file );
                    return encode_json( { 'success' => 1 } );
                };
            };

            prefix '/remove' => sub {
                get '/location' => with_types [
                    [ 'query', 'id', 'Str',  'MissingID' ],
                ] => sub {
                    my $id = query_parameters->get('id');
                    $repo->remove_location( $id );
                    return encode_json( { 'success' => 1 } );
                };

                get '/content' => with_types [
                    [ 'query', 'id', 'Str',  'MissingID' ],
                ] => sub {
                    my $id = query_parameters->get('id');
                    $repo->remove_content( $id );
                    return encode_json( { 'success' => 1 } );
                };
            };
        }
    };
}

1;
