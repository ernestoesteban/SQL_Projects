							--E-Commerce Data and Customer Retention Analysis with SQL

--1. Using the columns of “market_fact”, “cust_dimen”, “orders_dimen”, “prod_dimen”, “shipping_dimen”, Create a new table, named as “combined_table”.

SELECT  
mf.*, pd.Product_Category, pd.Product_Sub_Category, od.Order_Date, od.Order_Priority, sd.Ship_Date, sd.Ship_Mode, cd.Customer_Name, cd.Province, cd.Region, cd.Customer_Segment
INTO combined_table
FROM market_fact mf, orders_dimen od, prod_dimen pd, shipping_dimen sd, cust_dimen cd
WHERE
mf.Prod_ID = pd.Prod_ID and
mf.Ord_ID = od.Ord_ID and
mf.Ship_ID = sd.Ship_ID and
mf.Cust_ID = cd.Cust_ID;

--Optional 1. altering key columns as meaningful.

UPDATE combined_table SET Cust_ID = SUBSTRING(Cust_ID, PATINDEX('%[_]%', Cust_ID)+1, 5);
UPDATE combined_table SET Ord_ID =  SUBSTRING(Ord_ID, PATINDEX('%[_]%', Ord_ID)+1, 5);
UPDATE combined_table SET Prod_ID = SUBSTRING(Prod_ID, PATINDEX('%[_]%', Prod_ID)+1, 5);
UPDATE combined_table SET Ship_ID = SUBSTRING(Ship_ID, PATINDEX('%[_]%', Ship_ID)+1, 5);
ALTER TABLE combined_table ALTER COLUMN Cust_ID INT
ALTER TABLE combined_table ALTER COLUMN Ord_ID INT
ALTER TABLE combined_table ALTER COLUMN Prod_ID INT
ALTER TABLE combined_table ALTER COLUMN Ship_ID INT

--2. Find the top 3 customers who have the maximum count of orders.

SELECT TOP 3 Cust_ID, COUNT(Ord_ID) as order_count FROM combined_table
GROUP BY Cust_ID
ORDER BY COUNT(Ord_ID) DESC;


--3. Create a new column at combined_table as DaysTakenForShipping that contains the date difference of Order_Date and Ship_Date.

ALTER TABLE combined_table ADD DaysTakenForShipping AS DATEDIFF(DAY, Order_Date, Ship_Date);


--4. Find the customer whose order took the maximum time to get shipping.

SELECT TOP 1 Cust_ID, MAX(DaysTakenForShipping) as max_DaysTakenForShipping FROM combined_table
GROUP BY Cust_ID
ORDER BY MAX(DaysTakenForShipping) DESC


--5. Count the total number of unique customers in January and how many of them came back every month over the entire year in 2011

SELECT YEAR(Order_Date) AS 'Year', MONTH(Order_Date) AS 'Month', COUNT(DISTINCT Cust_ID) as Customer_Count
FROM combined_table 
WHERE YEAR(Order_Date) = 2011
AND Cust_ID IN (
SELECT  DISTINCT Cust_ID FROM combined_table
WHERE YEAR(Order_Date) = 2011 AND MONTH(Order_Date) = 1)
GROUP BY YEAR(Order_Date), MONTH(Order_Date);


--6. Write a query to return for each user the time elapsed between the first purchasing and the third purchasing, in ascending order by Customer ID.

WITH T1 AS(
SELECT Cust_ID, Order_Date,
COUNT(Order_Date) OVER(PARTITION BY Cust_ID) as 'order_number',
ROW_NUMBER() OVER(PARTITION BY Cust_ID ORDER BY Order_Date) as order_no
FROM combined_table),
T2 AS(
SELECT *,
DATEDIFF(DAY, LAG(Order_Date,2) OVER(PARTITION BY Cust_ID ORDER BY Order_Date), Order_Date) as diff
FROM T1
WHERE order_number > 2)
SELECT Cust_ID, diff FROM T2
WHERE order_no=3
ORDER BY Cust_ID


--7. Write a query that returns customers who purchased both product 11 and product 14, as well as the ratio of these products to the total number of products purchased by the customer.

WITH T_11 AS (
SELECT Cust_ID, Prod_ID,
SUM(Order_Quantity) OVER(PARTITION BY Cust_ID, Prod_ID) AS quantity_11 FROM combined_table WHERE Prod_ID = 11),
T_14 AS(
SELECT Cust_ID, Prod_ID,
SUM(Order_Quantity) OVER(PARTITION BY Cust_ID, Prod_ID) AS quantity_14 FROM combined_table WHERE Prod_ID = 14),
T_ALL AS(
SELECT DISTINCT Cust_ID, Prod_ID,
SUM(Order_Quantity) OVER(PARTITION BY Cust_ID) AS quantity_all FROM combined_table)
SELECT DISTINCT T_11.Cust_ID, CAST((T_11.quantity_11+T_14.quantity_14)/T_ALL.quantity_all AS DECIMAL(7,2)) as ratio FROM T_11, T_14, T_ALL
WHERE T_11.Cust_ID = T_14.Cust_ID AND T_11.Cust_ID = T_ALL.Cust_ID



--Customer Segmentation

--1. Create a “view” that keeps visit logs of customers on a monthly basis. (For each log, three field is kept: Cust_id, Year, Month)

CREATE OR ALTER VIEW [dbo].[visit_logs] AS
SELECT TOP 10000 Cust_ID, YEAR(Order_Date) 'Year', MONTH(Order_Date) 'Month' FROM combined_table
GROUP BY Cust_ID, YEAR(Order_Date), MONTH(Order_Date)
ORDER BY Cust_ID, YEAR(Order_Date), MONTH(Order_Date);

--2. Create a “view” that keeps the number of monthly visits by users. (Show separately all months from the beginning business)

CREATE OR ALTER VIEW [dbo].[visit_logs_aggregate] AS
SELECT TOP 100 Year, Month, COUNT(Cust_ID) as visit_count FROM visit_logs
GROUP BY Year, Month
ORDER BY Year, Month;


--3. For each visit of customers, create the next month of the visit as a separate column.

CREATE OR ALTER VIEW [dbo].next_visit AS
SELECT TOP 10000 Cust_ID, Year, Month, 
LEAD(Year) OVER(PARTITION BY Cust_ID ORDER BY Year, Month) as year_lead,
LEAD(Month) OVER(PARTITION BY Cust_ID ORDER BY Year, Month) as month_lead
FROM visit_logs
ORDER BY Cust_ID, Year, Month;


--4. Calculate the monthly time gap between two consecutive visits by each customer.

CREATE OR ALTER VIEW [dbo].gap AS
SELECT TOP 10000 Cust_ID, Year, Month, year_lead, month_lead,
((year_lead-Year)*12+(month_lead-Month)) as month_gap  
FROM next_visit
--WHERE ((year_lead-Year)*12+(month_lead-Month)) IS NOT NULL
ORDER BY Cust_ID;


--5. Categorise customers using average time gaps. Choose the most fitted labeling model for you.

SELECT Cust_ID, AVG(month_gap*1.0) as avg_gap, 
CASE 
	WHEN AVG(month_gap*1.0)=1 THEN 'retained'
    WHEN AVG(month_gap*1.0)>1 THEN 'lagger'
    WHEN AVG(month_gap*1.0) IS NULL THEN 'lost'
END AS cust_type
FROM gap GROUP BY Cust_ID
-- bir müþterinin birbirini takip eden 2 sipariþi arasýndaki ortalama ay farký



								--Month-Wise Retention Rate

--1. Find the number of customers retained month-wise. (You can use time gaps)

WITH cumulative_visits AS(
SELECT TOP 10000 Cust_ID,
       datediff(month, CAST('2009/01/01' AS DATE), Order_Date) AS visit_month
FROM combined_table
GROUP BY Cust_ID, datediff(month, CAST('2009/01/01' AS DATE), Order_Date)
ORDER BY 1,
         2),
next_visits AS(
SELECT Cust_ID, visit_month,
lead(visit_month) OVER(PARTITION BY Cust_ID ORDER BY Cust_ID, visit_month) as next_visit
FROM cumulative_visits),
source_table AS(
SELECT Cust_ID, visit_month, next_visit, (next_visit - visit_month) as gap, 
CASE 
	WHEN (next_visit - visit_month)=1 THEN 'retained'
    WHEN (next_visit - visit_month)>1 THEN 'lagger'
    WHEN (next_visit - visit_month) IS NULL THEN 'lost'
END AS cust_type
FROM next_visits)
SELECT visit_month, COUNT(Cust_ID) as retained_customer_count FROM source_table 
WHERE cust_type='retained'
GROUP BY visit_month 
ORDER BY visit_month;


--2. Calculate the month-wise retention rate.

WITH cumulative_visits AS(
SELECT TOP 10000 Cust_ID,
       datediff(month, CAST('2009/01/01' AS DATE), Order_Date) AS visit_month
FROM combined_table
GROUP BY Cust_ID, datediff(month, CAST('2009/01/01' AS DATE), Order_Date)
ORDER BY 1,
         2),
next_visits AS(
SELECT Cust_ID, visit_month,
lead(visit_month) OVER(PARTITION BY Cust_ID ORDER BY Cust_ID, visit_month) as next_visit
FROM cumulative_visits),
source_table AS(
SELECT Cust_ID, visit_month, next_visit, (next_visit - visit_month) as gap, 
CASE 
	WHEN (next_visit - visit_month)=1 THEN 'retained'
    WHEN (next_visit - visit_month)>1 THEN 'lagger'
    WHEN (next_visit - visit_month) IS NULL THEN 'lost'
END AS cust_type
FROM next_visits)
SELECT visit_month, 1.0*SUM(IIF(cust_type = 'retained', 1, 0))/COUNT(Cust_ID) as ratio FROM source_table 
GROUP BY visit_month 
ORDER BY visit_month;