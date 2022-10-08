											--DETERMINER SYSTEM FOR DISCOUNT EFFECTS

--Following strategy was adopted for determining the discount effect according to the number of discount levels:
	-- discount effect determined as 'neutral' when only one discount level present
	-- simple comparison adopted when two discount levels present
	-- triple comparison adopted when three discount levels present
	-- nonparametric spearman's correlation coefficent adopted when four discount levels present

--discount levels were located
WITH discount_number as(
SELECT product_id, COUNT(DISTINCT discount) as discount_number FROM sale.order_item
GROUP BY product_id),

--total quantity by discount levels were calculated
discounts as(
SELECT DISTINCT product_id, discount, 
SUM(quantity) OVER(PARTITION BY product_id, discount) as total_quantity
FROM sale.order_item),

--lag 1 was calculated for products have 2 discount levels
lags1 as(
SELECT DISTINCT d.product_id,
d.total_quantity as lag0,
LAG(d.total_quantity) OVER(PARTITION BY d.product_id ORDER BY d.discount) as lag1
FROM discounts d, discount_number dn
WHERE d.product_id = dn.product_id and dn.discount_number = 2),

--lag 1 and 2 was calculated for products have 3 discount levels
lags2 as(
SELECT DISTINCT d.product_id,
d.total_quantity as lag0,
LAG(d.total_quantity) OVER(PARTITION BY d.product_id ORDER BY d.discount) as lag1,
LAG(d.total_quantity, 2) OVER(PARTITION BY d.product_id ORDER BY d.discount) as lag2
FROM discounts d, discount_number dn
WHERE d.product_id = dn.product_id and dn.discount_number = 3),

--discount effect was determined for products have 3 discount levels
discount_three as(
SELECT DISTINCT d.product_id,
CASE WHEN l2.lag0 > l2.lag1 and l2.lag1 > l2.lag2 THEN 'positive'
WHEN l2.lag0 < l2.lag1 and l2.lag1 < l2.lag2 THEN 'negative'
ELSE 'neutral'
END as discount_effect
FROM discounts d, discount_number dn, lags2 l2
WHERE d.product_id = dn.product_id and
d.product_id = l2.product_id and 
l2.lag2 is not null and
l2.lag1 is not null and
dn.discount_number = 3),

--discount effect was determined for products have 2 discount levels
discount_two as(
SELECT DISTINCT d.product_id,
CASE WHEN l1.lag0 > l1.lag1 THEN 'positive'
	WHEN l1.lag0 < l1.lag1 THEN 'negative'
	ELSE 'neutral'
END as discount_effect
FROM discounts d, discount_number dn, lags1 l1
WHERE d.product_id = dn.product_id and
d.product_id = l1.product_id and
l1.lag1 is not null and
dn.discount_number = 2),

--discount effect was determined for products only have 1 discount level
discount_one as(
SELECT DISTINCT d.product_id, 'neutral' as discount_effect
FROM discounts d, discount_number dn
WHERE d.product_id = dn.product_id and
dn.discount_number = 1),

--ranks were located for spearman's correlation
ranks as(
SELECT DISTINCT d.product_id, d.discount, d.total_quantity,
RANK() OVER(PARTITION BY d.product_id ORDER BY d.discount) as 'rank_discount',
RANK() OVER(PARTITION BY d.product_id ORDER BY d.total_quantity) +  (COUNT(*) OVER(PARTITION BY d.product_id, d.total_quantity ORDER BY d.total_quantity)-1)/2.0 as 'modified_rank_quantity'
FROM discounts d, discount_number dn
WHERE d.product_id = dn.product_id and dn.discount_number = 4),

--spearman's correlation was calculated
spearman as(
SELECT product_id, 
CASE WHEN COUNT(*)>1 THEN CAST(1-SUM(SQUARE(rank_discount-modified_rank_quantity))*1.00/(COUNT(*)*SQUARE(COUNT(*))-1)*1.00 AS DECIMAL(5,3)) 
ELSE -1 END as corr FROM ranks
GROUP BY product_id),

--discount effect was determined for products have 4 discount levels according to spearman's correlation
discount_four as(
SELECT product_id,
CASE WHEN corr > 0.9 THEN 'positive'
WHEN corr BETWEEN 0.6 and 0.9 THEN 'negative'
ELSE 'neutral'
END AS discount_effect
FROM spearman)

--all discount levels were merged
SELECT * FROM discount_one
UNION
SELECT * FROM discount_two
UNION
SELECT * FROM discount_three
UNION
SELECT * FROM discount_four;