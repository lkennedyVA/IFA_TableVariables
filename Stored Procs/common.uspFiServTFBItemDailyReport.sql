USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [common].[uspFiServTFBItemDailyReport]
	Created By: Chris Sharp
	Description: This procedure reports on TFB Item activity for the date range.
		Accepts @pdtStartDate and @pdtEndDate passed in from [common].[uspFiServItemDailyReport]

	Tables: [ifa].[Process] 
		,[ifa].[Item]
		,[payer].[Payer] - 
		,[common].[ClientAccepted]
		,[ifa].[RuleBreakData]

	Functions: [common].[ufnDimension]
		,[common].[ufnNotEligibleAndCarveOutILTFDeux]
		,[common].[ufnOrgClientId]
		,[common].[ufnOnUsRoutingNumber]

	History:
		2023-08-30 - CBS - VALID-1221: Created
		2025-01-08 - LXK - Removed table Variable to local temp table, BMO proc written the same, implementing same change
*****************************************************************************************/
ALTER   PROCEDURE [common].[uspFiServTFBItemDailyReport](
	 @piOrgId INT
	,@pdtStartDate DATETIME2(7)
	,@pdtEndDate DATETIME2(7)
	,@pnvHeader NVARCHAR(4000) 
)
AS
BEGIN
	SET NOCOUNT ON;
	drop table if exists #FiServTFBItemDaily
	CREATE TABLE #FiServTFBItemDaily(
		 LevelId int
		,ParentId int
		,OrgId int primary key
		,OrgCode nvarchar(25)
		,OrgName nvarchar(255)
		,ExternalCode nvarchar(50)
		,TypeId int
		,[Type] nvarchar(50)
		,StatusFlag int
		,DateActivated datetime2(7)
		,ChannelName nvarchar(50)
	);
	DECLARE @dtStartDate datetime2(7) = @pdtStartDate
		,@dtEndDate datetime2(7) = @pdtEndDate
		,@iOrgId int = @piOrgId
		,@iOrgDimensionId int = [common].[ufnDimension]('Organization')
		,@nvHeader nvarchar(4000) = @pnvHeader;
			   		 
	INSERT INTO #FiServTFBItemDaily(LevelId,ParentId,OrgId,OrgCode,OrgName,ExternalCode,TypeId,[Type],StatusFlag,DateActivated,ChannelName)
	SELECT LevelId,ParentId,OrgId,OrgCode,OrgName,ExternalCode,TypeId,[Type],StatusFlag,DateActivated,[common].[ufnOrgChannelName](OrgId)
	FROM [common].[ufnDownDimensionByOrgIdILTF](@iOrgId,@iOrgDimensionId)
	WHERE OrgCode NOT LIKE '%Test%'
	ORDER BY ParentId, OrgId;

	--Fields were pulled from uspFiServTFBItemDailyReport in the TFB section
	SELECT @nvHeader as Txt
	UNION ALL
	SELECT Txt
	FROM (SELECT TOP 1000000 CONVERT(NVARCHAR(27),p.DateActivated) + ','+
		CONVERT(NVARCHAR(10),p.OrgId) + ','+
		CONVERT(NVARCHAR(25),p.ProcessKey) + ','+
		CONVERT(NVARCHAR(25),ClientRequestId) + ','+
		CONVERT(NVARCHAR(25),ISNULL(ClientRequestId2,'')) + ','+
		CONVERT(NVARCHAR(100),p.CustomerId) + ','+
		CONVERT(NVARCHAR(50),i.ClientItemId) + ','+
		CONVERT(NVARCHAR(25),i.ItemKey) + ','+
		CONVERT(NVARCHAR(25),i.Rulebreak) + ','+
		CONVERT(NVARCHAR(25),ca.Code) + ','+
		CONVERT(NVARCHAR(25),i.CheckAmount) + ','+
		ISNULL(CONVERT(NVARCHAR(1),neaco.NotEligible),'1') + ','+
		ISNULL(CONVERT(NVARCHAR(1),neaco.CarveOut),'0') + ','+
		CONVERT(NVARCHAR(1),CASE WHEN CheckAmount < 25.00 AND i.PayerId in (45511602,46749418,57286220,75780082,49162868,49162869,49162870
			,49162871,44140511,72675662,62086301,75019594,65055313,56231928,56231929,56208484,60818649
			,60818650,60818651,63767456,72897759,44983753) THEN 1 ELSE 0 END) + ','+
		CONVERT(NVARCHAR(25),CASE WHEN [common].[ufnOnUsRoutingNumber]([common].[ufnOrgClientId](p.OrgId),py.RoutingNumber) = 1 THEN 'Yes' ELSE 'No' END) as Txt 
	FROM [ifa].[Process] p WITH (READUNCOMMITTED)
	INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) ON p.ProcessId = i.ProcessId
	INNER JOIN [payer].[Payer] py WITH (READUNCOMMITTED) ON i.PayerId = py.PayerId
	INNER JOIN [common].[ClientAccepted] ca WITH (READUNCOMMITTED) ON i.ClientAcceptedId = ca.ClientAcceptedId
	INNER JOIN #FiServTFBItemDaily dol ON p.OrgId = dol.OrgId
	OUTER APPLY [common].[ufnNotEligibleAndCarveOutILTFDeux](@iOrgId,i.ItemId) neaco 
	WHERE p.DateActivated >= @dtStartDate 
		AND p.DateActivated < @dtEndDate
	ORDER BY i.ItemId) a
END
