USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [ifa].[uspItemInsertOut]
	Created By: Larry Dugger
	Descr: This procedure will insert a new record, ABA verification is limited do
		to the  data being provided via the WSDL i.e. 'CheckPC' is defaulted to 0.
	Tables: [debug].[CannedRuleBreak]
		,[ifa].[Item]
		,[ifa].[ItemResponseType]
		,[ifa].[RuleBreakDataType]
		,[ifa].[TransactionKey]
		,[ifa].[RuleBreakData]
		,[financial].[ItemActivity]
		,[retail].[ItemActivity]
		,[payer].[Payer]
		,[stat].[Customer]
		,[stat].[Payer]
	Functions: [common].[ufnTransactionType]
		,[common].[ufnItemStatus]
		,[common].[ufnStatusFlag]
		,[common].[ufnItemType]
		,[common].[ufnRSubStr]
		,[common].[ufnABADataFix]
		,[common].[ufnResponseCode]
	Procedures: [error].[uspLogErrorDetailInsertOut]
	History:
		2015-05-07 - LBD - Created
		2020-03-03 - LBD - Recreated, reduced overhead, by migrating most lookups to 
			parent procedures. Elimited repeated calls for data that doesn't change.
			Isolated debug section.
		2020-02-09 - LBD - Remove 'BadField Filter until reviewed.
		2020-02-18 - LBD - Added in support for PNC Teller Account and Check Numbers.
			This is inactive until field definitions are changed, which should be 
			accompanied by risk processing changes. Corrected issue with ItemActivity
			creation/updates based ON ProcessMethodology paired 
			'Authorized' with 'Pre-Authorization'.
		2020-03-04 - LBD - Moved initial variable load so logging has processkey CCF1896
		2020-03-11 - LBD - Added population of [authorized].[ItemActivityDetail] CCF1905
			changed type definition of @ptblMiscStat to avoid truncation of data
		2020-04-07 - LBD - Changed logic for PNC Mobile '000000518' Routing numbers
			to use the MICR - CCF1943, only call DeMICR for TDB when provided CheckNumber = 0
		2020-04-17 - LBD - Adjusted to handle CheckType 63 logic, ItemActivity proceduralization,
			rules requirement, 518 flip for MTB...
		2020-06-03 - LBD - Adjusted logging so it operates without locking (unless necessary)
		2020-06-22 - LBD - Added 5th3rd (FTB) debug code...
		2020-09-03 - LBD - Added Fiserv Integrated debug code...
		2020-09-13 - LBD - Adjusted FTB debug code
		2020-10-16 - LBD - Adjusted debug code relative to DisableMultiItemRiskProcessing,
			also place process stats into @tblStat earlier.
		2020-10-21 - LBD - Converted the debug section to use the defined responsecodes
			for the specific Org, requires the [organization].[OrgResponseCodeXref] 
			to be define for the org or a hierarchical parent, typically defined at Client
			also realigned the '-debugrulebreaks' -1 to -9
			Adjusted 'RED|001' and 'RED|002' to correctly output the actual Descr
		2020-10-23 - LBD - Moved DisableMultiItemRiskProcessing retrieval up
			and added commented-out section to bypass risk processing altogether
			should that be the final decision (serious performance improvement)
		2020-11-10 - CBS - Per email from Mike R, agreed upon third party identifier will
			be 'THIRDPARTY00000000' instead of 'THIRDPARTY000000000'
		2020-11-18 - LBD - Replace SUBPRDCT with PRDCT-CD
		2020-12-03 - LBD - Incorporated 'PNC' MaxItemsExceed and DisableMultiItemRiskProcessing 
			into the same function and flag 'MaxItemsExceeded'
			,correctly set Item.RuleBreakDesc to the response code associated with the Client
			,ensure RuleBreakData has the proper Code and [Message]
			,eliminate the confusion of @tblItemRBDebug, replacing population of two temp tables
			with one @tblItemRB0 that captures rulebreak, code, and rulebreakresponse
			only transfer to @tblItemRB for Item and ItemActivity updates
		2020-12-08 - LBD - Adjusted FTB ABA filed replacement mirror the 'MICR'
			calculation (RTN len, ACCT an CHK = 0).
		2020-01-11 - LBD - adjust for debugtypeid 6 and 'B9' subproductcode, CCF2347.
		2020-01-16 - LBD - remove duplicate record insertion into @tblStatKey per CCF2362
		2021-03-01 - LBD - Reduce contention around AutoFraud reads
		2021-03-25 - LBD - Added new MICR logic for NFCU CCF2471.
		2021-04-23 - LBD - Corrected NFCU code for MTB mobile (should have been teller)
		2021-09-01 - LBD - Adjusted adding ItemId to the Stat Listing, Brisk version 2021.1
		2021-11-09 - CBS - Moving the call of ufnItemBriskStat to just after the call to ufnItemAtomicStat.
			We're missing the Customer stats when called from within ufnItemAtomicStat.	
		2022-02-04 - CBS - VALID-96: Moving the FTB specific Misc insert into @tblStat to ufnItemAtomicStat.
			Removed old commented out sections of code
		2022-04-04 - LBD - VALID-211. Adding support for D2C transactions. 
		2024-01-31 - CBS - VALID-1596: Adding DeMICR support for TFB and '000000518'.
*****************************************************************************************/
ALTER PROCEDURE [ifa].[uspItemInsertOut](
	 @ptblAvailableCheckTypeCode [ifa].[CheckTypeCodeType] READONLY
	,@ptblDecisionField [ifa].[DecisionFieldType] READONLY
	,@ptblItemRequest [ifa].[ItemRequestType] READONLY
	,@ptblProcessAutoFraud [ifa].[AutoFraudType] READONLY
	,@ptblProcessStat [ifa].[StatType] READONLY
	,@ptblItemList [ifa].[ItemListType] READONLY
	,@ptblLadderRung [riskprocessing].[LadderRungType] READONLY
	,@ptblMiscStat [ifa].[MiscStatType] READONLY
	,@ptblRCLadder [riskprocessing].[RCLadderType] READONLY
	,@ptblRuleDetail [rule].[RuleDetailType] READONLY
	,@ptblStatKey [ifa].[StatKeyType] READONLY
	,@pbiItemId BIGINT OUTPUT
	,@pxTableSet XML OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @iLogLevel int = ISNULL(TRY_CONVERT(INT,[common].[ufnConfigValue](N'LogLevel [ifa].[uspItemInsertOut]')),1)	
		,@iCheckDuplicateItem int = ISNULL(TRY_CONVERT(INT,[common].[ufnConfigValue](N'CheckDuplicateItem [ifa].[uspItemInsertOut]')),0) 
		,@dtTimerDate datetime2(7) = SYSDATETIME()
		,@dtInitial datetime2(7) = SYSDATETIME() --used for complete time in procedure
		,@ncSchemaName nchar(20) = CONVERT(nchar(20),OBJECT_SCHEMA_NAME(@@PROCID))
		,@ncObjectName nchar(50) = CONVERT(nchar(50),OBJECT_NAME(@@PROCID))
		,@iErrorDetailId int
		,@iCurrentTransactionLevel int
		,@sSchemaName nvarchar(128) = OBJECT_SCHEMA_NAME(@@PROCID)
		,@iOrgId int
		,@iOrgClientId int
		,@biProcessId bigint
		,@bFirstDataClient bit = 0
		,@bPNCClient bit = 0
		,@bTDClient bit = 0
		,@bMTBClient bit = 0		--2020-04-17
		,@bFTBClient bit = 0		--2020-09-13
		,@bTFBClient bit = 0		--2024-01-31
		,@ncProcessKey nchar(25)
		,@nvProcessKey nvarchar(25)
		,@iProcessMethodology int
		,@nvChannelName nvarchar(25) 
		,@nvUserName nvarchar(100)
		,@bDebug bit = 0
		,@iCnt int
		,@iPayerMissingCnt int = 0	
		,@iItemCnt int = 0			
		,@iItemRBCnt int			
		,@iTransactionTypeId int = [common].[ufnTransactionType]('Item')
		,@biItemId bigint
		,@iInitialItemStatusId int = [common].[ufnItemStatus]('Initial')
		,@iProcessedItemStatusId int = [common].[ufnItemStatus]('Processed')
		,@iUnknownClientAcceptedId int = [common].[ufnClientAccepted]('Unknown') 
		,@iFinByProxyItemStatusId int = [common].[ufnItemStatus]('FinByProxy')
		,@iGovernmentAssistanceCheckTypeId int =[common].[ufnGetCheckType]('Government Assistance') --2020-04-17
		,@iStatusFlag int = [common].[ufnStatusFlag]('Active')
		,@nvRuleBreak nvarchar(25) = N''
		,@nvRuleBreakResponse nvarchar(255) = N''
		,@mAmount money = 0.0
		,@xItem xml
		,@xPayer xml
		,@xRuleBreakData xml
		,@xProcessAndItemStat xml
		,@xDebugStat xml
		,@xD2CStat xml
		,@nvCustomeridentifier nvarchar(50) = NULL
		,@nvInternalBankAccountNumber nvarchar(50) = NULL
		,@nvError nvarchar(25)
		,@bMaxItemsExceeded bit = 0
		,@nvSUBPRDCT nvarchar(25) = NULL;

	--2020-03-04
	--THESE are populated even when MaxItemExceeded = 1
	SELECT @iOrgId = OrgId
		,@iOrgClientId = OrgClientId	
		,@biProcessId = ProcessId
		,@bFirstDataClient = CASE WHEN OrgClientExternalCode = 'TCClnt' THEN 1 ELSE 0 END
		,@bPNCClient = CASE WHEN OrgClientExternalCode = 'PNC' THEN 1 ELSE 0 END
		,@bTDClient = CASE WHEN OrgClientExternalCode = 'TDClnt' THEN 1 ELSE 0 END
		,@bMTBClient = CASE WHEN OrgClientExternalCode = 'MTBClnt' THEN 1 ELSE 0 END				--2020-04-17
		,@bFTBClient = CASE WHEN OrgClientExternalCode = 'FTBClnt' THEN 1 ELSE 0 END				--2020-09-13
		,@bTFBClient = CASE WHEN OrgClientExternalCode = 'TFBClnt' THEN 1 ELSE 0 END				--2024-01-31
		,@bDebug = Debug
		,@ncProcessKey = ProcessKey
		,@nvProcessKey = ProcessKey
		,@nvChannelName = OrgChannelName
		,@nvCustomerIdentifier = CustomerIdentifier
		,@nvInternalBankAccountNumber = InternalBankAccountNumber
		,@iProcessMethodology = ProcessMethodology
		,@bMaxItemsExceeded = MaxItemsExceeded
		,@nvUserName = UserName
		,@iItemCnt = ItemCount
	FROM @ptblDecisionField;

	IF @iLogLevel > 0
	BEGIN
		INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Enter' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
		SET @dtTimerDate  = SYSDATETIME();
	END

	DECLARE @tblItem [ifa].[ItemType]
		,@tblAutoFraud [ifa].[AutoFraudType]
		,@tblCannedRuleBreak [debug].[DebugType]
		,@tblItemCurrent [ifa].[ItemCurrentType]
		,@tblItemRB [ifa].[ItemType]
		,@tblStat [ifa].[StatType]
		,@tblStatKey [ifa].[StatKeyType]
		,@tblRuleDetail [rule].[RuleDetailType]
		,@tblPayerIR [payer].[PayerIRType]; --2020-04-17

	--IMPORT ProcessAutoFraud
	INSERT INTO @tblAutoFraud(AutoFraudId,AutoFraudTypeId,AutoFraudTypeCode,OrgId,KeyId,KeyIdType)
	SELECT AutoFraudId,AutoFraudTypeId,AutoFraudTypeCode,OrgId,KeyId,KeyIdType
	FROM @ptblProcessAutoFraud;

	--IMPORT RuleDetail into local table, for most transactions nothing is passed in.
	INSERT INTO @tblRuleDetail(RuleOrgXrefId,RuleCode,RuleId,CheckTypeCode,CheckTypeId,EnrollmentFlag,OverridableFlag,LevelId,AccountNotFound,AgeFloor,AllCheckTypes
		,AmountCeiling,AmountFloor,AmountVariation,Approved,CheckMax,CheckNumberFloor,CheckPayeeHistory,ClientSpecific,DaysToBegin,DaysToEnd
		,DaysToSpan,DaysToSpan2,DivisorFactor,EnrollmentLockdownList,GoodPayer,GroupCheckTypes,Ignore,IgnoreEmptySSN,IgnoreSendToXMLApp,Inconclusive
		,ItemOverThreshold,Leveling,MonitorRule,MaxScore,MinScore,MinutesToSpan,NegativeDataExists,NegativeFile,NoData,NonMemberBank,NotesToView
		,NumberVariation,Overlay,PayeeBlackList,PayeePayerTranCeiling,PayeePayerTranFloor,PayeeTranCeiling,PayerBlackList,PayerTranCeiling,Percent3090
		,RoutingAccountCheckFlag,RoutingNumber,SafeListFloor,TaxSeasonBegin,TaxSeasonEnd,TranAllowed,TranCeiling,TranFloor,TranFloor2,VerifyCheckSeries)
	SELECT RuleOrgXrefId,RuleCode,RuleId,CheckTypeCode,CheckTypeId,EnrollmentFlag,OverridableFlag,LevelId,AccountNotFound,AgeFloor,AllCheckTypes
		,AmountCeiling,AmountFloor,AmountVariation,Approved,CheckMax,CheckNumberFloor,CheckPayeeHistory,ClientSpecific,DaysToBegin,DaysToEnd
		,DaysToSpan,DaysToSpan2,DivisorFactor,EnrollmentLockdownList,GoodPayer,GroupCheckTypes,Ignore,IgnoreEmptySSN,IgnoreSendToXMLApp,Inconclusive
		,ItemOverThreshold,Leveling,MonitorRule,MaxScore,MinScore,MinutesToSpan,NegativeDataExists,NegativeFile,NoData,NonMemberBank,NotesToView
		,NumberVariation,Overlay,PayeeBlackList,PayeePayerTranCeiling,PayeePayerTranFloor,PayeeTranCeiling,PayerBlackList,PayerTranCeiling,Percent3090
		,RoutingAccountCheckFlag,RoutingNumber,SafeListFloor,TaxSeasonBegin,TaxSeasonEnd,TranAllowed,TranCeiling,TranFloor,TranFloor2,VerifyCheckSeries
	FROM @ptblRuleDetail;

	--Need to be able to update and add additional tracking fields
	DECLARE @tblItemRequest table(
		ItemTypeCode nvarchar(25)
		,ClientItemId nvarchar(50)
		,ItemKey nvarchar(25)
		,CheckTypeCode nvarchar(25)
		,[Date] datetime
		,CheckAmount money
		,MICR nvarchar(255)
		,RoutingNumber nchar (9)
		,AccountNumber nvarchar(50)
		,CheckNumber nvarchar(50)
		,Scanned bit
		,AcctChkNbrSwitch bit
		,OriginalCheckTypeCode nvarchar(25)
		,OriginalRoutingNumber nchar (9)
		,OriginalAccountNumber nvarchar(50)
		,OriginalCheckNumber nvarchar(50)
		,BadField bit
	);
	DECLARE @tblMICR TABLE (
		ItemKey nvarchar(25)
		,RoutingNumber nchar(9)
		,AccountNumber nvarchar(50)
		,CheckNumber nvarchar(50)
		,CheckPC nvarchar(50)
		,IRD bit
		,ValidMICR bit
		,SwitchRTN bit
		,SwitchACNT bit
		,SwitchCHK bit
	);
	--USED to store actual RuleBreakData
	DECLARE @tblItemRB0 Table (
		ItemId bigint
		,RuleBreak nvarchar(25)
		,Code nvarchar(25)
		,RuleBreakResponse nvarchar(255)
		,Fee money
		,Amount money
		,ItemStatusId int
	);
	DECLARE @tblRuleBreakData Table (
		RuleBreakDataid bigint
		,ItemId bigint
		,Code nvarchar(25)
		,[Message] nvarchar(255)
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @tblItemType table(
		ItemTypeId int
		,Code nvarchar(25)
		,ItemKey nvarchar(25) 
	);
	DECLARE @tblPayer table(
		PayerId bigint
		,[Name] nvarchar(50)
		,RoutingNumber nchar(9)
		,AccountNumber nvarchar(50)
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @tblDebugDuplicateItem table(
		ItemId bigint
		,DuplicateItem bit
	);

	--ONLY DE-MICR UNDER STRICT CLIENT CONDITIONS
	INSERT INTO @tblMICR(ItemKey,RoutingNumber,AccountNumber,CheckNumber,CheckPC,IRD,ValidMICR,SwitchRTN,SwitchACNT,SwitchCHK)
	SELECT ir.ItemKey,d.RoutingNumber,d.AccountNumber,d.CheckNumber,d.CheckPC,d.IRD, d.ValidMICR,
		CASE WHEN d.ValidMICR = 1 
			AND ((@bPNCClient = 1 AND @nvChannelName = 'ATM')
				OR (@bFTBClient = 1 AND LEN(ISNULL(ir.RoutingNumber,'')) < 9)
				) THEN 1
			ELSE 0
		END as SwitchRTN,
		CASE WHEN d.ValidMICR = 1 
			AND ((@bPNCClient = 1 AND ir.RoutingNumber <> '256074974')
				OR @bMTBClient = 1 
				OR @bFTBClient = 1
				OR @bTFBClient = 1 AND ir.RoutingNumber = '000000518' --2024-01-31
				) THEN 1
			ELSE 0
		END as SwitchACNT,
		CASE WHEN d.ValidMICR = 1
			AND (@bPNCClient = 1 
				OR @bTDClient = 1 
				OR @bMTBClient = 1 
				OR @bFTBClient = 1
				OR @bTFBClient = 1 --2024-01-31
				) THEN 1
			ELSE 0
		END as SwitchCHK
	FROM @ptblItemRequest ir
	CROSS APPLY [common].[ufnDeMICR](MICR) d
	WHERE (@bPNCClient = 1
			AND (@nvChannelName = 'ATM'
					AND ir.RoutingNumber <> '256074974')
				OR (@nvChannelName = 'Mobile'
					AND ir.RoutingNumber = '000000518')
			)
		OR (@bTFBClient = 1 --2024-01-31
			AND ir.RoutingNumber = '000000518' --2024-01-31
			)
		OR (@bMTBClient = 1
			AND @nvChannelName = 'Mobile'
			AND ir.RoutingNumber = '000000518'
			)
		OR (@bTDClient = 1
			AND [common].[ufnCleanCheckNumber](ir.CheckNumber) = '0'
			AND ir.RoutingNumber <> '256074974'
			)
		OR (@bFTBClient = 1
			--2021-04-23 AND (@nvChannelName <> 'Mobile'
			--	OR (@nvChannelName = 'Mobile'
			AND (@nvChannelName <> 'Teller'		--2021-04-23
				OR (@nvChannelName = 'Teller'	--2021-04-23
					AND ir.RoutingNumber <> '256074974'))
			AND (LEN(ISNULL(ir.RoutingNumber,'')) < 9
				OR [common].[ufnCleanAccountNumber](ir.AccountNumber) = '0'
				OR [common].[ufnCleanCheckNumber](ir.CheckNumber) = '0')
			);

	--ONLY DE-MICRNFCU UNDER STRICT CLIENT CONDITIONS
	INSERT INTO @tblMICR(ItemKey,RoutingNumber,AccountNumber,CheckNumber,CheckPC,IRD,ValidMICR,SwitchRTN,SwitchACNT,SwitchCHK)
	SELECT ir.ItemKey,d.RoutingNumber,d.AccountNumber,d.CheckNumber,d.CheckPC,d.IRD, d.ValidMICR,
		0 as SwitchRTN,
		d.ValidMICR as SwitchACNT,
		d.ValidMICR as SwitchCHK
	FROM @ptblItemRequest ir
	CROSS APPLY [common].[ufnDeMICRNFCU](MICR) d
	WHERE (@bPNCClient = 1
			AND ir.RoutingNumber = '256074974'
			AND (@nvChannelName = 'ATM'
				OR @nvChannelName = 'Teller')
			)
		OR (@bMTBClient = 1
			AND @nvChannelName = 'Mobile'
			AND ir.RoutingNumber = '256074974'
			)
		OR (@bTDClient = 1
			AND @nvChannelName = 'Teller'
			AND ir.RoutingNumber = '256074974'
			)
		OR (@bFTBClient = 1
			--2021-04-23 AND @nvChannelName = 'Mobile'
			AND @nvChannelName = 'Teller' --2021-04-23
			AND ir.RoutingNumber = '256074974'
			);
	--2021-03-25

	IF @iLogLevel > 0
		AND EXISTS (SELECT 'X' FROM @tblMICR)
	BEGIN
		INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Micr Load' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME()); 
		SET @dtTimerDate  = SYSDATETIME();
	END

	INSERT INTO @tblItemRequest(ItemTypeCode,ClientItemId,ItemKey,CheckTypeCode,[Date],CheckAmount,
		MICR,RoutingNumber,AccountNumber,CheckNumber,Scanned,AcctChkNbrSwitch,OriginalCheckTypeCode,BadField)
	SELECT ItemTypeCode,ClientItemId,ir.ItemKey,CheckTypeCode,[Date],CheckAmount,MICR,
		CASE WHEN micr.SwitchRTN = 1 
				THEN micr.RoutingNumber
			ELSE [common].[ufnCleanRoutingNumber](ir.RoutingNumber)	--no zero-fill
		END as RoutingNumber,
		CASE WHEN micr.SwitchACNT = 1 
				THEN micr.AccountNumber
			WHEN @bPNCClient = 1 AND @nvChannelName = 'Teller' --2020-02-18
				THEN CASE WHEN ir.AccountNumber IS NULL THEN '1' 
					WHEN ir.AccountNumber like '%*%' THEN '2'
					ELSE [common].[ufnCleanAccountNumber](ir.AccountNumber)
				END
			ELSE [common].[ufnCleanAccountNumber](ir.AccountNumber)
		END as AccountNumber,
		CASE WHEN micr.SwitchCHK = 1 
				THEN micr.CheckNumber
			WHEN @bPNCClient = 1 AND @nvChannelName = 'Teller' --2020-02-18
				THEN CASE WHEN ir.CheckNumber IS NULL THEN '0' 
					WHEN ir.CheckNumber like '%*%' THEN '0'
					ELSE [common].[ufnCleanCheckNumber](ir.CheckNumber)
				END
			ELSE [common].[ufnCleanCheckNumber](ir.CheckNumber) 
		END as CheckNumber,
		CASE WHEN (@nvChannelName = 'ATM' OR @bTDClient = 1) AND micr.ValidMICR = 1 AND ISNULL(ir.CheckNumber,'0') = '0' THEN 1 ELSE 0 END as Scanned,
		0,
		CheckTypeCode, 
		CASE WHEN @bDebug = 0 THEN 0
			ELSE CASE WHEN @bPNCClient = 1 AND @nvChannelName = 'ATM' AND micr.ValidMICR = 1
					AND LEN(micr.RoutingNumber) = 9 
					AND micr.CheckNumber <> N'0' 
					AND ir.CheckAmount > 0.00 THEN 0
				WHEN @bPNCClient = 1 AND @nvChannelName = 'Mobile' AND ir.RoutingNumber = '000000518' AND micr.ValidMICR = 1
					AND LEN(micr.RoutingNumber) = 9 
					AND micr.CheckNumber <> N'0' 
					AND ir.CheckAmount > 0.00 THEN 0
				WHEN @bPNCClient = 1 AND @nvChannelName = 'Teller'
					AND (ir.AccountNumber IS NULL
						OR ir.AccountNumber like '%*%'
						OR ir.CheckNumber IS NULL
						OR ir.CheckNumber like '%*%') THEN 1
				WHEN @bTDClient = 1 AND micr.ValidMICR = 1
					AND LEN(micr.RoutingNumber) = 9 
					AND micr.CheckNumber <> N'0' 
					AND ir.CheckAmount > 0.00 THEN 0
				WHEN @bFTBClient = 1 AND micr.ValidMICR = 1
					AND LEN(micr.RoutingNumber) = 9 
					AND micr.AccountNumber <> N'0' 
					AND micr.CheckNumber <> N'0' 
					AND ir.CheckAmount > 0.00 THEN 0
				WHEN LEN([common].[ufnCleanRoutingNumber](ir.RoutingNumber)) = 9
						AND [common].[ufnCleanCheckNumber](ir.CheckNumber) <> N'0'
						AND ir.CheckAmount > 0.00 THEN 0 
 				ELSE 1 
			END --@bDebug = 1
		END AS BadField
	FROM @ptblItemRequest ir
	LEFT JOIN @tblMICR micr ON ir.ItemKey = micr.ItemKey
								AND micr.ValidMICR = 1; 

	IF @iLogLevel > 2
	BEGIN
		INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'@tblItemRequest Updated' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
		SET @dtTimerDate  = SYSDATETIME();
	END

	--NEED a valid item type to continue
	INSERT INTO @tblItemType(ItemTypeId,Code,ItemKey)
	SELECT [common].[ufnItemType](ItemTypeCode),ItemTypeCode,ItemKey
	FROM @tblItemRequest;

	--EACH Item must have a type, 'CC-checkchasing, D-deposit
	IF EXISTS (SELECT 'X' FROM @tblItemType WHERE ItemTypeId IS NULL)  
	BEGIN
		IF @iLogLevel > 0
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Invalid Transaction Item Type Code',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());

		SELECT @nvError = Code FROM @tblItemType WHERE ItemTypeId IS NULL;
		RAISERROR ('Invalid Transaction Item Type Code', 16, 1, @nvError);
		RETURN
	END

	--VERIFICATION of ABA Data (adjustment of Account/Check Numbers
	--Adjustment Of CheckTypeCode occurs here
	--CheckPC initialize to 0 since it is not provided
	--IF MICR is provide CheckPC could be acquired via parsing
	UPDATE ir
		SET AccountNumber = adf.AccountNumber
			,CheckNumber = adf.CheckNumber
			,CheckTypeCode = adf.CheckTypeCode
			,AcctChkNbrSwitch = adf.AcctChkNbrSwitch
			,OriginalCheckTypeCode = adf.OriginalCheckTypeCode
	FROM @tblItemRequest ir 
	CROSS APPLY [common].[ufnABADataFix](@iOrgClientId,ir.RoutingNumber,ir.AccountNumber,ir.CheckNumber,ir.CheckNumber,ir.CheckTypeCode) adf; --Note passing checknumber in twice, since CheckPc is unavailable

	--DO these payers already exist?
	INSERT INTO @tblPayerIR(PayerId,RoutingNumber,AccountNumber,ItemKey)
	SELECT ISNULL(p.PayerId,-1),ir.RoutingNumber,ir.AccountNumber,ir.ItemKey
	FROM @tblItemRequest ir
	LEFT JOIN [payer].[Payer] p  ON ir.RoutingNumber = p.RoutingNumber
											AND ir.AccountNumber = p.AccountNumber;
	--HOW many are in not in the system
	SELECT @iPayerMissingCnt = COUNT(*) FROM @tblPayerIR WHERE ISNULL(PayerId,-1) = -1;

	IF @iPayerMissingCnt > 0--Need to add some payers
	BEGIN
		SET @iCurrentTransactionLevel = @@TRANCOUNT;
		BEGIN TRANSACTION
		BEGIN TRY
			INSERT INTO [payer].[Payer](Name,RoutingNumber,AccountNumber,StatusFlag,UserName)
				OUTPUT
					inserted.PayerId
					,inserted.[Name]
					,inserted.RoutingNumber
					,inserted.AccountNumber
					,inserted.StatusFlag
					,inserted.DateActivated
					,inserted.UserName
				INTO @tblPayer
			SELECT DISTINCT ''
				,RoutingNumber
				,AccountNumber
				,@iStatusFlag
				,@nvUserName
			FROM @tblPayerIR
			WHERE ISNULL(PayerId,-1) = -1;
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
				ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			IF @iLogLevel > 0
				INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
				VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Exit-ErrorDetailId ='+CONVERT(NCHAR(10),@iErrorDetailId),DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			THROW;
		END CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel 
		BEGIN
			COMMIT TRANSACTION;
			UPDATE pir
				SET PayerId = p.PayerId
			FROM @tblPayerIR pir
			INNER JOIN @tblPayer p ON pir.RoutingNumber = p.RoutingNumber
										AND pir.AccountNumber = p.AccountNumber;
			IF @iLogLevel > 2
			BEGIN
				INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
				VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Payer Insert' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  		
				SET @dtTimerDate  = SYSDATETIME();
			END
		END
	END

	IF EXISTS (SELECT 'X' FROM @tblPayerIR WHERE PayerId IS NULL OR PayerId = -1)
	BEGIN
		IF @iLogLevel > 0
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Unable to create Payer',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME()); 
		RAISERROR ('Unable to create Payer', 16, 1);
		RETURN
	END
	--2020-10-16 LBD moved here so it always gets performed
	--Load Process Centric Stats
	INSERT INTO @tblStat(StatName,StatValue)
	SELECT ps.StatName,ps.StatValue
	FROM @ptblProcessStat ps;

	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	BEGIN TRANSACTION
	BEGIN TRY
		INSERT INTO [ifa].[Item]
			OUTPUT inserted.ItemId
				,inserted.ItemTypeId
				,inserted.ProcessId
				,inserted.PayerId
				,inserted.ItemKey
				,inserted.ClientItemId
				,inserted.CheckNumber
				,inserted.CheckAmount
				,inserted.CheckTypeId
				,inserted.ItemTypeDate
				,inserted.Fee
				,inserted.Amount
				,inserted.MICR
				,inserted.Scanned
				,inserted.RuleBreak
				,inserted.RuleBreakResponse
				,inserted.ItemStatusId
				,inserted.ClientAcceptedId
				,inserted.OriginalPayerId
				,inserted.OriginalCheckTypeId
				,inserted.AcctChkNbrSwitch
				,inserted.StatusFlag
				,inserted.DateActivated
				,inserted.UserName
			INTO @tblItem
		SELECT it.ItemTypeId
			,@biProcessId
			,pir.PayerId
			,ir.ItemKey
			,ir.ClientItemId
			,ir.CheckNumber
			,ir.CheckAmount
			,ct.CheckTypeId
			,ir.[Date]
			,NULL
			,NULL
			,ir.MICR
			,COALESCE(ir.Scanned, 0)
			,0
			,NULL
			,@iInitialItemStatusId
			,@iUnknownClientAcceptedId
			,NULL--original payer can't be determined, when we don't insert trash
			,cto.CheckTypeId
			,AcctChkNbrSwitch
			,@iStatusFlag
			,SYSDATETIME()
			,@nvUserName
		FROM @tblItemRequest ir
		INNER JOIN @tblItemType it ON ir.ItemTypeCode = it.Code
										AND ir.ItemKey = it.ItemKey
		INNER JOIN @tblPayerIR pir ON ir.ItemKey = pir.ItemKey
										AND ir.RoutingNumber =  pir.RoutingNumber
										AND ir.AccountNumber = pir.AccountNumber
		INNER JOIN @ptblAvailableCheckTypeCode ct ON ir.CheckTypeCode = ct.CheckTypeCode
		LEFT JOIN @ptblAvailableCheckTypeCode cto ON ir.OriginalCheckTypeCode = cto.CheckTypeCode;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		IF @iLogLevel > 0
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Exit-ErrorDetailId ='+CONVERT(NCHAR(10),@iErrorDetailId),DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
		THROW;
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel 
	BEGIN
		COMMIT TRANSACTION;
		IF @iLogLevel > 1
		BEGIN
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Item Insert' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  		
			SET @dtTimerDate  = SYSDATETIME();
		END

		SET @iCurrentTransactionLevel = @@TRANCOUNT;
		BEGIN TRANSACTION
		BEGIN TRY
			INSERT INTO [ifa].[TransactionKey](TransactionKey,TransactionId,TransactionTypeId,StatusFlag,DateActivated,UserName)
			SELECT ItemKey,ItemId,@iTransactionTypeId,@iStatusFlag,SYSDATETIME(),@nvUserName
			FROM @tblItem;
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
				ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			IF @iLogLevel > 0
				INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
				VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Exit-ErrorDetailId ='+CONVERT(NCHAR(10),@iErrorDetailId),DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			THROW;
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel 
			COMMIT TRANSACTION;
		
		--2020-04-17 converted to uspItemActivityInsert
		--ONLY INSERT non auto-decline
		--2022-04-04 converted to uspItemActivityInsertOut
		IF @bMaxItemsExceeded = 0
			--EXECUTE [ifa].[uspItemActivityInsert]
			EXECUTE [ifa].[uspItemActivityInsertOut]
				 @ptblDecisionField = @ptblDecisionField
				,@ptblItem = @tblItem
				,@ptblMiscStat = @ptblMiscStat
				,@ptblPayerIR = @tblPayerIR		--used for retail
				,@pxD2CStat = @xD2CStat OUTPUT;

		BEGIN TRY
		BEGIN	
			IF @bDebug = 0
			BEGIN
				IF @bMaxItemsExceeded = 1
					INSERT INTO @tblItemRB0(ItemId,RuleBreak,Code,RuleBreakResponse,Fee,Amount,ItemStatusId)	--2020-12-03 instead of @tblItemRB
					SELECT i.ItemId, 1, rc.Code, rc.Descr, 0.00, 0.00, @iProcessedItemStatusId					--2020-12-03 Both RuleBreak and Code passed back
					FROM @tblItem i
					INNER JOIN @tblItemRequest ir ON i.ItemKey = ir.ItemKey
					CROSS APPLY [common].[ufnResponseCode](@iOrgId,1,N'Red|002') rc;--2020-10-22
				ELSE IF EXISTS (SELECT 'X' FROM @tblItem i
								INNER JOIN @tblItemRequest ir ON i.ItemKey = ir.ItemKey)
					AND EXISTS (SELECT 'X' FROM @ptblLadderRung) --RiskProcessing Defined
				BEGIN
					--LOAD related Current, we can use Process related variables since they don't change
					INSERT INTO @tblItemCurrent(ItemId,ItemTypeId,ProcessId,OrgClientId,OrgId,Latitude,Longitude,OrgDistance,OrgName
						,OrgIdCode,OrgState,PayerId,Customerid,ItemKey,ClientItemId,RoutingNumber,AccountNumber,CheckNumber,CheckAmount,CheckTypeId,ItemTypeDate
						,Fee,Amount,MICR,Scanned,RuleBreak,RuleBreakResponse,ItemStatusId,ClientAcceptedId,AcctChkNbrSwitch,StatusFlag,DateActivated)
					SELECT i.ItemId,i.ItemTypeId,i.ProcessId,df.OrgClientId,df.OrgId,df.OrgLatitude,df.OrgLongitude,df.OrgDistance,df.OrgCode --OrgCode has always been used here
						,df.OrgExternalCode,df.OrgState,i.PayerId,df.CustomerId,i.ItemKey,i.ClientItemId,ir.RoutingNumber,ir.AccountNumber,i.CheckNumber,i.CheckAmount,i.CheckTypeId,i.ItemTypeDate
						,i.Fee,i.Amount,i.MICR,i.Scanned,i.RuleBreak,i.RuleBreakResponse,i.ItemStatusId,i.ClientAcceptedId,i.AcctChkNbrSwitch,i.StatusFlag,i.DateActivated
					FROM @tblItem i
					INNER JOIN @tblItemRequest ir ON ir.ItemKey = i.ItemKey
					CROSS APPLY @ptblDecisionField df; --Provides common decision fields used for ItemCurrent

					IF @iLogLevel > 1
					BEGIN
						INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
						VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Load Current Item',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
						SET @dtTimerDate  = SYSDATETIME();
					END

					--UPDATE @tlbStatKey from 'Process' to Item
					--2021-01-16 Added CheckAmount to the query, since it was incorrectly set via the Process Record
					INSERT INTO @tblStatKey(ProcessMethodology,FilterName,ItemId,CustomerId,OrgParentId,OrgClientId,OrgId,RoutingNumber,AccountNumber,IdTypeId,CheckAmount,DollarStratRangeId,OrgGeoLargeId,OrgGeoSmallId,OrgGeoZip4Id,OrgChannelId,InternalBankAccountNumber,ClientProvidedIdentifier,IdMac64)
					SELECT ProcessMethodology,'Item',d.ItemId,CustomerId,OrgParentId,OrgClientId,OrgId,d.RoutingNumber,d.AccountNumber,IdTypeId,d.CheckAmount,d.DollarStratRangeId,OrgGeoLargeId,OrgGeoSmallId,OrgGeoZip4Id,OrgChannelId,InternalBankAccountNumber,ClientProvidedIdentifier,IdMac64
					FROM @ptblStatKey sk
					CROSS APPLY (SELECT i.ItemId, ir.RoutingNumber, ir.AccountNumber, i.CheckAmount, TRY_CONVERT(NVARCHAR(50),dsr.DollarStratRangeId) AS DollarStratRangeId
								FROM @tblItem i
								INNER JOIN @tblItemRequest ir ON ir.ItemKey = i.ItemKey
								INNER JOIN [stat].[DollarStratRange] dsr ON i.CheckAmount >= dsr.RangeFloor 
																	AND i.CheckAmount <= dsr.RangeCeiling) d;
					
					IF @iLogLevel > 1
					BEGIN
						INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
						VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Load Item StatKey',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
						SET @dtTimerDate = SYSDATETIME();
					END

					/*--2022-02-04 Moving this section of code to ufnItemAtomicStat
					--2020-09-13 FTB Specific
					INSERT INTO @tblStat(StatName,StatValue)
					SELECT StatName, SUBSTRING([common].[ufnCleanNumber](StatValue), 1, 100)
					FROM @ptblMiscStat
					WHERE @bFTBClient = 1
						--AND StatName = 'SUBPRDCT'; 2020-11-18
						AND StatName = 'PRDCT-CD';
					*/

					--LOAD Item Centric Stats
					INSERT INTO @tblStat(StatName,StatValue)
					SELECT  iast.StatName, iast.StatValue
					FROM [stat].[ufnItemAtomicStat](@tblStatKey,@ptblDecisionField,@tblItemCurrent,@ptblItemList,@ptblMiscStat) iast
					WHERE NOT EXISTS (SELECT 'X'
										FROM @tblStat s
										WHERE iast.StatName = s.StatName)
					ORDER BY StatName;

					--2021-11-09 The actual call to ufnItemBriskStat
					INSERT INTO @tblStat(StatName, StatValue)
					SELECT bs.StatName, bs.StatValue
					FROM [stat].[ufnItemBriskStat](@tblItemCurrent,@tblStat) bs
					WHERE NOT EXISTS (SELECT 'X'
									FROM @tblStat s
									WHERE bs.StatName = s.StatName);

					--2020-04-17 only insert when CheckTypeId is '63' and it wasn't loaded above
					INSERT INTO @tblRuleDetail(RuleOrgXrefId,RuleId,RuleCode,CheckTypeId,CheckTypeCode,EnrollmentFlag,OverridableFlag,LevelId,
						AccountNotFound,AgeFloor,AllCheckTypes,AmountCeiling,AmountFloor,AmountVariation,Approved,
						CheckMax,CheckNumberFloor,CheckPayeeHistory,ClientSpecific,DaysToBegin,DaysToEnd,DaysToSpan,DaysToSpan2,
						DivisorFactor,EnrollmentLockdownList,GoodPayer,GroupCheckTypes,Ignore,IgnoreEmptySSN,IgnoreSendToXMLApp,
						Inconclusive,ItemOverThreshold,Leveling,MonitorRule,MaxScore,MinScore,MinutesToSpan,NegativeDataExists,NegativeFile,
						NoData,NonMemberBank,NotesToView,NumberVariation,Overlay,PayeeBlackList,PayeePayerTranCeiling,PayeePayerTranFloor,PayeeTranCeiling,
						PayerBlackList,PayerTranCeiling,Percent3090,RoutingAccountCheckFlag,RoutingNumber,SafeListFloor,
						TaxSeasonBegin,TaxSeasonEnd,TranAllowed,TranCeiling,TranFloor,TranFloor2,VerifyCheckSeries)
					SELECT RuleOrgXrefId,RuleId,RuleCode,CheckTypeId,CheckTypeCode,EnrollmentFlag,OverridableFlag,LevelId,
						AccountNotFound,AgeFloor,AllCheckTypes,AmountCeiling,AmountFloor,AmountVariation,Approved,
						CheckMax,CheckNumberFloor,CheckPayeeHistory,ClientSpecific,DaysToBegin,DaysToEnd,DaysToSpan,DaysToSpan2,
						DivisorFactor,EnrollmentLockdownList,GoodPayer,GroupCheckTypes,Ignore,IgnoreEmptySSN,IgnoreSendToXMLApp,
						Inconclusive,ItemOverThreshold,Leveling,MonitorRule,MaxScore,MinScore,MinutesToSpan,NegativeDataExists,NegativeFile,
						NoData,NonMemberBank,NotesToView,NumberVariation,Overlay,PayeeBlackList,PayeePayerTranCeiling,PayeePayerTranFloor,PayeeTranCeiling,
						PayerBlackList,PayerTranCeiling,Percent3090,RoutingAccountCheckFlag,RoutingNumber,SafeListFloor,
						TaxSeasonBegin,TaxSeasonEnd,TranAllowed,TranCeiling,TranFloor,TranFloor2,VerifyCheckSeries
					FROM [common].[ufnCurrentRuleDetail](@iOrgId)
					WHERE EXISTS (SELECT 'X' FROM @tblItem WHERE CheckTypeId = @iGovernmentAssistanceCheckTypeId)
						AND NOT EXISTS (SELECT 'X' FROM @ptblRuleDetail);

					IF @iLogLevel > 1
					BEGIN
						INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
						VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Load ufnItemAtomicStat',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
						SET @dtTimerDate = SYSDATETIME();
					END

					--LOAD related AutoFraud Records, by KeyIdType 'Payer'
					INSERT INTO @tblAutoFraud(AutoFraudId,AutoFraudTypeId,AutoFraudTypeCode,OrgId,KeyId,KeyIdType)
					SELECT af.AutoFraudId, af.AutoFraudTypeId, aft.Code, af.OrgId, af.KeyId, aft.KeyIdType
					FROM @tblItemCurrent c
					INNER JOIN [ifa].[AutoFraud] af  WITH (READUNCOMMITTED) ON c.PayerId = af.KeyId	--2021-03-01
														AND c.OrgClientId = af.OrgId	--THIS is how Auto currently defines each AutoFraud, using Client
					INNER JOIN [ifa].[AutoFraudType] aft ON af.AutoFraudTypeId = aft.AutoFraudTypeId
															AND aft.KeyIdType = 'PayerId'
					WHERE af.StatusFlag > 0;
	
					IF @iLogLevel > 1
					BEGIN
						INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
						VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Load Payer AutoFraud',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
						SET @dtTimerDate = SYSDATETIME();
					END

					EXECUTE [riskprocessing].[uspProcessRiskControl]
						@pnvProcessKey=@nvProcessKey
						,@ptblAutoFraud=@tblAutoFraud
						,@ptblItemCurrent=@tblItemCurrent
						,@ptblItemList=@ptblItemList
						,@ptblLadderRung=@ptblLadderRung
						,@ptblMiscStat=@ptblMiscStat		--2020-03-11
						,@ptblRCLadder=@ptblRCLadder
						,@ptblRuleDetail=@tblRuleDetail		--2020-04-17 local variable we populate under exact conditions
						--,@ptblRuleDetail=@ptblRuleDetail	--2020-04-17 stop using passed in table
						,@ptblStat=@tblStat
						,@pxTableSet=@pxTableSet OUTPUT;

					IF @iLogLevel > 2
					BEGIN
						INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
						VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Exit ProcessRiskControl' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  		
						SET @dtTimerDate = SYSDATETIME();				
					END

					INSERT INTO @tblItemRB0(ItemId,RuleBreak,Code,RuleBreakResponse,Fee,Amount,ItemStatusId)	--2020-12-03 instead of @tblItemRB
					SELECT i.ItemId 
						,CONVERT(NVARCHAR(25),CASE WHEN rp1.StatValue = '0' THEN '1' ELSE '0' END) as RuleBreak
						--,rp2.StatValue
						,CONVERT(NVARCHAR(25),CASE WHEN rp1.StatValue = '0' THEN rc.Code ELSE '0' END) as Code
						,CONVERT(NVARCHAR(255),CASE WHEN rp1.StatValue = '0' THEN rc.Descr ELSE rp2.StatValue END) as RuleBreakResponse
						,CASE WHEN rp1.StatValue = '0' THEN 0.0
								ELSE i.Fee 
							END as Fee
						,CASE WHEN rp1.StatValue = '0' THEN 0.0
								ELSE i.CheckAmount 
							END as Amount
						,CASE WHEN rp1.StatValue = '0' and @bFirstDataClient = 1 THEN @iFinByProxyItemStatusId--FirstData failure transactions must be completed by proxy
								ELSE @iProcessedItemStatusId
							END as ItemStatusId
					FROM @tblItem i
					INNER JOIN (SELECT r.a.value('ItemId[1]','bigint') AS ItemId
									,r.a.value('StatName[1]','nvarchar(128)') AS StatName
									,NULLIF(r.a.value('StatValue[1]','nvarchar(100)'),N'NULL') AS StatValue
								FROM @pxTableSet.nodes('Stat/.') r(a)
								WHERE r.a.value('StatName[1]','nvarchar(128)') = 'RPLadderResult') rp1 ON i.ItemId = rp1.ItemId
					INNER JOIN (SELECT r.a.value('ItemId[1]','bigint') AS ItemId
									,r.a.value('StatName[1]','nvarchar(128)') AS StatName
									,NULLIF(r.a.value('StatValue[1]','nvarchar(100)'),N'NULL') AS StatValue
								FROM @pxTableSet.nodes('Stat/.') r(a)
								WHERE r.a.value('StatName[1]','nvarchar(128)') = 'RPMsg') rp2 ON i.ItemId = rp2.ItemId
					CROSS APPLY [common].[ufnResponseCode](@iOrgId,CONVERT(NVARCHAR(25),CASE WHEN rp1.StatValue = '0' THEN '1' ELSE '0' END),rp2.StatValue) rc;

					IF @iLogLevel > 2
					BEGIN
						INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
						VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Load @tblItemRB0' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  		
						SELECT @dtTimerDate = SYSDATETIME();
					END
				END--IF EXISTS (SELECT 'X' FROM @tblItem)
			END--IF @bDebug = 0
			ELSE IF @bDebug = 1
			BEGIN
				IF EXISTS (SELECT 'X' FROM @tblItemRequest where BadField = 1)	--2019-11-04
				BEGIN
					INSERT INTO @tblItemRB0(ItemId,RuleBreak,Code,RuleBreakResponse,Fee,Amount,ItemStatusId)
					SELECT i.ItemId, 1, rbc.Code, rbc.Descr, 0.00, 0.00, @iProcessedItemStatusId
					FROM @tblItem i
					INNER JOIN @tblItemRequest ir ON i.ItemKey = ir.ItemKey
					CROSS APPLY [common].[ufnResponseCode](@iOrgId,1,N'Red|001') rbc --2020-10-22
					WHERE ir.BadField = 1;
				END
				IF @bMaxItemsExceeded = 1 
					INSERT INTO @tblItemRB0(ItemId,RuleBreak,Code,RuleBreakResponse,Fee,Amount,ItemStatusId)
					SELECT i.ItemId, 1, rbc.Code, rbc.Descr, 0.00, 0.00, @iProcessedItemStatusId
					FROM @tblItem i
					INNER JOIN @tblItemRequest ir ON i.ItemKey = ir.ItemKey
					CROSS APPLY [common].[ufnResponseCode](@iOrgId,1,N'Red|002') rbc --2020-10-22
					WHERE BadField = 0;	
				ELSE IF @bMaxItemsExceeded = 0
				BEGIN
					--Used by several Banks for eligiblity
					SELECT @nvInternalBankAccountNumber = InternalBankAccountNumber --MTB & TDB
					FROM @tblStatKey;
					--2020-09-13
					SELECT @nvSUBPRDCT = ISNULL(TRY_CONVERT(nvarchar(25),StatValue), '') 	--Used By FTB
					FROM @ptblMiscStat
					WHERE @bFTBClient = 1
						--AND StatName = 'SUBPRDCT';
						AND StatName = 'PRDCT-CD';

					IF @iCheckDuplicateItem = 1 --if the conditions require us to check duplicate item...
						INSERT INTO @tblDebugDuplicateItem(ItemId,DuplicateItem)
						SELECT ItemId,DuplicateItem
						FROM [debug].[ufnDebugDuplicateItem](@tblItem,@iOrgClientId,@nvChannelName);
					--SELECT ALL if the OrgId matches

					--PRINT 'ProcessMethodology:'+CONVERT(nvarchar(1), @iProcessMethodology);
					--PRINT 'SubPrdCt:'+CONVERT(nvarchar(5), @nvSUBPRDCT);
					--PRINT 'ChannelName:'+@nvChannelName;

					INSERT INTO @tblCannedRuleBreak(DebugId,DebugTypeId,OrgId,CustomerIdentifier,ItemId,DebugRuleBreak)
					SELECT crb.DebugId,crb.DebugTypeId,crb.OrgId,crb.CustomerIdentifier,i.ItemId,
						--we are here because the OrgId or PayerId matched
						/*2020-10-21  realigned, simplified
						-1	Treat as a '1' RuleBreak (used for i.CheckAmount % 1.00 also)
						-2	Treat as a '0' or 'Green' RuleBreak, i.e. none
						-3	Treat as a 'Red' Rulebreak
						-4	Treat as a 'Yellow' Rulebreak
						-5	Treat as a '1' Rulebreak when IRD=0 and CheckAmt < 25 or when IRD=1 - Non Eligible
						-6  Treat as a '1' Rulebreak Non-Eligible 
						-7	Treat as a '1' Rulebreak Exceed Alowed CheckAmount - Non-Eligible
						-8	Treat as a '1' Rulebreak Duplicate Item
						-9	Treat as a '1' Rulebreak ThirdParty
						*/
						CASE 
							WHEN EXISTS (SELECT 'X' FROM @tblDebugDuplicateItem WHERE i.ItemId = ItemId) THEN -8 --consider check duplicate item...
							WHEN DebugTypeId = 1 THEN --First Debug Type
								CASE WHEN @bPNCClient = 1 AND i.CheckAmount > 5000.00 THEN -7
										WHEN @bPNCClient = 1 AND [common].[ufnDemoCustBankAccountNumberSubCodeMatch](@iOrgClientId,@nvInternalBankAccountNumber,N'B9') = 1 THEN -6	
										WHEN [common].[ufnDemoCheck](@iOrgClientId,i.RoutingNumber,i.AccountNumber,i.CheckAmount) <> 0 THEN 
											[common].[ufnDemoCheck](@iOrgClientId,i.RoutingNumber,i.AccountNumber,i.CheckAmount)--returns -2 (Treat as '0' Rulebreak), 
																																--or -6 treat as non-eligible, if 0 process below 
										WHEN i.CheckAmount % 1.00 IN (0.01,0.02,0.03,0.04,0.05,0.06,0.07,0.08,0.09,0.10) THEN -1-- Treat as '1' Rulebreak
										ELSE -2																					-- Treat as '0' Rulebreak
								END
							WHEN DebugTypeId = 2 THEN --ANSWERS
								CASE WHEN  i.CheckAmount % 1.00 IN (0.01,0.02,0.03,0.04,0.05,0.06) THEN -3						-- Treat as Red Rulebreak
									WHEN i.CheckAmount % 1.00 IN (0.07,0.08,0.09) THEN -4										-- Treat as Yellow Rulebreak
									ELSE -2																						-- Treat as Green
								END
							--IRD must be considered
							WHEN DebugTypeId = 3 THEN --PNC ATM IRD Debug Type
								CASE WHEN @bPNCClient = 1 AND i.CheckAmount > 5000.00 THEN -7
									WHEN @bPNCClient = 1 AND [common].[ufnDemoCustBankAccountNumberSubCodeMatch](@iOrgClientId,@nvInternalBankAccountNumber,N'B9') = 1 THEN -6	
									WHEN i.IRD = 0 
										AND i.CheckAmount % 1.00 IN (0.01,0.02,0.03,0.04,0.05,0.06,0.07,0.08,0.09,0.10) THEN -1 -- Treat as '1' Rulebreak ii cent in range
									WHEN i.IRD = 0 
										AND [common].[ufnDemoCheck](@iOrgClientId,i.RoutingNumber,i.AccountNumber,i.CheckAmount) <> 0 THEN 
												[common].[ufnDemoCheck](@iOrgClientId,i.RoutingNumber,i.AccountNumber,i.CheckAmount)	--returns -2 (Treat as '0' Rulebreak), 
																																--or -6 treat as non-eligible, if 0 process below
									WHEN i.IRD = 0 AND i.CheckAmount < 25.00 THEN -5											-- Treat as '1' Rulebreak															   
									WHEN i.IRD = 0 THEN -2																		-- Treat as '0' Rulebreak
									WHEN i.IRD = 1 THEN -5																		-- Treat as '1' Rulebreak
								END
							WHEN DebugTypeId = 4 THEN --MTB DemoInternalBankAccountNumber 2019-01-09
								CASE WHEN [common].[ufnDemoInternalBankAccountNumber](@iOrgClientId,@nvInternalBankAccountNumber,i.AccountNumber) = 1 THEN -7 
									WHEN i.CheckAmount % 1.00 IN (0.01,0.02,0.03,0.04,0.05,0.06,0.07,0.08,0.09,0.10) THEN -1					-- Treat as '1' Rulebreak
									ELSE -2																										-- Treat as '0' Rulebreak
								END
							WHEN DebugTypeId = 5 THEN --TD DemoInternalBankAccountNumber
								CASE WHEN @bTDClient = 1 AND i.CheckAmount > 100000.00 THEN -7 --2019-07-23
										WHEN [common].[ufnDemoInternalBankAccountNumber](@iOrgClientId,@nvInternalBankAccountNumber,i.AccountNumber) = 1 THEN -7
										WHEN i.CheckAmount % 1.00 IN (0.01,0.02,0.03,0.04,0.05,0.06,0.07,0.08,0.09,0.10) THEN -1				-- Treat as '1' Rulebreak 
										ELSE -2																									-- Treat as '0' Rulebreak
								END
							WHEN DebugTypeId = 6 THEN --PNC DemoCustBankAccountNumber
								CASE WHEN @bPNCClient = 1 AND i.CheckAmount > 5000.00 THEN -7													--2019-09-09 activated--2019-07-23 commented out for now		 
									WHEN [common].[ufnOnUsRoutingNumber](@iOrgClientId,i.RoutingNumber) = 1 THEN
										CASE WHEN [common].[ufnDemoCustBankAccountNumber](@iOrgClientId,@nvInternalBankAccountNumber) = 1 THEN --Eligiblity
												CASE WHEN i.CheckAmount % 1.00 IN (0.01,0.02,0.03,0.04,0.05,0.06,0.07,0.08,0.09,0.10) THEN -1	--Treat as '1' Rulebreak or IF cents apply, change result accordingly
													ELSE -2 --Eligible
												END
											ELSE -6 --OnUs not eligible for any other accounts
										END																						
								-- Treat as normal	 
								WHEN [common].[ufnDemoCheck](@iOrgClientId,i.RoutingNumber,i.AccountNumber,i.CheckAmount) <> 0 THEN 
											[common].[ufnDemoCheck](@iOrgClientId,i.RoutingNumber,i.AccountNumber,i.CheckAmount)--returns -2 (Treat as '0' Rulebreak), 
																																--or -6 treat as non-eligible, if 0 process below 
								WHEN [common].[ufnDemoCustBankAccountNumberSubCodeMatch](@iOrgClientId,@nvInternalBankAccountNumber,N'N6') = 1 THEN -6	
								WHEN [common].[ufnDemoCustBankAccountNumberSubCodeMatch](@iOrgClientId,@nvInternalBankAccountNumber,N'B9') = 1 THEN -6	
								WHEN i.CheckAmount % 1.00 IN (0.01,0.02,0.03,0.04,0.05,0.06,0.07,0.08,0.09,0.10) THEN -1		-- Treat as '1' Rulebreak
								ELSE -2	 																						-- Treat as '0' Rulebreak
							END
							--2020-09-13 Formalized the operation for DebugTypeId = 8
							WHEN DebugTypeId = 8 AND @nvChannelName in (N'Mobile',N'Teller') THEN	--2020-06-22 FTB
								CASE WHEN @iProcessMethodology = 1																--Financial User In Session Third Party Check
										AND @nvCustomerIdentifier = N'THIRDPARTY00000000' THEN -9 --2020-11-10
										--AND @nvCustomerIdentifier = N'THIRDPARTY000000000' THEN -9 --2020-11-10
									--WHEN @iProcessMethodology = 0 AND @nvChannelName = N'Teller' AND i.CheckAmount > 100000.00 THEN -6	--Not Instansiated by FTB
									WHEN @iProcessMethodology = 1 AND @nvChannelName = N'Teller' AND i.CheckAmount > 100000.00 THEN -6		--Financial Branch Limit
									WHEN @iProcessMethodology = 0 AND i.CheckAmount % 1.00 = 0.05 THEN -1					--Retail OFAC
									WHEN @iProcessMethodology = 1																--Financial 'Relationship' Business only and not eligible
										AND EXISTS (SELECT 'X' FROM [debug].[FTBTypeCodeEligibility]							--IS this a Business
													WHERE @nvSUBPRDCT = SUBPRDCT 
														AND Customer = N'Business'
														AND ((@nvChannelName = N'Mobile' AND MobileEligibility = 1)
															OR (@nvChannelName = N'Teller' AND BranchEligibility = 1)))
										AND EXISTS (SELECT 'X' FROM [debug].[FTBCustomerOpenDate]								--IS the Customer Tenure < 120 days
														WHERE @nvCustomerIdentifier = CustomerIdentifier
														AND DATEDIFF(day,CustomerOpenDate,getdate()) < 120
													) THEN -6
									WHEN @iProcessMethodology = 1																--Financial Deposit to Account SUBPRDCT is ineligible
										AND EXISTS (SELECT 'X' FROM [debug].[FTBTypeCodeEligibility] 
													WHERE @nvSUBPRDCT = SUBPRDCT AND ((@nvChannelName = N'Mobile' AND MobileEligibility = 0)
																							OR (@nvChannelName = N'Teller' AND BranchEligibility = 0))) THEN -6
									WHEN i.CheckAmount % 1.00 IN (0.01,0.02,0.03,0.04,0.06,0.07,0.08,0.09,0.10) THEN -1			--Treat as '1' Rulebreak or IF cents apply, change result accordingly
									ELSE -2 --Eligible
								END
							WHEN DebugTypeId = 9 THEN --2020-09-03 Fiserv Integrated
								CASE WHEN i.CheckAmount % 1.00 IN (0.01,0.02,0.03,0.04,0.05,0.06,0.07,0.08,0.09,0.10) THEN -1	--Treat as '1' Rulebreak or IF cents apply, change result accordingly
									ELSE -2 --Eligible
								END
							ELSE 0
						END DebugRuleBreak
					FROM [debug].[CannedRuleBreak] crb (NOLOCK)
					CROSS APPLY (SELECT i0.*,ir0.RoutingNumber, ir0.AccountNumber, ISNULL(m.IRD,0) as IRD
									FROM @tblItem i0
									INNER JOIN @tblItemRequest ir0 ON i0.ItemKey = ir0.ItemKey
									LEFT JOIN @tblMICR m ON ir0.ItemKey = m.ItemKey
									WHERE ir0.BadField = 0) i
					WHERE crb.OrgId = @iOrgId
						AND crb.DateActivated <= @dtTimerDate
						AND crb.StatusFlag = @iStatusFlag; --manadatory for all cases

					IF @iLogLevel > 1
					BEGIN
						INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
						VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Checked Debug' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  		
						SET @dtTimerDate = SYSDATETIME();
					END
				END -- IF @bMaxItemsExceeded = 0

				IF EXISTS (SELECT 'X' FROM @tblCannedRuleBreak WHERE DebugRuleBreak <> 0)
				BEGIN
					INSERT INTO @tblItemRB0(ItemId,RuleBreak,Code,RuleBreakResponse,Fee,Amount,ItemStatusId)
					SELECT i.ItemId
						,CONVERT(NVARCHAR(25),
							CASE WHEN crb.DebugRuleBreak in (-1,-3,-5,-6,-7,-8,-9) THEN 1														--2020-10-21
									WHEN crb.DebugRuleBreak = -4 THEN 2
									WHEN crb.DebugRuleBreak = -2 THEN 0
							END) as RuleBreak
						,CONVERT(NVARCHAR(25),
							CASE WHEN crb.DebugRuleBreak in (-1,-3,-4) THEN								
									CONVERT(NVARCHAR(25),CONVERT(TINYINT,(i.CheckAmount % 1.00)*100))	--CONVERT TO CODE
								WHEN crb.DebugRuleBreak in (-5,-6,-7) THEN '2'						
								WHEN crb.DebugRuleBreak in (-8,-9) THEN '6'							
							END													 
							) as Code
						,CASE WHEN (crb.DebugRuleBreak = -1
									OR (crb.DebugRuleBreak = -5 AND m.IRD = 0))
									AND i.CheckAmount % 1.00 IN (0.01,0.02,0.03,0.04,0.05,0.06,0.07,0.08,0.09,0.10) THEN
									[common].[ufnResponseCodeDesc](@iOrgId,CONVERT(NVARCHAR(25),CONVERT(TINYINT,(i.CheckAmount % 1.00)*100)))	--2020-10-21
							WHEN crb.DebugRuleBreak in (-3,-4)
								AND i.CheckAmount % 1.00 IN (0.01,0.02,0.03,0.04,0.05,0.06,0.07,0.08,0.09) THEN
									[common].[ufnResponseCodeDesc](@iOrgId,CONVERT(NVARCHAR(25),CONVERT(TINYINT,(i.CheckAmount % 1.00)*100)))	--2020-10-21
							WHEN crb.DebugRuleBreak = -2 THEN ''
							WHEN crb.DebugRuleBreak IN (-5,-6,-7) THEN 
								N'Non-Eligible Transaction. Item or Account Holder does not meet predefined client criteria.'					--2020-09-13
							WHEN crb.DebugRuleBreak = -8 THEN
								N'Duplicate MICR.  Item presented has already been presented in network.' 
							WHEN crb.DebugRuleBreak = -9 THEN 'Third-Party Transaction, not eligible for approval.'
						END as RuleBreakResponse
						,CASE WHEN crb.DebugRuleBreak IN (-1,-3,-5,-6) THEN 0.0
								ELSE i.Fee
							END as Fee
						,i.CheckAmount
						,CASE WHEN crb.DebugRuleBreak IN (-1,-3,-5,-6) and @bFirstDataClient = 1 THEN @iFinByProxyItemStatusId					--FirstData failure transactions must be completed by proxy
								ELSE @iProcessedItemStatusId
							END
					FROM @tblItem i
					INNER JOIN @tblCannedRuleBreak crb ON i.ItemId = crb.ItemId
					LEFT JOIN @tblMICR m ON i.ItemKey = m.ItemKey
					WHERE crb.DebugRuleBreak <> 0;
			
					IF @iLogLevel > 2
					BEGIN
						INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
						VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Load @tblItemRB0' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  		
						SET @dtTimerDate = SYSDATETIME();	
					END

					--INSERTED BELOW
					----INSERT the debug stuff if it exists
					--INSERT INTO @tblItemRB(ItemId,RuleBreak,RuleBreakResponse,Fee,Amount,ItemStatusId)
					--SELECT ItemId,RuleBreak,RuleBreakResponse,Fee,Amount,ItemStatusId 
					--FROM @tblItemRB0;
				END --EXISTS (SELECT 'X' FROM @tblCannedRuleBreak WHERE DebugRuleBreak <> 0)

			END --IF @bDebug = 1 

			--ADD Process and Item Stats into XML --2017-05-01
			SELECT @xProcessAndItemStat = (SELECT s.ItemId, s.StatName, s.StatValue
								FROM (SELECT i.ItemId, s.StatName, s.StatValue
									FROM @tblStat s
									CROSS APPLY @tblItem i
									--2021-09-01
									UNION ALL
									SELECT i2.ItemId
										,TRY_CONVERT(NVARCHAR(128),N'ItemId') as StatName
										,TRY_CONVERT(NVARCHAR(100),i2.ItemId) as StatValue
									FROM @tblItem i2
									--2021-09-01
									) as s
								ORDER BY 1
								FOR XML PATH ('Stat')--element set identifier
							)
			--COMBINE current XML Sets
			SELECT @pxTableSet = (SELECT @pxTableSet, @xProcessAndItemStat
									FOR XML PATH(''));
			--2022-04-04
			--Add D2CStats into XML, provided via [authorized].[uspItemActivityInsertOut]
			If @iProcessMethodology = 4
				SELECT @pxTableSet = (SELECT @pxTableSet, @xD2CStat
										FOR XML PATH(''));

			--Debug Flag
			SELECT @xDebugStat = ( SELECT unpvt.ItemId, unpvt.StatName, unpvt.StatValue as StatValue
					FROM (SELECT i.ItemId, @bDebug AS DebugDefined
						FROM @tblItem i
						) stat
						UNPIVOT
							(StatValue FOR StatName IN ( DebugDefined ) 
						) AS unpvt
					FOR XML PATH('Stat')
			)
			SELECT @pxTableSet = (SELECT @pxTableSet, @xDebugStat
										FOR XML PATH(''));

			IF @bDebug = 1
			BEGIN
				SELECT @xDebugStat = (SELECT ItemId, StatName, StatValue
									FROM [common].[ufnItemTestStat](@tblItem)
									FOR XML PATH ('Stat')--element set identifier
								)
				SELECT @pxTableSet = (SELECT @pxTableSet, @xDebugStat
											FOR XML PATH(''));
				--Add in additional D2CStats
				If @iProcessMethodology = 4
					SELECT @pxTableSet = (SELECT @pxTableSet, @xD2CStat
											FOR XML PATH(''));
			END

			IF NOT EXISTS (SELECT 'X' FROM @tblItemRB0) --NO RiskProcessing
			BEGIN
				INSERT INTO @tblItemRB0(ItemId,RuleBreak,Code,RuleBreakResponse,Fee,Amount,ItemStatusId)	--2020-12-03 instead of @tblItemRB
				SELECT ItemId, 1, 1, 'Incomplete information. Transaction does not contain all of the required information.',0.00,0.00,@iProcessedItemStatusId
				FROM @tblItem;
				IF @iLogLevel > 2
				BEGIN
					INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
					VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'No Riskprocessing Defined' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  		
					SET @dtTimerDate = SYSDATETIME();
				END
			END

			IF @iLogLevel > 2
			BEGIN
				INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
				VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Processed Items' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  		
				SET @dtTimerDate = SYSDATETIME();	
			END

			--Grab payer item data
			SET @xPayer = (SELECT PayerId,RoutingNumber,AccountNumber
							FROM @tblPayerIR Payer
							FOR XML PATH('Payer')
				);

			--TRANSFER @tblItemRB0 to @tblItemRB  so uspItemUpdateRBOut and uspItemActivityUpdate are set correctly 2020-12-03
			INSERT INTO @tblItemRB(ItemId,RuleBreak,RuleBreakResponse,Fee,Amount,ItemStatusId)	--2020-12-03
			SELECT ItemId,RuleBreak,RuleBreakResponse,Fee,Amount,ItemStatusId
			FROM @tblItemRB0;

			EXECUTE [ifa].[uspItemUpdateRBOut]
				@ptblItem = @tblItemRB		--only '0' or '1'
				,@pbiItemId = @pbiItemId OUTPUT --will be negative if an issue
				,@pxItem = @xItem OUTPUT;
			--AT this point we need to add in the Item TableSet
			SET @pxTableSet = (SELECT @pxTableSet, @xItem, @xPayer
							FOR XML PATH(''));

		END 
		END TRY
		BEGIN CATCH
			EXEC [error].[uspLogErrorDetailInsertOut2] @psSchemaName = @sSchemaName, @pnvProcessKey=@ncProcessKey, @piErrorDetailId=@iErrorDetailId OUTPUT;
			IF @iLogLevel > 0
				INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
				VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Exit-ErrorDetailId ='+CONVERT(NCHAR(10),@iErrorDetailId),DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			THROW;
		END CATCH;

		--UPDATE ItemActivity via procedure, first update any rulebreak info
		UPDATE i
			SET i.RuleBreak = rb.RuleBreak --only '0' or '1'
		FROM @tblItem i
		INNER JOIN @tblItemRB rb ON i.ItemId = rb.ItemId;

		--2020-12-03 ONLY UPDATE non auto-decline
		IF @bMaxItemsExceeded = 0
			EXECUTE [ifa].[uspItemActivityUpdate]
				 @ptblItem = @tblItem
				,@piProcessMethodology = @iProcessMethodology
				,@pncProcessKey = @ncProcessKey
				,@pnvSrc = @ncObjectName;   --uspItemInsertOut

		SET @iCurrentTransactionLevel = @@TRANCOUNT;
		BEGIN TRANSACTION
		BEGIN TRY
			INSERT INTO [ifa].[RuleBreakData](ItemId,Code,[Message],StatusFlag,DateActivated,UserName)
			OUTPUT inserted.RuleBreakDataId
				,inserted.ItemId
				,inserted.Code
				,inserted.[Message]
				,inserted.StatusFlag
				,inserted.DateActivated
				,inserted.UserName
			INTO @tblRuleBreakData
			SELECT ItemId,Code,RuleBreakResponse,1,SYSDATETIME(),@nvUserName	--2020-12-03 no further adjustment required, already completed above
			FROM @tblItemRB0
			WHERE RuleBreak <> '0'
			ORDER BY ItemId;
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
				ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut2] @psSchemaName = @sSchemaName, @pnvProcessKey=@ncProcessKey,@piErrorDetailId=@iErrorDetailId OUTPUT;
			IF @iLogLevel > 0
				INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
				VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Exit-ErrorDetailId ='+CONVERT(NCHAR(10),@iErrorDetailId),DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			THROW;
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel 
		BEGIN
			COMMIT TRANSACTION;	
			IF @iLogLevel > 2
			BEGIN
				INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
				VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Inserted RuleBreakData' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  		
				SET @dtTimerDate  = SYSDATETIME();
			END
			--GENERATE RuleBreakData XML
			SET @xRuleBreakData = (SELECT RuleBreakDataId,ItemId,Code,[Message],StatusFlag,DateActivated,UserName
							FROM @tblRuleBreakData RuleBreakData
							ORDER BY RuleBreakDataId
							FOR XML PATH('RuleBreakData')
				)
			--AT this point we need to add in the RuleBreakData TableSet
			SET @pxTableSet = (SELECT @pxTableSet,@xRuleBreakData
							FOR XML PATH(''));
		END

		--Last Message uses @dtInitial
		IF @iLogLevel > 0
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Exit' ,DATEDIFF(microsecond,@dtInitial,SYSDATETIME()),SYSDATETIME());
	END
END

