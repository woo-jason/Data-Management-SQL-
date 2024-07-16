USE individual_project;

/*
 * Clean Population Source Table.
 */
 
 -- Remove commas from numeric fields.
UPDATE population_estimates_trimmed 
SET 
Population_1990 = REPLACE(Population_1990, ',', ''),
Population_2000 = REPLACE(Population_2000, ',', ''),
Population_2010 = REPLACE(Population_2010, ',', ''),
Population_2020 = REPLACE(Population_2020, ',', '');

-- Are there empty strings in the columns?
select * from population_estimates_trimmed where rural_urban_code_2013 = '';
select * from population_estimates_trimmed where population_1990 = '';
select * from population_estimates_trimmed where population_2000 = '';
select * from population_estimates_trimmed where population_2010 = '';
select * from population_estimates_trimmed where population_2020 = '';

-- Change the empty strings to nulls.
update population_estimates_trimmed 
SET rural_urban_code_2013 = null where rural_urban_code_2013 = '';
update population_estimates_trimmed
set population_1990 = null where population_1990 = '';
update population_estimates_trimmed
set population_2000 = null where population_2000 = '';
update population_estimates_trimmed
set population_2010 = null where population_2010 = '';
update population_estimates_trimmed
set population_2020 = null where population_2020 = '';

-- Add Geo_Level to populationsestimates_trimmed, so we can use this
-- most complete list of counties and states to build geo_codes.
-- Comment out ALTER TABLE if rerunning the script.
ALTER TABLE population_estimates_trimmed 
ADD Geo_Level VARCHAR(12);

update population_estimates_trimmed
set geo_level = null;
update population_estimates_trimmed
set Geo_Level = 'COUNTRY' WHERE (FIPStxt % 1000 = 0) AND (State ='US');
update population_estimates_trimmed
set Geo_Level = 'STATE' WHERE (FIPStxt % 1000 = 0) AND (State != 'US');
update population_estimates_trimmed
set Geo_Level = 'COUNTY' WHERE FIPStxt % 1000 != 0;

-- Add State_ANSI and County_ANSI to populationsestimates_trimmed, 
-- so it will be easier to build geo_codes and population.
-- Comment out ALTER TABLE commands if rerunning the script.
ALTER TABLE population_estimates_trimmed 
ADD State_ANSI INTEGER;

ALTER TABLE population_estimates_trimmed
ADD County_ANSI INTEGER;

update population_estimates_trimmed 
set State_ANSI = FLOOR(FIPStxt/1000);

update population_estimates_trimmed
SET COunty_ANSI = FIPStxt%1000;

-- Quick check that we created State_ANSI and Count_ANSI correctly.
SELECT FIPStxt, State_ANSI, County_ANSI FROM population_estimates_trimmed
WHERE State_ANSI*1000+County_ANSI != Fipstxt;

/*
 * Drop existing target tables in correct order to re-create them.
 */

-- Drop tables with foreign keys first and then the tables they reference.
DROP TABLE IF EXISTS population;
DROP TABLE IF EXISTS Bee_Colonies;
DROP TABLE IF EXISTS geo_codes;
DROP TABLE IF EXISTS ag_codes;

/*
 * Create Geo_Codes.
 */

CREATE TABLE Geo_Codes (
	Geo_Level    VARCHAR(12),
    State_ANSI   INTEGER,
    County_ANSI  INTEGER,
    State        VARCHAR(2),
    Area_Name    VARCHAR(50),
    PRIMARY KEY (State_ANSI, County_ANSI));

INSERT INTO Geo_Codes
SELECT DISTINCT Geo_Level, State_ANSI, County_ANSI, State, Area_Name 
FROM population_estimates_trimmed;

/*
 * Create Population.
 */
 
 -- Population must be created after the table that the foreign key references.

CREATE TABLE population (
    State_ANSI INTEGER,
    County_ANSI INTEGER,
    Rural_Urban_Code_2013 INTEGER,
	Population_1990 INTEGER,
    Population_2000 INTEGER,
    Population_2010 INTEGER,
    Population_2020 INTEGER,
    PRIMARY KEY(State_ANSI, County_ANSI),
    FOREIGN KEY(State_ANSI, County_ANSI) 
		REFERENCES geo_codes(State_ANSI, County_ANSI));
        
INSERT INTO population 
SELECT State_ANSI, County_ANSI, Rural_Urban_Code_2013, 
Population_1990, Population_2000, Population_2010, Population_2020 
FROM population_estimates_trimmed;

/*
 * Clean Bee Colonies County Source Table.
 */

-- Checking out bee_colonies_county_column_subset.
-- Check for D in value column.  D means that the value is withheld/secret.
-- Check for empty strings in County_ANSI.  We are converting this field to
-- an integer.
SELECT COUNT(*) FROM bee_colonies_county_column_subset WHERE Value LIKE '%D%';
SELECT * FROM bee_colonies_county_column_subset WHERE County_ANSI = '';

-- Changing missing County_ANSI value to null
Update bee_colonies_county_column_subset 
set County_Ansi = null
WHERE County_ANSI = '';

-- Changing the D value to null
Update bee_colonies_county_column_subset
set value = null WHERE value LIKE '%D%';

-- Removing commas from the value column
Update bee_colonies_county_column_subset
set value = REPLACE(value, ',', '');

-- Missing County_ANSI values will cause the insert into bee_colonies
-- to fail.  Having noticed the the area names in Geo_Codes are longer and
-- contain the county names in bee_colonies_county_column_subset, let's
-- explore if updating the COUNTY_ANSI with data from Geo_Codes looks right.
SELECT * 
FROM Geo_Codes JOIN 
	(SELECT * 
     FROM Bee_Colonies_County_Column_Subset 
     WHERE County_ANSI IS NULL) B
ON Geo_Codes.State_ANSI = B.State_ANSI AND
	Area_Name LIKE CONCAT('%', B.County, '%');

-- The answer to the previous query shows the correct information,
-- so update the null County_ANSI values in Bee_Colonies_County_Column_Subset.
-- This fixes the Alaska problem.  This is an update with a correlated
-- subquery.
UPDATE Bee_Colonies_County_Column_Subset 
SET County_ANSI = 
	(SELECT Geo_Codes.County_ANSI 
     FROM Geo_Codes
     WHERE Geo_Codes.State_ANSI = Bee_Colonies_County_Column_Subset.State_ANSI
		AND Geo_Codes.Area_Name LIKE 
		CONCAT('%', Bee_Colonies_County_Column_Subset.County, '%'))
WHERE County_ANSI IS NULL;

/*
 * Create the Ag_Codes Table from Bee_Colonies_County_Column_Subset.
 */
 
CREATE TABLE Ag_Codes (
    State_ANSI			INTEGER,
	Ag_District_Code 	INTEGER,
	Ag_District 		VARCHAR(50),
    PRIMARY KEY (State_ANSI, Ag_District_Code));

-- We need DISTINCT, because these fields are duplciated in 
-- Bee_Colonies_County_Column_Subset for each year.
INSERT INTO Ag_Codes
SELECT DISTINCT State_ANSI, Ag_District_Code, Ag_District 
FROM bee_colonies_county_column_subset;

/*
 * Create the Bee_Colonies Table and insert the relevant tuples from
 * Bee_Colonies_County_Column_Subset.
 */
 CREATE TABLE Bee_Colonies (
    State_ANSI INTEGER,
	County_ANSI INTEGER,
    Ag_District_Code INTEGER,
    Colonies_2002 INTEGER,
    Colonies_2007 INTEGER,
    Colonies_2012 INTEGER,
    Colonies_2017 INTEGER,
    PRIMARY KEY(State_ANSI, County_ANSI),
    FOREIGN KEY(State_ANSI, County_ANSI) 
		REFERENCES Geo_Codes(State_ANSI, County_ANSI),
    FOREIGN KEY(State_ANSI, Ag_District_Code) 
		REFERENCES Ag_Codes(State_ANSI, Ag_District_Code));

-- State_ANSI, County_ANSI and Year were read in as text.  We are
-- changing them to integer to make sure they are cleaned up and
-- ready for the INSERT, and so we can add a index.
-- Comment out ALTER TABLE commands if rerunning the script.
ALTER TABLE Bee_Colonies_County_Column_Subset 
	CHANGE State_ANSI State_ANSI INTEGER;
ALTER TABLE Bee_Colonies_County_Column_Subset 
	CHANGE County_ANSI County_ANSI INTEGER;
ALTER TABLE Bee_Colonies_County_Column_Subset 
	CHANGE Year Year INTEGER;

-- Create the framework for the pivot that creates the
-- the columns of values for colonies number for each year.
-- The framework is one tuple per county for attributes other
-- than the columns of colony numbers.
INSERT INTO Bee_Colonies(State_ANSI, County_ANSI, Ag_District_Code)
SELECT DISTINCT State_ANSI, County_ANSI, Ag_District_Code
FROM bee_colonies_county_column_subset;

-- Create an index exist to make the update of the 
-- colony counts faster.  We will drop this index after the update,
-- so the script can be re-run without change.

CREATE INDEX subquery_idx 
ON Bee_Colonies_County_Column_Subset(State_ANSI, County_ANSI, Year);

-- Run an update with correlated subquery to fill in the column
-- of colony counts for each year.  Doing this one year at a time.
UPDATE Bee_Colonies 
SET Colonies_2002 = (
	SELECT Value 
    FROM bee_colonies_county_column_subset B 
    WHERE Bee_Colonies.State_ANSI = B.State_ANSI AND
		  Bee_Colonies.County_ANSI = B.County_ANSI AND
          Year = 2002);
          
UPDATE Bee_Colonies 
SET Colonies_2007 = (
	SELECT Value 
    FROM bee_colonies_county_column_subset B 
    WHERE Bee_Colonies.State_ANSI = B.State_ANSI AND
		  Bee_Colonies.County_ANSI = B.County_ANSI AND
          Year = 2007);
          
UPDATE Bee_Colonies 
SET Colonies_2012 = (
	SELECT Value 
    FROM bee_colonies_county_column_subset B 
    WHERE Bee_Colonies.State_ANSI = B.State_ANSI AND
		  Bee_Colonies.County_ANSI = B.County_ANSI AND
          Year = 2012);

UPDATE Bee_Colonies 
SET Colonies_2017 = (
	SELECT Value 
    FROM bee_colonies_county_column_subset B 
    WHERE Bee_Colonies.State_ANSI = B.State_ANSI AND
		  Bee_Colonies.County_ANSI = B.County_ANSI AND
          Year = 2017);
          
-- Drop the index.
DROP INDEX subquery_idx 
ON Bee_Colonies_County_Column_Subset;

/*
 * Clean Bee Colonies State Source Table.
 */

-- We need Ag_District_Code and County_ANSI for bee_colonies, let's
-- check their values and then clean them.
SELECT * FROM bee_colonies_state_column_subset WHERE Ag_District_Code = '';
SELECT * FROM bee_colonies_state_column_subset WHERE County_ANSI = '';

-- These columns are empty strings, so let's change Ag_District_Code to null
-- since Ag_District_Code does not apply at the state level.  Change  
-- County_ANSI to 0, because the instructions indicate County_ANSI is 0
-- for states.

Update bee_colonies_state_column_subset 
set Ag_District_Code = null
WHERE Ag_District_Code = '';

Update bee_colonies_state_column_subset 
set County_ANSI = 0
WHERE County_ANSI = '';

-- Remove commas from the value field.  No need to look for (D) in value,
-- because (D) is only used to suppress county numbers.
Update bee_colonies_state_column_subset 
set value = REPLACE(value, ',', '');

-- State_ANSI, County_ANSI and Year were read in as text.  We are
-- changing them to integer to make sure they are cleaned up and
-- ready for the INSERT.
-- Comment out ALTER TABLE commands if rerunning the script.
ALTER TABLE Bee_Colonies_State_Column_Subset 
	CHANGE State_ANSI State_ANSI INTEGER;
ALTER TABLE Bee_Colonies_State_Column_Subset 
	CHANGE County_ANSI County_ANSI INTEGER;
ALTER TABLE Bee_Colonies_State_Column_Subset 
	CHANGE Year Year INTEGER;

-- Create the framework for the pivot that creates the
-- the columns of values for colonies number for each year.
-- The framework is one tuple per state for attributes other
-- than the columns of colony numbers.
INSERT INTO Bee_Colonies(State_ANSI, County_ANSI, Ag_District_Code)
SELECT DISTINCT State_ANSI, County_ANSI, Ag_District_Code
FROM bee_colonies_state_column_subset;

-- Run an update with correlated subquery to fill in the column
-- of colony counts for each year.  Doing this one year at a time.
UPDATE Bee_Colonies 
SET Colonies_2002 = (
	SELECT Value 
    FROM bee_colonies_state_column_subset B 
    WHERE Bee_Colonies.State_ANSI = B.State_ANSI AND
		  Bee_Colonies.County_ANSI = B.County_ANSI AND
          Year = 2002)
WHERE Colonies_2002 IS NULL;
          
UPDATE Bee_Colonies 
SET Colonies_2007 = (
	SELECT Value 
    FROM bee_colonies_state_column_subset B 
    WHERE Bee_Colonies.State_ANSI = B.State_ANSI AND
		  Bee_Colonies.County_ANSI = B.County_ANSI AND
          Year = 2007)
WHERE Colonies_2007 IS NULL;
          
UPDATE Bee_Colonies 
SET Colonies_2012 = (
	SELECT Value 
    FROM bee_colonies_state_column_subset B 
    WHERE Bee_Colonies.State_ANSI = B.State_ANSI AND
		  Bee_Colonies.County_ANSI = B.County_ANSI AND
          Year = 2012)
WHERE Colonies_2012 IS NULL;

UPDATE Bee_Colonies 
SET Colonies_2017 = (
	SELECT Value 
    FROM bee_colonies_state_column_subset B 
    WHERE Bee_Colonies.State_ANSI = B.State_ANSI AND
		  Bee_Colonies.County_ANSI = B.County_ANSI AND
          Year = 2017)
WHERE Colonies_2017 IS NULL;

/*
 * Data Cleaning and Integration, and Table Creation are complete.
 */
 
 /*
  * Question 3: What are the geographic codes for Middlesex County, NJ?
  */
 
 Select * 
 FROM Geo_Codes
 WHERE State = 'NJ' and Area_Name = 'Middlesex County';
 
 /* 
  *  Question 4: Using the code for the State of New Jersey retreived 
  *  in the previous query, list all the bee_colony data for each 
  *  County_ANSI for the State of NJ in descending order by the
  *  number of colonies in 2017.
  *
  *  Note:  County_ANSI > 0 restricts this answer to counties in NJ.
  *         Not adding that to WHERE results in the state aggregate
  *         being included as well which is okay.
  */
  
  SELECT County_ANSI, Colonies_2002, Colonies_2007, Colonies_2012, Colonies_2017
  FROM bee_colonies
  WHERE State_ANSI = 34 AND County_ANSI > 0
  ORDER BY Colonies_2017 DESC;
  
/*
  *  Question 5:  What are the 2-letter state abbreviations, 
  *  state names, populations of states for the years available
  *  in descending order by the population in 2020?  Format 
  *  the population counts to have commas for readability by using 
  *  the FORMAT function but be sure the column names for the columns
  *  match the attribute names.  List only the first 12 rows of the
  *  answer by using LIMIT 12 at the end of the query. 
  * 
  * Note:  You need to qualify Population_2020 with the table name
  *        to use the numeric value rather than the formatted value
  *        you created in the SELECT with the same name.  An
  *        acceptable alternative is to add a second underscore to
  *        the names after AS in SELECT or make some other minor
  *        change to the new names.
  *
  * Note2: I use NATURAL JOIN throughout, because the attributes
  *        that need to be matched in each join have the same names,
  *        and the only attributes with the same names are the ones
  *        that need to be matched.
  */
 
 SELECT State, Area_Name, 
	FORMAT(Population_1990,0) AS Population_1990,
	FORMAT(Population_2000,0) AS Population_2000, 
	FORMAT(Population_2010,0) AS Population_2010,
	FORMAT(Population_2020,0) AS Population_2020
 FROM Population NATURAL JOIN Geo_Codes
 WHERE Geo_Level = 'State'
 ORDER BY Population.Population_2020 DESC LIMIT 12;
 
 -- Alternative using INNER JOIN.
 
SELECT State, Area_Name, 
	FORMAT(Population_1990,0) AS Population_1990,
	FORMAT(Population_2000,0) AS Population_2000, 
	FORMAT(Population_2010,0) AS Population_2010,
	FORMAT(Population_2020,0) AS Population_2020
FROM Population INNER JOIN Geo_Codes
ON Population.State_ANSI = Geo_Codes.State_ANSI
	AND Population.County_ANSI = Geo_Codes.County_ANSI
	WHERE Geo_Level = 'State'
	ORDER BY Population.Population_2020 DESC LIMIT 12;
 
 /*
 * Question 6: How many counties are there in the US with Green 
 * in their name?  Since no states have Green in their names, you
 * could drop AND Geo_Level = 'County' from the query below.  Since
 * Geo_Codes contains only one tuple per county, no DISTINCT is
 * necessary.  In fact, using DISTINCT with area_name is incorrect,
 * because some different counties have exactly the same name.
 */
 SELECT COUNT(*) AS 'Counties with Green in Name'
FROM Geo_Codes 
 WHERE Area_Name LIKE '%Green%'
 AND Geo_Level = 'County';
  
/*
 *  Question 7: What is the Ag_District_Code, Ag_District Name,
 *  and total bee colonies for each year for each
 *  agricultural district in NJ.
 *
 *  Note:  Since Ag_District functionally depends on Ag_District_Code,
 *         it is not strictly necessary in the GROUP BY to be incuded after
 *         SELECT.
 */
 
 SELECT Ag_District_Code, Ag_District, 
	SUM(Colonies_2002), SUM(Colonies_2007), 
    SUM(Colonies_2012), SUM(Colonies_2017)
 FROM Bee_Colonies NATURAL JOIN Geo_Codes NATURAL JOIN Ag_Codes
 WHERE State = 'NJ' 
 GROUP BY Ag_District_Code, Ag_District;
  
 -- Alternative using INNER JOIN.
 
 SELECT Ag_Codes.Ag_District_Code, Ag_District, 
	SUM(Colonies_2002), SUM(Colonies_2007), 
    SUM(Colonies_2012), SUM(Colonies_2017)
 FROM Bee_Colonies INNER JOIN Geo_Codes 
 ON Bee_Colonies.state_ANSI = Geo_Codes.state_ANSI AND
	Bee_Colonies.county_ANSI = Geo_Codes.county_ANSI
 INNER JOIN Ag_Codes
 ON Ag_Codes.state_ANSI = Geo_Codes.state_ANSI AND
	Ag_Codes.Ag_District_Code = Bee_Colonies.Ag_District_Code
 WHERE State = 'NJ' 
 GROUP BY Ag_Codes.Ag_District_Code, Ag_District;
 
 /*
  * Question 8: What is the state two letter code, county name
  * (also known as area name), agricultural district code, AND
  * agricultural district name for counties in the same agricultural
  * district as Middlesex County, NJ.  Search
  * using Middlesex County and NJ.  Note that the only constants you
  * can use in your query are: 'Middlesex County' and 'NJ'.
  */
  
  Select State, Area_Name, Ag_District_Code, Ag_District
  FROM Bee_colonies NATURAL JOIN Geo_Codes NATURAL JOIN Ag_Codes
  WHERE Bee_Colonies.Ag_District_Code = (
		SELECT Ag_District_Code
		FROM bee_colonies NATURAL JOIN Geo_Codes 
		WHERE State = 'NJ' and Area_Name = 'Middlesex County') 
  AND Bee_Colonies.State_ANSI = (
		SELECT DISTINCT State_ANSI
		FROM Geo_Codes
        WHERE State = 'NJ')
;

 -- Alternative using INNER JOIN.
 
Select State, Area_Name, Ag_Codes.Ag_District_Code, Ag_District
FROM Bee_Colonies INNER JOIN Geo_Codes 
ON Bee_Colonies.state_ANSI = Geo_Codes.state_ANSI AND
   Bee_Colonies.county_ANSI = Geo_Codes.county_ANSI
INNER JOIN Ag_Codes
ON Ag_Codes.state_ANSI = Geo_Codes.state_ANSI AND
   Ag_Codes.Ag_District_Code = Bee_Colonies.Ag_District_Code
WHERE Bee_Colonies.Ag_District_Code = (
		SELECT Ag_District_Code
		FROM Bee_Colonies INNER JOIN Geo_Codes 
		ON Bee_Colonies.state_ANSI = Geo_Codes.state_ANSI AND
			Bee_Colonies.county_ANSI = Geo_Codes.county_ANSI
		WHERE State = 'NJ' and Area_Name = 'Middlesex County') 
	AND Bee_Colonies.State_ANSI = (
		SELECT DISTINCT State_ANSI
		FROM Geo_Codes
        WHERE State = 'NJ')
;
 
 /*
  * Question 9: Generate a report for the states that have have experienced
  * (1) the largest decline in the number of bee colonies from 2002 to 2017,
  * and (2) the largest percentage decline in the number of colonies from
  * from 2002 to 2017.  List the 2 letter abbreviation for the state, the 
  * state name, the colonies for each of the available years, the amount 
  * of the change in the colonies in a column called Amount_of_Change, the 
  * percent change in colonies in a column called Percent_Change.  When 
  * decribing the amount or pecent of change, a decline should
  * be negative and growth should be positive. Format the colony counts and 
  * Amount_of_Change to have commas for readability.  Consider only the counts
  * for 2002 and 2017 in calculating the change in
  * amount or percent.
  *
  * Do not use LIMIT to produce your answer, since LIMIT will miss ties for 
  * most declines.
  * 
  * TIP:  Write and debug a query for amount and a query for percent and 
  *       then form the union of the two queries, or depending on 
  *       the query structure, combine the WHERE clauses with OR.
  *       Use the FORMAT function to add commas to the numbers.  Consider
  *       creating a table to make creating the SQL simpler.
  */

CREATE TABLE Q9_Temp AS
SELECT State, Area_Name, 
	FORMAT(Colonies_2002,0) AS Colonies_2002, 
    FORMAT(Colonies_2007,0) AS Colonies_2007, 
    FORMAT(Colonies_2012,0) AS Colonies_2012, 
    FORMAT(Colonies_2017, 0) AS Colonies_2017, 
    (Colonies_2017 - Colonies_2002) AS Amount_of_Change_Numeric,
	FORMAT(Colonies_2017 - Colonies_2002,0) AS Amount_of_Change,
    (Colonies_2017 - Colonies_2002)/Colonies_2002*100 AS Percent_Change_Numeric,
    CONCAT(ROUND(((Colonies_2017 - Colonies_2002)/Colonies_2002*100),0),'%') 
		AS Percent_Change
FROM bee_colonies Natural Join geo_codes 
WHERE Geo_Level = 'STATE';

SELECT State, Area_Name, Colonies_2002, Colonies_2007, Colonies_2012,
	Colonies_2017, Amount_of_Change, Percent_Change
FROM Q9_Temp
WHERE Amount_of_Change_Numeric = (
		SELECT MIN(Amount_of_Change_Numeric)
		FROM Q9_Temp)
      OR Percent_Change_Numeric = (
		SELECT MIN(Percent_Change_Numeric)
		FROM Q9_Temp);

DROP TABLE IF EXISTS Q9_Temp;

-- Alternative answer using a combined WHERE clause.
     
SELECT State, Area_Name, FORMAT(Colonies_2002,0) AS Colonies_2002, FORMAT(Colonies_2007,0) AS Colonies_2007, 
    FORMAT(Colonies_2012,0) AS Colonies_2012, FORMAT(Colonies_2017, 0) AS Colonies_2017, 
	FORMAT(Colonies_2017 - Colonies_2002,0) AS Amount_of_Change,
    CONCAT(ROUND(((Colonies_2017 - Colonies_2002)/Colonies_2002*100),0),'%') AS Percent_Change
FROM bee_colonies Natural Join geo_codes 
WHERE Geo_Level = 'STATE' AND (
    (Colonies_2017 - Colonies_2002) = 
	(SELECT MIN(Colonies_2017 - Colonies_2002)
     FROM bee_colonies
     WHERE County_ANSI=0)
     OR
     (ROUND(((Colonies_2002 - Colonies_2017)/Colonies_2002*100),0) = 
	 (SELECT MAX(ROUND(((Colonies_2002 - Colonies_2017)/Colonies_2002*100),0))
     FROM bee_colonies NATURAL JOIN Geo_Codes
     WHERE County_ANSI=0)));

-- Alternate answer using UNION.

SELECT State, Area_Name, FORMAT(Colonies_2002,0) AS Colonies_2002, FORMAT(Colonies_2007,0) AS Colonies_2007, 
    FORMAT(Colonies_2012,0) AS Colonies_2012, FORMAT(Colonies_2017, 0) AS Colonies_2017, 
	FORMAT(Colonies_2017 - Colonies_2002,0) AS Amount_of_Change,
    CONCAT(ROUND(((Colonies_2017 - Colonies_2002)/Colonies_2002*100),0),'%') AS Percent_Change
FROM bee_colonies Natural Join geo_codes 
WHERE Geo_Level = 'STATE' AND (
    (Colonies_2017 - Colonies_2002) = 
	(SELECT MIN(Colonies_2017 - Colonies_2002)
     FROM bee_colonies
     WHERE County_ANSI=0))
UNION
SELECT State, Area_Name, FORMAT(Colonies_2002,0) AS Colonies_2002, FORMAT(Colonies_2007,0) AS Colonies_2007, 
    FORMAT(Colonies_2012,0) AS Colonies_2012, FORMAT(Colonies_2017, 0) AS Colonies_2017, 
	FORMAT(Colonies_2017 - Colonies_2002,0) AS Amount_of_Change,
    CONCAT(ROUND(((Colonies_2017 - Colonies_2002)/Colonies_2002*100),0),'%') AS Percent_Change
FROM bee_colonies Natural Join geo_codes 
WHERE Geo_Level = 'STATE' AND (
     (ROUND(((Colonies_2002 - Colonies_2017)/Colonies_2002*100),0) = 
	 (SELECT MAX(ROUND(((Colonies_2002 - Colonies_2017)/Colonies_2002*100),0))
     FROM bee_colonies NATURAL JOIN Geo_Codes
     WHERE County_ANSI=0)));
     
/*
 * Question 10: Generate a report for the counties that have have
 * experienced (1) the largest percentage growth in their population
 * from 2000 to 2020, and (2) the largest percentage decline in their
 * population from 2000 to 2020.  List the 2 letter abbreviation for the
 * state, the county name, the colony counts for each of the available years,
 * the amount of the change in the colonies in a column
 * called Amount_of_Change, the percent change in colonies in a column
 * called Percent_Change, and the percent change in population in a column
 * called Population_Percent_Change.  When decribing the amount or pecent
 * of change, a decline should be negative and growth should be positive.
 * Format the colony counts and Amount_of_Change to have commas for readability.
 * Consider only the counts for 2002 and 2017 in calculating the
 * Amount_of_Change and Percent_Change.  Consider only the populations for
 * 2000 and 2020 in calculating the Population_Percent_Change.
 *
 * Do not use LIMIT to produce your answer, since LIMIT will miss ties
 * for most declines or most growth.
 *
 * TIPS:  Write and debug a query for the percent growth and a query for
 *        percent decline and then form the union the two queries, or
 *        depending on the query structure, combine the WHERE clauses
 *        for the two queries with OR.  Use the FORMAT function to add
 *        commas to the numbers. The percentage change from 
 *        a value x for 2000 to a value y for 2020 is (y-x)/x*100.
 */

CREATE TABLE Q10_Temp AS
SELECT State, Area_Name, 
	FORMAT(Colonies_2002,0) AS Colonies_2002, 
    FORMAT(Colonies_2007,0) AS Colonies_2007, 
    FORMAT(Colonies_2012,0) AS Colonies_2012, 
    FORMAT(Colonies_2017, 0) AS Colonies_2017, 
	FORMAT(Colonies_2017 - Colonies_2002,0) AS Amount_of_Change,
    CONCAT(ROUND(((Colonies_2017 - Colonies_2002)/Colonies_2002*100),0),'%') 
		AS Percent_Change,
	ROUND(((Population_2020 - Population_2000)/Population_2000*100),0)
		AS Percent_Population_Change_Numeric,
	CONCAT(ROUND(((Population_2020 - Population_2000)/Population_2000*100),0),'%') 
		AS Percent_Population_Change
FROM bee_colonies Natural Join geo_codes Natural Join Population
WHERE Geo_Level = 'COUNTY';

SELECT State, Area_Name, Colonies_2002, Colonies_2007, Colonies_2012,
	Colonies_2017, Amount_of_Change, Percent_Change, Percent_Population_Change
FROM Q10_Temp
WHERE Percent_Population_Change_Numeric = (
		SELECT MIN(Percent_Population_Change_Numeric)
		FROM Q10_Temp)
      OR Percent_Population_Change_Numeric = (
		SELECT MAX(Percent_Population_Change_Numeric)
		FROM Q10_Temp);

DROP TABLE IF EXISTS Q10_Temp;

-- Alternate answer using a combined WHERE clause.

SELECT State, Area_Name, FORMAT(Colonies_2002,0) AS Colonies_2002, FORMAT(Colonies_2007,0) AS Colonies_2007, 
	FORMAT(Colonies_2012,0) AS Colonies_2012, FORMAT(Colonies_2017, 0) AS Colonies_2017,
    FORMAT(Colonies_2017 - Colonies_2002,0) AS Amount_of_Change,
	CONCAT(ROUND(((Colonies_2017 - Colonies_2002)*100/Colonies_2002),0),'%') AS Percent_Colony_Change,
    CONCAT(ROUND(((Population_2020 - Population_2000)*100/Population_2000),0),'%') AS Percent_Population_Change
FROM bee_colonies Natural Join geo_codes Natural Join Population
WHERE
	Geo_Level = 'COUNTY' AND 
    ((ROUND(((Population_2020 - Population_2000)*100/Population_2000),0) = 
	(SELECT MAX(ROUND(((Population_2020 - Population_2000)*100/Population_2000),0))
     FROM bee_colonies Natural Join geo_codes Natural Join Population
     WHERE Geo_Level = 'COUNTY')
     OR 
     ROUND(((Population_2020 - Population_2000)*100/Population_2000),0) = 
	(SELECT MIN(ROUND(((Population_2020 - Population_2000)*100/Population_2000),0))
     FROM bee_colonies Natural Join geo_codes Natural Join Population
     WHERE Geo_Level = 'COUNTY'))
     );

