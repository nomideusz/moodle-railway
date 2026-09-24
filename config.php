<?php
// Railway: Moodle's settings come from the service variables, read on every request,
// so the Variables tab stays the source of truth. Everything else is set in
// Site administration.
unset($CFG);
global $CFG;
$CFG = new stdClass();

$CFG->dbtype    = 'pgsql';
$CFG->dblibrary = 'native';
$CFG->dbhost    = getenv('PGHOST');
$CFG->dbname    = getenv('PGDATABASE');
$CFG->dbuser    = getenv('PGUSER');
$CFG->dbpass    = getenv('PGPASSWORD');
$CFG->prefix    = 'mdl_';
$CFG->dboptions = ['dbport' => (int) (getenv('PGPORT') ?: 5432)];

$CFG->wwwroot  = rtrim(getenv('MOODLE_URL'), '/');
$CFG->dataroot = '/var/moodledata';
$CFG->admin    = 'admin';

// Railway's edge terminates HTTPS and forwards plain HTTP.
$CFG->sslproxy = str_starts_with($CFG->wwwroot, 'https://');
// Apache hands unknown paths to r.php (FallbackResource), so routed URLs need no r.php.
$CFG->routerconfigured = true;
// REMOTE_ADDR only: Apache already set it to the visitor from Railway's X-Real-IP.
$CFG->getremoteaddrconf = 3;
// The code is in the image and read-only; plugins are added to the image instead.
$CFG->disableupdateautodeploy = true;

require_once(__DIR__ . '/lib/setup.php'); // Do not edit
