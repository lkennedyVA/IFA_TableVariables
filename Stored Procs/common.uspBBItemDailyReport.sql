USE [IFA]
GO
/****** Object:  StoredProcedure [common].[uspBBItemDailyReport]    Script Date: 1/2/2025 7:28:02 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [common].[uspBBItemDailyReport]
	Created By: Chris Sharp
	Description: This procedure reports on Item activity for the date range.
	
	Tables: [ifa].[Process] 
		,[ifa].[Item]
		,[payer].[Payer]
		,[common].[ClientAccepted]
		,[common].[ProcessType]
		,[ifa].[RuleBreakData]
		,[customer].[CustomerIdXref]

	Functions: [common].[ufnDownDimensionByOrgIdILTF]

	History:
		2024-01-23 - CBS - VALID-1568: Created
*****************************************************************************************/
ALTER   PROCEDURE [common].[uspBBItemDailyReport](
	 @piOrgId INT
	,@pdtStartDate DATETIME2(7) = NULL
	,@pdtEndDate DATETIME2(7) = NULL
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @tblDownOrgList table(
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
		
	INSERT INTO @tblDownOrgList(LevelId,ParentId,OrgId,OrgCode,OrgName,ExternalCode,TypeId,[Type],StatusFlag,DateActivated,ChannelName)
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
	SELECT DISTINCT p.DateActivated as 'DateActivated'
		,p.OrgId as 'OrgId'
		,p.ProcessKey as 'TransactionKey' 
		,ClientRequestId
		,ClientRequestId2
		,CONVERT(NVARCHAR(100),p.CustomerId) as 'CustomerIdentifier'
		,i.ClientItemId as 'ClientItemID'
		,i.ItemKey as 'TransactionItemID'		
		,i.Rulebreak as 'ItemRuleBreakCode'
		,ca.Code as 'ClientResponse'
		,i.CheckAmount as 'ItemAmount'
	FROM [ifa].[Process] p WITH (READUNCOMMITTED)
	INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) on p.ProcessId = i.ProcessId
	INNER JOIN [payer].[Payer] pa WITH (READUNCOMMITTED) on i.PayerId = pa.PayerId
	INNER JOIN [customer].[CustomerIdXref] cix WITH (READUNCOMMITTED) on p.CustomerId = cix.CustomerId
																	AND cix.IdTypeId = 2 --Drivers License 
																	AND cix.StatusFlag = 1
	INNER JOIN [common].[ClientAccepted] ca WITH (READUNCOMMITTED) on i.ClientAcceptedId = ca.ClientAcceptedId
	LEFT OUTER JOIN [ifa].[RuleBreakData] rbd WITH (READUNCOMMITTED) on i.ItemId = rbd.ItemId
	CROSS APPLY @tblDownOrgList dol
	WHERE p.DateActivated >= @dtStartDate 
		AND p.DateActivated < @dtEndDate
		AND dol.OrgId = p.OrgId
	ORDER BY p.DateActivated, i.ClientItemId;
	CLOSE SYMMETRIC KEY VALIDSYMKEY;
END
