/*
SQL - Pep Chat Marketing Performance & MRR Dashboards

This script extracts data from multiple tables, performs calculations for marketing performance,
and calculates Monthly Recurring Revenue (MRR) to assess the success of various campaigns.
*/

-- Step 1: Extract data from campaigns, users, and subscriptions tables
WITH

-- Extract marketing spend and performance (impressions, clicks, cost)
cost_data AS (
    SELECT
        DATE,              -- Date of campaign activity
        CAMPAIGN,          -- Campaign name
        COST,              -- Daily cost of the campaign
        CLICKS,            -- Number of clicks on the campaign
        IMPRESSIONS        -- Number of impressions (views) of the campaign
    FROM SQLIII.RAW_DATA.CAMPAIGNS
),

-- Extract user signup data with the campaign they signed up from
users AS (
    SELECT
        signup_date,       -- The date the user signed up
        USER_ID,           -- Unique user identifier
        SIGNUP_CAMPAIGN    -- Campaign through which the user was acquired
    FROM SQLIII.RAW_DATA.USERS
), 

-- Combine subscription details with the campaign and signup date of the user
subscriptions AS (
    SELECT
        S.USER_ID,                    -- Unique user identifier
        U.SIGNUP_CAMPAIGN,            -- The campaign through which the user signed up
        U.signup_date,                -- The signup date of the user
        S.SUBSCRIPTION_ID,            -- Unique subscription identifier
        S.SUBSCRIPTION_TYPE,          -- The type of subscription (Monthly/Yearly)
        S.SUBSCRIPTION_START_DATE,    -- When the subscription started
        S.SUBSCRIPTION_END_DATE,      -- When the subscription ended (null if active)
        S.PLAN_PRICE                  -- Price of the subscription plan
    FROM SQLIII.RAW_DATA.SUBSCRIPTIONS S
    JOIN users U ON S.user_id = U.user_id  -- Join subscriptions with users to get campaign info
),

-- Step 2: Generate Monthly Recurring Revenue (MRR) for each month of 2024

-- Create a temporary table with all months in 2024 for calculating MRR
subscriptions_dates AS (
    SELECT
        D.DATE_MONTH,                 -- Each month in 2024
        S.USER_ID,                    -- Unique user identifier
        S.SIGNUP_CAMPAIGN,            -- The campaign through which the user signed up
        S.signup_date,                -- The date the user signed up
        S.SUBSCRIPTION_ID,            -- Unique subscription identifier
        S.SUBSCRIPTION_TYPE,          -- Subscription type (Monthly/Yearly)
        S.SUBSCRIPTION_START_DATE,    -- Subscription start date
        S.SUBSCRIPTION_END_DATE,      -- Subscription end date (null if active)
        S.PLAN_PRICE,                 -- Price of the subscription plan
        CASE WHEN (S.SUBSCRIPTION_START_DATE <= LAST_DAY(D.date_month)) 
             AND (S.SUBSCRIPTION_END_DATE >= LAST_DAY(D.date_month) OR S.SUBSCRIPTION_END_DATE IS NULL)
        THEN 1 ELSE NULL END AS is_active  -- Flag if subscription is active in the month
    FROM subscriptions S
    JOIN SQLIII.RAW_DATA.MONTHS D 
      ON (S.SUBSCRIPTION_START_DATE <= LAST_DAY(D.date_month))  -- Join subscriptions with months
),

-- Calculate the monthly payment for each subscription, prorating yearly subscriptions
subscription_payments AS (
    SELECT *,
        CASE WHEN is_active = 1 AND SUBSCRIPTION_TYPE = 'Monthly' THEN PLAN_PRICE
             WHEN is_active = 1 AND SUBSCRIPTION_TYPE = 'Yearly' THEN PLAN_PRICE / 12
             ELSE NULL
        END AS monthly_plan_price  -- Calculated monthly price based on subscription type
    FROM subscriptions_dates
),

-- Step 3: Calculate total MRR by campaign using cohorted data

-- Group subscription payments by the campaign the user signed up through
subscriptions_cohorted AS (
    SELECT 
        S.signup_date,                 -- The date the user signed up
        S.SIGNUP_CAMPAIGN,             -- The campaign through which the user signed up
        SUM(monthly_plan_price) AS total_mrr,    -- Total Monthly Recurring Revenue (MRR)
        SUM(IFF(S.SUBSCRIPTION_TYPE = 'Yearly', monthly_plan_price, 0)) AS yearly_subscriptions_mrr,
        SUM(IFF(S.SUBSCRIPTION_TYPE = 'Monthly', monthly_plan_price, 0)) AS monthly_subscriptions_mrr,
        COUNT(DISTINCT S.SUBSCRIPTION_ID) AS total_subscriptions  -- Total subscriptions
    FROM subscription_payments S 
    GROUP BY S.signup_date, S.SIGNUP_CAMPAIGN  -- Group by signup date and campaign
),

-- Step 4: Count the number of signups per campaign per day
users_agg AS (
    SELECT
        signup_date,                   -- The date the user signed up
        SIGNUP_CAMPAIGN,               -- Campaign through which the user signed up
        COUNT(user_id) AS signups      -- Total number of signups for each campaign
    FROM users
    GROUP BY signup_date, SIGNUP_CAMPAIGN  -- Group by date and campaign
),

-- Step 5: Combine cost data with user signups and MRR from subscriptions
cost_conversions AS (
    SELECT
        C.DATE,                        -- Date of campaign activity
        C.CAMPAIGN,                    -- Campaign name
        C.COST,                        -- Cost of the campaign
        C.CLICKS,                      -- Clicks for the campaign
        C.IMPRESSIONS,                 -- Impressions (views) for the campaign
        U.signups,                     -- Number of signups
        S.yearly_subscriptions_mrr,    -- MRR from yearly subscriptions
        S.monthly_subscriptions_mrr,   -- MRR from monthly subscriptions
        S.total_mrr::int AS total_mrr, -- Total MRR generated
        S.total_subscriptions           -- Total number of subscriptions
    FROM cost_data C 
    LEFT JOIN users_agg U ON C.DATE = U.signup_date AND C.CAMPAIGN = U.SIGNUP_CAMPAIGN
    LEFT JOIN subscriptions_cohorted S ON C.DATE = S.signup_date AND C.CAMPAIGN = S.SIGNUP_CAMPAIGN
)

-- Step 6: Retrieve final dataset, ordered by date and campaign
SELECT *
FROM cost_conversions
ORDER BY DATE, CAMPAIGN;
