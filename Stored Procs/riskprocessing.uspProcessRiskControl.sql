USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspProcessRiskControl
	CreatedBy: Larry Dugger
	Descr: This procedure travels the risk control structure 
		Processes an RC ladder collection.
		Expects a single 'Process' record 
		RiskProcesses multiple 'Item', submitting singularly. 
	Tables: [riskprocessing].[RPResult]
		,[ifa].[ItemListType]
		,[rule].[RuleDetailType]
      
	Functions: [common].[ufnRCLadderTopByOrg]
		,[common].[ufnCurrentRuleDetail]
		,[common].[ufnRCLadderTopLadderTopXrefTreeMini]
		,[common].[ufnCustomerItemList]
		,[riskprocessing].[ufnTraverseLadder]
		,[common].[ufnItemFinancialCustomerStat]
		,[common].[ufnItemAccountUtilizationStat]
		,[common].[ufnItemFinancialPayerStat]
		,[common].[ufnItemFinancialKCPStat]
		,[common].[ufnItemOLTPStat]
		,[common].[ufnItemRetailStat]
		,[common].[ufnItemRetailSupplementalStat]
		,[common].[ufnItemDeluxeStat]
		,[common].[ufnItemIRDStat]
		,[common].[ufnItemAction]

	History:
		2015-11-10 - LBD - Created
		2020-02-07 - LBD - Recreated, Reduced the overhead by migrating most lookups to
			parent procedures
		2020-03-11 - LBD - Added @ptblMiscStat CCF1905
		2020-04-21 - LBD - adjustment to return DBProcessResult correctly
		2020-06-03 - LBD - Adjusted logging so it operates without locking (unless necessary)
*****************************************************************************************/
ALTER   PROCEDURE [riskprocessing].[uspProcessRiskControl](
	 @pnvProcessKey NVARCHAR(25)
	,@ptblAutoFraud [ifa].[AutoFraudType] READONLY
	,@ptblItemCurrent [ifa].[ItemCurrentType] READONLY
	,@ptblItemList [ifa].[ItemListType] READONLY
	,@ptblLadderRung [riskprocessing].[LadderRungType] READONLY
	,@ptblMiscStat [ifa].[MiscStatType] READONLY
	,@ptblRCLadder [riskprocessing].[RCLadderType] READONLY	
	,@ptblRuleDetail [rule].[RuleDetailType] READONLY
	,@ptblStat [ifa].[StatType] READONLY
	,@pxTableSet XML OUTPUT									--Return complete stat list, CurrentItem in XML 
) AS
BEGIN
	DECLARE @iLogLevel int = ISNULL(TRY_CONVERT(INT,[common].[ufnConfigValue](N'LogLevel [riskprocessing].[uspProcessRiskControl]')),1) --2019-08-23 LBD
		,@dtTimerDate datetime2(7)= SYSDATETIME()
		,@dtInitial datetime2(7) = SYSDATETIME() --used for complete time in procedure
		,@ncSchemaName nchar(20) = CONVERT(nchar(20),OBJECT_SCHEMA_NAME(@@PROCID))
		,@ncObjectName nchar(50) = CONVERT(nchar(50),OBJECT_NAME(@@PROCID))
		,@ncProcessKey nchar(25) = @pnvProcessKey
		,@ncMsg nchar(50);

	IF @iLogLevel > 0
	BEGIN
		INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Enter' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  					
		SET @dtTimerDate = SYSDATETIME();	
	END					

	--BE SURE TO POPULATE THESE
	DECLARE @tblRPResult [riskprocessing].[RPResultType]
		,@tblRPResultStat [ifa].[ItemStatType];

	DECLARE @dtExecuted datetime2(7)
		,@biMicroSeconds bigint = 0
		,@iRCLadderTopId int
		,@iRCId int
		,@iLadderTopXrefId int
		,@iLadderTopId int
		,@iLadderSuccessLTXId int
		,@iSuccessLtId int
		,@iLadderContinueLTXId int
		,@iContinueLtId int
		,@nvRCCollectionName nvarchar(50)
		,@nvLadderCollectionName nvarchar(50)
		,@nvLadderSuccessValue nvarchar(50)
		,@iNextLadderTopXrefId int = -1		--we initialize to some non-zero value
		,@iNextLadderTopId int
		,@iRPResult int = 0					--initialized to zero;

	IF @iLogLevel > 1
	BEGIN
		INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Imported Parameter Tables',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  					
		SET @dtTimerDate  = SYSDATETIME();					
	END

	--1 Grab initial ladder, setting @iLadderTopId to the initial Ladder 
	SELECT @iRCLadderTopId=RCLadderTopId
		,@iRCId=RCId
		,@iLadderTopXrefId=LadderTopXrefId
		,@iNextLadderTopXrefId=LadderTopXrefId
		,@iLadderTopId=LadderTopId
		,@iLadderSuccessLTXId=LadderSuccessLTXId
		,@iSuccessLtId=SuccessLtId
		,@iLadderContinueLTXId=LadderContinueLTXId
		,@iContinueLtId=ContinueLtId
		,@nvRCCollectionName=RCCollectionName
		,@nvLadderCollectionName=LadderCollectionName
		,@nvLadderSuccessValue=LadderSuccessValue
	FROM @ptblRCLadder
	WHERE Id = 1; 
	--2 walk the path, generate ladder steps using prior Boolean result
	WHILE @iNextLadderTopXrefId > 0
	BEGIN
		--3 Determine which of the defined processes to execute, represented here by their riskprocessing.DBProcess.Code
		--ALL dbprocesses are table functions, returning a boolean and a message
		INSERT INTO @tblRPResult(ItemId,LadderTopId,LadderDBprocessXrefId,LadderResult,DBProcessResult,Msg,StatusFlag,DateCompleted,DBProcessCode)
		SELECT ItemId,LadderTopId,LadderDBProcessXrefId,LadderResult,DBProcessResult,Msg,StatusFlag,DateCompleted,DBProcessCode
		FROM [riskprocessing].[ufnTraverseLadder](@iLadderTopId,@ptblAutoFraud,@ptblItemCurrent,@ptblItemList,@ptblLadderRung,@ptblMiscStat,@ptblRuleDetail,@ptblStat)
		--2020-03-11 FROM [riskprocessing].[ufnTraverseLadder](@iLadderTopId,@ptblAutoFraud,@ptblItemCurrent,@ptblItemList,@ptblLadderRung,@ptblRuleDetail,@ptblStat)
		ORDER BY Id; 
		--4 What is the ladder result?, what 'ladder' is next?
		SELECT @iRPResult = LadderResult
			,@iNextLadderTopXrefId = CASE WHEN LadderResult = CONVERT(int,@nvLadderSuccessValue) THEN @iLadderSuccessLTXId ELSE @iLadderContinueLTXId END
			,@iNextLadderTopId = CASE WHEN LadderResult = CONVERT(int,@nvLadderSuccessValue) THEN @iSuccessLtId ELSE @iContinueLtId END
		FROM @tblRPResult
		WHERE LadderTopId = @iLadderTopId
			AND ISNULL(LadderResult,-9999) <> -9999
		ORDER BY ID DESC;
		--5 Grab next ladder
		IF @iNextLadderTopXrefId > 0
		BEGIN
			SELECT @iRCLadderTopId=RCLadderTopId
				,@iRCId=RCId
				,@iLadderTopXrefId=LadderTopXrefId
				,@iLadderTopId=LadderTopId
				,@iLadderSuccessLTXId=LadderSuccessLTXId
				,@iSuccessLtId=SuccessLtId
				,@iLadderContinueLTXId=LadderContinueLTXId
				,@iContinueLtId=ContinueLtId
				,@nvRCCollectionName=RCCollectionName
				,@nvLadderCollectionName=LadderCollectionName
				,@nvLadderSuccessValue=LadderSuccessValue
			FROM @ptblRCLadder
			WHERE LadderTopXrefId = @iNextLadderTopXrefId;
		END
		--NOTE We don't generate any 'result' messages here, that is all handled by the 'ladders'
	END--WHILE @iNextLadderTopXrefId > 0
	--For this Item we now know the RC result, compare and update...
	UPDATE rp
		SET RCResult = LadderResult
	FROM @tblRPResult rp
	INNER JOIN (SELECT MAX(id) as MaxId FROM @tblRPResult) rp0 on rp.Id = rp0.MaxId;
	--6 Save the results...
	INSERT INTO [riskprocessing].[RPResult](ItemId, LadderTopId, LadderDBProcessXrefId, RCResult, LadderResult
		,DBProcessResult, Msg, StatusFlag, DateCompleted, DateActivated, UserName)
	SELECT ItemId,LadderTopId,LadderDBprocessXrefId, RCResult, LadderResult
		,DBProcessResult,Msg,StatusFlag,ISNULL(DateCompleted,'1900-01-01'),SYSDATETIME(), 'System'--traps errors
	FROM @tblRPResult
	WHERE EXISTS (SELECT 'X' FROM @tblRPResult)
	ORDER BY Id;

	IF @iLogLevel > 1
	BEGIN
		INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Insert RPResults',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
		SET @dtTimerDate = SYSDATETIME();
	END

	--RPResults Final Ladder Result
	INSERT INTO @tblRPResultStat(ItemId,StatName,StatValue)
	SELECT unpvt.ItemId, unpvt.StatName, unpvt.StatValue as StatValue
	FROM (SELECT rp.ItemId
			,TRY_CONVERT(NVARCHAR(100),rp.LadderResult) AS RPLadderResult
			,TRY_CONVERT(NVARCHAR(100),rp.Msg) AS RPMsg
		FROM @tblRPResult rp
		INNER JOIN (SELECT MAX(id) as MaxId FROM @tblRPResult) rp0 on rp.Id = rp0.MaxId
		) stat
		UNPIVOT
			(StatValue FOR StatName IN ( RPLadderResult, RPMsg ) 
		) AS unpvt;
	--RPResults Final DBProcess Result
	INSERT INTO @tblRPResultStat(ItemId,StatName,StatValue)
	SELECT unpvt.ItemId, unpvt.StatName, unpvt.StatValue as StatValue
	FROM (SELECT rp.ItemId
			,TRY_CONVERT(NVARCHAR(100),rp.DBProcessResult) AS DBProcessResult --2020-04-21 was LadderResult which is null
			,TRY_CONVERT(NVARCHAR(100),rp.Msg) AS DBProcessMsg
			,TRY_CONVERT(NVARCHAR(100),lr.ProcessName) AS DBProcessName
		FROM @tblRPResult rp
		INNER JOIN @ptblLadderRung lr on rp.LadderDBprocessXrefId = lr.LadderDBProcessXrefId
		INNER JOIN (SELECT MAX(Id)-1 as MaxIdMinus1 FROM @tblRPResult) rp0 on rp.Id = rp0.MaxIdMinus1
		) stat
		UNPIVOT
			(StatValue FOR StatName IN ( DBProcessResult, DBProcessMsg, DBProcessName ) 
		) AS unpvt;
	--Return this data
	SELECT @pxTableSet = (SELECT ItemId, StatName, StatValue
						FROM @tblRPResultStat Stat
						ORDER BY 1
						FOR XML PATH ('Stat')--element set identifier
					)

	--Last Message uses @dtInitial
	IF @iLogLevel > 0
		INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Exit' ,DATEDIFF(microsecond,@dtInitial,SYSDATETIME()),SYSDATETIME());

END
