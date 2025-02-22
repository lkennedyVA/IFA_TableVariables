USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspItemDailyDetailReport
	CreatedBy: Larry Dugger
	Description: This procedure reports on Item activity for the date range.

	Tables: [ifa].[Process] p
		,[ifa].[Item]
		,[payer].[Payer]
		,[common].[ClientAccepted]
		,[riskprocessing].[RPResult]
		,[condensed].[LadderRungCondensed]

	Functions: [common].[ufnDownDimensionByOrgIdILTF]

	History:
		2017-06-01 - LBD - Created
		2018-03-14 - LBD - Modified, uses more efficient function
		2019-11-13 - LBD - Modified, removed references in table list, that aren't used
		2025-01-08 - LXK - Removed table Variable to local temp table, BMO proc written the same, implementing same change
*****************************************************************************************/
ALTER   PROCEDURE [common].[uspItemDailyDetailReport](
	 @piOrgId INT
	,@pdtStartDate DATETIME = NULL
	,@pdtEndDate DATETIME = NULL
)
AS
BEGIN
	SET NOCOUNT ON;
	drop table if exists #ItemDailyDetailReport
	CREATE TABLE #ItemDailyDetailReport(
		 LevelId int
		,ParentId int
		,OrgId int
		,OrgName nvarchar(255)
		,ExternalCode nvarchar(50)
		,TypeId int
		,[Type] nvarchar(50)
		,StatusFlag int
		,DateActivated datetime2(7)
	);
	DECLARE @iOrgId int = @piOrgId
		,@iOrgDimensionId int = [common].[ufnDimension]('Organization');

	INSERT INTO #ItemDailyDetailReport(LevelId,ParentId,OrgId,OrgName,ExternalCode,TypeId,[Type],StatusFlag,DateActivated)
	SELECT LevelId,ParentId,OrgId,OrgName,ExternalCode,TypeId,[Type],StatusFlag,DateActivated
	FROM [common].[ufnDownDimensionByOrgIdILTF](@iOrgId,@iOrgDimensionId)
	ORDER BY ParentId, OrgId;

	IF ISNULL(@pdtStartDate,'') = ''
	BEGIN
		SET @pdtStartDate = CONVERT(DATETIME2(7),CONVERT(NVARCHAR(20),CONVERT(DATE,GETDATE()-1)) + ' 21:00:00.000')
		SET @pdtEndDate = CONVERT(DATETIME2(7),CONVERT(NVARCHAR(20),CONVERT(DATE,GETDATE())) + ' 20:59:59.997')
	END

	SELECT p.DateActivated as 'DateActivated'
		,p.OrgId as 'OrgId'
		,p.ProcessKey as 'TransactionKey' 
		,ClientRequestId
		,ClientRequestId2
		,CONVERT(NVARCHAR(100),p.CustomerId) as 'Customer Identifier'
		,i.ClientItemId as 'ClientItem ID'
		,i.ItemKey as 'TransactionItemID'
		,i.Rulebreak as 'Item Rule Break Code'
		,ca.Code as 'Client Response'
		,i.CheckAmount as 'Check Amount'
		,CASE WHEN i.RuleBreakResponse like 'Red%' AND lrc.RPName = 'Eligibility' THEN 1 ELSE 0 END as NotEligible
		,i.RuleBreakResponse
		,lrc.RPName
	FROM [ifa].[Process] p
	INNER JOIN [ifa].[Item] i on p.ProcessId = i.ProcessId
	INNER JOIN [payer].[Payer] py on i.PayerId = py.PayerId
	INNER JOIN [riskprocessing].[RPResult] rpr on i.ItemId = rpr.ItemId 
											AND (rpr.RCResult = 0
												OR rpr.RCResult = 1)
	INNER JOIN [condensed].[LadderRungCondensed] lrc on rpr.LadderDBProcessXrefId = lrc.LadderDBProcessXrefId
	INNER JOIN [common].[ClientAccepted] ca on i.ClientAcceptedId = ca.ClientAcceptedId
	CROSS APPLY #ItemDailyDetailReport dol
	WHERE p.DateActivated BETWEEN @pdtStartDate AND @pdtEndDate
		AND dol.OrgId = p.OrgId;
END
