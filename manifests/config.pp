/*

== Definition: mysql::config

Set mysql configuration parameters

Parameters:
- *value*: the value to be set, defaults to the empty string;
- *ensure*: defaults to present.

Example usage:
  mysql::config {'mysqld/pid-file':
    ensure  => present,
    value   => '/var/run/mysqld/mysqld.pid',
  }

If the section (e.g. 'mysqld/') is ommitted in the resource name,
it defaults to 'mysqld/'.

*/
define mysql::config (
  $ensure='present',
  $value=''
) {

  $key = inline_template("<%= name.split('/')[-1] %>")
  $section = inline_template("<%= if name.split('/')[-2]
      name.split('/')[-2]
    else
      'mysqld'
    end %>")

  case $ensure {
    present: {
      $changes = "set ${key} ${value}"
    }

    absent: {
      $changes = "rm ${key}"
    }

    default: { err ( "unknown ensure value ${ensure}" ) }
  }

  augeas { "my.cnf/${section}/${key}":
    context   => "${mysql::params::mycnfctx}/target[.='${section}']",
    changes   => [
      "set ${mysql::params::mycnfctx}/target[.='${section}'] ${section}",
      $changes,
      ],
    require   => [ File["${mysql::params::mycnf}"],
                   File["${mysql::params::data_dir}"] ],
    notify    => Service["mysql"],
  }
}
