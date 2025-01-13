USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [common].[uspKEYItemDailyReport]
	CreatedBy: Larry Dugger
	Description: This procedure reports on Item activity for the date range.

	Tables: [ifa].[Process] p
		,[ifa].[Item]
		,[payer].[Payer]
		,[common].[ClientAccepted]
		,[common].[ProcessType]
		,[ifa].[RuleBreakData]

	Functions: [common].[ufnDownDimensionByOrgIdILTF]

	History:
		2022-11-12 - LBD - Created
		2023-02-08 - LBD - Adjusted to return AccountNumber presented VALID-766
		2023-03-02 - LBD - Adjusted from 9pm to 11pm VALID-826
		2023-04-06 - LBD - Pushed to prod VALID-883 adjusted to run 10pm to 10pm
		2023-07-12 - CBS - VALID-1112: Adjusted KeyBank Logic to use GETDATE()-2 + 22:00:00
			if the report executes after midnight, else use the standard calculation
		2025-01-08 - LXK - Removed table Variable to local temp table, BMO proc written the same, implementing same change

*****************************************************************************************/
ALTER   PROCEDURE [common].[uspKEYItemDailyReport](
	 @piOrgId INT
	,@pdtStartDate DATETIME2(7) = NULL
	,@pdtEndDate DATETIME2(7) = NULL
)
AS
BEGIN
	SET NOCOUNT ON;
	drop table if exists #ItemDailyReportKEY
	CREATE TABLE #ItemDailyReportKEY(
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
		,@tTime time --2023-07-12
		,@iOrgDimensionId int = [common].[ufnDimension]('Organization');

	INSERT INTO #ItemDailyReportKEY(LevelId,ParentId,OrgId,OrgCode,OrgName,ExternalCode,TypeId,[Type],StatusFlag,DateActivated,ChannelName)
	SELECT LevelId,ParentId,OrgId,OrgCode,OrgName,ExternalCode,TypeId,[Type],StatusFlag,DateActivated,[common].[ufnOrgChannelName](OrgId)
	FROM [common].[ufnDownDimensionByOrgIdILTF](@iOrgId,@iOrgDimensionId)
	WHERE OrgCode not like '%Test%'
	ORDER BY ParentId, OrgId;

	IF ISNULL(@dtStartDate,'') = ''
	BEGIN
		--SET @dtStartDate = CONVERT(DATETIME2(7),CONVERT(NVARCHAR(20),CONVERT(DATE,GETDATE()-1)) + ' 22:00:00.0000000') --2023-07-12
		--SET @dtEndDate = CONVERT(DATETIME2(7),CONVERT(NVARCHAR(20),CONVERT(DATE,GETDATE())) + ' 22:00:00.0000000') --2023-07-12

		SET @tTime = CONVERT(time, GETDATE()); --2023-07-12

		--Use the standard calculation... prior day 22:00 through current day 22:00
		IF @tTime NOT BETWEEN '00:00:00.0000000' AND '08:00:00.0000000'
		BEGIN
			SET @dtStartDate = CONVERT(DATETIME2(7),CONVERT(NVARCHAR(20),CONVERT(DATE,GETDATE()-1)) + ' 22:00:00.0000000');
			SET @dtEndDate = CONVERT(DATETIME2(7),CONVERT(NVARCHAR(20),CONVERT(DATE,GETDATE())) + ' 22:00:00.0000000');
		END
		--Otherwise use two days ago 22:00 through prior day 22:00
		ELSE IF @tTime BETWEEN '00:00:00.0000000' AND '08:00:00.0000000'
		BEGIN
			SET @dtStartDate = CONVERT(DATETIME2(7),CONVERT(NVARCHAR(20),CONVERT(DATE,GETDATE()-2)) + ' 22:00:00.0000000');
			SET @dtEndDate = CONVERT(DATETIME2(7),CONVERT(NVARCHAR(20),CONVERT(DATE,GETDATE()-1)) + ' 22:00:00.0000000');
		END
	END
	
	OPEN SYMMETRIC KEY VALIDSYMKEY DECRYPTION BY ASYMMETRIC KEY VALIDASYMKEY
	SELECT distinct p.DateActivated as 'DateActivated'
		,p.OrgId as 'OrgId'
		,p.ProcessKey as 'TransactionKey' 
		,ClientRequestId
		,ClientRequestId2
		,CONVERT(NVARCHAR(100),CONVERT(NVARCHAR(50),DECRYPTBYKEY(cix.IdEncrypted ))) as 'CustomerIdentifier'
		,i.ClientItemId as 'ClientItemID'
		,i.ItemKey as 'TransactionItemID'		
		,i.Rulebreak as 'ItemRuleBreak'
		,ISNULL(rbd.Code,'') as 'ItemRuleBreakCode' --2023-02-08
		,ca.Code as 'ClientResponse'
		,i.CheckAmount as 'ItemAmount'
		,i.Fee as 'Fee'
		,a.AccountNumber as 'CustomerAccountNumber'
	FROM [ifa].[Process] p WITH (READUNCOMMITTED)
	INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) on p.ProcessId = i.ProcessId
	INNER JOIN [customer].[CustomerIdXref] cix WITH (READUNCOMMITTED) on p.CustomerId = cix.CustomerId
																	AND cix.IdTypeId = 25 
																	AND cix.StatusFlag = 1
	INNER JOIN [common].[ClientAccepted] ca WITH (READUNCOMMITTED) on i.ClientAcceptedId = ca.ClientAcceptedId
--	INNER JOIN [customer].[Account] a WITH (READUNCOMMITTED) on p.CustomerId = a.CustomerId
	INNER JOIN [customer].[Account] a WITH (READUNCOMMITTED) on p.AccountId = a.AccountId  --2023-02-08
														AND p.CustomerId = a.CustomerId
														AND a.AccountTypeId = 1 
	LEFT OUTER JOIN [ifa].[RuleBreakData] rbd WITH (READUNCOMMITTED) on i.ItemId = rbd.ItemId
	CROSS APPLY #ItemDailyReportKEY dol
	WHERE p.DateActivated >= @dtStartDate 
		AND p.DateActivated < @dtEndDate
		AND dol.OrgId = p.OrgId
	ORDER BY p.DateActivated, i.ClientItemId;
	CLOSE SYMMETRIC KEY VALIDSYMKEY 
END
