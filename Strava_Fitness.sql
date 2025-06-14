-- SQL Data cleaning, Merging and Analysis. --
USE strava_fitness;
-- Set safe updates off for bulk operations
SET SQL_SAFE_UPDATES = 0;
------------------------------------------------------
-- dailyactivity dataset cleaning --
CREATE OR REPLACE VIEW cleaned_daily_activity AS
WITH deduplicated AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY Id, ActivityDate 
               ORDER BY 
                   CASE WHEN TotalSteps = 0 THEN 1 ELSE 0 END, -- Prioritize non-zero records
                   Calories DESC, -- Prefer higher calorie counts
                   TotalSteps DESC
           ) AS rn
    FROM dailyactivity
    WHERE ActivityDate IS NOT NULL
)
SELECT 
    Id,
    STR_TO_DATE(ActivityDate, '%m/%d/%Y') AS ActivityDate,
    -- Steps (0 only valid if full sedentary day)
    CASE 
        WHEN TotalSteps = 0 AND SedentaryMinutes >= 1400 THEN 0
        WHEN TotalSteps = 0 THEN NULL
        WHEN TotalSteps > 100000 THEN NULL -- Unrealistically high
        ELSE TotalSteps
    END AS TotalSteps,
    
  
    CASE 
        WHEN TotalDistance = 0 AND 
             (VeryActiveMinutes + FairlyActiveMinutes + LightlyActiveMinutes) > 0 THEN NULL
        ELSE TotalDistance
    END AS TotalDistance,
    
    -- Active distances
    NULLIF(VeryActiveDistance, 0) AS VeryActiveDistance,
    NULLIF(ModeratelyActiveDistance, 0) AS ModeratelyActiveDistance,
    NULLIF(LightActiveDistance, 0) AS LightActiveDistance,
    
    -- Activity minutes (validate with distances)
    CASE 
        WHEN VeryActiveMinutes = 0 AND VeryActiveDistance > 0 THEN NULL
        ELSE VeryActiveMinutes
    END AS VeryActiveMinutes,
    
    CASE 
        WHEN FairlyActiveMinutes = 0 AND ModeratelyActiveDistance > 0 THEN NULL
        ELSE FairlyActiveMinutes
    END AS FairlyActiveMinutes,
    
    LightlyActiveMinutes,
    
    -- Sedentary minutes (0 is invalid)
    CASE 
        WHEN SedentaryMinutes = 0 THEN 1440 -- Assume full day
        WHEN SedentaryMinutes > 1440 THEN 1440 -- Cap at 24hrs
        ELSE SedentaryMinutes
    END AS SedentaryMinutes,
    
    -- Calories (0 is invalid)
    NULLIF(Calories, 0) AS Calories,
    
    -- Data quality flags
    CASE 
        WHEN TotalSteps IS NULL OR Calories IS NULL THEN 'Partial'
        WHEN TotalSteps = 0 THEN 'Sedentary'
        ELSE 'Complete'
    END AS DataQuality
FROM deduplicated
WHERE rn = 1;
-----------------------------------------------------------------------------
-- sleepday dataset cleaning --
CREATE OR REPLACE VIEW cleaned_sleepday AS
WITH sleep_stats AS (
    SELECT 
        Id,
        AVG(TotalMinutesAsleep) AS avg_sleep,
        STDDEV(TotalMinutesAsleep) AS std_sleep
    FROM sleepday
    WHERE TotalMinutesAsleep BETWEEN 60 AND 900 -- Reasonable sleep duration
    GROUP BY Id
),
deduplicated AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY Id, SleepDay 
               ORDER BY TotalSleepRecords DESC
           ) AS rn
    FROM sleepday
    WHERE SleepDay IS NOT NULL
)
SELECT 
    s.Id,
    STR_TO_DATE(SleepDay, '%m/%d/%Y %h:%i:%s %p') AS SleepDate,
    s.TotalSleepRecords,
    CASE 
        WHEN s.TotalMinutesAsleep BETWEEN 60 AND 900 THEN s.TotalMinutesAsleep
        WHEN s.TotalMinutesAsleep > 900 THEN 900 -- Cap at 15 hours
        ELSE NULL
    END AS TotalMinutesAsleep,
    
    CASE 
        WHEN s.TotalTimeInBed BETWEEN 60 AND 1200 THEN s.TotalTimeInBed
        WHEN s.TotalTimeInBed > 1200 THEN 1200 -- Cap at 20 hours
        ELSE NULL
    END AS TotalTimeInBed,
    
    -- Sleep efficiency calculation
    CASE 
        WHEN s.TotalMinutesAsleep BETWEEN 60 AND 900 
             AND s.TotalTimeInBed BETWEEN 60 AND 1200
             AND s.TotalTimeInBed >= s.TotalMinutesAsleep
        THEN ROUND(s.TotalMinutesAsleep * 100.0 / s.TotalTimeInBed, 1)
        ELSE NULL
    END AS SleepEfficiency,
    
    -- Data quality flag
    CASE 
        WHEN s.TotalMinutesAsleep IS NULL OR s.TotalTimeInBed IS NULL THEN 'Invalid'
        WHEN ABS(s.TotalMinutesAsleep - stats.avg_sleep) > 3*stats.std_sleep THEN 'Outlier'
        ELSE 'Valid'
    END AS DataQuality
FROM deduplicated s
LEFT JOIN sleep_stats stats ON s.Id = stats.Id
WHERE rn = 1;
-------------------------------------------------------------------------------
-- weightloginfo dataset cleaning --
CREATE OR REPLACE VIEW cleaned_weightloginfo AS
WITH weight_stats AS (
    SELECT 
        Id,
        AVG(WeightKg) AS avg_weight,
        STDDEV(WeightKg) AS std_weight
    FROM weightloginfo
    WHERE WeightKg BETWEEN 30 AND 300
    GROUP BY Id
),
deduplicated AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY Id, Date 
               ORDER BY 
                   CASE WHEN IsManualReport = TRUE THEN 0 ELSE 1 END,
                   LogId DESC
           ) AS rn
    FROM weightloginfo
    WHERE Date IS NOT NULL
)
SELECT 
    w.Id,
    DATE(STR_TO_DATE(w.Date, '%c/%e/%Y %H:%i:%s')) AS MeasurementDate,  

    CASE 
        WHEN w.WeightKg BETWEEN 30 AND 300 THEN w.WeightKg
        ELSE NULL
    END AS WeightKg,

    CASE 
        WHEN w.WeightPounds BETWEEN 66 AND 660 THEN w.WeightPounds
        ELSE NULL
    END AS WeightPounds,

    CASE 
        WHEN w.Fat BETWEEN 1 AND 70 THEN w.Fat
        ELSE NULL
    END AS BodyFatPercentage,

    CASE 
        WHEN w.BMI BETWEEN 10 AND 60 THEN w.BMI
        ELSE NULL
    END AS BMI,

    w.IsManualReport,

    CASE 
        WHEN w.WeightKg IS NULL THEN 'Invalid Weight'
        WHEN ABS(w.WeightKg - stats.avg_weight) > 3*stats.std_weight THEN 'Outlier'
        WHEN w.BMI IS NOT NULL AND 
             (ABS((w.WeightKg / NULLIF((POWER(w.BMI/1.3, 0.5)), 0)) - 1) > 0.3) THEN 'Weight/BMI Mismatch'
        ELSE 'Valid'
    END AS DataQuality
FROM deduplicated w
LEFT JOIN weight_stats stats ON w.Id = stats.Id
WHERE rn = 1;
------------------------------------------------------------------------
-- heartrate_seconds dataset cleaning --
CREATE OR REPLACE VIEW cleaned_heartrate_seconds AS
WITH hr_stats AS (
    SELECT 
        Id,
        AVG(Value) AS avg_hr,
        STDDEV(Value) AS std_hr
    FROM heartrate_seconds
    WHERE Value BETWEEN 40 AND 220
    GROUP BY Id
),
valid_hr AS (
    SELECT 
        h.Id,
        STR_TO_DATE(h.Time, '%m/%d/%Y %h:%i:%s %p') AS TimeStamp,
        DATE(STR_TO_DATE(h.Time, '%m/%d/%Y %h:%i:%s %p')) AS ActivityDate,
        h.Value,
        s.avg_hr,
        s.std_hr
    FROM heartrate_seconds h
    LEFT JOIN hr_stats s ON h.Id = s.Id
    WHERE h.Time IS NOT NULL AND h.Value BETWEEN 40 AND 220
),
filtered_hr AS (
    SELECT *,
           CASE 
               WHEN ABS(Value - avg_hr) > 3 * std_hr THEN 'Outlier'
               ELSE 'Valid'
           END AS DataQuality
    FROM valid_hr
    WHERE avg_hr IS NOT NULL AND std_hr IS NOT NULL
)
SELECT
    Id,
    ActivityDate,
    MIN(Value) AS RestingHeartRate,   -- proxy for resting HR
    MAX(Value) AS MaxHeartRate,
    COUNT(*) AS HR_Samples,
    COUNT(CASE WHEN DataQuality = 'Valid' THEN 1 END) AS ValidSamples
FROM filtered_hr
GROUP BY Id, ActivityDate;
--------------------------------------------------------------------

-- hourlysteps
CREATE OR REPLACE VIEW cleaned_hourlysteps AS
SELECT 
    Id,
    STR_TO_DATE(ActivityHour, '%m/%d/%Y %H:%i:%s') AS ActivityHour,
    CASE WHEN StepTotal BETWEEN 0 AND 5000 THEN StepTotal ELSE NULL END AS Steps,
    'Valid' AS DataQuality
FROM hourlysteps
WHERE ActivityHour IS NOT NULL;

-- hourlycalories dataset cleaning --
CREATE OR REPLACE VIEW cleaned_hourlycalories AS
SELECT 
    Id,
    STR_TO_DATE(ActivityHour, '%m/%d/%Y %H:%i:%s') AS ActivityHour,
    CASE WHEN Calories BETWEEN 1 AND 1500 THEN Calories ELSE NULL END AS Calories,
    'Valid' AS DataQuality
FROM hourlycalories
WHERE ActivityHour IS NOT NULL;

-- hourlyintensities dataset cleaning --
CREATE OR REPLACE VIEW cleaned_hourlyintensities AS
SELECT 
    Id,
    STR_TO_DATE(ActivityHour, '%m/%d/%Y %H:%i:%s') AS ActivityHour,
    CASE WHEN TotalIntensity BETWEEN 0 AND 180 THEN TotalIntensity ELSE NULL END AS TotalIntensity,
    CASE WHEN AverageIntensity BETWEEN 0 AND 3 THEN AverageIntensity ELSE NULL END AS AverageIntensity,
    'Valid' AS DataQuality
FROM hourlyintensities
WHERE ActivityHour IS NOT NULL;


--  minute-level data cleaning --
CREATE OR REPLACE VIEW cleaned_minutecalorieswide AS
SELECT 
    Id,
    STR_TO_DATE(ActivityHour, '%m/%d/%Y %H:%i:%s') AS ActivityHour,
    CASE WHEN Calories00 BETWEEN 0 AND 50 THEN Calories00 ELSE NULL END AS Calories00,
    CASE WHEN Calories01 BETWEEN 0 AND 50 THEN Calories01 ELSE NULL END AS Calories01,
    -- Continue for all 60 minute columns...
    'Valid' AS DataQuality
FROM minutecalorieswide
WHERE ActivityHour IS NOT NULL;

------------------------------------------------------
-- merged view --
------------------------------------------------------

CREATE OR REPLACE VIEW merged_strava_daily_relaxed AS
SELECT 
    d.Id,
    d.ActivityDate,

    -- Daily activity
    d.TotalSteps,
    d.TotalDistance,
    d.VeryActiveMinutes,
    d.FairlyActiveMinutes,
    d.LightlyActiveMinutes,
    d.SedentaryMinutes,
    d.Calories,
    d.DataQuality AS ActivityDataQuality,

    -- Sleep
    s.TotalMinutesAsleep,
    s.TotalTimeInBed,
    s.SleepEfficiency,
    s.DataQuality AS SleepDataQuality,

    -- Weight
    CASE WHEN w.WeightKg BETWEEN 20 AND 300 THEN w.WeightKg ELSE NULL END AS WeightKg,
    w.WeightPounds,
    w.BodyFatPercentage,
    w.BMI,
    w.IsManualReport,
    w.WeightDataQuality,

    -- Heart rate (relaxed range)
    hr.RestingHeartRate,
    hr.MaxHeartRate,
    hr.HR_Samples,
    hr.ValidSamples,

    -- Hourly aggregates
    hs.TotalSteps AS HourlyStepsTotal,
    hc.TotalCalories AS HourlyCaloriesTotal,
    hi.TotalIntensitySum,
    hi.AverageIntensityAvg,

    -- Derived metrics
    CASE 
        WHEN d.VeryActiveMinutes + d.FairlyActiveMinutes + d.LightlyActiveMinutes + d.SedentaryMinutes > 0
        THEN ROUND(d.VeryActiveMinutes * 100.0 / 
              (d.VeryActiveMinutes + d.FairlyActiveMinutes + d.LightlyActiveMinutes + d.SedentaryMinutes), 1)
        ELSE NULL
    END AS PercentVeryActive,

    -- Overall data quality score
    CASE
        WHEN d.TotalSteps IS NOT NULL AND d.Calories IS NOT NULL THEN 'Good'
        WHEN d.TotalSteps IS NOT NULL THEN 'Partial'
        ELSE 'Poor'
    END AS OverallDataQuality

FROM cleaned_daily_activity d
LEFT JOIN cleaned_sleepday s 
    ON d.Id = s.Id AND d.ActivityDate = s.SleepDate
LEFT JOIN (
    SELECT *,
           CASE 
               WHEN WeightKg BETWEEN 20 AND 300 THEN 'Valid'
               ELSE 'Invalid'
           END AS WeightDataQuality
    FROM cleaned_weightloginfo
) w ON d.Id = w.Id AND d.ActivityDate = w.MeasurementDate
LEFT JOIN (
    SELECT 
        Id, ActivityDate,
        MIN(Value) AS RestingHeartRate,
        MAX(Value) AS MaxHeartRate,
        COUNT(*) AS HR_Samples,
        COUNT(Value) AS ValidSamples
    FROM (
        SELECT Id, DATE(STR_TO_DATE(Time, '%m/%d/%Y %h:%i:%s %p')) AS ActivityDate, Value
        FROM heartrate_seconds
        WHERE Value BETWEEN 30 AND 230
    ) AS hr_raw
    GROUP BY Id, ActivityDate
) hr ON d.Id = hr.Id AND d.ActivityDate = hr.ActivityDate
LEFT JOIN (
    SELECT Id, DATE(ActivityHour) AS ActivityDate, SUM(Steps) AS TotalSteps
    FROM cleaned_hourlysteps
    GROUP BY Id, DATE(ActivityHour)
) hs ON d.Id = hs.Id AND d.ActivityDate = hs.ActivityDate
LEFT JOIN (
    SELECT Id, DATE(ActivityHour) AS ActivityDate, SUM(Calories) AS TotalCalories
    FROM cleaned_hourlycalories
    GROUP BY Id, DATE(ActivityHour)
) hc ON d.Id = hc.Id AND d.ActivityDate = hc.ActivityDate
LEFT JOIN (
    SELECT 
        Id, 
        DATE(ActivityHour) AS ActivityDate, 
        SUM(TotalIntensity) AS TotalIntensitySum,
        AVG(AverageIntensity) AS AverageIntensityAvg
    FROM cleaned_hourlyintensities
    GROUP BY Id, DATE(ActivityHour)
) hi ON d.Id = hi.Id AND d.ActivityDate = hi.ActivityDate;


-- heartrate_seconds analysis --
SELECT 
    Id,
    DATE(STR_TO_DATE(Time, '%m/%d/%Y %h:%i:%s %p')) AS HR_Date,
    MIN(Value) AS RestingHeartRate,
    MAX(Value) AS MaxHeartRate,
    AVG(Value) AS AvgHeartRate,
    COUNT(*) AS TotalSamples
FROM heartrate_seconds
WHERE Value BETWEEN 30 AND 230
GROUP BY Id, DATE(STR_TO_DATE(Time, '%m/%d/%Y %h:%i:%s %p'))
ORDER BY HR_Date;

-- WeightKgInfo Analysis --
SELECT 
    w.Id,
    DATE(STR_TO_DATE(w.Date, '%m/%d/%Y %h:%i:%s %p')) AS MeasurementDate,
    
    -- Weight stats
    AVG(w.WeightKg) AS avg_weight,
    STDDEV(w.WeightKg) AS std_weight,
    
    -- BMI stats
    AVG(w.BMI) AS avg_bmi,
    STDDEV(w.BMI) AS std_bmi

FROM weightloginfo w
WHERE w.WeightKg BETWEEN 25 AND 300
  AND w.BMI BETWEEN 10 AND 60  -- Optional: filter unrealistic BMIs
GROUP BY w.Id, DATE(STR_TO_DATE(w.Date, '%m/%d/%Y %h:%i:%s %p'))
ORDER BY MeasurementDate;

-- Check view creation
SELECT * FROM merged_strava_daily;

-- Check for NULL values
SELECT 
    COUNT(*) AS total_records,
    COUNT(WeightKg) AS weight_records,
    COUNT(TotalMinutesAsleep) AS sleep_records,
    COUNT(HourlyStepsTotal) AS hourly_steps_records,
    COUNT(HourlyCaloriesTotal) AS hourly_calories_records,
    COUNT(RestingHeartRate) AS hr_records
FROM merged_strava_daily;

-- Check data quality distribution
SELECT 
    OverallDataQuality,
    COUNT(*) AS record_count,
    ROUND(COUNT(*)*100.0/(SELECT COUNT(*) FROM merged_strava_daily),1) AS percentage
FROM merged_strava_daily
GROUP BY OverallDataQuality;

------------------------------------------------------
-- Analysis Queries --
------------------------------------------------------
-- 1. Activity vs. Sleep with NULL handling
SELECT 
    CASE 
        WHEN TotalSteps IS NULL THEN 'No Step Data'
        WHEN TotalSteps < 5000 THEN 'Low Activity'
        WHEN TotalSteps BETWEEN 5000 AND 9999 THEN 'Moderate Activity'
        ELSE 'High Activity'
    END AS ActivityLevel,
    AVG(TotalMinutesAsleep) AS AvgSleepMinutes,
    COUNT(*) AS RecordCount
FROM merged_strava_daily
WHERE TotalMinutesAsleep IS NOT NULL
GROUP BY ActivityLevel;
-----------------------------------------------------------
-- 2. Weight vs. Activity with --
SELECT 
    CASE 
        WHEN WeightKg IS NULL THEN 'No Weight Data'
        WHEN WeightKg < 60 THEN 'Under 60kg'
        WHEN WeightKg BETWEEN 60 AND 80 THEN '60-80kg'
        ELSE 'Over 80kg'
    END AS WeightGroup,
    ROUND(AVG(TotalSteps)) AS AvgSteps,
    ROUND(AVG(Calories)) AS AvgCalories
FROM merged_strava_daily_relaxed
GROUP BY WeightGroup;
-----------------------------------------------------------------
-- 3. Hourly Patterns
SELECT 
    HOUR(ActivityHour) AS HourOfDay,
    AVG(Steps) AS AvgSteps,
    AVG(Calories) AS AvgCalories
FROM (
    SELECT 
        Id,
        ActivityHour,
        Steps,
        NULL AS Calories
    FROM cleaned_hourlysteps
    WHERE DataQuality = 'Valid'
    
    UNION ALL
    
    SELECT 
        Id,
        ActivityHour,
        NULL AS Steps,
        Calories
    FROM cleaned_hourlycalories
    WHERE DataQuality = 'Valid'
) AS combined_data
GROUP BY HOUR(ActivityHour)
ORDER BY HourOfDay;
-------------------------------------------------------------
-- 3. Daily Averages by User --
SELECT 
    ROUND(AVG(TotalSteps)) AS avg_steps,
    ROUND(AVG(Calories)) AS avg_calories,
    ROUND(AVG(TotalMinutesAsleep)) AS avg_sleep_minutes
FROM merged_strava_daily_relaxed
WHERE OverallDataQuality = 'Good' 
  AND SleepDataQuality = 'Valid';

-------------------------------------------------------------------
-- 4. Activity and Sleep Correlation --
SELECT 
    ROUND(AVG(TotalSteps)) AS avg_steps,
    ROUND(AVG(TotalMinutesAsleep)) AS avg_sleep
FROM merged_strava_daily_relaxed
WHERE TotalMinutesAsleep >= 420 
  AND SleepDataQuality = 'Valid';
--------------------------------------------------------------------
-- 5. Average Daily Metrics by Day of the Week--
SELECT 
    DAYNAME(ActivityDate) AS DayOfWeek,
    ROUND(AVG(TotalSteps)) AS avg_steps,
    ROUND(AVG(Calories)) AS avg_calories,
    ROUND(AVG(TotalMinutesAsleep)) AS avg_sleep_minutes
FROM merged_strava_daily_relaxed
WHERE SleepDataQuality = 'Valid'
GROUP BY DayOfWeek
ORDER BY FIELD(DayOfWeek, 'Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday');
-----------------------------------------------------------
-- 6. Users with Best Sleep Consistency --
SELECT 
    Id,
    COUNT(*) AS valid_days,
    ROUND(STDDEV(TotalMinutesAsleep)) AS sleep_stddev
FROM merged_strava_daily
WHERE SleepDataQuality = 'Valid'
GROUP BY Id
HAVING valid_days > 5
ORDER BY sleep_stddev ASC
LIMIT 10;
----------------------------------------------------------------
-- 7. Calories Burned vs Activity Minutes --
SELECT 
    VeryActiveMinutes + FairlyActiveMinutes + LightlyActiveMinutes AS TotalActiveMinutes,
    Calories
FROM merged_strava_daily
WHERE DataQuality = 'Complete';

-- 8. Average Resting and Maximum Heart Rate --
SELECT 
    ROUND(AVG(RestingHeartRate)) AS avg_resting_hr,
    ROUND(AVG(MaxHeartRate)) AS avg_max_hr
FROM merged_strava_daily
WHERE RestingHeartRate IS NOT NULL AND MaxHeartRate IS NOT NULL;
-------------------------------------------------
-- 9.High HR Days vs. Activity Levels--
SELECT 
    CASE 
        WHEN MaxHeartRate >= 160 THEN 'High HR'
        WHEN MaxHeartRate BETWEEN 120 AND 159 THEN 'Moderate HR'
        ELSE 'Low HR'
    END AS HR_Category,
    COUNT(*) AS days_count
FROM merged_strava_daily
WHERE MaxHeartRate IS NOT NULL
GROUP BY HR_Category;
--------------------------------------------------------------------------
-- 10. MaxHeartRate vs Calories correlation --
SELECT 
    ROUND((
        COUNT(*) * SUM(MaxHeartRate * Calories) - SUM(MaxHeartRate) * SUM(Calories)
    ) /
    SQRT((
        COUNT(*) * SUM(POWER(MaxHeartRate, 2)) - POWER(SUM(MaxHeartRate), 2)
    ) * (
        COUNT(*) * SUM(POWER(Calories, 2)) - POWER(SUM(Calories), 2)
    )), 3) AS max_hr_calories_corr
FROM merged_strava_daily
WHERE MaxHeartRate IS NOT NULL AND Calories IS NOT NULL;

------------------------------------------------------------------------------- END --------------------------------------------------------------------------------------------






