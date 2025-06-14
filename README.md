# Strava-Fitness-App-Data-Analysis
## Problem Statement
The objective of this project is to analyze and understand fitness behavior patterns using minute-level and daily data from the Strava Fitness App. By exploring metrics such as steps, calories, sleep, heart rate, and activity intensity, we aim to discover actionable insights that can help improve user performance, recovery, and overall wellness.

## Project Structure
This project is divided into three main components:

### SQL Analysis – /SQL/Strava_Fitness.sql
- Dataset Views: Cleaned and standardized 11 raw datasets using SQL views.

- Merging: Created a comprehensive merged view final merge dataset incorporating activity, sleep, heart rate, weight, and intensity data.

### Analysis Topics:

- Daily behavior summaries

- Weekday trends in calories, steps, and sleep

- Active minutes analysis

- Intensity vs. Calories

- Sleep vs. Steps and Recovery Patterns


## Power BI Dashboard – /PowerBI/strava_visuals.pbix
Interactive Visualizations:

- Weekly calories and steps

- Sleep quality trends

- Heart rate patterns vs. activity

- Calories burned by time and day

### User Behavior Insights:

- Compare user activity types

- Spot high- or low-engagement periods

- Highlight data quality differences

## Python Visualization – /Python/strava_analysis.ipynb
Data Used: Merged CSV from SQL view merged_strava_daily_relaxed

### Visual Insights:

- Scatter plot: Sleep Duration vs. Next Day Steps

- Correlation heatmap: Steps, Calories, Sleep Efficiency

- Analysis Goals:

- Understand how sleep impacts performance

- Examine how steps and calories interact

- Reveal sleep's limited but existing role in energy output

## Final Business Impact
- This project equips the Strava Fitness App with deep behavioral insights for its user base.
- By integrating multi-source data (activity, sleep, heart rate), we uncover:

- The importance of balancing performance with recovery

- The moderate correlation between steps and calories

- The weaker but relevant impact of sleep on daily activity

## Business Solutions:
- Smart goal recommendations based on sleep/activity history

- Personalized recovery notifications

- Weekly behavioral summaries

- AI-based wellness coaching models

With these enhancements, Strava can evolve from a tracker to a true personal wellness advisor, improving user engagement, retention, and long-term health outcomes.
