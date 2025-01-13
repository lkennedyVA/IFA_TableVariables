USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspFNBPAItemDailyReport
	CreatedBy: Larry Dugger
	Description: This procedure reports on Item activity for the date range.

	Tables: [ifa].[Process] p
		,[ifa].[Item]
		,[payer].[Payer]
		,[common].[ClientAccepted]
		,[ifa].[RuleBreakData]

	Functions: [common].[ufnDownDimensionByOrgIdILTF]

	History:
		2021-09-20 - LBD - Created CCF2676
		2022-05-26 - CBS - VALID:255 - Replace Item.Amount with Item.CheckAmount
		2025-01-08 - LXK - Removed table Variable to local temp table, BMO proc written the same, implementing same change
*****************************************************************************************/
ALTER PROCEDURE [common].[uspFNBPAItemDailyReport](
	 @piOrgId INT = 172436
	,@pdtStartDate DATETIME2(7) = NULL
	,@pdtEndDate DATETIME2(7) = NULL
)
AS
BEGIN
	SET NOCOUNT ON;
	drop table if exists #ItemDailyReportFNBPA
	CREATE TABLE #ItemDailyReportFNBPA(
		 LevelId int
		,ParentId int
		,OrgId int
		,OrgCode nvarchar(25)
		,OrgName nvarchar(255)
		,ExternalCode nvarchar(50)
		,TypeId int
		,[Type] nvarchar(50)
		,StatusFlag int
		,DateActivated datetime2(7)
	);
	DECLARE @iOrgId int = @piOrgId
		,@dtStartDate datetime2(7) = @pdtStartDate
		,@dtEndDate datetime2(7) = @pdtEndDate
		,@iOrgDimensionId int = [common].[ufnDimension]('Organization');

	INSERT INTO #ItemDailyReportFNBPA(LevelId,ParentId,OrgId,OrgCode,OrgName,ExternalCode,TypeId,[Type],StatusFlag,DateActivated)
	SELECT LevelId,ParentId,OrgId,OrgCode,OrgName,ExternalCode,TypeId,[Type],StatusFlag,DateActivated
	FROM [common].[ufnDownDimensionByOrgIdILTF](@iOrgId,@iOrgDimensionId)
	WHERE OrgCode <> 'FNBTest'
	ORDER BY ParentId, OrgId;

	IF ISNULL(@dtStartDate,'') = ''
	BEGIN
		SET @dtStartDate = CONVERT(DATETIME2(7),CONVERT(NVARCHAR(20),CONVERT(DATE,GETDATE()-1)) + ' 21:00:00.0000000')
		SET @dtEndDate = CONVERT(DATETIME2(7),CONVERT(NVARCHAR(20),CONVERT(DATE,GETDATE())) + ' 21:00:00.0000000')
	END
	OPEN SYMMETRIC KEY VALIDSYMKEY DECRYPTION BY ASYMMETRIC KEY VALIDASYMKEY
	SELECT p.DateActivated as 'DateActivated'
				,p.OrgId as 'OrgId'
				,p.ProcessKey as 'TransactionKey' 
				,ClientRequestId
				,ClientRequestId2
				,CONVERT(NVARCHAR(100),CONVERT(NVARCHAR(50),DECRYPTBYKEY(cix.IdEncrypted ))) as 'Customer Identifier'
				,i.ClientItemId as 'ClientItem ID'
				,i.ItemKey as 'TransactionItemID'
				,i.CheckAmount as 'ItemAmount' --2022-05-26
				--,i.Amount as 'ItemAmount' --2022-05-26
				,i.Rulebreak as 'Item Rule Break Code'
				,ca.Code as 'Client Response'
	FROM [ifa].[Process] p WITH (READUNCOMMITTED)
	INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) on p.ProcessId = i.ProcessId
	INNER JOIN [payer].[Payer] py WITH (READUNCOMMITTED) on i.PayerId = py.PayerId
	INNER JOIN [customer].[CustomerIdXref] cix WITH (READUNCOMMITTED) on p.CustomerId = cix.CustomerId
	INNER JOIN [common].[ClientAccepted] ca WITH (READUNCOMMITTED) on i.ClientAcceptedId = ca.ClientAcceptedId
	LEFT OUTER JOIN [ifa].[RuleBreakData] rbd WITH (READUNCOMMITTED) on i.ItemId = rbd.ItemId
	CROSS APPLY #ItemDailyReportFNBPA dol
	WHERE p.DateActivated >= @dtStartDate 
		AND p.DateActivated < @dtEndDate
		AND cix.IdTypeId = 25
		AND dol.OrgId = p.OrgId;
	CLOSE SYMMETRIC KEY VALIDSYMKEY 
END
