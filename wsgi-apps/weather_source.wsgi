#!/usr/bin/python

import sys, re, json
import MySQLdb
from cgi import parse_qs

def json_data(headers, srcid, col=None):
    all_columns = [ "barometer", "temp_in", "humid_in", "temp_out", "high_temp_out", "low_temp_out", "humid_out", "wind_samples", "wind_speed", "wind_dir", "high_wind_speed", "high_wind_dir", "rain", "high_rain"]
    cols = []
    if col:
        for c in col.split(","):
            if c in all_columns:
                cols.append(c)
    if len(cols) == 0:
        cols = all_columns
    db=MySQLdb.connect("localhost","weather","69ftweather","weather")
    dbc = db.cursor()
    stmt = 'select time_observed, ' + ",".join(cols) + ' from weather_samples where source_id = %(srcid)s'
    dbc.execute(stmt, vars())
    result = []
    row = dbc.fetchone()
    while row:
        data = [int(row[0].strftime("%s"))*1000]
        data.extend(row[1:])
        result.append(data)
        row = dbc.fetchone()
    headers.append(('Content-Type','application/json'))
    return json.dumps(result)

def get_params(environ, names):
    args = parse_qs(environ.get('QUERY_STRING', ''))
    params = dict()
    for name in names:
        if name in args:
            params[name] = args[name][0]
    return params

def napa_data(environ, start_response):
    params = get_params(environ, ['source','col'])
    headers = []
    page = json_data(headers, 0, **params)
    start_response('200 OK', headers)
    return [page]

def not_found(environ, start_response):
    """Called if no URL matches."""
    start_response('404 NOT FOUND', [('Content-Type', 'text/plain')])
    return ['Not Found']

urls = [
    (r'^napa/?', napa_data),
]

def application(environ, start_response):
    path = environ.get('PATH_INFO', '').lstrip('/')
    for regex, app in urls:
        match = re.search(regex, path)
        if match is not None:
            return app(environ, start_response)
    return not_found(environ, start_response)

# for debugging exceptions
#from paste.exceptions.errormiddleware import ErrorMiddleware
#application = ErrorMiddleware(application, debug=True)
