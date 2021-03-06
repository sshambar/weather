
## Probably want to drop trigger weather_insert_trigger for speed...

## For Migration...
TRUNCATE TABLE weather_samples;
TRUNCATE TABLE weather_summary;

DELETE FROM weather_sources
WHERE id = 1;

INSERT INTO weather_sources (id, name)
VALUES (1, 'napa');

INSERT INTO weather_samples
       (source_id, time_observed, time_utc, barometer, temp_in, humid_in,
        temp_out, high_temp_out, low_temp_out, humid_out, wind_samples,
        wind_speed, wind_dir, high_wind_speed, high_wind_dir, rain, high_rain)
SELECT	1 source_id, time_observed,
	convert_tz(time_observed, "US/Pacific", "UTC") time_utc,
	barometer, temp_in, humid_in, temp_out, high_temp_out,
	low_temp_out, humid_out, wind_samples, wind_speed, w.id wind_dir,
	high_wind_speed, hw.id high_wind_dir, rain, high_rain
FROM weather_samples_orig s, weather_windmap w, weather_windmap hw
WHERE w.direction = s.wind_dir
AND hw.direction = s.high_wind_dir;

#AND s.time_observed > DATE_SUB(CURDATE(),INTERVAL 90 DAY);

#limit 0, 10;

#AND s.time_observed > DATE_SUB(CURDATE(),INTERVAL 30 DAY);

#AND s.time_observed like '2017-06-05%';

## Now re-add trigger weather_insert_trigger, and call weather_recalc_all;
