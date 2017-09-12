# Full Text Search (FTS) demo for PostgreSQL

This is a proof-of-concept for using PostgreSQL's native FTS capabilities. 

The dataset comes from Stackoverflow records accessed with their [data export tool](http://data.stackexchange.com/stackoverflow/query/new). 
I downloaded 1M records (50k records, one month at a time to guarantee uniqueness).

Import the data using your favorite method. 

# Schema
The `NOT NULL` and `DEFAULT ''` constraints are important because I don't want the index or the query to account for `NULL` values. 
This is a hard requirement to impose on some datasets, but I believe any project involving text searching needs this extra requirement.

```sql
DROP TABLE IF EXISTS stackoverflow;
CREATE TABLE stackoverflow(
	id BIGINT PRIMARY KEY
	, title VARCHAR NOT NULL DEFAULT ''
	, body VARCHAR  NOT NULL DEFAULT ''
	, creationDate VARCHAR
);
 ```
 
 # Indexing
 I used a `GIN` rather than `GIST` index because I prioritize lookup speed over insert/update speed. Also, space is not a significant
 enough concern in my use case. Notice this is a **functional index** on two columns (`title` and `body`). I don't have to create a
 separate column to store the searched values because my index handles this for me! This is a huge win for FTS.
 
 Note: this index will need to be  re-created each time a new column is added to the search space. Try to get this right the
 first time because `GIN` indexes take a long  time to build. 
 
 ```sql
CREATE INDEX stackoverflow_to_ts_vector_GIN ON stackoverflow USING GIN(to_tsvector('english', title || body));
```

# Searching
PostgreSQL FTS requires the query to use two special datatypes. The search value is converted into a `tsquery` and 
the underlying data is converted into a `tsvector`. There are special PostgreSQL functions that handle the conversion:
`to_tsvector()`, `to_tsquery()`, and `plainto_tsquery()` are the functions to use.

I wrote a `SQL` function that to handle the searching. This function accepts the `search_string` as a parameter and returns 
all the columns of the `stackoverflow` table. FTS querying is slightly different from traditional RDBMS querying. Writing a function 
this way allows devs unfamiliar with PostgreSQL to focus on other matters. It also standardizes the way the table is searched. 
PostgreSQL FTS has many fine-tuning capabilities (e.g. setting weights, using multiple languages). I prefer an environment where a DBA
can write an API for other devs to use rather that expecting all devs to be intimately familiar with all PostgreSQL features. It also
means queries don't have to be re-written as the FTS parameters change - only the underlying functions do!

Since this is simple proof-of-concept, I elected to use the `plainto_tsquery()` function. It converts all words in the `search_string` 
to a `tsquery`. Example: `"cat, dog, bird"::text` becomes `'cat' & 'dog' & 'bird'::tsquery`. FTS allows for `AND`, `OR`, `NOT`, etc 
logical operations. This example doesn't aim to get into those details. Every search term is treated equally and "`AND`ed" together.

```sql
DROP FUNCTION search_query(search_string VARCHAR);
CREATE OR REPLACE FUNCTION search_query(search_string VARCHAR) RETURNS 
TABLE(id BIGINT, title VARCHAR, body VARCHAR, creationdate VARCHAR) AS
$$
SELECT id, title, body, creationdate
FROM stackoverflow
WHERE to_tsvector('english', title || body) @@ plainto_tsquery('english', search_string)
$$ LANGUAGE SQL;
```

# Data Analysis
Run this on your machine and notice how many titles are blank. Imagine how many articles would be ignored if `NULL` titles 
are concatenated to article bodies!

```sql
-- Record Analysis: record count, blank title, non-blank tite grouped by month
SELECT left(creationDate, 7) as "month", count(id)
, sum(case when title = '' then 1 else 0 end) as no_title
, sum(case when title = '' then 0 else 1 end) as has_title
FROM stackoverflow
GROUP BY left(creationDate, 7)
ORDER BY 1
```

Also notice the size of the dataset. 1M rows of stackoverflow data takes 1.3 GB of disk space and the `GIN` index is about 500MB.
```sql
-- This query displays the disk usage of all db objects related to this project
SELECT relname as db_object, relpages as num_pages 
, reltuples AS approximate_row_count
, pg_size_pretty(relpages::bigint*8*1024) AS disk_size
FROM pg_class
WHERE relname ilike 'stackoverflow%'
ORDER BY relpages DESC;
```

# EXAMPLES
```sql
select * from search_query('apache kotlin')
select * from stackoverflow where body ilike '%apache%' and body ilike '%kotlin%'
```
