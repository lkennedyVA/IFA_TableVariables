USE [IFA]
GO

/****** Object:  StoredProcedure [common].[uspFiServFTBItemDailyReportDuex]    Script Date: 3/14/2025 1:11:07 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


/****************************************************************************************
	Name: uspFiServFTBItemDailyReport
	CreatedBy: Larry Dugger
	Description: This procedure reports on FTB Item activity for the date range.

	Tables: [ifa].[Process] p
		,[ifa].[Item]
		,[payer].[Payer]
		,[customer].[CustomerIdXref]
		,[common].[ClientAccepted]
		,[ifa].[RuleBreakData]

	Functions: [common].[ufnDownDimensionByOrgIdILTF]
		,[common].[ufnNotEligibleAndCarveOutILTFDeux]
		,[common].[ufnCleanNumber]

	History:
		2022-07-18 - LBD - Created
		2024-03-14 - LXK - Added local temp tables
*****************************************************************************************/
ALTER   PROCEDURE [common].[uspFiServFTBItemDailyReport](
	 @piOrgId INT
	,@pdtStartDate DATETIME2(7)
	,@pdtEndDate DATETIME2(7)
	,@pnvHeader NVARCHAR(4000) 
)
AS
BEGIN
	SET NOCOUNT ON;

/*Testing*/
--Declare @piOrgId INT = 163769
--	,@pdtStartDate DATETIME2(7)
--	,@pdtEndDate DATETIME2(7)
--	,@pnvHeader NVARCHAR(4000) = N'DateActivated,OrgId,TransactionKey,ClientRequestId,ClientRequestId2,Customer Identifier,ClientItem ID,TransactionItemID,Item Rule Break Code,Client Response,Check Amount,NotEligible,CarveOut,Demo'

	drop table if exists #FiServItemDailyFTB
	create table #FiServItemDailyFTB (
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
	drop table if exists #CleanMisc
	create table #CleanMisc (
		 ProcessId bigint primary key
		,[PrdctCd] int
	);

	--set @pdtStartDate = '2025-03-03 20:00:00.0000000'--@pdtStartDate
	--set @pdtEndDate = '2025-03-04 20:59:59.9999999' --@pdtEndDate
	DECLARE @dtStartDate datetime2(7) = @pdtStartDate
		,@dtEndDate datetime2(7) = @pdtEndDate
		, @iOrgId int = @piOrgId
		,@iOrgDimensionId int = [common].[ufnDimension]('Organization')
		,@nvHeader nvarchar(4000) = @pnvHeader;

	INSERT INTO #FiServItemDailyFTB(LevelId,ParentId,OrgId,OrgCode,OrgName,ExternalCode,TypeId,[Type],StatusFlag,DateActivated,ChannelName)
	SELECT LevelId,ParentId,OrgId,OrgCode,OrgName,ExternalCode,TypeId,[Type],StatusFlag,DateActivated,[common].[ufnOrgChannelName](OrgId)
	FROM [common].[ufnDownDimensionByOrgIdILTF](@iOrgId,@iOrgDimensionId)
	WHERE OrgCode not like '%Test%'
	ORDER BY ParentId, OrgId;

	INSERT INTO #CleanMisc (ProcessId, [PrdctCd])
	SELECT p.ProcessId, TRY_CONVERT(INT,SUBSTRING([common].[ufnCleanNumber](m.MiscInfo), 1, 25),0) 'PRDCT-CD' --'0' not being used below
	FROM  [ifa].[Process] p WITH (READUNCOMMITTED)
	INNER JOIN [ifa].[Misc] m WITH (READUNCOMMITTED) on p.ProcessId = m.ProcessId	
														AND m.MiscTypeId = 8 --PRDCT-CD
	WHERE p.DateActivated >= @dtStartDate 
		AND p.DateActivated < @dtEndDate;

	SELECT @nvHeader as Txt
	UNION ALL
	SELECT Txt
	FROM (SELECT  TOP 1000000 CONVERT(NVARCHAR(27),p.DateActivated) + ','+
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
			,60818650,60818651,63767456,72897759,44983753) THEN 1 ELSE 0 END)+ ','+
		CONVERT(NVARCHAR(25),dol.ChannelName) + ','+
		CONVERT(NVARCHAR(25),UPPER(pt.[Code]) + ','+
		CONVERT(NVARCHAR(25),CASE WHEN ISNULL(m.[PrdctCd],0) = 0 THEN '' ELSE m.[PrdctCd] END) + ','+
		--2020-12-02
		CASE WHEN ISNULL(m.[PrdctCd],0) = 324 THEN '1' ELSE '0' END + ','+
		CASE WHEN ISNULL(m.[PrdctCd],0) IN (1,2,3,5,6,7,9,13,14,16,17,60,62,
					69,100,101,102,103,104,105,106,108,109,110,111,112,113,114,115,117,
					120,300,301,302,303,304,305,306,307,308,309,310,311,312,313,314,315,316,
					317,318,322,323,324,325,326,328,330,332,338,339,340,341,2020118,2030513) THEN 'Consumer'
			WHEN ISNULL(m.[PrdctCd],0) IN (21,23,25,28,30,32,33,34,35,36,37,38,
					39,126,128,129,130,320,321,329,331,335,336) THEN 'Business'
			WHEN ISNULL(m.[PrdctCd],0) IN (10,12,19,20,22,24,26,
					27,29,31,40,41,42,43,46,49,55,58,64,65,107,119,122,123,124,125,
					127,132,133,134,135,137,144,145,151,243,297,333,334,342,343,346) THEN 'Commercial'
			ELSE '' END) as Txt 
	FROM [ifa].[Process] p WITH (READUNCOMMITTED)
	INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) ON p.ProcessId = i.ProcessId
	INNER JOIN [payer].[Payer] py WITH (READUNCOMMITTED) ON i.PayerId = py.PayerId
	INNER JOIN [common].[ClientAccepted] ca WITH (READUNCOMMITTED) ON i.ClientAcceptedId = ca.ClientAcceptedId
	INNER JOIN #FiServItemDailyFTB dol ON p.OrgId = dol.OrgId
	INNER JOIN [common].[ProcessType] pt WITH (READUNCOMMITTED) on p.ProcessTypeId = pt.ProcessTypeId
	LEFT OUTER JOIN #CleanMisc m on p.ProcessId = m.ProcessId
	OUTER APPLY [common].[ufnNotEligibleAndCarveOutILTFDeux](@iOrgId,i.ItemId) neaco 
	WHERE p.DateActivated >= @dtStartDate 
		AND p.DateActivated < @dtEndDate
	ORDER BY i.ItemId) a
END
GO