/*

==Class: mysql::server

Parameters:
 $mysql_data_dir:
   set the data directory path, which is used to store all the databases

   If set, copies the content of the default mysql data location. This is
   necessary on Debian systems because the package installation script
   creates a special user used by the init scripts.

*/
class mysql::server {

  include mysql::params

  user { "mysql":
    ensure => present,
    require => Package["mysql-server"],
  }

  package { "mysql-server":
    ensure => installed,
  }

  file { "${mysql::params::data_dir}":
    ensure  => directory,
    owner   => "mysql",
    group   => "mysql",
    seltype => "mysqld_db_t",
    require => Package["mysql-server"],
  }

  if( "${mysql::params::data_dir}" != "/var/lib/mysql" ) {
    File["${mysql::params::data_dir}"]{
      source  => "/var/lib/mysql",
      recurse => true,
      replace => false,
    }
  }

  file { "/etc/mysql/my.cnf":
    ensure => present,
    path => $mysql::params::mycnf,
    owner => root,
    group => root,
    mode => 644,
    seltype => "mysqld_etc_t",
    require => Package["mysql-server"],
  }

  file { "/usr/share/augeas/lenses/contrib/mysql.aug":
    ensure => present,
    source => "puppet:///modules/mysql/mysql.aug",
  }

  mysql::config {
    'pid-file':             value => '/var/run/mysqld/mysqld.pid';
    'old_passwords':        value => '0';
    'character-set-server': value => 'utf8';
    'log-warnings':         value => '1';
    'datadir':              value => "${mysql::params::data_dir}";
    'log-error':            value => $::operatingsystem ? {
      /RedHat|Fedora|CentOS/ => '/var/log/mysql-slow-queries.log',
      default                => '/var/log/mysql/mysql-slow.log',
      };
    # "ins log-slow-admin-statements after log-slow-queries", # BUG: not implemented in puppet yet
    'socket':                value => $::operatingsystem ? {
      /RedHat|Fedora|CentOS/ => '/var/lib/mysql/mysql.sock',
      default                => '/var/run/mysqld/mysqld.sock',
      };
  }

  # Replication
  # by default, replication is disabled
  mysql::config {
    'log-bin':         ensure => absent;
    'server-id':       ensure => absent;
    'master-host':     ensure => absent;
    'master-user':     ensure => absent;
    'master-password': ensure => absent;
    'report-host':     ensure => absent;
  }

  # mysqld_safe
  mysql::config {
    'mysqld_safe/pid-file':
      value   => '/var/run/mysqld/mysqld.pid';
    'mysqld_safe/socket':
      value   => $::operatingsystem ? {
        /RedHat|Fedora|CentOS/ => '/var/lib/mysql/mysql.sock',
        default                => '/var/run/mysqld/mysqld.sock', 
      };
  }

  # force use of system defaults
  mysql::config {
    'key_buffer':                      ensure => absent;
    'max_allowed_packet':              ensure => absent;
    'table_cache':                     ensure => absent;
    'sort_buffer_size':                ensure => absent;
    'read_buffer_size':                ensure => absent;
    'read_rnd_buffer_size':            ensure => absent;
    'net_buffer_length':               ensure => absent;
    'myisam_sort_buffer_size':         ensure => absent;
    'thread_cache_size':               ensure => absent;
    'query_cache_size':                ensure => absent;
    'thread_concurrency':              ensure => absent;
    'thread_stack':                    ensure => absent;
    'mysqld_dump/max_allowed_packet':  ensure => absent;
    'isamchk/key_buffer':              ensure => absent;
    'isamchk/sort_buffer_size':        ensure => absent;
    'isamchk/read_buffer':             ensure => absent;
    'isamchk/write_buffer':            ensure => absent;
    'myisamchk/key_buffer':            ensure => absent;
    'myisamchk/sort_buffer_size':      ensure => absent;
    'myisamchk/read_buffer':           ensure => absent;
    'myisamchk/write_buffer':          ensure => absent;
  }

  augeas { "my.cnf/performance":
    context => "${mysql::params::mycnfctx}/",
    load_path => "/usr/share/augeas/lenses/contrib/",
    changes => [
    ],
    require => File["/etc/mysql/my.cnf"],
    notify => Service["mysql"],
  }

  mysql::config {
    'client/socket':
      value => $::operatingsystem ? {
        /RedHat|Fedora|CentOS/ => '/var/lib/mysql/mysql.sock',
        default                => '/var/run/mysqld/mysqld.sock',
      }
  }

  service { "mysql":
    ensure      => running,
    enable      => true,
    name        => $operatingsystem ? {
      /RedHat|Fedora|CentOS/ => "mysqld",
      default => "mysql",
    },
    require   => Package["mysql-server"],
  }


  if $mysql_user {} else { $mysql_user = "root" }

  if $mysql_password {

    if $mysql_exists == "true" {
      mysql_user { "${mysql_user}@localhost":
        ensure => present,
        password_hash => mysql_password($mysql_password),
        require => Exec["Generate my.cnf"],
      }
    }

    file { "/root/.my.cnf":
      ensure => present,
      owner => root,
      group => root,
      mode  => 600,
      content => template("mysql/my.cnf.erb"),
      require => Exec["Initialize MySQL server root password"],
    }

  } else {

    $mysql_password = generate("/usr/bin/pwgen", 20, 1)

    file { "/root/.my.cnf":
      owner => root,
      group => root,
      mode  => 600,
      require => Exec["Initialize MySQL server root password"],
    }

  }

  exec { "Initialize MySQL server root password":
    unless      => "test -f /root/.my.cnf",
    command     => "mysqladmin -u${mysql_user} password ${mysql_password}",
    notify      => Exec["Generate my.cnf"],
    require     => [Package["mysql-server"], Service["mysql"]]
  }

  exec { "Generate my.cnf":
    command     => "/bin/echo -e \"[mysql]\nuser=${mysql_user}\npassword=${mysql_password}\n[mysqladmin]\nuser=${mysql_user}\npassword=${mysql_password}\n[mysqldump]\nuser=${mysql_user}\npassword=${mysql_password}\n[mysqlshow]\nuser=${mysql_user}\npassword=${mysql_password}\n\" > /root/.my.cnf",
    refreshonly => true,
    creates     => "/root/.my.cnf",
  }

  $logfile_group = $mysql::params::logfile_group

  file { "/etc/logrotate.d/mysql-server":
    ensure => present,
    content => $operatingsystem ? {
      /RedHat|Fedora|CentOS/ => template('mysql/logrotate.redhat.erb'),
                    /Debian/ => template('mysql/logrotate.debian.erb'),
      default => undef,
    }
  }

  file { "mysql-slow-queries.log":
    ensure  => present,
    owner   => mysql,
    group   => mysql,
    mode    => 640,
    seltype => mysqld_log_t,
    path    => $operatingsystem ? {
      /RedHat|Fedora|CentOS/ => "/var/log/mysql-slow-queries.log",
      default => "/var/log/mysql/mysql-slow-queries.log",
    };
  }

}
