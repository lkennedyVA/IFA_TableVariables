USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [common].[uspBMOItemDailyReport]
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
		,[common].[ufnGetReportDatesByClient]
		,[common].[ufnOrgClientId]
		,[common].[ufnOnUsRoutingNumber]

	History:
		2024-03-25 - CBS - VALID-1726: Created
		2024-04-11 - CBS - VALID-1777: Update the field length for ClientRequestId and ClientRequestId2 
			to nvarchar(50)
*****************************************************************************************/
ALTER PROCEDURE [common].[uspBMOItemDailyReport](
	 @piOrgId INT 
	,@pnvFileName NVARCHAR(100)
	,@pdtStartDate DATETIME2(7) 
	,@pdtEndDate DATETIME2(7) 
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
	DECLARE @tblDetail table (
		 RowId int identity(1,1)
		,DateActivated datetime2(7)
		,OrgId int
		,TransactionKey nvarchar(25)
		,ClientRequestId nvarchar(50)
		,ClientRequestId2 nvarchar(50)
		,CustomerIdentifier nvarchar(50)
		,ClientItemID nvarchar(50)
		,TransactionItemID nvarchar(25)
		,ItemRuleBreakCode nvarchar(25)
		,ClientResponse nvarchar(25)
		,ItemAmount money
		--,OnUs nvarchar(10)
	);
	DECLARE @iOrgId int = @piOrgId
		,@dtStartDate datetime2(7) = @pdtStartDate
		,@dtEndDate datetime2(7) = @pdtEndDate
		,@iOrgDimensionId int = [common].[ufnDimension]('Organization')
		,@tTime time
		,@nvHeaderDate nvarchar(10) = CONVERT(nvarchar(10), GETDATE(), 112) --YYYYMMDD
		,@nvHeader nvarchar(4000)
		,@nvFooter nvarchar(4000)
		,@nvOrgName nvarchar(50);

	SET @nvHeader = CONVERT(NVARCHAR(10), 1) + ','+ @nvHeaderDate;

	SELECT @nvOrgName = [Name] FROM [organization].[Org] WHERE OrgId = @iOrgId;

	INSERT INTO @DownOrgList(LevelId,ParentId,OrgId,OrgCode,OrgName,ExternalCode,TypeId,[Type],StatusFlag,DateActivated,ChannelName)
	SELECT LevelId,ParentId,OrgId,OrgCode,OrgName,ExternalCode,TypeId,[Type],StatusFlag,DateActivated,[common].[ufnOrgChannelName](OrgId)
	FROM [common].[ufnDownDimensionByOrgIdILTF](@iOrgId,@iOrgDimensionId)
	WHERE OrgCode <> 'BMOTest'
	ORDER BY ParentId, OrgId;

	--Adding this so we have a single place where the Start and End Dates are managed
	IF ISNULL(@dtStartDate,'') = ''
		SELECT @dtStartDate = StartDate
			,@dtEndDate = EndDate
		FROM [common].[ufnGetReportDatesByClient](@nvOrgName);
	   	  
	OPEN SYMMETRIC KEY VALIDSYMKEY DECRYPTION BY ASYMMETRIC KEY VALIDASYMKEY
	INSERT INTO @tblDetail (
		 DateActivated 
		,OrgId 
		,TransactionKey 
		,ClientRequestId
		,ClientRequestId2
		,CustomerIdentifier
		,ClientItemID
		,TransactionItemID
		,ItemRuleBreakCode 
		,ClientResponse
		,ItemAmount
		--,OnUs
	)
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
		--,CASE WHEN [common].[ufnOnUsRoutingNumber]([common].[ufnOrgClientId](p.OrgId),pa.RoutingNumber) = 1 THEN 'Yes' ELSE 'No' END AS OnUs
	FROM [ifa].[Process] p WITH (READUNCOMMITTED)
	INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) on p.ProcessId = i.ProcessId
	INNER JOIN [payer].[Payer] pa WITH (READUNCOMMITTED) on i.PayerId = pa.PayerId
	INNER JOIN [customer].[CustomerIdXref] cix WITH (READUNCOMMITTED) on p.CustomerId = cix.CustomerId
																	AND cix.IdTypeId = 25 
																	AND cix.StatusFlag = 1
	INNER JOIN [common].[ClientAccepted] ca WITH (READUNCOMMITTED) on i.ClientAcceptedId = ca.ClientAcceptedId
	LEFT JOIN [customer].[Account] a WITH (READUNCOMMITTED) on p.AccountId = a.AccountId  
														AND p.CustomerId = a.CustomerId
														AND a.AccountTypeId = 1 
	LEFT OUTER JOIN [ifa].[RuleBreakData] rbd WITH (READUNCOMMITTED) on i.ItemId = rbd.ItemId
	CROSS APPLY @DownOrgList dol
	WHERE p.DateActivated >= @dtStartDate 
		AND p.DateActivated < @dtEndDate
		AND dol.OrgId = p.OrgId
	ORDER BY p.DateActivated, i.ClientItemId;
	CLOSE SYMMETRIC KEY VALIDSYMKEY;
	
	SELECT @nvFooter = CONVERT(NVARCHAR(10),'9') +','+ @pnvFileName +','+ CONVERT(NVARCHAR(25),ISNULL(COUNT(1),0))
	FROM @tblDetail;

	--Putting it all together in preparation for the Txt output
	SELECT @nvHeader as Txt
	UNION ALL
	SELECT Txt
	FROM (
		SELECT CONVERT(NVARCHAR(27),DateActivated) + ','+
		CONVERT(NVARCHAR(10),OrgId) + ','+
		CONVERT(NVARCHAR(25),TransactionKey) + ','+
		--CONVERT(NVARCHAR(25),ClientRequestId) + ','+ --2024-04-11
		--CONVERT(NVARCHAR(25),ISNULL(ClientRequestId2,'')) + ','+ --2024-04-11
		CONVERT(NVARCHAR(50),ClientRequestId) + ','+ --2024-04-11
		CONVERT(NVARCHAR(50),ISNULL(ClientRequestId2,'')) + ','+ --2024-04-11
		CONVERT(NVARCHAR(100),CustomerIdentifier) + ','+
		CONVERT(NVARCHAR(50),ClientItemID) + ','+
		CONVERT(NVARCHAR(25),TransactionItemID) + ','+
		CONVERT(NVARCHAR(25),ItemRuleBreakCode) + ','+
		CONVERT(NVARCHAR(25),ClientResponse) + ','+
		CONVERT(NVARCHAR(25),ItemAmount) AS Txt
		--CONVERT(NVARCHAR(25),OnUs) AS Txt
	FROM @tblDetail) a
	UNION ALL 
	SELECT @nvFooter;

END
