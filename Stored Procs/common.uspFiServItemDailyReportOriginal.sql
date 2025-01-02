USE [IFA]
GO
/****** Object:  StoredProcedure [common].[uspFiServItemDailyReportOriginal]    Script Date: 1/2/2025 8:42:55 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspFiServItemDailyReportOriginal
	CreatedBy: Larry Dugger
	Description: This procedure reports on Item activity for the date range.

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
		2017-02-08 - LBD - Created
		2017-04-19 - LBD - Replace Decrypted id with CustomerId field
		2017-06-01 - LBD - Added in 'NotEligible' logic
		2018-03-14 - LBD - Use more efficient function
		2018-03-22 - LBD - Added in 'CarveOut' logic 
		2018-10-03 - LBD - Added in Demo logic
		2018-10-23 - LBD - Converted to single string column
		2019-04-29 - LBD - Adjusted to work with MTB
		2019-05-17 - LBD - Removed MTBTest PNCTest
		2019-06-20 - LBD - Adjusted datetime variables to datetime2
		2019-10-08 - LBD - Adjusted creating version for TDB
		2019-12-11 - LBD - Adjusted for PNC 'Channel'
		2019-12-16 - LBD - Added ufnNotEligibleAndCarveOutILTF for TDB
		2019-12-28 - LBD - Adjusted to acquire channelname during @DownOrgList pop
		2020-11-18 - LBD - Revamped to add FTB, and set the header, associated section 'c'
			with MTB Bank
		2020-11-30 - LBD - Added Misc info (as AccountTypeCode)
		2020-12-02 - LBD - Add hardcoded logic to support Express and AccountTypeFields,
			based on MiscInfo data.
		2020-12-04 - LBD - Use new more flexible version of 
			[common].[ufnNotEligibleAndCarveOutILTFDeux]
		2021-03-30 - LBD - Corrected default returns for FTB and TD
		2021-09-20 - LBD - Added FNBPA to the FiServe Report CCF2676
*****************************************************************************************/
ALTER   PROCEDURE [common].[uspFiServItemDailyReportOriginal](
	 @piOrgId INT
	,@pdtStartDate DATETIME2(7) = NULL
	,@pdtEndDate DATETIME2(7) = NULL
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @DownOrgList table(
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
		,@nvOrgName nvarchar(50)
		,@nvHeader nvarchar(4000) = N'DateActivated,OrgId,TransactionKey,ClientRequestId,ClientRequestId2,Customer Identifier,ClientItem ID,TransactionItemID,Item Rule Break Code,Client Response,Check Amount,NotEligible,CarveOut,Demo';

	SELECT @nvOrgName = [Name] FROM [organization].[Org] WHERE OrgId = @iOrgId;

	SET @nvHeader = @nvHeader +
			CASE WHEN @nvOrgName = 'PNC Bank' THEN N',Channel'
				WHEN @nvOrgName = 'FTB Bank' THEN N',Channel,ProcessType,AccountTypeCode,Express,AccountType'
				ELSE ''
			END;

	INSERT INTO @DownOrgList(LevelId,ParentId,OrgId,OrgCode,OrgName,ExternalCode,TypeId,[Type],StatusFlag,DateActivated,ChannelName)
	SELECT LevelId,ParentId,OrgId,OrgCode,OrgName,ExternalCode,TypeId,[Type],StatusFlag,DateActivated,[common].[ufnOrgChannelName](OrgId)
	FROM [common].[ufnDownDimensionByOrgIdILTF](@iOrgId,@iOrgDimensionId)
	WHERE OrgCode not like '%Test%'
	ORDER BY ParentId, OrgId;

	IF ISNULL(@dtStartDate,'') = ''
	BEGIN
		SET @dtStartDate = CONVERT(DATETIME2(7),CONVERT(NVARCHAR(20),CONVERT(DATE,GETDATE()-1)) + ' 21:00:00.0000000')
		SET @dtEndDate = CONVERT(DATETIME2(7),CONVERT(NVARCHAR(20),CONVERT(DATE,GETDATE())) + ' 21:00:00.0000000')
	END

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
		CONVERT(NVARCHAR(1),CASE WHEN neaco.NotEligible = 0 AND p.ItemCount > 1 AND dol.ChannelName = 'ATM' THEN 1 ELSE neaco.NotEligible END) + ','+
		CONVERT(NVARCHAR(1),neaco.CarveOut) + ','+
		CONVERT(NVARCHAR(1),CASE WHEN CheckAmount < 25.00 AND i.PayerId in (45511602,46749418,57286220,75780082,49162868,49162869,49162870
			,49162871,44140511,72675662,62086301,75019594,65055313,56231928,56231929,56208484,60818649
			,60818650,60818651,63767456,72897759,44983753) THEN 1 ELSE 0 END) + ','+
		CONVERT(NVARCHAR(25),dol.ChannelName) as Txt
	FROM [ifa].[Process] p WITH (READUNCOMMITTED)
	INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) ON p.ProcessId = i.ProcessId
	INNER JOIN [payer].[Payer] py WITH (READUNCOMMITTED) ON i.PayerId = py.PayerId
	INNER JOIN [common].[ClientAccepted] ca WITH (READUNCOMMITTED) ON i.ClientAcceptedId = ca.ClientAcceptedId
	INNER JOIN @DownOrgList dol ON p.OrgId = dol.OrgId
	CROSS APPLY [common].[ufnNotEligibleAndCarveOutILTFDeux](@iOrgId,i.ItemId) neaco 
	WHERE @nvOrgName = N'PNC Bank'
		AND p.DateActivated >= @dtStartDate 
		AND p.DateActivated < @dtEndDate
	ORDER BY i.ItemId) a
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
		--2021-03-30 CONVERT(NVARCHAR(1),neaco.NotEligible) + ','+
		--2021-03-30 CONVERT(NVARCHAR(1),neaco.CarveOut) + ','+
		ISNULL(CONVERT(NVARCHAR(1),neaco.NotEligible),'1') + ','+
		ISNULL(CONVERT(NVARCHAR(1),neaco.CarveOut),'0') + ','+
		CONVERT(NVARCHAR(1),CASE WHEN CheckAmount < 25.00 AND i.PayerId in (45511602,46749418,57286220,75780082,49162868,49162869,49162870
			,49162871,44140511,72675662,62086301,75019594,65055313,56231928,56231929,56208484,60818649
			,60818650,60818651,63767456,72897759,44983753) THEN 1 ELSE 0 END) as Txt
	FROM [ifa].[Process] p WITH (READUNCOMMITTED)
	INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) ON p.ProcessId = i.ProcessId
	INNER JOIN [payer].[Payer] py WITH (READUNCOMMITTED) ON i.PayerId = py.PayerId
	INNER JOIN [common].[ClientAccepted] ca WITH (READUNCOMMITTED) ON i.ClientAcceptedId = ca.ClientAcceptedId
	INNER JOIN @DownOrgList dol ON p.OrgId = dol.OrgId
	--2021-03-30 CROSS APPLY [common].[ufnNotEligibleAndCarveOutILTFDeux](@iOrgId,i.ItemId) neaco 
	OUTER APPLY [common].[ufnNotEligibleAndCarveOutILTFDeux](@iOrgId,i.ItemId) neaco 
	WHERE @nvOrgName = N'TD Bank'
		AND p.DateActivated >= @dtStartDate 
		AND p.DateActivated < @dtEndDate
	ORDER BY i.ItemId) b
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
		CONVERT(NVARCHAR(1),CASE WHEN neaco.NotEligible = 0 AND p.ItemCount > 1 THEN 1 ELSE neaco.NotEligible END) + ','+
		CONVERT(NVARCHAR(1),neaco.CarveOut) + ','+
		CONVERT(NVARCHAR(1),CASE WHEN CheckAmount < 25.00 AND i.PayerId in (45511602,46749418,57286220,75780082,49162868,49162869,49162870
			,49162871,44140511,72675662,62086301,75019594,65055313,56231928,56231929,56208484,60818649
			,60818650,60818651,63767456,72897759,44983753) THEN 1 ELSE 0 END)  as Txt
	FROM [ifa].[Process] p WITH (READUNCOMMITTED)
	INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) ON p.ProcessId = i.ProcessId
	INNER JOIN [payer].[Payer] py WITH (READUNCOMMITTED) ON i.PayerId = py.PayerId
	INNER JOIN [common].[ClientAccepted] ca WITH (READUNCOMMITTED) ON i.ClientAcceptedId = ca.ClientAcceptedId
	INNER JOIN @DownOrgList dol ON p.OrgId = dol.OrgId
	CROSS APPLY [common].[ufnNotEligibleAndCarveOutILTFDeux](@iOrgId,i.ItemId) neaco 
	WHERE @nvOrgName = 'MTB Bank' --2020-11-18
		AND p.DateActivated >= @dtStartDate 
		AND p.DateActivated < @dtEndDate
	ORDER BY i.ItemId) c
	--2020-11-18
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
		--2021-03-30 CONVERT(NVARCHAR(1),neaco.NotEligible) + ','+
		--2021-03-30 CONVERT(NVARCHAR(1),neaco.CarveOut) + ','+
		ISNULL(CONVERT(NVARCHAR(1),neaco.NotEligible),'1') + ','+
		ISNULL(CONVERT(NVARCHAR(1),neaco.CarveOut),'0') + ','+
		CONVERT(NVARCHAR(1),CASE WHEN CheckAmount < 25.00 AND i.PayerId in (45511602,46749418,57286220,75780082,49162868,49162869,49162870
			,49162871,44140511,72675662,62086301,75019594,65055313,56231928,56231929,56208484,60818649
			,60818650,60818651,63767456,72897759,44983753) THEN 1 ELSE 0 END)+ ','+
		CONVERT(NVARCHAR(25),dol.ChannelName) + ','+
		CONVERT(NVARCHAR(25),UPPER(pt.[Code]) + ','+
		CONVERT(NVARCHAR(25),ISNULL([common].[ufnCleanNumber](m.MiscInfo),'')) + ','+
		--2020-12-02
		CASE WHEN TRY_CONVERT(INT,SUBSTRING([common].[ufnCleanNumber](m.MiscInfo), 1, 25)) = 324 THEN '1' ELSE '0' END + ','+
		CASE WHEN TRY_CONVERT(INT,SUBSTRING([common].[ufnCleanNumber](m.MiscInfo), 1, 25)) 
					IN (1,2,3,5,6,7,9,13,14,16,17,60,62,
					69,100,101,102,103,104,105,106,108,109,110,111,112,113,114,115,117,
					120,300,301,302,303,304,305,306,307,308,309,310,311,312,313,314,315,316,
					317,318,322,323,324,325,326,328,330,332,338,339,340,341,2020118,2030513) THEN 'Consumer'
				WHEN TRY_CONVERT(INT,SUBSTRING([common].[ufnCleanNumber](m.MiscInfo), 1, 25)) 
					IN (21,23,25,28,30,32,33,34,35,36,37,38,
					39,126,128,129,130,320,321,329,331,335,336) THEN 'Business'
			WHEN TRY_CONVERT(INT,SUBSTRING([common].[ufnCleanNumber](m.MiscInfo), 1, 25)) 
					IN (10,12,19,20,22,24,26,
					27,29,31,40,41,42,43,46,49,55,58,64,65,107,119,122,123,124,125,
					127,132,133,134,135,137,144,145,151,243,297,333,334,342,343,346) THEN 'Commercial'
			ELSE '' END) as Txt 
	FROM [ifa].[Process] p WITH (READUNCOMMITTED)
	INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) ON p.ProcessId = i.ProcessId
	INNER JOIN [payer].[Payer] py WITH (READUNCOMMITTED) ON i.PayerId = py.PayerId
	INNER JOIN [common].[ClientAccepted] ca WITH (READUNCOMMITTED) ON i.ClientAcceptedId = ca.ClientAcceptedId
	INNER JOIN @DownOrgList dol ON p.OrgId = dol.OrgId
	INNER JOIN [common].[ProcessType] pt WITH (READUNCOMMITTED) on p.ProcessTypeId = pt.ProcessTypeId
	LEFT OUTER JOIN [ifa].[Misc] m WITH (READUNCOMMITTED) on p.ProcessId = m.ProcessId	--2020-11-30
															AND m.MiscTypeId = 8 --PRDCT-CD
	--2021-03-30 CROSS APPLY [common].[ufnNotEligibleAndCarveOutILTFDeux](@iOrgId,i.ItemId) neaco 
	OUTER APPLY [common].[ufnNotEligibleAndCarveOutILTFDeux](@iOrgId,i.ItemId) neaco 
	WHERE @nvOrgName = N'FTB Bank'
		AND p.DateActivated >= @dtStartDate 
		AND p.DateActivated < @dtEndDate
	ORDER BY i.ItemId) d
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
			,60818650,60818651,63767456,72897759,44983753) THEN 1 ELSE 0 END) as Txt
	FROM [ifa].[Process] p WITH (READUNCOMMITTED)
	INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) ON p.ProcessId = i.ProcessId
	INNER JOIN [payer].[Payer] py WITH (READUNCOMMITTED) ON i.PayerId = py.PayerId
	INNER JOIN [common].[ClientAccepted] ca WITH (READUNCOMMITTED) ON i.ClientAcceptedId = ca.ClientAcceptedId
	INNER JOIN @DownOrgList dol ON p.OrgId = dol.OrgId
	OUTER APPLY [common].[ufnNotEligibleAndCarveOutILTFDeux](@iOrgId,i.ItemId) neaco 
	WHERE @nvOrgName = N'FNBPA Bank'
		AND p.DateActivated >= @dtStartDate 
		AND p.DateActivated < @dtEndDate
	ORDER BY i.ItemId) e
END
