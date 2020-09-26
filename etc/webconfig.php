<?php

// database connection details
$db_pdo = 'mysql:host=localhost;unix_socket=/var/lib/mysql/mysql.sock;dbname=weewx';
$db_user = 'weewx';
$db_pass = 'password';
// source with null dbprefix
$default_source = 'default';

// flat-file index location
$datadir = '/var/lib/weather';

// source -> name map
$source_map = array(
    'default' => array(
        'title' => 'Default Station',
    ),
);
