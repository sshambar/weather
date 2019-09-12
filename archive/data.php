<?php
/**
 * This file loads content from four different data tables
 * depending on the required time range.
 *
 * @param callback {String} The name of the JSONP callback to pad the JSON within
 * @param source {String} Which sample set to query
 * @param start {Integer} The starting point in JS time
 * @param end {Integer} The ending point in JS time
 */

//error_reporting( E_ALL );
//ini_set('display_errors', 1);

$callback = null;
$add_extra = 0;

function jsonp_header() {
	global $callback;
	// RFC 4329 (js) and 4627 (json)
	if ($callback) header('Content-Type: application/javascript');
	else header('Content-Type: application/json');
}
function jsonp_pre() {
	global $callback;
	if($callback) echo "$callback(";
}
function jsonp_post() {
	global $callback;
	if($callback) echo ");";
	else ";";
}

function weather_error($code, $msg) {
	jsonp_header();
	jsonp_pre();
	echo json_encode(array(
		'error' => array('code' => $code, 'msg' => $msg)));
	jsonp_post();
	die();
}

function ajaxExceptionHandler($e) {
	weather_error($e->getCode(), $e->getMessage());
}
set_exception_handler('ajaxExceptionHandler');

/* on client:
$(document).ajaxSuccess(function(evt, request, settings){
    var data=request.responseText;
    if (data.length>0) {
        var resp=$.parseJSON(data);
        if (resp.error)
        {
            showDialog(resp.msg);
            return;
        }
    }
});
*/

// get the parameters

$callback = @$_GET['callback'];
if (!preg_match('/^[a-zA-Z0-9_]+$/', $callback)) {
	$callback = null;
}

$source = @$_GET['source'];
if (!$source) $source = 'napa';
if (!preg_match('/^[a-z]+$/', $source)) {
	weather_error(1, "Invalid source parameter: '$source'");
}

$start = @$_GET['start'];
if ($start) {
	if (!preg_match('/^[0-9]+$/', $start)) {
		weather_error(2, "Invalid start parameter: '$start'");
	}
	$start /= 1000;
}
else {
	$start = 0;
}

$end = @$_GET['end'];
if ($end) {
	if (!preg_match('/^[0-9]+$/', $end)) {
		weather_error(3, "Invalid end parameter: '$end'");
	}
	$end /= 1000;
}
else {
	$end = 0;
}

$cols = @$_GET['cols'];
if (strlen($cols)) {
	if (!preg_match('/^[a-z_,]+$/', $cols)) {
		weather_error(4, "Invalid cols parameter: '$cols'");
	}
}
else {
	$cols = "temp_out,humid_out,wind_speed,rain";
}

$valid_cols = [ 'barometer', 'temp_in', 'humid_in', 'temp_out',
		'high_temp_out', 'low_temp_out', 'humid_out',
		'wind_samples', 'wind_speed', 'wind_dir',
		'high_wind_speed', 'high_wind_dir', 'rain',
		'high_rain' ];
$test_cols = explode(',', $cols);
foreach ($test_cols as $col) {
	if(! in_array($col, $valid_cols)) {
		weather_error(5, "Invalid column: '$col'");
	}
}

require_once '/etc/weather/webconfig.php';

$options = [
	PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
	PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
	PDO::ATTR_EMULATE_PREPARES   => false,
];

$pdo = new PDO($db_pdo.';charset=utf8', $db_user, $db_pass, $options);
$pdo->exec("SET time_zone='+00:00';");

if ($start == 0) {
	$sql = "SELECT UNIX_TIMESTAMP(MIN(w.time_utc)) start
		FROM weather_samples w, weather_sources s
		WHERE s.name = :source
		AND w.source_id = s.id";
	$query = $pdo->prepare($sql);
	$query->execute(['source' => $source]);
	$result = $query->fetch();
	$start = $result['start'];

	if (! $start) {
		weather_error(10, "Unknown source '$source'");
	}
}

if ($end == 0) {
	$sql = "SELECT UNIX_TIMESTAMP(MAX(w.time_utc)) end
		FROM weather_samples w, weather_sources s
		WHERE s.name = :source
		AND w.source_id = s.id";
	$query = $pdo->prepare($sql);
	$query->execute(['source' => $source]);
	$result = $query->fetch();
	$end = $result['end'];

	if (! $end) {
		weather_error(10, "Unknown source '$source'");
	}
}

// set some utility variables
$range_secs = $end - $start;

$sql = "SELECT MAX(r.range_mins) range_mins, s.id source_id
	FROM weather_ranges r, weather_sources s
	WHERE :range_secs >= r.min_query_secs
	AND s.name = :source
	GROUP by s.id";

$query = $pdo->prepare($sql);
$query->execute(['range_secs' => $range_secs,
		 'source' => $source]);
$result = $query->fetch();

$range_mins = $result['range_mins'];
$source_id = $result['source_id'];

if (! $source_id) {
	weather_error(11, "Unknown source '$source'");
}

// move start backwards to include first part of range...
$start -= $range_mins * 60;
$start_time = gmstrftime('%Y-%m-%d %H:%M:%S', $start);
$end_time = gmstrftime('%Y-%m-%d %H:%M:%S', $end);

$query_args = ['start_time' => $start_time,
	       'end_time' => $end_time,
	       'source_id' => $source_id];

if ($range_mins > 30) {
	$table = "weather_summary";
	$match = "AND range_mins = :range_mins";
	$query_args['range_mins'] = $range_mins;

	$sql = "SELECT UNIX_TIMESTAMP(MAX(time_utc)) last
		FROM weather_summary
		WHERE source_id = :source_id
		AND range_mins = :range_mins";
	$query = $pdo->prepare($sql);
	$query->execute(['source_id' => $source_id,
			 'range_mins' => $range_mins]);
	$result = $query->fetch();
	$last = $result['last'];

	if ($end > $last) {
		$add_extra = $end * 1000;
	}
}
else {
	$table = "weather_samples";
	$match = "";
}

$sql = "SELECT UNIX_TIMESTAMP(time_utc) * 1000 dt,
		$cols
	FROM $table
	WHERE time_utc BETWEEN :start_time AND :end_time
        AND source_id = :source_id $match
	ORDER BY time_utc
	LIMIT 0, 5000";

$query = $pdo->prepare($sql);
$query->execute($query_args);
$rows = $query->fetchAll();

$query = null;
$pdo = null;

//header('Content-Type: text/html');
//var_dump($rows);
//die();

// print it
jsonp_header();
$response['range'] =
	[ 'start' => $start_time,
	  'end' => $end_time,
	  'sid' => $source_id,
	  'range_secs' => $range_secs,
	  'range' => $range_mins ];
$cols = "start_time," . $cols;
$response['cols'] = [ 'cols' => $cols ];
$response['data'] = array();
jsonp_pre();
$prefix = json_encode($response, JSON_PRETTY_PRINT);
echo rtrim($prefix, "]}\n") . "\n";
$lead = "";
foreach ($rows as $row) {
	echo $lead . "[" . join(",", $row) . "]";
	$lead = ",\n";
}
// add fake summary item if no end limit
if ($add_extra && is_array($row)) {
	$row['dt'] = $add_extra;
	echo $lead . "[" . join(",", $row) . "]";
}
echo "    ]\n}\n";
jsonp_post();
?>
