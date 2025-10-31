-- Project: Crypto Exchange User Behavior Analysis
-- Author: Qowiyu Yusrizal
-- Purpose: Analyze funnel drop-off, retention, and trading patterns

-- 1. Create mock user table
CREATE TABLE IF NOT EXISTS users (
    user_id INT PRIMARY KEY,
    signup_date DATE,
    country VARCHAR(50),
    device_type VARCHAR(20), -- 'mobile', 'desktop'
    completed_kyc BOOLEAN
);

-- 2. Create mock trading activity
CREATE TABLE IF NOT EXISTS trades (
    trade_id INT PRIMARY KEY,
    user_id INT,
    trade_date DATE,
    trade_amount_usd DECIMAL(10,2),
    fee_usd DECIMAL(10,2),
    FOREIGN KEY (user_id) REFERENCES users(user_id)
);

-- Optional: small mock dataset for quick testing
INSERT INTO users (user_id, signup_date, country, device_type, completed_kyc) VALUES
(1, '2025-10-01', 'US', 'mobile', TRUE),
(2, '2025-10-02', 'US', 'desktop', FALSE),
(3, '2025-10-03', 'ID', 'mobile', TRUE),
(4, '2025-09-25', 'ID', 'desktop', TRUE),
(5, '2025-09-29', 'SG', 'mobile', FALSE)
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO trades (trade_id, user_id, trade_date, trade_amount_usd, fee_usd) VALUES
(1, 1, '2025-10-02', 500.00, 2.50),
(2, 1, '2025-10-10', 200.00, 1.00),
(3, 3, '2025-10-05', 1000.00, 5.00),
(4, 4, '2025-10-01', 50.00, 0.25)
ON CONFLICT (trade_id) DO NOTHING;

-- 3. Funnel drop-off: From signup → KYC → first trade (counts + rates)
WITH first_trade AS (
    SELECT user_id, MIN(trade_date) AS first_trade_date
    FROM trades
    GROUP BY user_id
)
SELECT
    COUNT(u.user_id) AS total_users,
    SUM(CASE WHEN u.completed_kyc THEN 1 ELSE 0 END) AS kyc_completed,
    ROUND(100.0 * SUM(CASE WHEN u.completed_kyc THEN 1 ELSE 0 END) / NULLIF(COUNT(u.user_id),0), 2) AS kyc_rate_pct,
    SUM(CASE WHEN ft.first_trade_date IS NOT NULL THEN 1 ELSE 0 END) AS traded_users,
    ROUND(100.0 * SUM(CASE WHEN ft.first_trade_date IS NOT NULL THEN 1 ELSE 0 END) / NULLIF(COUNT(u.user_id),0), 2) AS trade_rate_pct,
    ROUND(100.0 * SUM(CASE WHEN u.completed_kyc AND ft.first_trade_date IS NOT NULL THEN 1 ELSE 0 END) / NULLIF(SUM(CASE WHEN u.completed_kyc THEN 1 ELSE 0 END),0), 2) AS trade_among_kyc_pct
FROM users u
LEFT JOIN first_trade ft ON u.user_id = ft.user_id;

-- 4. Retention by device type (Day 7 & Day 30)
-- Determine each user's first trade and compare to signup date
WITH first_trades AS (
    SELECT u.user_id, u.device_type, u.signup_date, MIN(t.trade_date) AS first_trade_date
    FROM users u
    LEFT JOIN trades t ON t.user_id = u.user_id
    GROUP BY u.user_id, u.device_type, u.signup_date
)
SELECT
    device_type,
    COUNT(*) AS users,
    ROUND(AVG(CASE WHEN first_trade_date IS NOT NULL AND first_trade_date <= signup_date + INTERVAL '7 days' THEN 1.0 ELSE 0.0 END) * 100, 2) AS day7_retention_pct,
    ROUND(AVG(CASE WHEN first_trade_date IS NOT NULL AND first_trade_date <= signup_date + INTERVAL '30 days' THEN 1.0 ELSE 0.0 END) * 100, 2) AS day30_retention_pct
FROM first_trades
GROUP BY device_type
ORDER BY device_type;

-- 5. Average trades per user (by country) + avg trade size + total fees
SELECT 
    u.country,
    ROUND(CAST(COUNT(t.trade_id) AS NUMERIC) / NULLIF(COUNT(DISTINCT u.user_id),0), 4) AS avg_trades_per_user,
    ROUND(AVG(t.trade_amount_usd) FILTER (WHERE t.trade_id IS NOT NULL), 2) AS avg_trade_amount_usd,
    ROUND(SUM(t.fee_usd) FILTER (WHERE t.trade_id IS NOT NULL), 2) AS total_fees_usd,
    COUNT(DISTINCT CASE WHEN t.trade_id IS NOT NULL THEN u.user_id END) AS users_who_traded,
    COUNT(DISTINCT u.user_id) AS total_users
FROM users u
LEFT JOIN trades t ON u.user_id = t.user_id
GROUP BY u.country
ORDER BY avg_trades_per_user DESC;
