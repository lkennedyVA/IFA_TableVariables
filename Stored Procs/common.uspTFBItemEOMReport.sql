USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [common].[uspTFBItemEOMReport]
	Created By: Chris Sharp
	Description: This procedure reports on Item activity for the date range. Should only 
		contain records of Adopted items that meet the following criteria:
			Rule Break = 0
			Client Response = Accepted
			Item Status = 3

	The footer, these are the parameters:
		Footer identified with – 9
		Count: Transit <= 100
		SUM Amount: Transit <= 100
		Count: Transit > 100
		SUM Amount: Transit > 100
		Count: OnUs <= 100
		SUM Amount: OnUs <= 100
		Count: OnUs > 100
		SUM Amount: OnUs > 100
		Example:
		9,Transit <= 100 Count:17,Transit <= 100 Sum:1153.21,Transit > 100 Count:56
		,Transit > 100 Sum:205349.49,OnUs <= 100 Count:16,OnUs <= 100 Sum:827.95
		,OnUs > 100 Count:35,OnUst > 100 Sum:249964.76
	
	Name of file Example:
		TFBT02112_EOM_20230802211503100_VAL_TXN.csv
		TFB002112_EOM_20230802211503100_VAL_TXN.csv

	Tables: [ifa].[Process] 
		,[ifa].[Item]
		,[payer].[Payer]
		,[common].[ClientAccepted]
		,[common].[ProcessType]
		,[ifa].[RuleBreakData]

	Functions: [common].[ufnDimension]
		,[common].[ufnDownDimensionByOrgIdILTF]
		,[common].[ufnOnUsRouting]

	History:
		2023-08-30 - CBS - VALID-1221: Created
		2025-01-08 - LXK - Removed table Variables to local temp tables, BMO proc written the same, implementing same change
*****************************************************************************************/
ALTER   PROCEDURE [common].[uspTFBItemEOMReport](
	 @piOrgId INT
	,@pdtStartDate DATETIME2(7) = NULL
	,@pdtEndDate DATETIME2(7)  = NULL
)
AS
BEGIN
	SET NOCOUNT ON;
	drop table if exists #ItemDailyReportTFBEOM
	CREATE TABLE #ItemDailyReportTFBEOM(
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
	drop table if exists #tblDetailTFBEOM
	CREATE TABLE #tblDetailTFBEOM(
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
		,OnUs nvarchar(10)
	);
	DECLARE @iOrgId int = @piOrgId
		,@dtStartDate datetime2(7) = @pdtStartDate
		,@dtEndDate datetime2(7) = @pdtEndDate
		,@iOrgDimensionId int = [common].[ufnDimension]('Organization')
		,@nvHeader nvarchar(4000) = N'DateActivated,OrgId,TransactionKey,ClientRequestId,ClientRequestId2,CustomerIdentifier,ClientItemID,TransactionItemID,ItemRuleBreakCode,ClientResponse,ItemAmount,OnUs'
		,@nvFooter nvarchar(4000);

	INSERT INTO #ItemDailyReportTFBEOM(LevelId,ParentId,OrgId,OrgCode,OrgName,ExternalCode,TypeId,[Type],StatusFlag,DateActivated,ChannelName)
	SELECT LevelId,ParentId,OrgId,OrgCode,OrgName,ExternalCode,TypeId,[Type],StatusFlag,DateActivated,[common].[ufnOrgChannelName](OrgId)
	FROM [common].[ufnDownDimensionByOrgIdILTF](@iOrgId,@iOrgDimensionId)
	WHERE OrgCode NOT LIKE '%Test%'
	ORDER BY ParentId, OrgId;

	IF ISNULL(@dtStartDate,'') = ''
	BEGIN
		SET @dtStartDate = CONVERT(DATETIME2(7),CONVERT(NVARCHAR(20),CONVERT(DATE, EOMONTH(GETDATE(), -2))) + ' 20:00:00.0000000');
		SET @dtEndDate = CONVERT(DATETIME2(7),CONVERT(NVARCHAR(20),CONVERT(DATE, EOMONTH(GETDATE(), -1))) + ' 19:59:59.9999999');
	END
	
	--Include the same fields that are included in uspTFBItemDailyReport but only items Accepted Items (ItemStatusId = 3, ClientAcceptedId = 1 and RuleBreak = 0)
	--Truist bills differently for OnUs (same Client and OnUs RoutingNumber) versus Transit (Non-OnUs)
	OPEN SYMMETRIC KEY VALIDSYMKEY DECRYPTION BY ASYMMETRIC KEY VALIDASYMKEY
	INSERT INTO #tblDetailTFBEOM (
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
		,OnUs
	)
	SELECT p.DateActivated
		,p.OrgId
		,p.ProcessKey
		,ClientRequestId
		,ClientRequestId2
		,CONVERT(NVARCHAR(50),DECRYPTBYKEY(cix.IdEncrypted)) AS CustomerIdentifier
		,i.ClientItemId
		,i.ItemKey
		,i.Rulebreak
		,ca.Code
		,i.CheckAmount
		,CASE WHEN [common].[ufnOnUsRoutingNumber]([common].[ufnOrgClientId](p.OrgId),pa.RoutingNumber) = 1 THEN 'Yes' ELSE 'No' END AS OnUs
	FROM [ifa].[Process] p WITH (READUNCOMMITTED)
	INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) on p.ProcessId = i.ProcessId
	INNER JOIN [payer].[Payer] pa WITH (READUNCOMMITTED) on i.PayerId = pa.PayerId
	INNER JOIN [customer].[CustomerIdXref] cix WITH (READUNCOMMITTED) on p.CustomerId = cix.CustomerId
																	AND cix.IdTypeId = 25 
																	AND cix.StatusFlag = 1
	INNER JOIN [common].[ClientAccepted] ca WITH (READUNCOMMITTED) on i.ClientAcceptedId = ca.ClientAcceptedId
	INNER JOIN [customer].[Account] a WITH (READUNCOMMITTED) on p.AccountId = a.AccountId 
														AND p.CustomerId = a.CustomerId
														AND a.AccountTypeId = 1 
	LEFT OUTER JOIN [ifa].[RuleBreakData] rbd WITH (READUNCOMMITTED) on i.ItemId = rbd.ItemId
	CROSS APPLY #ItemDailyReportTFBEOM dol
	WHERE p.DateActivated >= @dtStartDate 
		AND p.DateActivated < @dtEndDate
		AND dol.OrgId = p.OrgId
		AND i.RuleBreak = 0
		AND i.ItemStatusId = 3
		AND i.ClientAcceptedId = 1
	ORDER BY p.DateActivated, i.ClientItemId;
	CLOSE SYMMETRIC KEY VALIDSYMKEY;

	--Footer sample row
	--9,72,2457.35,67,38765.80,66,3388.53,38,26333.08
	SELECT @nvFooter = CONVERT(NVARCHAR(10),'9') +','
		+ N'Transit <= 100 Count: ' +CONVERT(NVARCHAR(25),ISNULL(TRY_CONVERT(int, SUM(CASE WHEN OnUs = 'No' AND ItemAmount <= 100.00 THEN 1 ELSE 0 END)),0)) +',' --TransitCountLt$100
		+ N'Transit <= 100 Sum: ' +CONVERT(NVARCHAR(50),ISNULL(TRY_CONVERT(money, SUM(CASE WHEN OnUs = 'No' AND ItemAmount <= 100.00 THEN ItemAmount ELSE 0.00 END)),0.00)) +','--TransitAmountLt$100
		+ N'Transit > 100 Count:' +CONVERT(NVARCHAR(25),ISNULL(TRY_CONVERT(int, SUM(CASE WHEN OnUs = 'No' AND ItemAmount > 100.00 THEN 1 ELSE 0 END)),0)) +','--TransitCountGt$100
		+ N'Transit > 100 Sum: ' +CONVERT(NVARCHAR(50),ISNULL(TRY_CONVERT(money, SUM(CASE WHEN OnUs = 'No' AND ItemAmount > 100.00 THEN ItemAmount ELSE 0.00 END)),0.00)) +','--TransitAmountGt$100
		+ N'OnUs <= 100 Count: '+CONVERT(NVARCHAR(25),ISNULL(TRY_CONVERT(int, SUM(CASE WHEN OnUs = 'Yes' AND ItemAmount <= 100.00 THEN 1 ELSE 0 END)),0)) +','--OnUsCountLt$100
		+ N'OnUs <= 100 Sum: ' +CONVERT(NVARCHAR(50),ISNULL(TRY_CONVERT(money, SUM(CASE WHEN OnUs = 'Yes' AND ItemAmount <= 100.00 THEN ItemAmount ELSE 0.00 END)),0.00)) +','--OnUsAmountLt$100
		+ N'OnUs > 100 Count: ' +CONVERT(NVARCHAR(25),ISNULL(TRY_CONVERT(int, SUM(CASE WHEN OnUs = 'Yes' AND ItemAmount > 100.00 THEN 1 ELSE 0 END)),0)) +','--OnUsCountLt$100
		+ N'OnUst > 100 Sum: ' +CONVERT(NVARCHAR(50),ISNULL(TRY_CONVERT(money, SUM(CASE WHEN OnUs = 'Yes' AND ItemAmount > 100.00 THEN ItemAmount ELSE 0.00 END)),0.00))	--AS OnUsAmountLt$100
	FROM #tblDetailTFBEOM;

	--Putting it all together in preparation for the CSV output
	SELECT @nvHeader as Txt
	UNION ALL
	SELECT Txt
	FROM (
		SELECT CONVERT(NVARCHAR(27),DateActivated) + ','+
		CONVERT(NVARCHAR(10),OrgId) + ','+
		CONVERT(NVARCHAR(25),TransactionKey) + ','+
		CONVERT(NVARCHAR(25),ClientRequestId) + ','+
		CONVERT(NVARCHAR(25),ISNULL(ClientRequestId2,'')) + ','+
		CONVERT(NVARCHAR(100),CustomerIdentifier) + ','+
		CONVERT(NVARCHAR(50),ClientItemID) + ','+
		CONVERT(NVARCHAR(25),TransactionItemID) + ','+
		CONVERT(NVARCHAR(25),ItemRuleBreakCode) + ','+
		CONVERT(NVARCHAR(25),ClientResponse) + ','+
		CONVERT(NVARCHAR(25),ItemAmount) + ','+
		CONVERT(NVARCHAR(25),OnUs) as Txt
	FROM #tblDetailTFBEOM) a
	UNION ALL 
	SELECT @nvFooter;

END
