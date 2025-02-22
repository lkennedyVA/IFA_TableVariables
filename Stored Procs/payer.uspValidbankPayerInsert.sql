USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [payer].[uspValidbankPayerInsert]
	CreatedBy: Chris Sharp 
	Description: This procedure insert Validbank Payers into IFA for the given time frame.
		We truncate [dbo].[Payer] at the start of the proc and load it with any payers 
		created in Validbank between the lower and upper bound datetime2s. 

		** Remember to keep the PageSize small (10) inserting into [payer].[Payer] **

	Params:	@pdtLowerBoundDate DATETIME2(7)	
			Full: '2014-01-01 00:00:00.0000000'
			Differential: CONVERT(datetime2(7),CONVERT(DATE,GETDATE()-1))
		,@pdtUpperBoundDate DATETIME2(7)		
			Full: CONVERT(datetime2(7),CONVERT(DATETIME,DATEADD(HOUR,-1,GETDATE())))
			Differential: CONVERT(DATETIME2(7),CONVERT(DATETIME,DATEADD(HOUR,-1,GETDATE())))
		,@piPageSize INT 
			Full: 10
			Differential: 10

	Tables: [dbo].[Payer]
		,[payer].[Payer]
		,[ValidBank].[dbo].[EN_CUST_PAYER]

	Procedures: [error].[uspLogErrorDetailInsertOut]

	History:
		2023-11-15 - CBS - VALID-1414: Created
*****************************************************************************************/
ALTER   PROCEDURE [payer].[uspValidbankPayerInsert](
	 @pdtLowerBoundDate DATETIME2(7) = NULL
	,@pdtUpperBoundDate DATETIME2(7) = NULL
	,@piPageSize INT = 10							
)
AS 
BEGIN
	SET NOCOUNT ON;
	DECLARE @dtLowerBoundDate datetime2(7) = ISNULL(@pdtLowerBoundDate,CONVERT(datetime2(7),CONVERT(DATE,GETDATE()-1)))
		,@dtUpperBoundDate datetime2(7) = ISNULL(@pdtUpperBoundDate,CONVERT(datetime2(7),CONVERT(DATE,GETDATE())))
		,@iPageSize int = @piPageSize
		,@nvUserName nvarchar(100) = 'Validbank Migration'
		,@iErrorDetailId int
		,@sSchemaName sysname = 'payer';

	--Truncate the staging table before proceeding with the insert
	TRUNCATE TABLE [dbo].[Payer];

	--Insert Payers created in Validbank that don't currently exist in IFA into dbo.Payer on Route / Account
	INSERT INTO [dbo].[Payer](
		 PayerId
		,[Name]
		,RoutingNumber
		,AccountNumber
		,StatusFlag
		,DateActivated
		,UserName
	)
	SELECT e.PAYER_ID AS PayerId
		,ISNULL(UPPER(RTRIM(LTRIM(SUBSTRING(e.PAYER_NAME,1,50)))), '') AS [Name]
		,UPPER(RTRIM(LTRIM(e.PAYER_RT_NUMBER))) AS RoutingNumber
		,UPPER(RTRIM(LTRIM(e.PAYER_ACNT_NUMBER))) AS AccountNumber
		,1 AS StatusFlag
		,ISNULL(e.CREATE_DATE,SYSDATETIME()) AS DateActivated
		,@nvUserName AS UserName
	FROM [ValidBank].[dbo].[EN_CUST_PAYER] e
	WHERE e.CREATE_DATE BETWEEN @dtLowerBoundDate AND @dtUpperBoundDate
		AND ISNULL(PAYER_RT_NUMBER ,'') <> '' 
		AND LEN(PAYER_RT_NUMBER) = 9 --Excluding 5 Payers that have a RoutingNumber length of 10... 
		AND NOT EXISTS (SELECT 'X' 
						FROM [payer].[Payer] p 
						WHERE e.PAYER_RT_NUMBER = p.RoutingNumber 
							AND e.PAYER_ACNT_NUMBER = p.AccountNumber)
	ORDER BY e.PAYER_ID ASC;

	SELECT @@ROWCOUNT;

	BEGIN TRY

		--While the inserted rowcount is not equal to 0, continue looping through the records @iRowCount at a time
		--As noted above, we NEED TO KEEP THE NUMBER OF RECORDS SMALL to prevent contention
		WHILE 1 = 1
		BEGIN

			INSERT INTO [payer].[Payer](
				 [Name]
				,RoutingNumber
				,AccountNumber
				,StatusFlag
				,DateActivated
				,UserName
			)
			SELECT TOP (@piPageSize) 
				 [Name]
				,RoutingNumber
				,AccountNumber
				,StatusFlag
				,DateActivated
				,UserName
			FROM [dbo].[Payer] p
			WHERE NOT EXISTS (SELECT 'X' 
							FROM [payer].[Payer] p0 
							WHERE p.RoutingNumber = p0.RoutingNumber 
								AND p.AccountNumber = p0.AccountNumber)
			ORDER BY PayerId ASC;

			IF @@ROWCOUNT = 0
				BREAK

			WAITFOR DELAY '00:00:00.1'
		END
	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @iErrorDetailId = -1 * @iErrorDetailId; 
		THROW;
	END CATCH	
END
