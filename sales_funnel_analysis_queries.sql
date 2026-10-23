-- GROUP A: FUNNEL SHAPE & LEAKAGE

-- Q1. What's the overall count and % of opportunities in each deal_stage?
SELECT
    deal_stage,
    COUNT(*) AS opportunity_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM sales_pipeline_cleaned
GROUP BY deal_stage
ORDER BY opportunity_count DESC;

-- Answer: Won leads with 4,238 deals (48%), Lost is 2,473 (28%), Engaging
-- 1,589 (18%), Prospecting 500 (6%). Most deals that enter the pipeline
-- do eventually get decided one way or another.


-- Q2. Of opportunities that reached Engaging, what % converted to Won vs Lost?
SELECT
    deal_stage,
    COUNT(*) AS count_,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM sales_pipeline_cleaned
WHERE deal_stage IN ('Won', 'Lost')
GROUP BY deal_stage;

-- Answer: 63.15% Won, 36.85% Lost once a deal is actually decided. This is
-- the real win rate to use everywhere else in the project.


-- Q3. Does the Engaging -> Won conversion rate change month over month?
SELECT
    DATE_TRUNC('month', engage_date) AS engage_month,
    COUNT(*) FILTER (WHERE deal_stage = 'Won') AS won,
    COUNT(*) FILTER (WHERE deal_stage = 'Lost') AS lost,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE deal_stage = 'Won')
        / NULLIF(COUNT(*) FILTER (WHERE deal_stage IN ('Won','Lost')), 0), 2
    ) AS won_pct
FROM sales_pipeline_cleaned
WHERE deal_stage IN ('Won', 'Lost')
GROUP BY engage_month
ORDER BY engage_month;

-- Answer: No clear trend up or down across 2017. The rate mostly wobbles
-- between roughly 55% and 68% month to month, so the leak isn't getting
-- worse over time. The very first (Oct 2016, only 7 deals) and last
-- (Dec 2017, 80 deals) months sit outside that band, but both are small
-- sample sizes at the edges of the dataset, not a real trend.


-- Q4. What's the average number of days from engage_date to close_date,
-- split by Won vs Lost?
SELECT
    deal_stage,
    ROUND(AVG(close_date - engage_date), 1) AS avg_days_to_close,
    MIN(close_date - engage_date) AS min_days,
    MAX(close_date - engage_date) AS max_days
FROM sales_pipeline_cleaned
WHERE deal_stage IN ('Won', 'Lost')
GROUP BY deal_stage;

-- Answer: Lost deals average 41.5 days, Won deals average 51.8 days. Won
-- deals actually take longer, the opposite of what I expected going in.
-- Lost deals seem to get killed off fast; Won deals go through more
-- back-and-forth before closing.


-- GROUP B: LEAD SOURCE IMPACT

-- Q5. What's the Won rate by lead_source?
SELECT
    ls.lead_source,
    COUNT(*) FILTER (WHERE sp.deal_stage IN ('Won','Lost')) AS decided_deals,
    COUNT(*) FILTER (WHERE sp.deal_stage = 'Won') AS won,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE sp.deal_stage = 'Won')
        / NULLIF(COUNT(*) FILTER (WHERE sp.deal_stage IN ('Won','Lost')), 0), 2
    ) AS won_pct
FROM sales_pipeline_cleaned sp
JOIN lead_sources_cleaned ls ON sp.opportunity_id = ls.opportunity_id
GROUP BY ls.lead_source
ORDER BY won_pct DESC;

-- Answer: Referral wins the most at 84.42%, then Partner 77.92%, Webinar
-- 66.02%. Organic Search, Outbound, and Paid Ads trail behind at 59.71%,
-- 40.64%, and 28.11%. Lead source clearly matters a lot.


-- Q6. What's the average lead_score for Won vs Lost vs still-open deals?
SELECT
    CASE
        WHEN sp.deal_stage IN ('Prospecting','Engaging') THEN 'Open'
        ELSE sp.deal_stage
    END AS outcome,
    ROUND(AVG(ls.lead_score), 1) AS avg_lead_score,
    COUNT(*) AS n
FROM sales_pipeline_cleaned sp
JOIN lead_sources_cleaned ls ON sp.opportunity_id = ls.opportunity_id
GROUP BY outcome
ORDER BY avg_lead_score DESC;

-- Answer: Won deals have the highest average lead score, confirming the
-- score is actually tracking real outcomes rather than being noise.


-- Q7. What's the average cost_per_lead by source, alongside Won rate?
SELECT
    ls.lead_source,
    ROUND(AVG(ls.cost_per_lead_inr), 0) AS avg_cost_per_lead,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE sp.deal_stage = 'Won')
        / NULLIF(COUNT(*) FILTER (WHERE sp.deal_stage IN ('Won','Lost')), 0), 2
    ) AS won_pct
FROM sales_pipeline_cleaned sp
JOIN lead_sources_cleaned ls ON sp.opportunity_id = ls.opportunity_id
GROUP BY ls.lead_source
ORDER BY won_pct DESC;

-- Answer: Referral is both cheap and effective. Paid Ads is expensive and
-- has the worst win rate. Referral and Paid Ads sit at opposite corners of
-- cost vs. performance.


-- Q8. What's the average days lead_created -> mql -> sql -> engage, by source?
SELECT
    ls.lead_source,
    ROUND(AVG(ls.mql_date - ls.lead_created_date), 1) AS avg_days_lead_to_mql,
    ROUND(AVG(ls.sql_date - ls.mql_date), 1) AS avg_days_mql_to_sql,
    ROUND(AVG(sp.engage_date - ls.sql_date), 1) AS avg_days_sql_to_engage
FROM sales_pipeline_cleaned sp
JOIN lead_sources_cleaned ls ON sp.opportunity_id = ls.opportunity_id
WHERE ls.lead_created_date IS NOT NULL
GROUP BY ls.lead_source
ORDER BY avg_days_lead_to_mql;

-- Answer: Funnel speed doesn't vary dramatically by source. Not a major
-- lever on its own, more of a supporting stat.


-- GROUP C: REP PERFORMANCE

-- Q9. Total Won deals and total close_value (revenue) per sales_agent
SELECT
    sales_agent,
    COUNT(*) FILTER (WHERE deal_stage = 'Won') AS deals_won,
    SUM(close_value) FILTER (WHERE deal_stage = 'Won') AS total_revenue
FROM sales_pipeline_cleaned
GROUP BY sales_agent
ORDER BY total_revenue DESC;

-- Answer: Darcel Schlecht brings in the most total revenue (₹11.5L, 349
-- wins) by far, mostly through volume rather than a standout win rate.


-- Q10. Win rate (%) per agent: Won / (Won + Lost)
SELECT
    sales_agent,
    COUNT(*) FILTER (WHERE deal_stage IN ('Won','Lost')) AS decided_deals,
    COUNT(*) FILTER (WHERE deal_stage = 'Won') AS won,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE deal_stage = 'Won')
        / NULLIF(COUNT(*) FILTER (WHERE deal_stage IN ('Won','Lost')), 0), 2
    ) AS win_rate_pct
FROM sales_pipeline_cleaned
GROUP BY sales_agent
ORDER BY win_rate_pct DESC;

-- Answer: Hayden Neloms tops the raw leaderboard at 70.39%. But raw win
-- rate alone doesn't say whether that's skill or just good leads, which
-- is what Q11 and the Python quality-adjusted model dig into.


-- Q11. Per-agent win rate broken down by lead_source (min 5 decided deals
-- per agent-source pair, to filter out noise from tiny samples)
SELECT
    sp.sales_agent,
    ls.lead_source,
    COUNT(*) FILTER (WHERE sp.deal_stage IN ('Won','Lost')) AS decided_deals,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE sp.deal_stage = 'Won')
        / NULLIF(COUNT(*) FILTER (WHERE sp.deal_stage IN ('Won','Lost')), 0), 2
    ) AS win_rate_pct
FROM sales_pipeline_cleaned sp
JOIN lead_sources_cleaned ls ON sp.opportunity_id = ls.opportunity_id
GROUP BY sp.sales_agent, ls.lead_source
HAVING COUNT(*) FILTER (WHERE sp.deal_stage IN ('Won','Lost')) >= 5
ORDER BY sp.sales_agent, win_rate_pct DESC;

-- Answer: On Outbound leads specifically (the hardest lead type to close),
-- Jonathan Berthelot leads at 58.46%, well above most peers who cluster
-- around 33-45%. This first suggested he was a hidden gem, though the
-- fuller quality-adjusted model built later in Python told a more complete
-- story (see main_analysis.ipynb) — this single-channel cut was a useful
-- starting signal but too narrow to be the final word on its own.


-- Q12. Per-agent average lead_score of the leads they were assigned
SELECT
    sp.sales_agent,
    ROUND(AVG(ls.lead_score), 1) AS avg_lead_score_assigned,
    COUNT(*) AS total_leads
FROM sales_pipeline_cleaned sp
JOIN lead_sources_cleaned ls ON sp.opportunity_id = ls.opportunity_id
GROUP BY sp.sales_agent
ORDER BY avg_lead_score_assigned DESC;

-- Answer: Hayden Neloms also gets the best average lead score (68.7), so
-- part of the raw leaderboard position in Q10 is explained by lead quality,
-- not just closing skill. This is exactly why the quality-adjusted model
-- was needed.


-- Q13. Win rate and revenue by manager and by regional_office
SELECT
    t.manager,
    COUNT(*) FILTER (WHERE sp.deal_stage IN ('Won','Lost')) AS decided_deals,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE sp.deal_stage = 'Won')
        / NULLIF(COUNT(*) FILTER (WHERE sp.deal_stage IN ('Won','Lost')), 0), 2
    ) AS win_rate_pct,
    SUM(sp.close_value) FILTER (WHERE sp.deal_stage = 'Won') AS total_revenue
FROM sales_pipeline_cleaned sp
JOIN sales_teams_cleaned t ON sp.sales_agent = t.sales_agent
GROUP BY t.manager
ORDER BY win_rate_pct DESC;

SELECT
    t.regional_office,
    COUNT(*) FILTER (WHERE sp.deal_stage IN ('Won','Lost')) AS decided_deals,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE sp.deal_stage = 'Won')
        / NULLIF(COUNT(*) FILTER (WHERE sp.deal_stage IN ('Won','Lost')), 0), 2
    ) AS win_rate_pct,
    SUM(sp.close_value) FILTER (WHERE sp.deal_stage = 'Won') AS total_revenue
FROM sales_pipeline_cleaned sp
JOIN sales_teams_cleaned t ON sp.sales_agent = t.sales_agent
GROUP BY t.regional_office
ORDER BY win_rate_pct DESC;

-- Answer: Manager Cara Losch's team has the best win rate (64.43%), but
-- Melvin Marxen's team brings in the most total revenue (₹22.5L) by
-- running more volume at a slightly lower rate. Same pattern by region:
-- West has the best win rate (63.94%), Central generates the most revenue
-- on the lowest win rate of the three. Volume and rate pull in different
-- directions and neither one alone tells the full story.


-- ============================================================
-- GROUP D: PRODUCT & ACCOUNT
-- ============================================================

-- Q14. Win rate and avg close_value by product
SELECT
    product,
    COUNT(*) FILTER (WHERE deal_stage IN ('Won','Lost')) AS decided_deals,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE deal_stage = 'Won')
        / NULLIF(COUNT(*) FILTER (WHERE deal_stage IN ('Won','Lost')), 0), 2
    ) AS win_rate_pct,
    ROUND(AVG(close_value) FILTER (WHERE deal_stage = 'Won'), 0) AS avg_close_value
FROM sales_pipeline_cleaned
GROUP BY product
ORDER BY win_rate_pct DESC;

-- Answer: Win rates sit in a narrow 60-65% band across all products, so
-- product isn't a major lever here. GTK 500 stands out with a much higher
-- average deal value but very low volume (25 deals) — a low-volume,
-- high-ticket outlier worth a one-line mention, not a deep dive.


-- Q15a. Which sector converts best?
SELECT
    a.sector,
    COUNT(*) FILTER (WHERE sp.deal_stage IN ('Won','Lost')) AS decided_deals,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE sp.deal_stage = 'Won')
        / NULLIF(COUNT(*) FILTER (WHERE sp.deal_stage IN ('Won','Lost')), 0), 2
    ) AS win_rate_pct
FROM sales_pipeline_cleaned sp
JOIN accounts_cleaned a ON sp.account = a.account
GROUP BY a.sector
ORDER BY win_rate_pct DESC;

-- Answer: Marketing converts best (64.85%), Finance worst (61.17%), but
-- the spread is narrow. A mild effect, not a headline finding.


-- Q15b. Does any agent specialize in a sector (highest volume also their
-- best or near-best win rate there)?
SELECT
    sp.sales_agent,
    a.sector,
    COUNT(*) FILTER (WHERE sp.deal_stage IN ('Won','Lost')) AS decided_deals,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE sp.deal_stage = 'Won')
        / NULLIF(COUNT(*) FILTER (WHERE sp.deal_stage IN ('Won','Lost')), 0), 2
    ) AS win_rate_pct
FROM sales_pipeline_cleaned sp
JOIN accounts_cleaned a ON sp.account = a.account
GROUP BY sp.sales_agent, a.sector
HAVING COUNT(*) FILTER (WHERE sp.deal_stage IN ('Won','Lost')) >= 5
ORDER BY sp.sales_agent, decided_deals DESC;

-- Answer: A few agents show real specialization — their highest-volume
-- sector is also their best or near-best win rate. Jonathan Berthelot in
-- Technology (71 deals, 73.24%), Versie Hillebrand in Medical (55 deals,
-- 74.55%), Maureen Marcano in Retail (39 deals, 76.92%). Worth one line in
-- the writeup, a secondary finding rather than the headline.

---------------------------------------------------------------
-- Overall takeaway
---------------------------------------------------------------
-- The biggest story from SQL is that raw performance numbers (Q9, Q10)
-- reward reps who get fed better leads, not necessarily the best closers.
-- Q11 and Q12 together first hinted at this gap using Outbound leads as a
-- proxy for "hard" leads. The full picture, adjusting for lead quality
-- across every deal instead of just one channel, was then built out in
-- Python (see main_analysis.ipynb) and is the real headline finding of
-- the whole project.
