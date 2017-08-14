delimiter //

DROP FUNCTION IF EXISTS weather_min_date //
CREATE DEFINER = weather@localhost
FUNCTION weather_min_date (dt DATETIME, range_mins INTEGER)
RETURNS DATETIME
DETERMINISTIC
BEGIN
  DECLARE new_dt DATETIME;
  DECLARE day_sub INTEGER;
  SET new_dt := CAST(CAST(dt as DATE) AS DATETIME);
  CASE range_mins
    WHEN 1440 THEN # daily
      SET day_sub := 0;
    WHEN 10080 THEN # weekly
      SET day_sub := DAYOFWEEK(new_dt) - 1;
    WHEN 43200 THEN # monthly
      SET day_sub := DAYOFMONTH(new_dt) - 1;
  END CASE;
  SET new_dt := DATE_SUB(new_dt, INTERVAL day_sub DAY);
  RETURN new_dt;
END //

DROP FUNCTION IF EXISTS weather_max_date //
CREATE DEFINER = weather@localhost
FUNCTION weather_max_date (dt DATETIME, range_mins INTEGER)
RETURNS DATETIME
DETERMINISTIC
BEGIN
  DECLARE new_dt DATETIME;
  SET new_dt := weather_min_date(dt, range_mins);
  CASE range_mins
    WHEN 1440 THEN # daily
      SET new_dt := DATE_ADD(new_dt, INTERVAL 1 DAY);
    WHEN 10080 THEN # weekly
      SET new_dt := DATE_ADD(new_dt, INTERVAL 1 WEEK);
    WHEN 43200 THEN # monthly
      SET new_dt := DATE_ADD(new_dt, INTERVAL 1 MONTH);
  END CASE;
  RETURN new_dt;
END //

delimiter ;

SELECT datediff(weather_max_date(now(), 1440), weather_min_date(now(), 1440)) Should_Return_1;

SELECT datediff(weather_max_date(now(), 10080), weather_min_date(now(), 10080)) Should_Return_7;

SELECT datediff(weather_max_date(now(), 43200), weather_min_date(now(), 43200)) Should_Return_28_31;

delimiter //

DROP PROCEDURE IF EXISTS weather_debug //
CREATE DEFINER = weather@localhost
PROCEDURE weather_debug (IN msg VARCHAR(255))
INSERT INTO weather_log (msg)
VALUES (msg) //

#CALL weather_debug((SELECT CONCAT_WS(' ', 'd:', d, 'min:', min_date, 'num:', num, 'range:', r)));

DROP PROCEDURE IF EXISTS weather_report //
CREATE DEFINER = weather@localhost
PROCEDURE weather_report ()
BEGIN
  SELECT msg FROM weather_log
  ORDER BY id;
END //

DROP PROCEDURE IF EXISTS weather_update_summary //
CREATE DEFINER = weather@localhost
PROCEDURE weather_update_summary
  (IN sid INTEGER, IN d DATETIME, IN r INTEGER)
BEGIN
  DECLARE min_date, max_date DATETIME;

  SET min_date := weather_min_date(d, r);
  SET max_date := weather_max_date(d, r);

  DELETE FROM weather_summary
  WHERE source_id = sid
  AND range_mins = r
  AND time_utc = min_date;

  INSERT INTO weather_summary
        (source_id, range_mins, time_utc, barometer, temp_in,
	 humid_in, temp_out, high_temp_out, low_temp_out, humid_out,
         wind_samples, wind_speed, wind_dir, high_wind_speed, high_wind_dir,
         rain, high_rain, num_samples)
  SELECT sid, r, min_date, sum(barometer)/count(*),
    	 sum(temp_in)/count(*), sum(humid_in)/count(*), 
  	 sum(temp_out)/count(*), max(high_temp_out), min(low_temp_out),
	 sum(humid_out)/count(*), sum(wind_samples),
	 sum(wind_speed)/count(*), sum(wind_dir)/count(*),
	 max(high_wind_speed), sum(high_wind_dir)/count(*),
	 sum(rain), max(high_rain), count(*)
  FROM weather_samples_new
  WHERE source_id = sid
  AND time_utc >= min_date
  AND time_utc < max_date
  HAVING count(*) > 0;

END //

DROP PROCEDURE IF EXISTS weather_update_summaries //
CREATE DEFINER = weather@localhost
PROCEDURE weather_update_summaries
  (IN sid INTEGER, IN d DATETIME)
BEGIN
  DECLARE r INTEGER;
  DECLARE done INT DEFAULT FALSE;

  DECLARE range_cur CURSOR FOR
  	  SELECT range_mins
  	  FROM weather_ranges
	  WHERE range_mins > 30;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

  OPEN range_cur;

  read_loop: LOOP

    FETCH range_cur INTO r;
    IF done THEN
       LEAVE read_loop;
    END IF;

    CALL weather_update_summary(sid, d, r);
  END LOOP;

  CLOSE range_cur;

END //

DROP TRIGGER IF EXISTS weather_insert_trigger //
CREATE DEFINER = weather@localhost
TRIGGER weather_insert_trigger
AFTER INSERT ON weather_samples_new FOR EACH ROW
BEGIN
  CALL weather_update_summaries(NEW.source_id, NEW.time_utc);
END //

DROP TRIGGER IF EXISTS weather_update_trigger //
CREATE DEFINER = weather@localhost
TRIGGER weather_update_trigger
AFTER UPDATE ON weather_samples_new FOR EACH ROW
BEGIN
  IF OLD.source_id != NEW.source_id OR
     OLD.time_utc != NEW.time_utc THEN
    CALL weather_update_summaries(OLD.source_id, OLD.time_utc);
  END IF;
  CALL weather_update_summaries(NEW.source_id, NEW.time_utc);
END //

DROP TRIGGER IF EXISTS weather_delete_trigger //
CREATE DEFINER = weather@localhost
TRIGGER weather_delete_trigger
AFTER DELETE ON weather_samples_new FOR EACH ROW
BEGIN
  CALL weather_update_summaries(OLD.source_id, OLD.time_utc);
END //

DROP PROCEDURE IF EXISTS weather_recalc_summary //
CREATE DEFINER = weather@localhost
PROCEDURE weather_recalc_summary
  (IN sid INTEGER, IN r INTEGER)
BEGIN
  DECLARE cur_time, min_date, prev_min_date DATETIME;
  DECLARE done INT DEFAULT FALSE;

  DECLARE time_cur CURSOR FOR
  	  SELECT time_utc
  	  FROM weather_samples_new
	  WHERE source_id = sid
	  ORDER by time_utc;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

  SELECT CONCAT_WS('', 'recalculating source_id: ', sid, ' range: ', r) status;

  # remove this sid,range
  DELETE FROM weather_summary
  WHERE source_id = sid
  AND range_mins = r;

  SET prev_min_date := NOW();
  OPEN time_cur;

  read_loop: LOOP

    FETCH time_cur INTO cur_time;
    IF done THEN
       LEAVE read_loop;
    END IF;

    SET min_date := weather_min_date(cur_time, r);

    IF prev_min_date <> min_date THEN
      # summarize once/range
      SET prev_min_date := min_date;
      CALL weather_update_summary(sid, cur_time, r);
    END IF;

  END LOOP;

  CLOSE time_cur;
  COMMIT;
END //

DROP PROCEDURE IF EXISTS weather_recalc_source //
CREATE DEFINER = weather@localhost
PROCEDURE weather_recalc_source
  (IN sid INTEGER)
BEGIN
  DECLARE r INTEGER;
  DECLARE done INT DEFAULT FALSE;

  DECLARE range_cur CURSOR FOR
  	  SELECT range_mins
  	  FROM weather_ranges
	  WHERE range_mins > 30;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

  OPEN range_cur;

  read_loop: LOOP

    FETCH range_cur INTO r;
    IF done THEN
       LEAVE read_loop;
    END IF;

    CALL weather_recalc_summary(sid, r);
  END LOOP;

  CLOSE range_cur;

END //

DROP PROCEDURE IF EXISTS weather_recalc_all //
CREATE DEFINER = weather@localhost
PROCEDURE weather_recalc_all ()
BEGIN
  DECLARE sid INTEGER;
  DECLARE done INT DEFAULT FALSE;

  DECLARE source_cur CURSOR FOR
  	  SELECT id
  	  FROM weather_sources;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

  OPEN source_cur;

  read_loop: LOOP

    FETCH source_cur INTO sid;
    IF done THEN
       LEAVE read_loop;
    END IF;

    CALL weather_recalc_source(sid);
  END LOOP;

  CLOSE source_cur;

END //

delimiter ;
