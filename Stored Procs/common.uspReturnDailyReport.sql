USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspReturnDailyReport
	CreatedBy: Larry Dugger
	Date: 2017-06-22
	Description: This procedure reports on Return activity for the date range.

	Tables: 

	Functions: 

	History:
		 2017-06-22 - LBD - Created
		 2025-01-08 - LXK -  Removed table variable for better performance
*****************************************************************************************/
ALTER PROCEDURE [common].[uspReturnDailyReport](
	 @piOrgId INT
	,@pdtStartDate DATETIME = NULL
	,@pdtEndDate DATETIME = NULL
)
AS
BEGIN
	SET NOCOUNT ON;
	drop table if exists #ReturnDailyReport
	CREATE TABLE #ReturnDailyReport(
		 Id int identity(1,1)
		,Strng nvarchar(512)
	);
	DECLARE @nvHeader nvarchar(100) = 'Daily Non Compliance Report Sent From Valid to TCK,'
		,@nvTotal nvarchar(100) = 'TOTAL,';

	IF ISNULL(@pdtStartDate,'') = ''
	BEGIN
		SET @pdtStartDate = CONVERT(DATETIME2(7),CONVERT(NVARCHAR(20),CONVERT(DATE,GETDATE()-1)) + ' 21:00:00.000')
		SET @pdtEndDate = CONVERT(DATETIME2(7),CONVERT(NVARCHAR(20),CONVERT(DATE,GETDATE())) + ' 20:59:59.997')
	END
	
	SET @nvHeader += CONVERT(NVARCHAR(10),GETDATE(),101)
	SET @nvTotal += '0';
	INSERT INTO #ReturnDailyReport(Strng)
	SELECT @nvHeader;
	INSERT INTO #ReturnDailyReport(Strng)
	SELECT @nvTotal;

	SELECT Strng
	FROM #ReturnDailyReport
	ORDER BY Id;
END
