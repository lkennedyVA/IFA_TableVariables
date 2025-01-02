USE [IFA]
GO
/****** Object:  StoredProcedure [common].[uspCurrentRuleDetailSelectByOrgId]    Script Date: 1/2/2025 8:12:52 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspCurrentRuleDetailSelectByOrgId
	Created By: Chris Sharp
	Descr: Uses new function that reads Condensed table
		   
	Tables: [organization].[Org]
		,[organization].[OrgType]
		,[organization].[OrgXref]
		,[rule].[RuleOrgXref]
      
	Functions: [common].[ufnRuleListDetailedByOrgId]

	History:
		2018-04-05 - CBS  - Created, from Validbank
*****************************************************************************************/
ALTER PROCEDURE [common].[uspCurrentRuleDetailSelectByOrgId](
	 @piOrgId INT 
)
AS 
BEGIN
	SET NOCOUNT ON;
	DECLARE @tblCurrentRuleDetail TABLE (
		[OrgId] [int] NOT NULL,
		[OrgName] [nvarchar](50) NULL,
		[OrgLevel] [nvarchar](25) NULL,
		[ReportName] [nvarchar](255) NULL,
   		[RuleOrgXrefId] [int] NULL,
		[RuleGroupCode] [nvarchar](25) NULL,
		[RuleGroupDesc] [nvarchar](50) NULL,
		[RuleCode] [nvarchar](25) NULL,
		[RuleId] [int] NULL,
		[Descr] [nvarchar](250) NULL,
		[Name] [nvarchar](50) NULL,
		[CheckTypeId] [int],
		[EnrollmentFlag] [int],
		[OverridableFlag] [bit],
		[LevelId] [int],
		[AccountNotFound] [nvarchar](5),
		[AgeFloor] [int],
		[AllCheckTypes] [bit],
		[AmountCeiling] [int],
		[AmountFloor] [money],
		[AmountVariation] [float],
		[Approved] [nvarchar](5),
		[CheckMax] [money],
		[CheckNumberFloor] [int],
		[CheckPayeeHistory] [bit],
		[ClientSpecific] [int],
		[DaysToBegin] [int],
		[DaysToEnd] [int],
		[DaysToSpan] [int],
		[DaysToSpan2] [int],
		[DivisorFactor] [int],
		[EnrollmentLockdownList] [bit],
		[GoodPayer] [int],
		[GroupCheckTypes] [nvarchar](25),
		[Ignore] [nvarchar](5),
		[IgnoreEmptySSN] [nvarchar](5),
		[IgnoreSendToXMLApp] [nvarchar](5),
		[Inconclusive] [nvarchar](5),
		[ItemOverThreshold] [nvarchar](5),
		[Leveling] [int],
		[MonitorRule] [int],
		[MaxScore] [int],
		[MinScore] [int],
		[MinutesToSpan] [int],
		[NegativeDataExists] [nvarchar](5),
		[NegativeFile] [nvarchar](25),
		[NoData] [nvarchar](5),
		[NonMemberBank] [nvarchar](5),
		[NotesToView] [bit],
		[NumberVariation] [int],
		[Overlay] [bit],
		[PayeeBlackList] [bit],
		[PayeePayerTranCeiling] [int],
		[PayeePayerTranFloor] [int],
		[PayeeTranCeiling] [int],
		[PayerBlackList] [bit],
		[PayerTranCeiling] [int],
		[Percent3090] [int],
		[RoutingAccountCheckFlag] [bit],
		[RoutingNumber] [bit],
		[SafeListFloor] [int],
		[TaxSeasonBegin] [nvarchar](5),
		[TaxSeasonEnd] [nvarchar](5),
		[TranAllowed] [int],
		[TranCeiling] [int],
		[TranFloor] [int],
		[TranFloor2] [int],
		[VerifyCheckSeries] [int]
	);
	DECLARE @iOrgId int = @piOrgId

   	INSERT INTO @tblCurrentRuleDetail(OrgId,OrgName,OrgLevel,RuleOrgXrefId,RuleId,RuleCode,Descr,CheckTypeId,Name,
		EnrollmentFlag,OverridableFlag,LevelId,
		AccountNotFound,AgeFloor,AllCheckTypes,AmountCeiling,AmountFloor,AmountVariation,Approved,
		CheckMax,CheckNumberFloor,CheckPayeeHistory,ClientSpecific,DaysToBegin,DaysToEnd,DaysToSpan,DaysToSpan2,
		DivisorFactor,EnrollmentLockdownList,GoodPayer,GroupCheckTypes,Ignore,IgnoreEmptySSN,IgnoreSendToXMLApp,
		Inconclusive,ItemOverThreshold,Leveling,MonitorRule,MaxScore,MinScore,MinutesToSpan,NegativeDataExists,NegativeFile,
		NoData,NonMemberBank,NotesToView,NumberVariation,Overlay,PayeeBlackList,PayeePayerTranCeiling,PayeePayerTranFloor,PayeeTranCeiling,
		PayerBlackList,PayerTranCeiling,Percent3090,RoutingAccountCheckFlag,RoutingNumber,SafeListFloor,
		TaxSeasonBegin,TaxSeasonEnd,TranAllowed,TranCeiling,TranFloor,TranFloor2,VerifyCheckSeries)
	SELECT o.OrgId,o.Name AS OrgName,ot.Name AS OrgLevel,RuleOrgXrefId, rdc.RuleId, RuleCode, r.Descr,rdc.CheckTypeId, ct.Name,
		EnrollmentFlag, OverridableFlag, rdc.LevelId,
		AccountNotFound,AgeFloor,AllCheckTypes,AmountCeiling,AmountFloor,AmountVariation,Approved,
		CheckMax,CheckNumberFloor,CheckPayeeHistory,ClientSpecific,DaysToBegin,DaysToEnd,DaysToSpan,DaysToSpan2,
		DivisorFactor,EnrollmentLockdownList,GoodPayer,GroupCheckTypes,Ignore,IgnoreEmptySSN,IgnoreSendToXMLApp,
		Inconclusive,ItemOverThreshold,Leveling,MonitorRule,MaxScore,MinScore,MinutesToSpan,NegativeDataExists,NegativeFile,
		NoData,NonMemberBank,NotesToView,NumberVariation,Overlay,PayeeBlackList,PayeePayerTranCeiling,PayeePayerTranFloor,PayeeTranCeiling,
		PayerBlackList,PayerTranCeiling,Percent3090,RoutingAccountCheckFlag,RoutingNumber,SafeListFloor,
		TaxSeasonBegin,TaxSeasonEnd,TranAllowed,TranCeiling,TranFloor,TranFloor2,VerifyCheckSeries
	FROM [common].[ufnCurrentRuleDetail](@iOrgId) rdc
	INNER JOIN [rule].[Rule] r 
		on rdc.RuleId = r.RuleId
	INNER JOIN [common].[CheckType] ct 
		on rdc.CheckTypeId = ct.CheckTypeId
	INNER JOIN [organization].[Org] o
		ON o.OrgId = @iOrgId
	INNER JOIN 	[organization].[OrgType] ot
		ON o.OrgTypeId = ot.OrgTypeId
	ORDER BY rdc.RuleId, rdc.CheckTypeId, rdc.EnrollmentFlag;

	UPDATE crd
		SET ReportName = ISNULL(TRY_CONVERT(nvarchar(255), OrgName + ' - ' + OrgLevel), 'N/A')
			,RuleGroupCode = rg.Code
			,RuleGroupDesc = SUBSTRING(rg.Descr,1,50) 
	FROM @tblCurrentRuleDetail crd
	INNER JOIN [rule].[RuleOrgXref] rox 
		ON crd.RuleOrgXrefId = rox.RuleOrgXrefId
	INNER JOIN [rule].[RuleGroup] rg 
		ON rox.RuleGroupId = rg.RuleGroupId;

	SELECT OrgId, OrgName,OrgLevel,ReportName,RuleOrgXrefId,RuleGroupCode,RuleGroupDesc,RuleCode,RuleId,
		Descr,[Name],CheckTypeId,EnrollmentFlag,OverridableFlag,LevelId,
		AccountNotFound,AgeFloor,AllCheckTypes,AmountCeiling,AmountFloor,AmountVariation,Approved,
		CheckMax,CheckNumberFloor,CheckPayeeHistory,ClientSpecific,DaysToBegin,DaysToEnd,DaysToSpan,DaysToSpan2,
		DivisorFactor,EnrollmentLockdownList,GoodPayer,GroupCheckTypes,Ignore,IgnoreEmptySSN,IgnoreSendToXMLApp,
		Inconclusive,ItemOverThreshold,Leveling,MonitorRule,MaxScore,MinScore,MinutesToSpan,NegativeDataExists,NegativeFile,
		NoData,NonMemberBank,NotesToView,NumberVariation,Overlay,PayeeBlackList,PayeePayerTranCeiling,PayeePayerTranFloor,PayeeTranCeiling,
		PayerBlackList,PayerTranCeiling,Percent3090,RoutingAccountCheckFlag,RoutingNumber,SafeListFloor,
		TaxSeasonBegin,TaxSeasonEnd,TranAllowed,TranCeiling,TranFloor,TranFloor2,VerifyCheckSeries
	FROM @tblCurrentRuleDetail;

END
