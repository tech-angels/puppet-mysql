class mysql::master inherits mysql::server {

  Mysql::Config['log-bin'] {
    ensure => 'present',
    value  => 'mysql-bin',
  }

  Mysql::Config['server-id'] {
    ensure => 'present',
    value  => ${mysql_serverid},
  }

  Mysql::Config['expire_logs_days'] {
    ensure => 'present',
    value  => '7',
  }

  Mysql::Config['max_binlog_size'] [
    ensure => 'present',
    value  => '100M',
  }

}
