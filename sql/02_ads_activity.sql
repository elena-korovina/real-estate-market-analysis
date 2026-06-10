/* ============================================================
   PROJECT: Real Estate Market Analysis
   FILE: 02_ads_activity.sql

   PURPOSE:
   Исследование времени активности объявлений и факторов,
   влияющих на скорость продажи недвижимости.

   BUSINESS QUESTIONS:

   1. Какие объекты продаются быстрее?
   2. Какие характеристики влияют на сроки продажи?
   3. Есть ли различия между Санкт-Петербургом
      и Ленинградской областью?

   AUTHOR: Elena Korovina
   ============================================================ */

-- Расчёт порогов для удаления выбросов:

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

-- Подготовка аналитической витрины:
-- объединение объявлений, объектов недвижимости
-- и справочников регионов.

prepared_data AS (
    SELECT 
        ad.id,
        ct.city,
        tp.type,
        fl.total_area,
        fl.rooms,
        fl.balcony,
        fl.ceiling_height,
        ad.last_price,
        ad.days_exposition,
        ROUND(ad.last_price / NULLIF(fl.total_area, 0)) AS price_per_sq_meter,
        CASE 
            WHEN ct.city = 'Санкт-Петербург' THEN 'СПб'
            ELSE 'ЛенОбл'
        END AS region,
        CASE 
            WHEN ad.days_exposition BETWEEN 1 AND 30 THEN 'до месяца'
            WHEN ad.days_exposition BETWEEN 31 AND 90 THEN 'до квартала'
            WHEN ad.days_exposition BETWEEN 91 AND 180 THEN 'до полугода'
            WHEN ad.days_exposition > 180 THEN 'более полугода'
            ELSE 'без данных'
        END AS activity_range
    FROM real_estate.advertisement ad
    JOIN real_estate.flats fl ON ad.id = fl.id
    JOIN real_estate.city ct ON fl.city_id = ct.city_id
    JOIN real_estate.type tp ON fl.type_id = tp.type_id
    WHERE fl.id IN (SELECT id FROM filtered_ids)
      AND tp.type = 'город'
      AND fl.total_area IS NOT NULL
      AND ad.last_price IS NOT NULL
      AND ad.days_exposition IS NOT NULL
),

-- Общее количество объявлений по регионам.

totals_by_region AS (
    SELECT region, COUNT(*) AS total_ads
    FROM prepared_data
    GROUP BY region
),

-- Расчёт итоговых метрик по сегментам активности.

aggregated AS (
    SELECT 
        pd.region,
        pd.activity_range,
        COUNT(*) AS ads_count,
        ROUND(100.0 * COUNT(*) / tr.total_ads, 2) AS percent_of_ads_per_region,
        ROUND(AVG(pd.price_per_sq_meter)) AS avg_price_per_sq_meter,
        ROUND(AVG(pd.total_area)::numeric, 1) AS avg_total_area,
        ROUND(AVG(pd.rooms)::numeric, 2) AS avg_rooms,
        ROUND(AVG(pd.balcony)::numeric, 2) AS avg_balconies,
        ROUND(AVG(pd.ceiling_height)::numeric, 2) AS avg_ceiling_height
    FROM prepared_data pd
    JOIN totals_by_region tr ON pd.region = tr.region
    GROUP BY pd.region, pd.activity_range, tr.total_ads
)

-- Итоговая таблица для визуализации в DataLens.

SELECT *
FROM aggregated
ORDER BY region, activity_range;
