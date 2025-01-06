USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspFTBItemDailyReport
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
		2020-10-05 - LBD - Created
		2020-11-17 - LBD - Added ChannelName
		2020-11-25 - LBD - Only return IdTypeID 25, added rulegroupcode
*****************************************************************************************/
ALTER PROCEDURE [common].[uspFTBItemDailyReport](
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
		,@iOrgDimensionId int = [common].[ufnDimension]('Organization');

	INSERT INTO @DownOrgList(LevelId,ParentId,OrgId,OrgCode,OrgName,ExternalCode,TypeId,[Type],StatusFlag,DateActivated,ChannelName)
	SELECT LevelId,ParentId,OrgId,OrgCode,OrgName,ExternalCode,TypeId,[Type],StatusFlag,DateActivated,[common].[ufnOrgChannelName](OrgId)
	FROM [common].[ufnDownDimensionByOrgIdILTF](@iOrgId,@iOrgDimensionId)
	WHERE OrgCode <> 'FTBTest'
	ORDER BY ParentId, OrgId;

	IF ISNULL(@dtStartDate,'') = ''
	BEGIN
		SET @dtStartDate = CONVERT(DATETIME2(7),CONVERT(NVARCHAR(20),CONVERT(DATE,GETDATE()-1)) + ' 21:00:00.0000000')
		SET @dtEndDate = CONVERT(DATETIME2(7),CONVERT(NVARCHAR(20),CONVERT(DATE,GETDATE())) + ' 21:00:00.0000000')
	END
	OPEN SYMMETRIC KEY VALIDSYMKEY DECRYPTION BY ASYMMETRIC KEY VALIDASYMKEY
	SELECT distinct p.DateActivated as 'DateActivated'
		,p.OrgId as 'OrgId'
		,p.ProcessKey as 'TransactionKey' 
		,ClientRequestId
		,ClientRequestId2
		,CONVERT(NVARCHAR(100),CONVERT(NVARCHAR(50),DECRYPTBYKEY(cix.IdEncrypted ))) as 'Customer Identifier'
		,i.ClientItemId as 'ClientItem ID'
		,i.ItemKey as 'TransactionItemID'
		,i.CheckAmount as 'ItemAmount'
		,i.Rulebreak as 'Item Rule Break Code'
		,ca.Code as 'Client Response'
		,dol.ChannelName as 'Channel'
		,UPPER(pt.[Code]) as 'ProcessType'
		,CASE WHEN ISNULL(rbd.Code,'0') = '0' THEN '0' ELSE rbd.Code END as 'RuleGroupCode' --2020-11-25
	FROM [ifa].[Process] p WITH (READUNCOMMITTED)
	INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) on p.ProcessId = i.ProcessId
	INNER JOIN [customer].[CustomerIdXref] cix WITH (READUNCOMMITTED) on p.CustomerId = cix.CustomerId
																	AND cix.IdTypeId = 25 
																	AND cix.StatusFlag = 1
																	--2020-11-25 AND ((p.ProcessTypeId = 0 AND cix.IdTypeId = 25)
																	--2020-11-25 OR (p.ProcessTypeId = 2 AND cix.IdTypeId = 3))
	INNER JOIN [common].[ClientAccepted] ca WITH (READUNCOMMITTED) on i.ClientAcceptedId = ca.ClientAcceptedId
	INNER JOIN [common].[ProcessType] pt WITH (READUNCOMMITTED) on p.ProcessTypeId = pt.ProcessTypeId
	LEFT OUTER JOIN [ifa].[RuleBreakData] rbd WITH (READUNCOMMITTED) on i.ItemId = rbd.ItemId
	CROSS APPLY @DownOrgList dol
	WHERE p.DateActivated >= @dtStartDate 
		AND p.DateActivated < @dtEndDate
		AND dol.OrgId = p.OrgId
		--AND ClientItemId NOT LIKE 'DEPO%'
		--AND ClientRequestId2 NOT LIKE 'Hal%'
	ORDER BY p.DateActivated, i.ClientItemId;
	CLOSE SYMMETRIC KEY VALIDSYMKEY 
END
