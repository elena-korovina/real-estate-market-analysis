/* ============================================================
   PROJECT: Real Estate Market Analysis
   FILE: 03_seasonality.sql

   PURPOSE:
   Анализ сезонности публикации и снятия объявлений
   на рынке недвижимости.

   BUSINESS QUESTIONS:

   1. В какие месяцы публикуется больше объявлений?
   2. В какие месяцы объекты снимаются с публикации?
   3. Как сезонность влияет на стоимость жилья
      и площадь объектов?

   AUTHOR: Elena Korovina
   ============================================================ */

WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
filtered_ids AS (
    SELECT id
    FROM real_estate.flats
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
              AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),

-- Подготовка данных для анализа сезонности.
-- Рассчитываются месяцы публикации и снятия объявлений.

valid_data AS (
    SELECT 
        a.id,
        a.first_day_exposition,
        a.days_exposition,
        a.last_price,
        f.total_area,
        (a.last_price / f.total_area) AS price_per_sqm,
        DATE_TRUNC('month', a.first_day_exposition)::date AS publish_month,
        CASE 
            WHEN a.days_exposition IS NOT NULL THEN 
                DATE_TRUNC('month', (a.first_day_exposition + (a.days_exposition * INTERVAL '1 day'))::date)
            ELSE NULL 
        END AS removal_month
    FROM real_estate.advertisement a
    JOIN real_estate.flats f ON a.id = f.id
    WHERE 
        a.last_price > 0 
        AND f.total_area > 0 
        AND a.id IN (SELECT id FROM filtered_ids)
        AND (
            (EXTRACT(YEAR FROM a.first_day_exposition) = 2014 AND EXTRACT(MONTH FROM a.first_day_exposition) = 12)
            OR (EXTRACT(YEAR FROM a.first_day_exposition) BETWEEN 2015 AND 2018)
            OR (EXTRACT(YEAR FROM a.first_day_exposition) = 2019 AND EXTRACT(MONTH FROM a.first_day_exposition) <= 5)
        )
),

-- Агрегация показателей по месяцам снятия объявлений.

monthly_publication AS (
    SELECT 
        EXTRACT(MONTH FROM publish_month)::int AS month_number,
        TO_CHAR(publish_month, 'Month') AS month_name,
        COUNT(*) AS ads_published,
        ROUND(AVG(price_per_sqm)) AS avg_price_sqm_pub,
        ROUND(AVG(total_area)) AS avg_area_pub
    FROM valid_data
    GROUP BY month_number, month_name
),
monthly_removal AS (
    SELECT 
        EXTRACT(MONTH FROM removal_month)::int AS month_number,
        TO_CHAR(removal_month, 'Month') AS month_name,
        COUNT(*) AS ads_removed,
        ROUND(AVG(price_per_sqm)) AS avg_price_sqm_rem,
        ROUND(AVG(total_area)) AS avg_area_rem
    FROM valid_data
    WHERE removal_month IS NOT NULL
    GROUP BY month_number, month_name
)

-- Сопоставление активности публикации
-- и снятия объявлений по месяцам.

SELECT 
    COALESCE(p.month_number, r.month_number) AS month_number,
    INITCAP(COALESCE(p.month_name, r.month_name)) AS month,
    p.ads_published,
    r.ads_removed,
    p.avg_price_sqm_pub,
    r.avg_price_sqm_rem,
    p.avg_area_pub,
    r.avg_area_rem
FROM monthly_publication p
FULL OUTER JOIN monthly_removal r
    ON p.month_number = r.month_number
ORDER BY month_number;
