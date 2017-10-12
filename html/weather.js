/*
 Chart setup for weather
*/

var weather_source = 'none';
var weather_cols = 'temp_out,humid_out,high_wind_speed,wind_speed,rain';
var weather_query = null;
var weather_updating = null;
var weather_range = { min: 0, max: -1 };
var weather_range_next = null;

function wdebug(msg) {
  console.log(msg);
}

function queryURL(range) {

  var url = '/weather/data?cols=' + weather_cols + '&source=' +
      weather_source + '&callback=?';

  if(range) {
    weather_range = range;
    url += '&start=' + Math.round(range.min) + '&end=' + Math.round(range.max);
  }

  weather_query = url;

  return url;
}

function showError(msg) {
  wdebug("query fail: " + msg);

  var loading = document.getElementById("loading");

  loading.innerHTML = "Request Failed: " + msg;
  $("#container").css('display', 'none');
  loading.style.display = 'block';
}

function hideError() {

  $("#loading").css('display', 'none');
  $("#container").css('display', 'block');
}

function parseData(response) {

  var meta = { temp: [], humid: [], wind: [], hwind: [], rain: [],
	       dayrain: [], error: null }, curdate, dayrain = 0, daystart = 0;

  if (typeof(response) != "object") {
    meta.error.msg = "Invalid weather values";
    return meta;
  }

  error = response.error;
  if (error) {
    meta.error = error;
    return meta;
  }

  data = response.data;
  if (! data) {
    meta.error.msg = "No weather data available";
    return meta;
  }

  for (i = 0; i < data.length; i++) {
    curdate = data[i][0];
    meta['temp'].push([curdate, data[i][1]]);
    meta['humid'].push([curdate, data[i][2]]);
    meta['hwind'].push([curdate, data[i][3]]);
    meta['wind'].push([curdate, data[i][4]]);
    meta['rain'].push([curdate, data[i][5]]);
    dayrain += data[i][5];
    if (curdate > (data[daystart][0] + 86400000)) {
      dayrain -= data[daystart][5];
      while(++daystart < i) {
	if (curdate <= (data[daystart][0] + 86400000)) {
	  break;
	}
      }
    }
    meta['dayrain'].push([curdate, dayrain]);
  }
  
  return meta;
}

function weatherFinishQuery() {

  wdebug("query finished: " + weather_range.min + " - " + weather_range.max);
  weather_query = null;

  if (weather_range_next) {
    if (weather_range.min != weather_range_next.min
	|| weather_range.max != weather_range_next.max) {
      weatherStartQuery(weather_range_next);
    }
    weather_range_next = null;
  }
}

function weatherStartQuery(range) {

  var chart = Highcharts.charts[0];

  wdebug("starting query: " + range.min + " - " + range.max);
  chart.showLoading('Loading data from server...');

  $.getJSON(queryURL(range), function (data) {
    var meta = parseData(data);
    chart.hideLoading();
    if (meta.error) {
      showError(meta.error.msg);
    }
    else {
      wdebug("query complete: " + meta['temp'].length);
      weather_updating = meta;
      hideError();
      chart.series[0].setData(meta['temp'], false);
      chart.series[1].setData(meta['humid'], false);
      chart.series[2].setData(meta['hwind'], false);
      chart.series[3].setData(meta['wind'], false);
      chart.series[4].setData(meta['dayrain'], false);
      chart.series[5].setData(meta['rain'], false);
      chart.redraw();
      weather_updating = null;
    }
    weatherFinishQuery();
  })
    .fail(function(jqxhr, textStatus, error) {
      chart.hideLoading();
      showError(error);
      weatherFinishQuery();
    });
}

function afterSetExtremes(e) {

  if (weather_updating == null) {
    var range = { min: e.min, max: e.max };

    wdebug("setting extremes: " + range.min + " - " + range.max);

    if (weather_query) {
      weather_range_next = range;
    }
    else {
      weatherStartQuery(range);
    }
  }
}

function setupChart(meta) {
  // Create the chart
  Highcharts.setOptions({
    global : {
      useUTC:  false
    }
  });
  Highcharts.stockChart('container', {
    chart: {
      type: 'spline',
      animation: false,
      zoomType: 'x'
    },
    plotOptions: {
      series: {
	getExtremesFromAll: true,
	showInNavigator: true,
	lineWidth: 1.5
      }
    },
    navigator: {
      adaptToUpdatedData: false
    },
    rangeSelector: {
      buttons: [{
	type: 'hour',
	count: 31,
	text: 'Day'
      }, {
	type: 'month',
	count: 1,
	text: 'Month'
      }, {
	type: 'year',
	count: 1,
	text: 'Year'
      }, {
	type: 'all',
	text: 'All'
      }],
      buttonTheme: {
	width: 50
      },
      inputEnabled: false, // it supports only days
      selected: 3 // all
    },
    legend : {
      enabled: true,
      x: -70,
      align: 'right',
      verticalAlign: 'top',
      floating: true
    },
    xAxis: {
      events: { afterSetExtremes: afterSetExtremes },
      minRange: 30 * 3600 * 1000 // one day
    },
    yAxis: [{
      labels: {
	align: 'right',
	x: -3
      },
      title: {
	text: 'F/%'
      },
      height: '40%',
      max: 100,
      min: 0,
      startOnTick: false,
      lineWidth: 2
    }, {
      labels: {
	align: 'right',
	x: -3
      },
      title: {
	text: 'mph'
      },
      top: '43%',
      height: '25%',
      max: 30,
      min: 0,
      offset: 0,
      lineWidth: 2
    }, {
      labels: {
	align: 'right',
	x: -3
      },
      title: {
	text: 'in'
      },
      top: '70%',
      height: '30%',
      max: 10,
      min: 0,
      offset: 0,
      lineWidth: 2
    }],
    series: [{
      data: meta['temp'],
      name: 'Temperature',
      tooltip: {
	valueDecimals: 2,
	valueSuffix: 'F'
      },
      colorIndex: 5
    }, {
      data: meta['humid'],
      name: 'Humidity',
      tooltip: {
	valueDecimals: 2,
	valueSuffix: '%'
      },
      colorIndex: 6
    }, {
      data: meta['hwind'],
      name: 'High Wind',
      type: 'areaspline',
      yAxis: 1,
      tooltip: {
	valueDecimals: 2,
	valueSuffix: ' mph'
      },
      colorIndex: 2,
      fillColor: {
	linearGradient: { x1: 0, y1: 0, x2: 0, y2: 1 },
	stops: [
	  [0, Highcharts.getOptions().colors[2]],
	  [1, Highcharts.Color(Highcharts.getOptions().colors[2]).setOpacity(0).get('rgba')]
	]
      }
    }, {
      data: meta['wind'],
      name: 'Avg Wind',
      yAxis: 1,
      tooltip: {
	valueDecimals: 2,
	valueSuffix: ' mph'
      },
      colorIndex: 3
    }, {
      data: meta['dayrain'],
      name: 'Daily Rain',
      type: 'areaspline',
      yAxis: 2,
      tooltip: {
	valueDecimals: 2,
	valueSuffix: ' in'
      },
      colorIndex: 0,
      fillColor: {
	linearGradient: { x1: 0, y1: 0, x2: 0, y2: 1 },
	stops: [
	  [0, Highcharts.getOptions().colors[0]],
	  [1, Highcharts.Color(Highcharts.getOptions().colors[0]).setOpacity(0).get('rgba')]
	]
      }
    }, {
      data: meta['rain'],
      name: 'Rain',
      yAxis: 2,
      tooltip: {
	valueDecimals: 2,
	valueSuffix: ' in'
      },
      colorIndex: 4
    }]
  });
}

function weatherSetup(source) {

  weather_source = source;

  $.getJSON(queryURL(), function (data) {
    var meta = parseData(data);
    if (meta.error) {
      showError(meta.error.msg);
    }
    else {
      hideError();
      setupChart(meta);
    }
    weatherFinishQuery();
  })
    .fail(function(jqxhr, textStatus, error) {
      showError(error);
      weatherFinishQuery();
    });
}
