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

ini_set('display_errors', 0);
//error_reporting( E_ALL );
//ini_set('display_errors', 1);
$config = '/etc/weather/webconfig.php';

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

if(! is_readable($config)) {
	throw new Exception("can't read config", 5);
}
require_once($config);

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
if (!preg_match('/^[a-z]+$/', $source)) {
	$dbprefix = null;
}
else {
	$dbprefix = $source.'_';
	$datadir .= '/'.$source;
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
	if (!preg_match('/^[a-zA-Z_,]+$/', $cols)) {
		weather_error(4, "Invalid cols parameter: '$cols'");
	}
}
else {
	$cols = "outTemp,outHumidity,windSpeed,rain";
}

$valid_cols = [ 'barometer', 'inTemp', 'inHumidity', 'outTemp',
		'max_outTemp', 'min_outTemp', 'outHumidity',
		'windSpeed', 'windDir',	'windGust', 'windGustDir',
		'rain',	'rainRate' ];
$acols = explode(',', $cols);
foreach ($acols as $col) {
	if(! in_array($col, $valid_cols)) {
		weather_error(5, "Invalid column: '$col'");
	}
}
$acols = array_merge([ 'dateTime' ], $acols);

if(isset($default_source) && $source == $default_source) {
	$dbprefix = null;
}

$options = [
	PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
	PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
	PDO::ATTR_EMULATE_PREPARES   => false,
];

$pdo = new PDO($db_pdo.';charset=utf8', $db_user, $db_pass, $options);
$pdo->exec("SET time_zone='+00:00';");

try {
        $result = $pdo->query("SELECT 1 FROM ".$dbprefix."archive LIMIT 1");
} catch (Exception $e) {
	$result = false;
}
if($result === false) { weather_error(6, "Unknown source '$source'"); }

if($start == 0 || $end == 0) {
	$sql = "SELECT MIN(dateTime) first, MAX(dateTime) last
		FROM ".$dbprefix."archive";
	$query = $pdo->prepare($sql);
	$query->execute();
	$result = $query->fetch();
	if($result === false) { weather_error(7, "No data found"); }
	$first = (int)$result['first'];
	$last = (int)$result['last'];
	if($start < $first) { $start = $first; }
	if($end == 0 || $end > $last) { $end = $last; }
	if($end < $start) { weather_error(8, "No data found"); }
}

function loadCSV($datadir, $file, $acols, $start, $end) {

	$path = $datadir.'/'.$file.'.csv';
	if(! is_readable($path)) { return []; }
	$fn = fopen($path, "r");
	if($fn === false) { return []; }
	$rows = [];
	$fcols = false;
	while(! feof($fn)) {
		if($fcols === false) {
			$fcols = fgets($fn);
			if($fcols === false) {
				weather_error(9, "No columns in source file");
			}
			$afcols = preg_split("/#[ ]*/", $fcols);
			if(count($afcols) < 2) { return []; }
			$colmap = explode(",", $afcols[1]);
			foreach($acols as $col) {
				$key = array_search($col, $colmap);
				if($key === false) {
					weather_error(10, "Unsupported column: '$col'");
				}
				$mapping[] = $key;
			}
		}
		else {
			// map values into rows
			$csv = fgetcsv($fn);
			if($csv !== false) {
				$row = [];
				foreach($mapping as $key) {
					if($key == 0) {
						$row[] = $csv[$key] * 1000;
					}
					else {
						$row[] = $csv[$key];
					}
				}
				$rows["$row[0]"] = $row;
			}
		}
	}
	fclose($fn);
	return $rows;
}

$range_secs = $end - $start;
if($range_secs > 5184000) { // > 60 days, use daily
	$mode = 'summary';
	if($range_secs > 157680000) { // > 5 years, use weekly
		$range_mins = 10080;
		$trailer = '-weekly';
	}
	else {
		$range_mins = 1440;
		$trailer = '-daily';
	}
	// move start backwards to include first part of range...
	$start -= $range_mins * 60;
	// File-pattern is YYYY-daily.csv
	$startYear = (int)gmstrftime('%Y', $start);
	$endYear = (int)gmstrftime('%Y', $end);
	$rows = [];
	foreach(range($startYear, $endYear) as $year) {
		$rows = array_merge($rows, loadCSV($datadir, $year.$trailer,
						   $acols, $start, $end));
	}
	if(count($rows) > 0) {
		$last = end($rows)[0] / 1000;
		if ($end > $last) {
			$add_extra = $end * 1000;
		}
	}
}
else {
	$mode = 'direct';
	$acols = explode(',', $cols);
	foreach(array_keys($acols) as $i) {
		if($acols[$i] == 'min_outTemp' ||
		   $acols[$i] == 'max_outTemp') {
			$acols[$i] = 'outTemp '.$acols[$i];
		}
	}
	$scols = implode(',', $acols);
	$range_mins = 30;
	$sql = "SELECT dateTime * 1000 dt,
		$scols
	FROM ".$dbprefix."archive
	WHERE dateTime BETWEEN :start_time AND :end_time
	ORDER BY dateTime
	LIMIT 0, 5000";

	$query = $pdo->prepare($sql);
	$query->execute(['start_time' => $start,
			 'end_time' => $end]);
	$rows = $query->fetchAll();
	$query = null;
}
$pdo = null;

if(count($rows) == 0) { weather_error(11, "No data found"); }

//header('Content-Type: text/html');
//var_dump($rows);
//die();

// print it
jsonp_header();
$response['range'] =
	[ 'start' => gmstrftime('%Y-%m-%d %H:%M:%S', $start),
	  'end' => gmstrftime('%Y-%m-%d %H:%M:%S', $end),
	  'range_secs' => $range_secs,
	  'range' => $range_mins ];
$response['mode'] = $mode;
$response['cols'] = [ 'cols' => "dateTime,".$cols ];
$response['data'] = array();
jsonp_pre();
$rprefix = json_encode($response, JSON_PRETTY_PRINT);
echo rtrim($rprefix, "]}\n") . "\n";
$lead = "";
foreach ($rows as $row) {
	echo $lead . "[" . join(",", $row) . "]";
	$lead = ",\n";
}
// add fake summary item if no end limit
if ($add_extra && is_array($row)) {
	$row[0] = $add_extra;
	echo $lead . "[" . join(",", $row) . "]";
}
echo "\n    ]\n}\n";
jsonp_post();
?>
