USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspRuleDetailCondensedBuild
	CreatedBy: Larry Dugger
	Descr: This procedure condenses the current rule details into a single table
		   
	Tables: [organization].[Org]
		,[organization].[OrgType]
		,[organization].[OrgXref]
		,[organization].[OrgCheckTypeXref]
		,[condensed].[RuleOrgXref]
		,[condensed].[RuleOrgDetailXref]
		,[condensed].[UtilityRuleDetailCondensed]
      
	Functions: 
	History:
		2015-07-01 - LBD - Created, updated from Validbank.
		2015-12-01 - CBS - Modified, force rule dimension exclusivity.
		2016-03-04 - LBD - Modified, added DimensionId.
		2017-02-07 - LBD - Modified, moved to condensed schema
		2017-02-15 - LBD - Modified, loads 'New' table, then switches with Current
			via renaming methodology.
		2018-08-16 - LBD - Modified, use switching instead of renaming
		2025-01-08 - LXK - Removed table variables to local temp tables
*****************************************************************************************/
ALTER   PROCEDURE [condensed].[uspRuleDetailCondensedBuild]
	 @piDimensionId INT = -9999 
	,@pnvUserName NVARCHAR(100) = 'N/A'
AS 
BEGIN
	drop table if exists #RuleDetailCondensed
	create table #RuleDetailCondensed(
		RuleDetailCondensedId int identity(1,1) primary key
		,DimensionId int
		,RuleOrgXrefId int
		,RuleCode nvarchar(25)
		,RuleId int
		,CheckTypeCode nvarchar(25)
		,CheckTypeId int
		,EnrollmentFlag int
		,OverridableFlag bit
		,LevelId int
		,AccountNotFound nvarchar(5)
		,AgeFloor int
		,AllCheckTypes bit
		,AmountCeiling int
		,AmountFloor money
		,AmountVariation float
		,Approved nvarchar(5)
		,CheckMax money
		,CheckNumberFloor int
		,CheckPayeeHistory bit
		,ClientSpecific int
		,DaysToBegin int
		,DaysToEnd int
		,DaysToSpan int
		,DaysToSpan2 int
		,DivisorFactor int
		,EnrollmentLockdownList bit
		,GoodPayer int
		,GroupCheckTypes nvarchar(25)
		,Ignore nvarchar(5)
		,IgnoreEmptySSN nvarchar(5)
		,IgnoreSendToXMLApp nvarchar(5)
		,Inconclusive nvarchar(5)
		,ItemOverThreshold nvarchar(5)
		,Leveling int
		,MonitorRule int
		,MaxScore int
		,MinScore int
		,MinutesToSpan int
		,NegativeDataExists nvarchar(5)
		,NegativeFile nvarchar(25)
		,NoData nvarchar(5)
		,NonMemberBank nvarchar(5)
		,NotesToView bit
		,NumberVariation int
		,Overlay bit
		,PayeeBlackList bit
		,PayeePayerTranCeiling int
		,PayeePayerTranFloor int
		,PayeeTranCeiling int
		,PayerBlackList bit
		,PayerTranCeiling int
		,Percent3090 int
		,RoutingAccountCheckFlag bit
		,RoutingNumber bit
		,SafeListFloor int
		,TaxSeasonBegin nvarchar(5)
		,TaxSeasonEnd nvarchar(5)
		,TranAllowed int
		,TranCeiling int
		,TranFloor int
		,TranFloor2 int
		,VerifyCheckSeries int
		,UserName nvarchar(100)
	);
	drop tale if exists #OrgRuleDetailCondensedXref
	create table #OrgRuleDetailCondensedXref(
		 OrgRuleDetailCondensedXrefId int identity(1,1) primary key
		,OrgId int 
		,RuleDetailCondensedId int
		,DimensionId int
	)
	DECLARE @iOrgId int
		,@iMaxRuleDetailCondensedId int = 0
		,@dtDate datetime2(7) = SYSDATETIME()
		,@dtDateActivated datetime2(7)
		,@bEnableTimer bit = 0
		,@dtMaxDate datetime2(7)
		,@dtMaxDateROX datetime2(7)
		,@dtMaxDateRODX datetime2(7)
		,@dtMaxDateOCTX datetime2(7)
		,@dtMaxDateOX datetime2(7)
	
	IF ISNULL(@piDimensionId,-9999) = -9999 
		SET @piDimensionId = [common].[ufnDimension]('Rule');
	SELECT @dtMaxDate = ISNULL(MAX(DateActivated), '1900-01-01')
	FROM [condensed].[RuleDetailCondensed]
	WHERE DimensionId = @piDimensionId;
	SELECT @iMaxRuleDetailCondensedId = ISNULL(MAX(RuleDetailCondensedId),0)
	FROM [condensed].[RuleDetailCondensed];
	SELECT @dtMaxDateROX = MAX(DateActivated)
	FROM [rule].[RuleOrgXref];
	SELECT @dtMaxDateRODX = MAX(DateActivated)
	FROM [rule].[RuleOrgDetailXref];
	SELECT @dtMaxDateOCTX  = MAX(DateActivated)
	FROM [organization].[OrgCheckTypeXref];
	SELECT @dtMaxDateOX = MAX(DateActivated)
	FROM [organization].[OrgXref]
	WHERE DimensionId = @piDimensionId;
	IF  @dtMaxDate < @dtMaxDateROX 
		OR @dtMaxDate < @dtMaxDateRODX
		OR @dtMaxDate < @dtMaxDateOCTX
		OR @dtMaxDate < @dtMaxDateOX
	BEGIN
		--DELETE from the utility table
		DELETE FROM [condensed].[UtilityRuleDetailCondensed];
		--LOAD the common defaults
		DECLARE csr_Insert CURSOR FOR
		SELECT DISTINCT OrgId 
		FROM [rule].[RuleOrgXref] rox
		INNER JOIN [organization].[OrgXref] ox on rox.OrgId = ox.OrgChildId
		WHERE ox.DimensionId = @piDimensionId
			AND rox.StatusFlag > 0
			AND rox.DateActivated < SYSDATETIME()
			AND ox.StatusFlag > 0
			AND ox.DateActivated < SYSDATETIME()
		ORDER BY OrgId;
		OPEN csr_Insert
		FETCH csr_Insert INTO @iOrgId;
		WHILE @@FETCH_STATUS = 0
		BEGIN
			EXECUTE [condensed].[uspUtilityRuleDetailCondensedBuild] @piOrgId = @iOrgId, @piDimensionId = @piDimensionId, @pnvUserName = 'System';
			FETCH csr_Insert INTO @iOrgId;
		END
		CLOSE csr_Insert
		DEALLOCATE csr_Insert
	   
		IF @bEnableTimer = 1
		BEGIN
			SELECT 'After building utility.RuleDetailCondensed '+ CONVERT(NVARCHAR(20),DATEDIFF(microsecond,@dtDate,SYSDATETIME()));			
			SET @dtDate = SYSDATETIME();
		END
		--BUILD in reference tables first
		INSERT INTO #RuleDetailCondensed(DimensionId,RuleOrgXrefId,RuleCode,RuleId,CheckTypeCode,CheckTypeId,EnrollmentFlag,OverridableFlag,LevelId,
			--*rdt
			AccountNotFound,AgeFloor,AllCheckTypes,AmountCeiling,AmountFloor,AmountVariation,Approved,
			CheckMax,CheckNumberFloor,CheckPayeeHistory,ClientSpecific,DaysToBegin,DaysToEnd,DaysToSpan,DaysToSpan2,
			DivisorFactor,EnrollmentLockdownList,GoodPayer,GroupCheckTypes,Ignore,IgnoreEmptySSN,IgnoreSendToXMLApp,
			Inconclusive,ItemOverThreshold,Leveling,MonitorRule,MaxScore,MinScore,MinutesToSpan,NegativeDataExists,NegativeFile,
			NoData,NonMemberBank,NotesToView,NumberVariation,Overlay,PayeeBlackList,PayeePayerTranCeiling,PayeePayerTranFloor,PayeeTranCeiling,
			PayerBlackList,PayerTranCeiling,Percent3090,RoutingAccountCheckFlag,RoutingNumber,SafeListFloor,
			TaxSeasonBegin,TaxSeasonEnd,TranAllowed,TranCeiling,TranFloor,TranFloor2,VerifyCheckSeries,UserName)
		select distinct DimensionId,RuleOrgXrefId,RuleCode,RuleId,CheckTypeCode,CheckTypeId,EnrollmentFlag,OverridableFlag,LevelId,
			--*rdt
			AccountNotFound,AgeFloor,AllCheckTypes,AmountCeiling,AmountFloor,AmountVariation,Approved,
			CheckMax,CheckNumberFloor,CheckPayeeHistory,ClientSpecific,DaysToBegin,DaysToEnd,DaysToSpan,DaysToSpan2,
			DivisorFactor,EnrollmentLockdownList,GoodPayer,GroupCheckTypes,Ignore,IgnoreEmptySSN,IgnoreSendToXMLApp,
			Inconclusive,ItemOverThreshold,Leveling,MonitorRule,MaxScore,MinScore,MinutesToSpan,NegativeDataExists,NegativeFile,
			NoData,NonMemberBank,NotesToView,NumberVariation,Overlay,PayeeBlackList,PayeePayerTranCeiling,PayeePayerTranFloor,PayeeTranCeiling,
			PayerBlackList,PayerTranCeiling,Percent3090,RoutingAccountCheckFlag,RoutingNumber,SafeListFloor,
			TaxSeasonBegin,TaxSeasonEnd,TranAllowed,TranCeiling,TranFloor,TranFloor2,VerifyCheckSeries,UserName
		FROM [condensed].[UtilityRuleDetailCondensed];
		--UPDATE utility with the condensed id
		UPDATE rdc
			SET RuleDetailCondensedId = m.RuleDetailCondensedId
		FROM [condensed].[UtilityRuleDetailCondensed] rdc
		INNER JOIN #RuleDetailCondensed m on
						ISNULL(rdc.DimensionId,0) = ISNULL(m.DimensionId,0)
						AND ISNULL(rdc.RuleOrgXrefId,0) = ISNULL(m.RuleOrgXrefId,0)
						AND ISNULL(rdc.RuleCode,'') = ISNULL(m.RuleCode,'') 
						AND ISNULL(rdc.RuleId,0) = ISNULL(m.RuleId,0) 
						AND ISNULL(rdc.CheckTypeCode,'') = ISNULL(m.CheckTypeCode,'')
						AND ISNULL(rdc.CheckTypeId,0) = ISNULL(m.CheckTypeCode,'')
						AND ISNULL(rdc.EnrollmentFlag,0) = ISNULL(m.EnrollmentFlag,0)
						AND ISNULL(rdc.OverridableFlag,0) = ISNULL(m.OverridableFlag,0)
						AND ISNULL(rdc.LevelId,0) = ISNULL(m.LevelId,0)
						AND ISNULL(rdc.AccountNotFound,'') = ISNULL(m.AccountNotFound,'')
						AND ISNULL(rdc.AgeFloor,0) = ISNULL(m.AgeFloor,0)
						AND ISNULL(rdc.AllCheckTypes,0) = ISNULL(m.AllCheckTypes,0)
						AND ISNULL(rdc.AmountCeiling,0) = ISNULL(m.AmountCeiling,0)
						AND ISNULL(rdc.AmountFloor,0) = ISNULL(m.AmountFloor,0)
						AND ISNULL(rdc.AmountVariation,0) = ISNULL(m.AmountVariation,0)
						AND ISNULL(rdc.Approved,'') = ISNULL(m.Approved,'')
						AND ISNULL(rdc.CheckMax,0) = ISNULL(m.CheckMax,0)
						AND ISNULL(rdc.CheckNumberFloor,0) = ISNULL(m.CheckNumberFloor,0)
						AND ISNULL(rdc.CheckPayeeHistory,0) = ISNULL(m.CheckPayeeHistory,0)
						AND ISNULL(rdc.ClientSpecific,0) = ISNULL(m.ClientSpecific,0)
						AND ISNULL(rdc.DaysToBegin,0) = ISNULL(m.DaysToBegin,0)
						AND ISNULL(rdc.DaysToEnd,0) = ISNULL(m.DaysToEnd,0)
						AND ISNULL(rdc.DaysToSpan,0) = ISNULL(m.DaysToSpan,0)
						AND ISNULL(rdc.DaysToSpan2,0) = ISNULL(m.DaysToSpan2,0)
						AND ISNULL(rdc.DivisorFactor,0) = ISNULL(m.DivisorFactor,0)
						AND ISNULL(rdc.EnrollmentLockdownList,0) = ISNULL(m.EnrollmentLockdownList,0)
						AND ISNULL(rdc.GoodPayer,0) = ISNULL(m.GoodPayer,0)
						AND ISNULL(rdc.GroupCheckTypes,'') = ISNULL(m.GroupCheckTypes,'')
						AND ISNULL(rdc.Ignore,'') = ISNULL(m.Ignore,'')
						AND ISNULL(rdc.IgnoreEmptySSN,'') = ISNULL(m.IgnoreEmptySSN,'')
						AND ISNULL(rdc.IgnoreSendToXMLApp,'') = ISNULL(m.IgnoreSendToXMLApp,'')
						AND ISNULL(rdc.Inconclusive,'') = ISNULL(m.Inconclusive,'')
						AND ISNULL(rdc.ItemOverThreshold,'') = ISNULL(m.ItemOverThreshold,'') 
						AND ISNULL(rdc.Leveling,0) = ISNULL(m.Leveling,0)
						AND ISNULL(rdc.MonitorRule,0) = ISNULL(m.MonitorRule,0)
						AND ISNULL(rdc.MaxScore,0) = ISNULL(m.MaxScore,0)
						AND ISNULL(rdc.MinScore,0) = ISNULL(m.MinScore,0)
						AND ISNULL(rdc.MinutesToSpan,0) = ISNULL(m.MinutesToSpan,0)
						AND ISNULL(rdc.NegativeDataExists,'') = ISNULL(m.NegativeDataExists,'')
						AND ISNULL(rdc.NegativeFile,'') = ISNULL(m.NegativeFile,'')
						AND ISNULL(rdc.NoData,'') = ISNULL(m.NoData,'')
						AND ISNULL(rdc.NonMemberBank,'') = ISNULL(m.NonMemberBank,'')
						AND ISNULL(rdc.NotesToView,0) = ISNULL(m.NotesToView,0)
						AND ISNULL(rdc.NumberVariation,0) = ISNULL(m.NumberVariation,0)
						AND ISNULL(rdc.Overlay,0) = ISNULL(m.Overlay,0)
						AND ISNULL(rdc.PayeeBlackList,0) = ISNULL(m.PayeeBlackList,0)
						AND ISNULL(rdc.PayeePayerTranCeiling,0) = ISNULL(m.PayeePayerTranCeiling,0)
						AND ISNULL(rdc.PayeePayerTranFloor,0) = ISNULL(m.PayeePayerTranFloor,0)
						AND ISNULL(rdc.PayeeTranCeiling,0) = ISNULL(m.PayeeTranCeiling,0)
						AND ISNULL(rdc.PayerBlackList,0) = ISNULL(m.PayerBlackList,0)
						AND ISNULL(rdc.PayerTranCeiling,0) = ISNULL(m.PayerTranCeiling,0)
						AND ISNULL(rdc.Percent3090,0) = ISNULL(m.Percent3090,0)
						AND ISNULL(rdc.RoutingAccountCheckFlag,0) = ISNULL(m.RoutingAccountCheckFlag,0)
						AND ISNULL(rdc.RoutingNumber,0) = ISNULL(m.RoutingNumber,0)
						AND ISNULL(rdc.SafeListFloor,0) = ISNULL(m.SafeListFloor,0)
						AND ISNULL(rdc.TaxSeasonBegin,'') = ISNULL(m.TaxSeasonBegin,'')
						AND ISNULL(rdc.TaxSeasonEnd,'') = ISNULL(m.TaxSeasonEnd,'')
						AND ISNULL(rdc.TranAllowed,0) = ISNULL(m.TranAllowed,0)
						AND ISNULL(rdc.TranCeiling,0) = ISNULL(m.TranCeiling,0)
						AND ISNULL(rdc.TranFloor,0) = ISNULL(m.TranFloor,0)
						AND ISNULL(rdc.TranFloor2,0) = ISNULL(m.TranFloor2,0)
						AND ISNULL(rdc.VerifyCheckSeries,0) = ISNULL(m.VerifyCheckSeries,0);
		IF @bEnableTimer = 1
		BEGIN
			SELECT 'After updating utility.RuleDetailCondensed with CondensedId '+ CONVERT(NVARCHAR(20),DATEDIFF(microsecond,@dtDate,SYSDATETIME()));			
			SET @dtDate = SYSDATETIME();
		END
		--INSERT the unique orgid/ruledetailcondensedid into the xref table
		INSERT INTO #OrgRuleDetailCondensedXref(OrgId,RuleDetailCondensedId,DimensionId)
		SELECT DISTINCT OrgId, RuleDetailCondensedId, @piDimensionId
		FROM [condensed].[UtilityRuleDetailCondensed]
		WHERE DimensionId = @piDimensionId;
		--MAKE A BACKUP COPY OF CURRENT
		SET @dtDate = SYSDATETIME();
	   
		INSERT INTO [archive].[RuleDetailCondensed](RuleDetailCondensedId,DimensionId,RuleOrgXrefId,RuleCode,RuleId,CheckTypeCode,CheckTypeId,EnrollmentFlag,OverridableFlag,LevelId,
			--*rdt
			AccountNotFound,AgeFloor,AllCheckTypes,AmountCeiling,AmountFloor,AmountVariation,Approved,
			CheckMax,CheckNumberFloor,CheckPayeeHistory,ClientSpecific,DaysToBegin,DaysToEnd,DaysToSpan,DaysToSpan2,
			DivisorFactor,EnrollmentLockdownList,GoodPayer,GroupCheckTypes,Ignore,IgnoreEmptySSN,IgnoreSendToXMLApp,
			Inconclusive,ItemOverThreshold,Leveling,MonitorRule,MaxScore,MinScore,MinutesToSpan,NegativeDataExists,NegativeFile,
			NoData,NonMemberBank,NotesToView,NumberVariation,Overlay,PayeeBlackList,PayeePayerTranCeiling,PayeePayerTranFloor,PayeeTranCeiling,
			PayerBlackList,PayerTranCeiling,Percent3090,RoutingAccountCheckFlag,RoutingNumber,SafeListFloor,
			TaxSeasonBegin,TaxSeasonEnd,TranAllowed,TranCeiling,TranFloor,TranFloor2,VerifyCheckSeries,DateActivated,UserName,DateArchived)
		SELECT RuleDetailCondensedId,DimensionId,RuleOrgXrefId,RuleCode,RuleId,CheckTypeCode,CheckTypeId,EnrollmentFlag,OverridableFlag,LevelId,
			--*rdt
			AccountNotFound,AgeFloor,AllCheckTypes,AmountCeiling,AmountFloor,AmountVariation,Approved,
			CheckMax,CheckNumberFloor,CheckPayeeHistory,ClientSpecific,DaysToBegin,DaysToEnd,DaysToSpan,DaysToSpan2,
			DivisorFactor,EnrollmentLockdownList,GoodPayer,GroupCheckTypes,Ignore,IgnoreEmptySSN,IgnoreSendToXMLApp,
			Inconclusive,ItemOverThreshold,Leveling,MonitorRule,MaxScore,MinScore,MinutesToSpan,NegativeDataExists,NegativeFile,
			NoData,NonMemberBank,NotesToView,NumberVariation,Overlay,PayeeBlackList,PayeePayerTranCeiling,PayeePayerTranFloor,PayeeTranCeiling,
			PayerBlackList,PayerTranCeiling,Percent3090,RoutingAccountCheckFlag,RoutingNumber,SafeListFloor,
			TaxSeasonBegin,TaxSeasonEnd,TranAllowed,TranCeiling,TranFloor,TranFloor2,VerifyCheckSeries, DateActivated, UserName, @dtDate
		FROM [condensed].[RuleDetailCondensed]
		WHERE DimensionId = @piDimensionId;
		INSERT INTO [archive].[OrgRuleDetailCondensedXref](OrgRuleDetailCondensedXrefId, OrgId, RuleDetailCondensedId, DateActivated, UserName, DateArchived)
		SELECT OrgRuleDetailCondensedXrefId, OrgId, RuleDetailCondensedId, DateActivated, @pnvUserName, @dtDate
		FROM [condensed].[OrgRuleDetailCondensedXref]
		WHERE DimensionId = @piDimensionId;
		IF @bEnableTimer = 1
		BEGIN
			SELECT 'After Making backup Copy '+ CONVERT(NVARCHAR(20),DATEDIFF(microsecond,@dtDate,SYSDATETIME()));			
			SET @dtDate = SYSDATETIME();
		END
		SET @dtDateActivated = SYSDATETIME();
		
		--LOAD into new tables
		EXECUTE [condensed].[uspTruncateTable] @pnvTargetTable='[new].[RuleDetailCondensed]'
		EXECUTE [condensed].[uspTruncateTable] @pnvTargetTable='[new].[OrgRuleDetailCondensedXref]'

		INSERT INTO [new].[RuleDetailCondensed](DimensionId,RuleOrgXrefId,RuleCode,RuleId,CheckTypeCode,CheckTypeId,EnrollmentFlag,OverridableFlag,LevelId,
			--*rdt
			AccountNotFound,AgeFloor,AllCheckTypes,AmountCeiling,AmountFloor,AmountVariation,Approved,
			CheckMax,CheckNumberFloor,CheckPayeeHistory,ClientSpecific,DaysToBegin,DaysToEnd,DaysToSpan,DaysToSpan2,
			DivisorFactor,EnrollmentLockdownList,GoodPayer,GroupCheckTypes,Ignore,IgnoreEmptySSN,IgnoreSendToXMLApp,
			Inconclusive,ItemOverThreshold,Leveling,MonitorRule,MaxScore,MinScore,MinutesToSpan,NegativeDataExists,NegativeFile,
			NoData,NonMemberBank,NotesToView,NumberVariation,Overlay,PayeeBlackList,PayeePayerTranCeiling,PayeePayerTranFloor,PayeeTranCeiling,
			PayerBlackList,PayerTranCeiling,Percent3090,RoutingAccountCheckFlag,RoutingNumber,SafeListFloor,
			TaxSeasonBegin,TaxSeasonEnd,TranAllowed,TranCeiling,TranFloor,TranFloor2,VerifyCheckSeries,DateActivated,UserName)
		SELECT DimensionId,RuleOrgXrefId,RuleCode,RuleId,CheckTypeCode,CheckTypeId,EnrollmentFlag,OverridableFlag,LevelId,
			--*rdt
			AccountNotFound,AgeFloor,AllCheckTypes,AmountCeiling,AmountFloor,AmountVariation,Approved,
			CheckMax,CheckNumberFloor,CheckPayeeHistory,ClientSpecific,DaysToBegin,DaysToEnd,DaysToSpan,DaysToSpan2,
			DivisorFactor,EnrollmentLockdownList,GoodPayer,GroupCheckTypes,Ignore,IgnoreEmptySSN,IgnoreSendToXMLApp,
			Inconclusive,ItemOverThreshold,Leveling,MonitorRule,MaxScore,MinScore,MinutesToSpan,NegativeDataExists,NegativeFile,
			NoData,NonMemberBank,NotesToView,NumberVariation,Overlay,PayeeBlackList,PayeePayerTranCeiling,PayeePayerTranFloor,PayeeTranCeiling,
			PayerBlackList,PayerTranCeiling,Percent3090,RoutingAccountCheckFlag,RoutingNumber,SafeListFloor,
			TaxSeasonBegin,TaxSeasonEnd,TranAllowed,TranCeiling,TranFloor,TranFloor2,VerifyCheckSeries, @dtDateActivated, @pnvUserName
		FROM #RuleDetailCondensed
		ORDER BY RuleDetailCondensedId;
	  
		INSERT INTO [new].[OrgRuleDetailCondensedXref](OrgId,RuleDetailCondensedId,DimensionId,DateActivated)
		SELECT OrgId,RuleDetailCondensedId,DimensionId,@dtDateActivated
		FROM #OrgRuleDetailCondensedXref
		ORDER BY OrgRuleDetailCondensedXrefId;
		IF @bEnableTimer = 1
		BEGIN
			SELECT 'After Loading Online Tables '+ CONVERT(NVARCHAR(20),DATEDIFF(microsecond,@dtDate,SYSDATETIME()));			
			SET @dtDate = SYSDATETIME();
		END

		--NOW switch the tables, minimizing impact
		BEGIN TRAN
			--Anyone who tries to query the table after the switch has happened and before
			--the transaction commits will be blocked: we've got a schema mod lock on the table

			--cycle out Current RuleDetailCondensed
			ALTER TABLE [Condensed].[condensed].[RuleDetailCondensed] SWITCH PARTITION 1 TO [Condensed].[old].[RuleDetailCondensed] PARTITION 1
				WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));  

			--Cycle in New RuleDetailCondensed
			ALTER TABLE [Condensed].[new].[RuleDetailCondensed] SWITCH PARTITION 1 TO [Condensed].[condensed].[RuleDetailCondensed] PARTITION 1
				WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));

			-- Cycle Old to New
			ALTER TABLE [Condensed].[old].[RuleDetailCondensed] SWITCH PARTITION 1 TO [Condensed].[new].[RuleDetailCondensed] PARTITION 1
				WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));  
		COMMIT
		BEGIN TRAN
			--Anyone who tries to query the table after the switch has happened and before
			--the transaction commits will be blocked: we've got a schema mod lock on the table

			--cycle out Current OrgRuleDetailCondensedXref
			ALTER TABLE [Condensed].[condensed].[OrgRuleDetailCondensedXref] SWITCH PARTITION 1 TO [Condensed].[old].[OrgRuleDetailCondensedXref] PARTITION 1
				WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));  

			--Cycle in New OrgRuleDetailCondensedXref
			ALTER TABLE [Condensed].[new].[OrgRuleDetailCondensedXref] SWITCH PARTITION 1 TO [Condensed].[condensed].[OrgRuleDetailCondensedXref] PARTITION 1
				WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));

			-- Cycle Old to New
			ALTER TABLE [Condensed].[old].[OrgRuleDetailCondensedXref] SWITCH PARTITION 1 TO [Condensed].[new].[OrgRuleDetailCondensedXref] PARTITION 1
				WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));  
		COMMIT
		----CURRENT to Old
		--EXEC [Condensed].[sys].[sp_rename] N'condensed.RuleDetailCondensed.pkRuleDetailCondensed', N'pkOldRuleDetailCondensed', N'INDEX';
		--EXEC [Condensed].[sys].[sp_rename] N'condensed.RuleDetailCondensed',N'OldRuleDetailCondensed';
		--EXEC [Condensed].[sys].[sp_rename] N'condensed.OrgRuleDetailCondensedXref.pkOrgRuleDetailCondensedXref', N'pkOldOrgRuleDetailCondensedXref', N'INDEX';
		--EXEC [Condensed].[sys].[sp_rename] N'condensed.OrgRuleDetailCondensedXref',N'OldOrgRuleDetailCondensedXref';
		----NEW to Current
		--EXEC [Condensed].[sys].[sp_rename] N'condensed.NewRuleDetailCondensed.pkNewRuleDetailCondensed', N'pkRuleDetailCondensed', N'INDEX';
		--EXEC [Condensed].[sys].[sp_rename] N'condensed.NewRuleDetailCondensed',N'RuleDetailCondensed';
		--EXEC [Condensed].[sys].[sp_rename] N'condensed.NewOrgRuleDetailCondensedXref.pkNewOrgRuleDetailCondensedXref', N'pkOrgRuleDetailCondensedXref', N'INDEX';
		--EXEC [Condensed].[sys].[sp_rename] N'condensed.NewOrgRuleDetailCondensedXref',N'OrgRuleDetailCondensedXref';
		----OLD to New for next time
		--EXEC [Condensed].[sys].[sp_rename] N'condensed.OldRuleDetailCondensed.pkOldRuleDetailCondensed', N'pkNewRuleDetailCondensed', N'INDEX';
		--EXEC [Condensed].[sys].[sp_rename] N'condensed.OldRuleDetailCondensed',N'NewRuleDetailCondensed';
		--EXEC [Condensed].[sys].[sp_rename] N'condensed.OldOrgRuleDetailCondensedXref.pkOldOrgRuleDetailCondensedXref', N'pkNewOrgRuleDetailCondensedXref', N'INDEX';
		--EXEC [Condensed].[sys].[sp_rename] N'condensed.OldOrgRuleDetailCondensedXref',N'NewOrgRuleDetailCondensedXref';

		IF @bEnableTimer = 1
		BEGIN
			SELECT 'After Loading Online Tables '+ CONVERT(NVARCHAR(20),DATEDIFF(microsecond,@dtDate,SYSDATETIME()));			
			SET @dtDate = SYSDATETIME();
		END

	END
	ELSE
		SELECT 'No new updates to process'
END
