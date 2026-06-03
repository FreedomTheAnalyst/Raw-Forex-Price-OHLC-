Select *
from eurusd_h4_;

create table eurusd_h4_string
like eurusd_h4_;

Select *
from eurusd_h4_string;

insert eurusd_h4_string
select *
from eurusd_h4_;

-- (STEP 1)--
 -- (CHECKING FOR DATA QUALITY)

-- Missing Values
   SELECT *
FROM eurusd_h4_string
WHERE '<OPEN>' IS NULL
   OR '<HIGH>' IS NULL
   OR '<LOW>' IS NULL
   OR '<CLOSE>' IS NULL;
   
   -- Invalid candles
SELECT *
FROM eurusd_h4_string
WHERE '<HIGH>' < '<LOW>'
   OR '<OPEN>' <= 0
   OR '<CLOSE>' <= 0;
   
   -- ( Replace '<DATE>' AND "<TIME>' TO Candle_time) 
SELECT 
    CAST('<DATE>' + ' ' + '<TIME>' AS DATETIME) AS candle_time
FROM eurusd_h4_string;

-- (Create candle_time in a SELECT query)

SELECT
    '<DATE>',
    '<TIME>',

    CAST(
        REPLACE('<DATE>', '.', '-') + ' ' + '<TIME>'
        AS DATETIME
    ) AS candle_time

FROM eurusd_h4_string;

-- (Add new column to the table, Then update it)

ALTER TABLE eurusd_h4_string
ADD candle_time DATETIME;

select *
from eurusd_h4_string;

UPDATE eurusd_h4_string
SET candle_time = CAST(
    CONCAT(REPLACE(`<DATE>`, '.', '-'), ' ', `<TIME>`)
    AS DATETIME
)
WHERE `<DATE>` IS NOT NULL
  AND `<TIME>` IS NOT NULL;
  
  -- (turn off safe mode)
  SET SQL_SAFE_UPDATES = 0;
  -- (turn on safe mode)
  SET SQL_SAFE_UPDATES = 1;
  
  -- (Check for Duplicate candles)
  
SELECT candle_time, COUNT(*) AS total
FROM eurusd_h4_string
GROUP BY candle_time
HAVING COUNT(*) > 1;

-- (Inspect the duplicates to see if they are exact same duplicates or partial duplicates)--

SELECT *
FROM eurusd_h4_string
WHERE candle_time = '2023-01-02 04:00:00';

-- (Create a clean deduplicated table)--

CREATE TABLE eurusd_h4_clean AS
SELECT *
FROM (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY candle_time
               ORDER BY candle_time
           ) AS rn
    FROM eurusd_h4_string
) x
WHERE rn = 1;

-- (Check if duplicates are gone)--

SELECT candle_time, COUNT(*) AS total
FROM eurusd_h4_clean
GROUP BY candle_time
HAVING COUNT(*) > 1;

-- (Count raw table)--

SELECT COUNT(*) AS raw_total
FROM eurusd_h4_string;

-- (Count clean table)--

SELECT COUNT(*) AS clean_total
FROM eurusd_h4_clean;

-- (Confirming if my raw table contains 3 duplicates)--

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT candle_time) AS unique_candle_times,
    COUNT(*) - COUNT(DISTINCT candle_time) AS duplicate_rows
FROM eurusd_h4_string;

-- (Check if every candle appears 3 times)

SELECT total, COUNT(*) AS number_of_timestamps
FROM (
    SELECT candle_time, COUNT(*) AS total
    FROM eurusd_h4_string
    GROUP BY candle_time
) x
GROUP BY total;

-- (Check errors on OHLC price)--

SELECT *
FROM eurusd_h4_clean
WHERE `<HIGH>` < `<OPEN>`
   OR `<HIGH>` < `<CLOSE>`
   OR `<HIGH>` < `<LOW>`
   OR `<LOW>` > `<OPEN>`
   OR `<LOW>` > `<CLOSE>`
   OR `<LOW>` > `<HIGH>`;
   
   -- (Check for uniqueness)--
   
   SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT candle_time) AS unique_candles,
    COUNT(*) - COUNT(DISTINCT candle_time) AS duplicate_count
FROM eurusd_h4_clean;
   
select *
from eurusd_h4_clean;

-- (DATA QUALITY ENDS HERE)--


-- (EURUSD_H4_FEATURES)--
-- (Candle_Direction, Candle_Range, Candle_Body, Upper_Wick, Lower_Wick, Previous_High, Previous_Low)--
-- (Previous_Close, Market_Structure, Trading_Session, Returns 1-4-12) --


CREATE TABLE eurusd_h4_features AS
SELECT
    candle_time,

    `<OPEN>`,
    `<HIGH>`,
    `<LOW>`,
    `<CLOSE>`,
    `<TICKVOL>`,
    `<VOL>`
    `<SPREAD>`,

    -- (Candle Direction) --
    CASE
        WHEN `<CLOSE>` > `<OPEN>` THEN 'Bullish'
        WHEN `<CLOSE>` < `<OPEN>` THEN 'Bearish'
        ELSE 'Doji'
    END AS candle_direction,

    -- (Candle Range) --
    (`<HIGH>` - `<LOW>`) AS candle_range,

    -- (Candle Body) --
    ABS(`<CLOSE>` - `<OPEN>`) AS candle_body,

    -- (Upper Wick) --
    (`<HIGH>` - GREATEST(`<OPEN>`, `<CLOSE>`)) AS upper_wick,

    -- (Lower Wick) --
    (LEAST(`<OPEN>`, `<CLOSE>`) - `<LOW>`) AS lower_wick,

    -- (Previous High) --
    LAG(`<HIGH>`, 1)
    OVER (ORDER BY candle_time) AS previous_high,

    -- (Previous Low) --
    LAG(`<LOW>`, 1)
    OVER (ORDER BY candle_time) AS previous_low,

    -- (Previous Close) --
    LAG(`<CLOSE>`, 1)
    OVER (ORDER BY candle_time) AS previous_close,

    -- (Market Structure) --
    CASE
        WHEN `<HIGH>` >
             LAG(`<HIGH>`, 1)
             OVER (ORDER BY candle_time)
        THEN 'Higher High'

        WHEN `<HIGH>` <
             LAG(`<HIGH>`, 1)
             OVER (ORDER BY candle_time)
        THEN 'Lower High'

        ELSE 'Equal High'
    END AS high_structure,

    CASE
        WHEN `<LOW>` >
             LAG(`<LOW>`, 1)
             OVER (ORDER BY candle_time)
        THEN 'Higher Low'

        WHEN `<LOW>` <
             LAG(`<LOW>`, 1)
             OVER (ORDER BY candle_time)
        THEN 'Lower Low'

        ELSE 'Equal Low'
    END AS low_structure,

    -- (Trading Session) --
    CASE
        WHEN HOUR(candle_time) BETWEEN 0 AND 7
        THEN 'Asian'

        WHEN HOUR(candle_time) BETWEEN 8 AND 12
        THEN 'London'

        WHEN HOUR(candle_time) BETWEEN 13 AND 21
        THEN 'New York'

        ELSE 'Off Session'
    END AS trading_session,

    -- (1 Candle Return) --
    (
        `<CLOSE>` -
        LAG(`<CLOSE>`, 1)
        OVER (ORDER BY candle_time)
    )
    /
    LAG(`<CLOSE>`, 1)
    OVER (ORDER BY candle_time)
    AS return_1,

    -- (4 Candle Return) --
    (
        `<CLOSE>` -
        LAG(`<CLOSE>`, 4)
        OVER (ORDER BY candle_time)
    )
    /
    LAG(`<CLOSE>`, 4)
    OVER (ORDER BY candle_time)
    AS return_4,

    -- (12 Candle Return) --
    (
        `<CLOSE>` -
        LAG(`<CLOSE>`, 12)
        OVER (ORDER BY candle_time)
    )
    /
    LAG(`<CLOSE>`, 12)
    OVER (ORDER BY candle_time)
    AS return_12,

    -- (Bullish Liquidity Sweep) --
    CASE
        WHEN `<LOW>` <
             LAG(`<LOW>`, 1)
             OVER (ORDER BY candle_time)

         AND `<CLOSE>` >
             LAG(`<LOW>`, 1)
             OVER (ORDER BY candle_time)

        THEN 'Bullish Sweep'

        ELSE NULL
    END AS bullish_sweep,

    -- (Bearish Liquidity Sweep) --
    CASE
        WHEN `<HIGH>` >
             LAG(`<HIGH>`, 1)
             OVER (ORDER BY candle_time)

         AND `<CLOSE>` <
             LAG(`<HIGH>`, 1)
             OVER (ORDER BY candle_time)

        THEN 'Bearish Sweep'

        ELSE NULL
    END AS bearish_sweep

FROM eurusd_h4_clean;

Select *
from eurusd_h4_features;

Select *
from eurusd_h4_clean;

Select *
from eurusd_h4_string;













  
  

   
   
   
