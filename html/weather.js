/*
 Chart setup for weather v1.0
*/

var weather_source = '';
var weather_cols = 'min_outTemp,max_outTemp,outHumidity,windGust,windSpeed,rain';
var weather_query = null;
var weather_updating = null;
var weather_range = { min: 0, max: -1 };
var weather_range_next = null;
var weather_options = {};

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
  wdebug("query: " + url);

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

function parseResponse(response) {

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

  meta.mode = response.mode;
  data = response.data;
  if (! data) {
    meta.error.msg = "No weather data available";
    return meta;
  }

  for (i = 0; i < data.length; i++) {
    curdate = data[i][0];
    if (meta.mode == "summary") {
      meta['temp'].push([curdate, data[i][1], data[i][2]]);
    }
    else {
      meta['temp'].push([curdate, data[i][1]]);
    }      
    meta['humid'].push([curdate, data[i][3]]);
    meta['hwind'].push([curdate, data[i][4]]);
    meta['wind'].push([curdate, data[i][5]]);
    meta['rain'].push([curdate, data[i][6]]);
    dayrain += data[i][6];
    if (curdate > (data[daystart][0] + 86400000)) {
      dayrain -= data[daystart][6];
      while(++daystart < i) {
	if (curdate <= (data[daystart][0] + 86400000)) {
	  break;
	}
	dayrain -= data[daystart][6];
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

  $.getJSON(queryURL(range), function (response) {
    var meta = parseResponse(response);
    chart.hideLoading();
    if (meta.error) {
      showError(meta.error.msg);
    }
    else {
      wdebug("query complete: " + meta['temp'].length);
      weather_updating = meta;
      hideError();
      //wdebug("setData[temp]");
      if (meta.mode == "summary") {
	chart.series[6].hide();
	chart.series[6].setData(null, false);
	chart.series[0].setData(meta['temp'], false, false, false);
	chart.series[0].show();
      }
      else {
	chart.series[0].hide();
	chart.series[0].setData(null, false);
	chart.series[6].setData(meta['temp'], false, false, false);
	chart.series[6].show();
      }
      //wdebug("setData[humid]");
      chart.series[1].setData(meta['humid'], false, false, false);
      //wdebug("setData[hwind]");
      chart.series[2].setData(meta['hwind'], false, false, false);
      //wdebug("setData[wind]");
      chart.series[3].setData(meta['wind'], false, false, false);
      //wdebug("setData[dayrain]");
      chart.series[4].setData(meta['dayrain'], false, false, false);
      //wdebug("setData[rain]");
      chart.series[5].setData(meta['rain'], false, false, false);
      wdebug("redraw");
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
  weather_options = {
    chart: {
      type: 'spline',
      animation: false,
      zoomType: 'x'
    },
    plotOptions: {
      series: {
	showInNavigator: true,
	lineWidth: 1.5,
	dataGrouping: {
	  enabled: false,
	},
	gapSize: 7,
      },
    },
    navigator: {
      margin: 40,
      adaptToUpdatedData: false
    },
    rangeSelector: {
      verticalAlign: 'bottom',
      floating: true,
      x: 20,
      y: -60,
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
      x: -40,
      y: -60,
      align: 'right',
      verticalAlign: 'bottom',
      floating: true
    },
    xAxis: {
      ordinal: false,
      events: { afterSetExtremes: afterSetExtremes },
      minRange: 30 * 3600 * 1000 // one day
    },
    tooltip: {
        xDateFormat: '%b %d, %Y',
        shared: true
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
      min: 0,
      startOnTick: false,
      max: 120,
      endOnTick: false,
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
      max: 5,
      min: 0,
      offset: 0,
      lineWidth: 2
    }],
    series: [{
      type: 'arearange',
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
	  [1, new Highcharts.Color(Highcharts.getOptions().colors[2]).setOpacity(0).get('rgba')]
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
	  [1, new Highcharts.Color(Highcharts.getOptions().colors[0]).setOpacity(0).get('rgba')]
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
    }, {
      name: 'Temperature',
      visible: false,
      tooltip: {
	valueDecimals: 2,
	valueSuffix: 'F'
      },
      colorIndex: 5
    }]
  };
  Highcharts.stockChart('container', weather_options);
}

function weatherSetup(source) {

  weather_source = source;

  $.getJSON(queryURL(), function (response) {
    var meta = parseResponse(response);
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
