/* ============================================================
   PROJECT: Real Estate Market Analysis
   FILE: 04_leningrad_region.sql

   PURPOSE:
   Сравнительный анализ населённых пунктов
   Ленинградской области.

   BUSINESS QUESTIONS:

   1. Где публикуется больше объявлений?
   2. Где выше доля закрытых объявлений?
   3. Где выше стоимость квадратного метра?
   4. Где недвижимость продаётся быстрее?

   AUTHOR: Elena Korovina
   ============================================================ */

WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit
    FROM real_estate.flats     
),
filtered_id AS (
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
),

-- Подготовка очищенного набора данных.

filtered_data AS (
    SELECT 
        a.id,
        a.last_price,
        a.days_exposition,
        f.total_area,
        f.city_id,
        f.type_id
    FROM real_estate.advertisement a
    JOIN real_estate.flats f ON a.id = f.id
    WHERE a.id IN (SELECT id FROM filtered_id)
      AND f.total_area IS NOT NULL
      AND a.last_price IS NOT NULL
),

-- Добавление географической информации.

data_with_location AS (
    SELECT 
        CASE 
            WHEN c.city = 'Кудрово' THEN 'Кудрово'
            ELSE c.city
        END AS locality_name,
        t.type AS locality_type,
        fd.last_price,
        fd.total_area,
        fd.days_exposition
    FROM filtered_data fd
    JOIN real_estate.city c ON fd.city_id = c.city_id
    JOIN real_estate.type t ON fd.type_id = t.type_id
    WHERE c.city != 'Санкт-Петербург'
),

-- Расчёт основных показателей по населённым пунктам.

agg_by_city AS (
    SELECT 
        locality_name,
        COUNT(*) AS total_ads,
        COUNT(CASE WHEN days_exposition IS NOT NULL THEN 1 END) AS sold_ads,
        ROUND(AVG((last_price / total_area)::numeric), 0) AS avg_price_per_sqm,
        ROUND(AVG(total_area)::numeric, 1) AS avg_area,
        ROUND(AVG(days_exposition)::numeric, 0) AS avg_days_exposition,
        ROUND(100.0 * COUNT(CASE WHEN days_exposition IS NOT NULL THEN 1 END) / COUNT(*), 2) AS sold_ratio_percent
    FROM data_with_location
    GROUP BY locality_name
),

-- Отбор населённых пунктов
-- с достаточным объёмом наблюдений.

filtered_cities AS (
    SELECT *
    FROM agg_by_city
    WHERE total_ads >= 30
)

-- Финальная таблица для анализа и визуализации.


SELECT *
FROM filtered_cities
ORDER BY total_ads DESC
LIMIT 15;
