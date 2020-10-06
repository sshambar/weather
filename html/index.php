<?php
$title = 'The';
$config = '/etc/weather/webconfig.php';
if(! is_readable($config)) {
	throw new Exception("Unable to read config");
}
require_once($config);
$source = $default_source;
if(isset($_SERVER['REDIRECT_ORIGINAL_PATH'])) {
    $source = preg_replace('|/([a-z]+)[^a-z]?.*|', '$1',
                           $_SERVER['REDIRECT_ORIGINAL_PATH'], 1);
}
if(isset($source_map) && isset($source_map[$source])) {
    $map = $source_map[$source];
    if(isset($map['title'])) { $title = $map['title']; }
    if(isset($map['source'])) { $source = $map['source']; }
}
?>
<!DOCTYPE HTML>
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
<title><?php echo $title ?> Weather</title>

<script src="https://code.jquery.com/jquery-3.4.1.min.js"></script>
<script src="https://code.highcharts.com/stock/highstock.js"></script>
<script src="https://code.highcharts.com/highcharts-more.js"></script>
<script src="<?php echo $_SERVER['CONTEXT_PREFIX']; ?>/weather.js"></script>
<script type="text/javascript">
 $(function() {
    weatherSetup(<?php echo "'$source'" ?>);
  });
</script>
</head>
<body>
    <h1 align="middle" style="color:#3E576F"><?php echo $title ?> Weather</h1>
    <div id="loading" align="middle" style="color:#3E576F; height:500px; min-width:310px">Loading...</div>
    <div id="container" style="display:none; height: 500px; min-width: 310px"></div>
</body>
</html>
