


DROP TABLE IF EXISTS stackoverflow;
CREATE TABLE stackoverflow(
	id BIGINT PRIMARY KEY
	, title VARCHAR NOT NULL DEFAULT ''
	, body VARCHAR  NOT NULL DEFAULT ''
	, creationDate VARCHAR	
);
 
CREATE INDEX stackoverflow_to_ts_vector_GIN ON stackoverflow USING GIN(to_tsvector('english', title || body));



-- This function encapsulates the parsing of the user's search string. 
DROP FUNCTION search_query(search_string VARCHAR);
CREATE OR REPLACE FUNCTION search_query(search_string VARCHAR) RETURNS 
TABLE(id BIGINT, title VARCHAR, body VARCHAR, creationdate VARCHAR) AS
$$
SELECT id, title, body, creationdate
FROM stackoverflow
WHERE to_tsvector('english', title || body) @@ plainto_tsquery('english', search_string)
$$ LANGUAGE SQL;



-- Record Analysis: record count, blank title, non-blank title grouped by month
SELECT left(creationDate, 7) as "month", count(id)
, sum(case when title = '' then 1 else 0 end) as no_title
, sum(case when title = '' then 0 else 1 end) as has_title
FROM stackoverflow
GROUP BY left(creationDate, 7)
ORDER BY 1



-- This query displays the disk usage of all db objects related to this project
SELECT relname as db_object, relpages as num_pages 
, reltuples AS approximate_row_count
, pg_size_pretty(relpages::bigint*8*1024) AS disk_size
FROM pg_class
WHERE relname ilike 'stackoverflow%'
ORDER BY relpages DESC;


-- EXAMPLES
select * from search_query('apache kotlin')
select * from stackoverflow where body ilike '%apache%' and body ilike '%kotlin%'

DO $$
DECLARE
	v_ts TIMESTAMP;
	v_start_ts TIMESTAMP;
	v_stop_ts TIMESTAMP;
	v_repeat CONSTANT INT := 10;
	num_recs INT;
BEGIN
 	v_start_ts := clock_timestamp();
	SELECT count(*) INTO num_recs FROM search_query('apache');
	v_stop_ts := clock_timestamp();
	RAISE INFO 'search_query elapsed time(%): %', num_recs, (v_stop_ts - v_start_ts);	
	v_start_ts := clock_timestamp();
	SELECT count(*) INTO num_recs FROM stackoverflow WHERE body ILIKE '%apache%';
	v_stop_ts := clock_timestamp();
	RAISE INFO 'stackoverflow elapsed time(%): %', num_recs, (v_stop_ts - v_start_ts);
END 
$$;
