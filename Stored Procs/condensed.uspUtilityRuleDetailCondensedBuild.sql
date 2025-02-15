USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/****************************************************************************************
	Name: uspUtilityRuleDetailCondensedBuild
	CreatedBy: Larry Dugger
	Date: 2015-07-01
	Descr: This procedure uses a common table expression (CTE) 
		and a Pivot table to generate the current rule detail list. It is important to
		note that the selected rule group associated with a given rule is determined by
		@piOrgId (the lowest Org leaf that is defined)
		When this procedure is called the results are often inserted into a TYPED table
		It fields should mirror TYPE [rule].[RuleDetailType]
		--all key points are indicated with --*rdt
		   
	Tables: [organization].[Org]
		,[organization].[OrgType]
		,[organization].[OrgXref]
		,[rule].[RuleOrgXref]
		,[rule].[UtilityRuleDetailCondensed]
      
	Functions: [common].[ufnRuleListDetailedByOrgId]
		,[common].[ufnUpDimensionListByOrgIdILTF]

	History:
		2015-07-01 - LBD - Created, updated from Validbank
		2015-12-01 - CBS - Modified, force rule dimension exclusivity.
		2017-02-06 - LBD - Moved to condensed schema
		2018-03-14 - LBD - Modified, uses more efficient function
		2025-01-08 - LXK - Removed table variable to local temp tables
*****************************************************************************************/
ALTER PROCEDURE [condensed].[uspUtilityRuleDetailCondensedBuild](
	 @piOrgId INT = -1
	,@piDimensionId INT
	,@pnvUserName NVARCHAR(100) = 'N/A'
)
AS 
BEGIN
drop table if exists #UtilityRuleDetailCondensedBld
	create table #UtilityRuleDetailCondensedBld(
		RuleId int
		,RuleCode nvarchar(25)
		,CheckTypeId int
		,CheckTypeCode nvarchar(25)
		,EnrollmentFlag bit
		,OverridableFlag bit
		,LevelId int
		,DetailCode nvarchar(25)
		,CodeValue nvarchar(512)
		,ColumnName varchar(25)
	);
	drop table if exists #UpOrgList
	create table #UpOrgList(
		LevelId int
		,ChildId int
		,OrgId int
		,OrgName nvarchar(255)
		,TypeId int
		,[Type] nvarchar(50)
	);
	DECLARE @nvColList nvarchar(max)
		,@nvSql nvarchar(max);
	IF ISNULL(@piDimensionId,-9999) = -9999 
		SET @piDimensionId = [common].[ufnDimension]('Rule');
	--INSERT RuleDetail Data
	INSERT INTO #UtilityRuleDetailCondensedBld(RuleId,RuleCode,CheckTypeId,CheckTypeCode,EnrollmentFlag,OverridableFlag,LevelId,DetailCode,CodeValue,ColumnName)
	SELECT RuleId,RuleCode,CheckTypeId,CheckTypeCode,EnrollmentFlag,OverridableFlag,DetailLevelCode,RuleOrgDetailXrefId,RuleDetailValue,RuleDetail
	FROM [common].[ufnRuleListDetailedByOrgId](@piOrgId,@piDimensionId);
   
	--INSERT Org Hierarchy
	INSERT INTO #UpOrgList(LevelId,ChildId,OrgId,OrgName,TypeId,[Type])
	SELECT LevelId,ChildId,OrgId,OrgName,TypeId,[Type]
	FROM [common].[ufnUpDimensionByOrgIdILTF](@piOrgId,@piDimensionId);
	INSERT INTO [condensed].[UtilityRuleDetailCondensed](OrgId,DimensionId,RuleOrgXrefId,RuleCode,RuleId,CheckTypeCode,CheckTypeId,EnrollmentFlag,OverridableFlag,LevelId,
		--*rdt
		AccountNotFound,AgeFloor,AllCheckTypes,AmountCeiling,AmountFloor,AmountVariation,Approved,
		CheckMax,CheckNumberFloor,CheckPayeeHistory,ClientSpecific,DaysToBegin,DaysToEnd,DaysToSpan,DaysToSpan2,
		DivisorFactor,EnrollmentLockdownList,GoodPayer,GroupCheckTypes,Ignore,IgnoreEmptySSN,IgnoreSendToXMLApp,
		Inconclusive,ItemOverThreshold,Leveling,MonitorRule,MaxScore,MinScore,MinutesToSpan,NegativeDataExists,NegativeFile,
		NoData,NonMemberBank,NotesToView,NumberVariation,Overlay,PayeeBlackList,PayeePayerTranCeiling,PayeePayerTranFloor,PayeeTranCeiling,
		PayerBlackList,PayerTranCeiling,Percent3090,RoutingAccountCheckFlag,RoutingNumber,SafeListFloor,
		TaxSeasonBegin,TaxSeasonEnd,TranAllowed,TranCeiling,TranFloor,TranFloor2,VerifyCheckSeries,UserName)
	SELECT DISTINCT @piOrgId, @piDimensionId, MAX(rox.RuleOrgXrefId) AS RuleOrgXrefId, pvt.RuleCode, pvt.RuleId, pvt.CheckTypeCode, pvt.CheckTypeId,pvt.EnrollmentFlag, pvt.OverridableFlag, pvt.LevelId,
		--*rdt
		AccountNotFound,AgeFloor,AllCheckTypes,AmountCeiling,AmountFloor,AmountVariation,Approved,
		CheckMax,CheckNumberFloor,CheckPayeeHistory,ClientSpecific,DaysToBegin,DaysToEnd,DaysToSpan,DaysToSpan2,
		DivisorFactor,EnrollmentLockdownList,GoodPayer,GroupCheckTypes,Ignore,IgnoreEmptySSN,IgnoreSendToXMLApp,
		Inconclusive,ItemOverThreshold,Leveling,MonitorRule,MaxScore,MinScore,MinutesToSpan,NegativeDataExists,NegativeFile,
		NoData,NonMemberBank,NotesToView,NumberVariation,Overlay,PayeeBlackList,PayeePayerTranCeiling,PayeePayerTranFloor,PayeeTranCeiling,
		PayerBlackList,PayerTranCeiling,Percent3090,RoutingAccountCheckFlag,RoutingNumber,SafeListFloor,
		TaxSeasonBegin,TaxSeasonEnd,TranAllowed,TranCeiling,TranFloor,TranFloor2,VerifyCheckSeries,@pnvUserName
	FROM (SELECT RuleId, RuleCode, CheckTypeId, CheckTypeCode, EnrollmentFlag, OverridableFlag, LevelId, CodeValue, ColumnName
		FROM #UtilityRuleDetailCondensedBld)p
	PIVOT(MAX(CodeValue) FOR ColumnName IN (
		--*rdt
		AccountNotFound,AgeFloor,AllCheckTypes,AmountCeiling,AmountFloor,AmountVariation,Approved,
		CheckMax,CheckNumberFloor,CheckPayeeHistory,ClientSpecific,DaysToBegin,DaysToEnd,DaysToSpan,DaysToSpan2,
		DivisorFactor,EnrollmentLockdownList,GoodPayer,GroupCheckTypes,Ignore,IgnoreEmptySSN,IgnoreSendToXMLApp,
		Inconclusive,ItemOverThreshold,Leveling,MonitorRule,MaxScore,MinScore,MinutesToSpan,NegativeDataExists,NegativeFile,
		NoData,NonMemberBank,NotesToView,NumberVariation,Overlay,PayeeBlackList,PayeePayerTranCeiling,PayeePayerTranFloor,PayeeTranCeiling,
		PayerBlackList,PayerTranCeiling,Percent3090,RoutingAccountCheckFlag,RoutingNumber,SafeListFloor,
		TaxSeasonBegin,TaxSeasonEnd,TranAllowed,TranCeiling,TranFloor,TranFloor2,VerifyCheckSeries)
	) AS pvt
	INNER JOIN [rule].[RuleOrgXref] rox on pvt.RuleId = rox.RuleId
	INNER JOIN #UpOrgList uol on rox.OrgId = uol.OrgId
	INNER JOIN [common].[CheckType] ct on pvt.CheckTypeId = ct.CheckTypeId
	INNER JOIN [rule].[RuleOrgDetailXref] rodx on rox.RuleOrgXrefId = rodx.RuleOrgXrefId
	INNER JOIN [organization].[OrgCheckTypeXref] octx on rodx.OrgCheckTypeXrefId = octx.OrgCheckTypeXrefId
													and ct.CheckTypeId = octx.CheckTypeId
	WHERE rox.StatusFlag > 0
		and rox.DateActivated <= SYSDATETIME()
		and rodx.StatusFlag > 0
		and rodx.DateActivated <= SYSDATETIME()
		and octx.StatusFlag > 0
		and octx.DateActivated <= SYSDATETIME()
	GROUP BY pvt.RuleId, pvt.RuleCode, pvt.CheckTypeId, pvt.CheckTypeCode, pvt.EnrollmentFlag, pvt.OverridableFlag, pvt.LevelId,
		--*rdt
		AccountNotFound,AgeFloor,AllCheckTypes,AmountCeiling,AmountFloor,AmountVariation,Approved,
		CheckMax,CheckNumberFloor,CheckPayeeHistory,ClientSpecific,DaysToBegin,DaysToEnd,DaysToSpan,DaysToSpan2,
		DivisorFactor,EnrollmentLockdownList,GoodPayer,GroupCheckTypes,Ignore,IgnoreEmptySSN,IgnoreSendToXMLApp,
		Inconclusive,ItemOverThreshold,Leveling,MonitorRule,MaxScore,MinScore,MinutesToSpan,NegativeDataExists,NegativeFile,
		NoData,NonMemberBank,NotesToView,NumberVariation,Overlay,PayeeBlackList,PayeePayerTranCeiling,PayeePayerTranFloor,PayeeTranCeiling,
		PayerBlackList,PayerTranCeiling,Percent3090,RoutingAccountCheckFlag,RoutingNumber,SafeListFloor,
		TaxSeasonBegin,TaxSeasonEnd,TranAllowed,TranCeiling,TranFloor,TranFloor2,VerifyCheckSeries
	ORDER BY pvt.RuleId, pvt.CheckTypeId;
   
END
