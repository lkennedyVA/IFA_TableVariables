USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [common].[uspTFBItemDailyReport]
	Created By: Chris Sharp
	Description: This procedure reports on Item activity for the date range.
	
	Tables: [ifa].[Process] 
		,[ifa].[Item]
		,[payer].[Payer]
		,[common].[ClientAccepted]
		,[common].[ProcessType]
		,[ifa].[RuleBreakData]
		,[customer].[Account]
		,[customer].[CustomerIdXref]

	Functions: [common].[ufnDownDimensionByOrgIdILTF]
		,[common].[ufnOrgClientId]
		,[common].[ufnOnUsRoutingNumber]

	History:
		2023-08-30 - CBS - VALID-1221: Created
			2025-01-08 - LXK - Removed table Variable to local temp table, BMO proc written the same, implementing same change
*****************************************************************************************/
ALTER   PROCEDURE [common].[uspTFBItemDailyReport](
	 @piOrgId INT
	,@pdtStartDate DATETIME2(7) = NULL
	,@pdtEndDate DATETIME2(7) = NULL
)
AS
BEGIN
	SET NOCOUNT ON;
	drop table if exists #ItemDailyReportTFB
	CREATE TABLE #ItemDailyReportTFB(
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
		,ChannelName nvarchar(50)
	);
	DECLARE @iOrgId int = @piOrgId
		,@dtStartDate datetime2(7) = @pdtStartDate
		,@dtEndDate datetime2(7) = @pdtEndDate
		,@iOrgDimensionId int = [common].[ufnDimension]('Organization')
		,@nvOrgName nvarchar(50);

	SELECT @nvOrgName = [Name] FROM [organization].[Org] WHERE OrgId = @iOrgId;
		
	INSERT INTO #ItemDailyReportTFB(LevelId,ParentId,OrgId,OrgCode,OrgName,ExternalCode,TypeId,[Type],StatusFlag,DateActivated,ChannelName)
	SELECT LevelId,ParentId,OrgId,OrgCode,OrgName,ExternalCode,TypeId,[Type],StatusFlag,DateActivated,[common].[ufnOrgChannelName](OrgId)
	FROM [common].[ufnDownDimensionByOrgIdILTF](@iOrgId,@iOrgDimensionId)
	WHERE OrgCode NOT LIKE '%Test%'
	ORDER BY ParentId, OrgId;

	--Adding this so we have a single place where the Start and End Dates are managed
	IF ISNULL(@dtStartDate,'') = ''
		SELECT @dtStartDate = StartDate
			,@dtEndDate = EndDate
		FROM [common].[ufnGetReportDatesByClient](@nvOrgName);
	   	  
	OPEN SYMMETRIC KEY VALIDSYMKEY DECRYPTION BY ASYMMETRIC KEY VALIDASYMKEY
	SELECT distinct p.DateActivated as 'DateActivated'
		,p.OrgId as 'OrgId'
		,p.ProcessKey as 'TransactionKey' 
		,ClientRequestId
		,ClientRequestId2
		,CONVERT(NVARCHAR(100),CONVERT(NVARCHAR(50),DECRYPTBYKEY(cix.IdEncrypted ))) as 'CustomerIdentifier'
		,i.ClientItemId as 'ClientItemID'
		,i.ItemKey as 'TransactionItemID'		
		,i.Rulebreak as 'ItemRuleBreakCode'
		,ca.Code as 'ClientResponse'
		,i.CheckAmount as 'ItemAmount'
		,CASE WHEN [common].[ufnOnUsRoutingNumber]([common].[ufnOrgClientId](p.OrgId),pa.RoutingNumber) = 1 THEN 'Yes' ELSE 'No' END AS OnUs --2023-08-03
	FROM [ifa].[Process] p WITH (READUNCOMMITTED)
	INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) on p.ProcessId = i.ProcessId
	INNER JOIN [payer].[Payer] pa WITH (READUNCOMMITTED) on i.PayerId = pa.PayerId
	INNER JOIN [customer].[CustomerIdXref] cix WITH (READUNCOMMITTED) on p.CustomerId = cix.CustomerId
																	AND cix.IdTypeId = 25 
																	AND cix.StatusFlag = 1
	INNER JOIN [common].[ClientAccepted] ca WITH (READUNCOMMITTED) on i.ClientAcceptedId = ca.ClientAcceptedId
	INNER JOIN [customer].[Account] a WITH (READUNCOMMITTED) on p.AccountId = a.AccountId  --2023-02-08
														AND p.CustomerId = a.CustomerId
														AND a.AccountTypeId = 1 
	LEFT OUTER JOIN [ifa].[RuleBreakData] rbd WITH (READUNCOMMITTED) on i.ItemId = rbd.ItemId
	CROSS APPLY #ItemDailyReportTFB dol
	WHERE p.DateActivated >= @dtStartDate 
		AND p.DateActivated < @dtEndDate
		AND dol.OrgId = p.OrgId
	ORDER BY p.DateActivated, i.ClientItemId;
	CLOSE SYMMETRIC KEY VALIDSYMKEY;
END
