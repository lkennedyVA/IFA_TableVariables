USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/****************************************************************************************
	Name: uspPNCItemDailyReport
	CreatedBy: Larry Dugger
	Description: This procedure reports on Item activity for the date range.

	Tables: [ifa].[Process] p
		,[ifa].[Item]
		,[payer].[Payer]
		,[common].[ClientAccepted]
		,[ifa].[RuleBreakData]

	Functions: [common].[ufnDownDimensionByOrgIdILTF]

	History:
		2019-12-11 - LBD - Created
		2025-01-08 - LXK - Removed table variable to local temp table, BMO proc written the same, implementing same change
*****************************************************************************************/

ALTER PROCEDURE [common].[uspPNCItemDailyReport](
	@piOrgId INT,
	@pdtStartDate DATETIME2(7) = NULL,
	@pdtEndDate DATETIME2(7) = NULL
)
AS
BEGIN
	SET NOCOUNT ON;

	-- SSIS Metadata Placeholder
	IF 1 = 0
	BEGIN
		SELECT 
			CAST(NULL AS DATETIME2(7)) AS DateActivated,
			CAST(NULL AS INT) AS OrgId,
			CAST(NULL AS NVARCHAR(25)) AS TransactionKey,
			CAST(NULL AS NVARCHAR(50)) AS ClientRequestId,
			CAST(NULL AS NVARCHAR(50)) AS ClientRequestId2,
			CAST(NULL AS NVARCHAR(100)) AS [Customer Identifier],
			CAST(NULL AS NVARCHAR(50)) AS [ClientItem ID],
			CAST(NULL AS NVARCHAR(25)) AS TransactionItemID,
			CAST(NULL AS NVARCHAR(25)) AS [Item Rule Break Code],
			CAST(NULL AS NVARCHAR(25)) AS [Client Response];
		RETURN;
	END;

	-- Drop and recreate local temp table
	DROP TABLE IF EXISTS #ItemDailyReportPNC;
	CREATE TABLE #ItemDailyReportPNC(
		LevelId INT,
		ParentId INT,
		OrgId INT,
		OrgCode NVARCHAR(25),
		OrgName NVARCHAR(255),
		ExternalCode NVARCHAR(50),
		TypeId INT,
		[Type] NVARCHAR(50),
		StatusFlag INT,
		DateActivated DATETIME2(7)
	);

	DECLARE @iOrgId INT = @piOrgId,
			@dtStartDate DATETIME2(7) = @pdtStartDate,
			@dtEndDate DATETIME2(7) = @pdtEndDate,
			@iOrgDimensionId INT = [common].[ufnDimension]('Organization');

	-- Populate local temp table
	INSERT INTO #ItemDailyReportPNC (LevelId, ParentId, OrgId, OrgCode, OrgName, ExternalCode, TypeId, [Type], StatusFlag, DateActivated)
	SELECT LevelId, ParentId, OrgId, OrgCode, OrgName, ExternalCode, TypeId, [Type], StatusFlag, DateActivated
	FROM [common].[ufnDownDimensionByOrgIdILTF](@iOrgId, @iOrgDimensionId)
	WHERE OrgCode NOT IN ('PNCTest', 'MTBTest')
	ORDER BY ParentId, OrgId;

	-- Default date range handling
	IF @dtStartDate IS NULL OR @dtEndDate IS NULL
	BEGIN
		SET @dtStartDate = CONVERT(DATETIME2(7), CONVERT(NVARCHAR(20), CONVERT(DATE, GETDATE() - 1)) + ' 21:00:00.0000000');
		SET @dtEndDate = CONVERT(DATETIME2(7), CONVERT(NVARCHAR(20), CONVERT(DATE, GETDATE())) + ' 21:00:00.0000000');
	END;

	-- Create Final Results Temp Table
	DROP TABLE IF EXISTS #FinalResults;
	CREATE TABLE #FinalResults (
		DateActivated DATETIME2(7),
		OrgId INT,
		TransactionKey NVARCHAR(25),
		ClientRequestId NVARCHAR(50),
		ClientRequestId2 NVARCHAR(50),
		[Customer Identifier] NVARCHAR(100),
		[ClientItem ID] NVARCHAR(50),
		TransactionItemID NVARCHAR(25),
		[Item Rule Break Code] NVARCHAR(25),
		[Client Response] NVARCHAR(25)
	);

	-- Open symmetric key for decryption
	OPEN SYMMETRIC KEY VALIDSYMKEY DECRYPTION BY ASYMMETRIC KEY VALIDASYMKEY;

	-- Insert results into final results table
	INSERT INTO #FinalResults (DateActivated, OrgId, TransactionKey, ClientRequestId, ClientRequestId2, [Customer Identifier], [ClientItem ID], TransactionItemID, [Item Rule Break Code], [Client Response])
	SELECT 
		p.DateActivated,
		p.OrgId,
		p.ProcessKey,
		ClientRequestId,
		ClientRequestId2,
		CONVERT(NVARCHAR(100), CONVERT(NVARCHAR(50), DECRYPTBYKEY(cix.IdEncrypted))),
		i.ClientItemId,
		i.ItemKey,
		i.Rulebreak,
		ca.Code
	FROM [ifa].[Process] p WITH (READUNCOMMITTED)
	INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) ON p.ProcessId = i.ProcessId
	INNER JOIN [payer].[Payer] py WITH (READUNCOMMITTED) ON i.PayerId = py.PayerId
	INNER JOIN [customer].[CustomerIdXref] cix WITH (READUNCOMMITTED) ON p.CustomerId = cix.CustomerId
	INNER JOIN [common].[ClientAccepted] ca WITH (READUNCOMMITTED) ON i.ClientAcceptedId = ca.ClientAcceptedId
	LEFT OUTER JOIN [ifa].[RuleBreakData] rbd WITH (READUNCOMMITTED) ON i.ItemId = rbd.ItemId
	CROSS APPLY #ItemDailyReportPNC dol
	WHERE p.DateActivated >= @dtStartDate
	  AND p.DateActivated < @dtEndDate
	  AND cix.IdTypeId = 25
	  AND dol.OrgId = p.OrgId;

	-- Close symmetric key
	CLOSE SYMMETRIC KEY VALIDSYMKEY;

	-- Final SELECT for SSIS package
	SELECT 
		DateActivated,
		OrgId,
		TransactionKey,
		ClientRequestId,
		ClientRequestId2,
		[Customer Identifier],
		[ClientItem ID],
		TransactionItemID,
		[Item Rule Break Code],
		[Client Response]
	FROM #FinalResults;

END;
