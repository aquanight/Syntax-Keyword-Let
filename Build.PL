use Module::Build;

use XS::Parse::Keyword::Builder;
 
my %module_build_args = (
  module_name => 'Syntax::Keyword::Let',
##{ $plugin->get_prereqs(1) ##}
##{ $plugin->get_default('share_dir') ##}
);
 
unless ( eval { Module::Build->VERSION(0.4004) } ) {
  my $tr = delete $module_build_args{test_requires};
  my $br = $module_build_args{build_requires};
  for my $mod ( keys %$tr ) {
    if ( exists $br->{$mod} ) {
      $br->{$mod} = $tr->{$mod} if $tr->{$mod} > $br->{$mod};
    }
    else {
      $br->{$mod} = $tr->{$mod};
    }
  }
} # end unless Module::Build is 0.4004 or newer
 
my $builder = Module::Build->new(%module_build_args);

XS::Parse::Keyword::Builder->extend_module_build( $builder );

$builder->create_build_script;
