USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [ifa].[uspItemMultiInsertOut]
	CreatedBy: Larry Dugger			 
	Descr: This procedure is a shell that repeatedly calls uspItemInsertOut
		to process items in a single per set until all are riskprocessed
		This iteration optimizes the AtomicStat Loads and uspProcessRiskControl
 
	Procedures:[error].[uspLogErrorDetailInsertOut2]
		, [ifa].[uspItemInsertOut]

	Functions: [common].[ufnConfigValue]
		,[common].[ufnCustomerItemList]
		,[common].[ufnCustomerItemListDeux]

	History:
		2020-01-04 - LBD - Created, provides a singular Item processing framework
			,the intent is to reduce the impact of large multi-item sets
		2020-02-07 - LBD - Modified,
			ProcessMethodology adjustments, 
			AtomicStat data retrieval, since Customer is pre-read here, the
			We redefine @tblPreStat and pass to uspItemInsertOut along
			with new parameter @pbMaxItemsExceeded
		2020-03-11 - LBD - Changed type definition of @ptblMiscStat to avoid 
			truncation of data CCF1905
		2020-03-18 - CBS - Modified, added Deluxe to the section that loads Rule Details
		2020-06-03 - LBD - Adjusted logging so it operates without locking (unless necessary)
		2020-07-27 - LBD - Swapped out use of ufnCustomerItemList with ufnCustomerItemListDeux
			to see if we could eliminate the 'unexplained' CPU at 100% issue.
			Includes flip-flop code ufnCustomerItemListDeux2 commented-out.
		2020-10-15 - CBS - Added ProcessItemCount into @tblProcessStat for TDB RP use,
			table will work for Client or lower level Org as long a both aren't defined
			in the table.
		2020-10-22 - LBD - Corrected DisableMultiItemRiskProcessing query
		2021-03-01 - LBD - Reduce contention around AutoFraud reads
		2022-03-10 - CBS - Replaced the CASE statement establishing IdTypeId using the 'Primary' 
			IdType based on the value returned by ifa.ufnProcessMethodologyDeux. Pass the IdMac64 
			from @tblDecisionField into @tblStatKey irregardless of ProcessMethodolgy
*****************************************************************************************/
ALTER   PROCEDURE [ifa].[uspItemMultiInsertOut](
	@ptblDecisionField [ifa].[DecisionFieldType] READONLY 
	,@ptblItemRequest [ifa].[ItemRequestType] READONLY
	,@ptblMiscStat [ifa].[MiscStatType] READONLY
	,@pbiItemId BIGINT OUTPUT
	,@pxTableSet XML OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @tblAutoFraud [ifa].[AutoFraudType]
		,@tblDecisionField [ifa].[DecisionFieldType] 
		,@tblItemRequest [ifa].[ItemRequestType]
		,@tblProcessStat [ifa].[StatType]
		,@tblDLStat [ifa].[StatType]
		,@tblCommon [ifa].[CommonType]
		,@tblRuleDetail [rule].[RuleDetailType]
		,@tblItemList [ifa].[ItemListType]
		,@tblItemCurrent [ifa].[ItemCurrentType]
		,@tblStatKey [ifa].[StatKeyType]
		,@tblRCLadderTop [riskprocessing].[RCLadderTopType]
		,@tblRCLadder [riskprocessing].[RCLadderType]
		,@tblLadderRung [riskprocessing].[LadderRungType]
		,@tblAvailableCheckTypeCode [ifa].[CheckTypeCodeType];

	DECLARE @tblItemRequestTypeEnhanced AS TABLE(
		RowId INT NOT NULL
		,ItemTypeCode nvarchar(25) NULL
		,ClientItemId nvarchar(50) NULL
		,ItemKey nvarchar(25) NULL
		,CheckTypeCode nvarchar(25) NULL
		,[Date] datetime NULL
		,CheckAmount money NULL
		,MICR nvarchar(255) NULL
		,RoutingNumber nchar(9) NULL
		,AccountNumber nvarchar(50) NULL
		,CheckNumber nvarchar(50) NULL
		,Scanned bit NULL
	)

	DECLARE @iLogLevel int = ISNULL(TRY_CONVERT(INT,[common].[ufnConfigValue](N'LogLevel [ifa].[uspItemMultiInsertOut]')),1)
		--,@iTestStats int = ISNULL(TRY_CONVERT(INT,[common].[ufnConfigValue](N'TestStats [riskprocessing].[uspItemMultiInsertOut]')),0) 
		,@dtTimerDate datetime2(7) = SYSDATETIME()
		,@dtInitial datetime2(7) = SYSDATETIME() --used for complete time in procedure
		,@ncSchemaName nchar(20) = CONVERT(nchar(20),OBJECT_SCHEMA_NAME(@@PROCID))
		,@ncObjectName nchar(50) = CONVERT(nchar(50),OBJECT_NAME(@@PROCID))
		,@iItemCount int = 0
		,@iCurrentRowId int
		,@xTableSet xml  = 0x
		,@xItem xml
		,@xCommon xml
		,@iErrorDetailId INT
		,@sSchemaName nvarchar(128)= OBJECT_SCHEMA_NAME(@@PROCID)
		,@bMaxItemsExceeded bit = 0
		,@nvCustomerIdentifier nvarchar(50) 
		,@iProcessMethodology int 
		,@ncSQLOpen nchar(100) = N'OPEN SYMMETRIC KEY VALIDSYMKEY DECRYPTION BY ASYMMETRIC KEY [VALIDASYMKEY]'
		,@ncSQLClose nchar(100) = N'CLOSE SYMMETRIC KEY VALIDSYMKEY'
		,@nvProcessKey nvarchar(25)
		,@dtProcessDateActivated datetime2(7);

	IF @iLogLevel > 0
	BEGIN
		INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		SELECT TRY_CONVERT(NCHAR(25),ProcessKey),@ncSchemaName,@ncObjectName,N'Enter' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME()
		FROM @ptblDecisionField;  		
		SET @dtTimerDate = SYSDATETIME();
	END

	--Load Common
	INSERT INTO @tblCommon(CommonName,CommonValue)
	SELECT N'OrgZipCode', ISNULL(TRY_CONVERT(NVARCHAR(100),OrgZipCode),N'NULL')
	FROM @ptblDecisionField;
	INSERT INTO @tblCommon(CommonName,CommonValue)
	SELECT N'OrgClientId', ISNULL(TRY_CONVERT(NVARCHAR(100),OrgClientId),N'NULL')
	FROM @ptblDecisionField;
	INSERT INTO @tblCommon(CommonName,CommonValue)
	SELECT N'OrgState', ISNULL(TRY_CONVERT(NVARCHAR(100),OrgState),N'NULL')
	FROM @ptblDecisionField;
	INSERT INTO @tblCommon(CommonName,CommonValue)
	SELECT N'OrgLocationId', ISNULL(TRY_CONVERT(NVARCHAR(100),OrgId),N'NULL')
	FROM @ptblDecisionField;

	--Set some local variables
	SELECT @iItemCount = ItemCount
		,@bMaxItemsExceeded = MaxItemsExceeded
		,@nvProcessKey = ProcessKey
		,@iProcessMethodology = ProcessMethodology
		,@dtProcessDateActivated = ProcessDateActivated --2020-10-22
	FROM @ptblDecisionField;

	--All active CheckTypes as available...(at some future time we should restrict, and raise and error on Item insert....
	INSERT INTO @tblAvailableCheckTypeCode(CheckTypeId,CheckTypeCode,StatusFlag)
	SELECT CheckTypeId,Code,StatusFlag 
	FROM [common].[CheckType]
	WHERE StatusFlag = 1;

	BEGIN TRY
		IF @bMaxItemsExceeded = 1 --Singular call to uspItemInsertOut
		BEGIN
			EXECUTE [ifa].[uspItemInsertOut]
					@ptblAvailableCheckTypeCode = @tblAvailableCheckTypeCode
				,@ptblDecisionField = @ptblDecisionField
				,@ptblItemRequest = @ptblItemRequest
				,@ptblProcessAutoFraud = @tblAutoFraud
				,@ptblProcessStat = @tblProcessStat
				,@ptblItemList = @tblItemList
				,@ptblLadderRung = @tblLadderRung
				,@ptblMiscStat = @ptblMiscStat
				,@ptblRCLadder = @tblRCLadder
				,@ptblRuleDetail = @tblRuleDetail
				,@ptblStatKey = @tblStatKey
				,@pbiItemId = @pbiItemId OUTPUT
				,@pxTableSet = @xTableSet OUTPUT;
			--COMBINE current XML Sets
			SELECT @pxTableSet = (SELECT @pxTableSet, @xTableSet
									FOR XML PATH(''));
		END
		ELSE 
		IF @iItemCount > 0	
		BEGIN
			--Add RowId to the provided Item(s)
			;WITH tblCteItemRequest AS
			(
				SELECT ROW_NUMBER() OVER (ORDER BY ItemKey) AS RowId
					,ItemTypeCode,ClientItemId,ItemKey,CheckTypeCode
					,[Date],CheckAmount,MICR,RoutingNumber,AccountNumber,CheckNumber,Scanned
				FROM @ptblItemRequest
			)
			INSERT INTO @tblItemRequestTypeEnhanced(RowId,[ItemTypeCode],[ClientItemId],[ItemKey],[CheckTypeCode]
				,[Date],[CheckAmount],[MICR],[RoutingNumber],[AccountNumber],[CheckNumber],[Scanned])
			SELECT RowId,ItemTypeCode,ClientItemId,ItemKey,CheckTypeCode
				,[Date],CheckAmount,MICR,RoutingNumber,AccountNumber,CheckNumber,Scanned
			FROM tblCteItemRequest;
			--Set the First Row
			SELECT @iCurrentRowId = min(RowId)
			FROM @tblItemRequestTypeEnhanced;
			--Insert the First Row
			INSERT INTO @tblItemRequest (ItemTypeCode,ClientItemId,ItemKey,CheckTypeCode
				,[Date],CheckAmount,MICR,RoutingNumber,AccountNumber,CheckNumber,Scanned)
			SELECT ItemTypeCode,ClientItemId,ItemKey,CheckTypeCode
				,[Date],CheckAmount,MICR,RoutingNumber,AccountNumber,CheckNumber,Scanned
			FROM @tblItemRequestTypeEnhanced 
			WHERE RowId = @iCurrentRowId;

			--Grab the LadderTop for this Org (if it exists)
			INSERT INTO @tblRCLadderTop(RCLadderTopId,RCId,RCName,OrgId,OrgXrefId,DimensionName
				,OrgName,OrgType,LadderTopXrefId,LadderTopId,CollectionName)
			SELECT RCLadderTopId,RCId,RCName,r.OrgId,OrgXrefId,DimensionName
				,r.OrgName,OrgType,LadderTopXrefId,LadderTopId,CollectionName 
			FROM @ptblDecisionField df
			CROSS APPLY [common].[ufnRCLadderTopByOrg](df.OrgId) r;

			IF @iLogLevel > 1
			BEGIN
				INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
				SELECT TRY_CONVERT(NCHAR(25),ProcessKey),@ncSchemaName,@ncObjectName,N'[common].[ufnRCLadderTopByOrg]',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME()
				FROM @ptblDecisionField;
				SET @dtTimerDate  = SYSDATETIME();
			END

			--RC for this organization, rollup occurs via any parent or self linked to RiskControl Dimension
			IF EXISTS (SELECT 'X' FROM @tblRCLadderTop)
			BEGIN			
				--1 Retrieve Ladders into a temp table
				INSERT INTO @tblRCLadder(RCLadderTopId,Id,RCId,LadderTopXrefId,LadderTopId,LadderSuccessLTXId,SuccessLtId,LadderContinueLTXId,ContinueLtId
					,RCCollectionName,LadderCollectionName,LadderSuccessValue)
				SELECT x.RCLadderTopId,x.Id,x.RCId,x.LadderTopXrefId,x.LadderTopId,x.LadderSuccessLTXId,x.SuccessLtId,x.LadderContinueLTXId,x.ContinueLtId
					,x.RCCollectionName,x.LadderCollectionName,x.LadderSuccessValue
				FROM @tblRCLadderTop rclt
				CROSS APPLY [common].[ufnRCLadderTopLadderTopXrefTreeMini](rclt.RCLadderTopId) x;
		
				--2 Retrieve Ladder Rungs into temp table
				INSERT INTO @tblLadderRung(LadderTopId,Id,LadderDBProcessXrefId,LadderCode,Title,ProcessCode,ProcessName,DBProcessSuccessValue
					,DBProcessSuccessLDBPXId,DBProcessContinueLDBPXId,Param1,Param2,Param3,Param4,Param5,Exitlevel,Result,RetrievalCode)
				SELECT rc.LadderTopId, lr.Id,LadderDBProcessXrefId,LadderCode,Title,ProcessCode,ProcessName,DBProcessSuccessValue
					,DBProcessSuccessLDBPXId,DBProcessContinueLDBPXId,Param1,Param2,Param3,Param4,Param5,Exitlevel,Result,RetrievalCode
				FROM @tblRCLadder rc
				CROSS APPLY [common].[ufnLadderRungs](rc.LadderTopId) lr;

				IF @iLogLevel > 1
				BEGIN
					INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
					SELECT TRY_CONVERT(NCHAR(25),ProcessKey),@ncSchemaName,@ncObjectName,N'[common].[ufnRCLadderTopLadderTopXrefTreeMini]',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME()
					FROM @ptblDecisionField;
					SET @dtTimerDate  = SYSDATETIME();
				END
			END

			--IS RiskProcessing Defined?
			INSERT INTO @tblProcessStat(StatName,StatValue)
			SELECT unpvt.StatName, unpvt.StatValue as StatValue
			FROM (SELECT TRY_CONVERT(NVARCHAR(100),CASE WHEN EXISTS (SELECT 'X' FROM @tblLadderRung) THEN '1' ELSE '0' END) AS RiskProcessingDefined
				FROM @tblItemRequest) stat
				UNPIVOT
					(StatValue FOR StatName IN ( RiskProcessingDefined ) 
				) AS unpvt;

			--Load RuleDetails
			--IF @iProcessMethodology = 0	--RETAIL ONLY, CURRENTLY 2020-03-18
			IF @iProcessMethodology IN (0,2,3)	--RETAIL and Deluxe 2020-03-18
			BEGIN
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
				FROM @ptblDecisionField df
				CROSS APPLY [common].[ufnCurrentRuleDetail](df.OrgId);
				IF @iLogLevel > 1
				BEGIN
					INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
					SELECT TRY_CONVERT(NCHAR(25),ProcessKey),@ncSchemaName,@ncObjectName,N'[common].[ufnCurrentRuleDetail]',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME()
					FROM @ptblDecisionField;
					SET @dtTimerDate = SYSDATETIME();
				END
			END

			--Load StatKey Information
			INSERT INTO @tblStatKey(ProcessMethodology,FilterName,ItemId,OrgParentId,OrgClientId,OrgId,CustomerId,RoutingNumber,AccountNumber,IdTypeId
				,DollarStratRangeId,OrgGeoLargeId,OrgGeoSmallId,OrgGeoZip4Id,OrgChannelId,InternalBankAccountNumber,ClientProvidedIdentifier,IdMac64)
			SELECT df.ProcessMethodology 
				,N'Process' as FilterName
				,0 as ItemId
				,df.OrgParentId
				,TRY_CONVERT(NVARCHAR(50),df.OrgClientId)
				,TRY_CONVERT(NVARCHAR(50),df.OrgId)
				,df.CustomerId
				,ir.RoutingNumber	--Gets reset for each specific item RoutingNumber
				,ir.AccountNumber	--Gets reset for each specific item AccountNumber
				/*2022-03-10 ,CASE WHEN df.ProcessMethodology <> 0 THEN N'25' ELSE N'3' END as IdTypeId */
				,df.PrimaryIdTypeId as IdTypeId --2022-03-10
				,NULL				--Gets reset for each specific item DollarStratRangeId
				,TRY_CONVERT(NVARCHAR(50),[common].[ufnOrgGeoLargeId](df.OrgId)) as OrgGeoLargeId
				,TRY_CONVERT(NVARCHAR(50),[common].[ufnOrgGeoSmallId](df.OrgId)) as OrgGeoSmallId
				,TRY_CONVERT(NVARCHAR(50),[common].[ufnOrgGeoZip4Id](df.OrgId)) as OrgGeoZip4Id
				,TRY_CONVERT(NVARCHAR(50),[common].[ufnOrgChannelOrgId](df.OrgId)) as OrgChannelId
				,df.InternalBankAccountNumber as InternalBankAccountNumber
				,df.CustomerIdentifier as ClientProvidedIdentifier
				/*2022-03-10 ,CASE WHEN df.ProcessMethodology <> 0 THEN 0x ELSE df.IdMac64 END as IdMac64 */
				,df.IdMac64	--2022-03-10
			FROM @tblItemRequest ir
			CROSS APPLY @ptblDecisionField df

			--Load Item History For Customer
			INSERT INTO @tblItemList(ItemId,ItemTypeId,ProcessId,OrgClientId,OrgId,Latitude,Longitude,OrgDistance,OrgName,OrgIdCode,OrgState,PayerId
				,CustomerId,ItemKey,ClientItemId,RoutingNumber,AccountNumber,CheckNumber,CheckAmount,CheckTypeId,ItemTypeDate,Fee,Amount
				,MICR,Scanned,RuleBreak,RuleBreakResponse,ItemStatusId,ClientAcceptedId,OriginalPayerId,AcctChkNbrSwitch,StatusFlag,DateActivated)
			SELECT cil.ItemId,cil.ItemTypeId,cil.ProcessId,df.OrgClientId,cil.OrgId,cil.Latitude,cil.Longitude,cil.OrgDistance,cil.OrgName,OrgIdCode,cil.OrgState,cil.PayerId
				,cil.CustomerId,cil.ItemKey,cil.ClientItemId,cil.RoutingNumber,cil.AccountNumber,cil.CheckNumber,cil.CheckAmount,cil.CheckTypeId,cil.ItemTypeDate,cil.Fee,cil.Amount
				,cil.MICR,cil.Scanned,cil.RuleBreak,cil.RuleBreakResponse,cil.ItemStatusId,cil.ClientAcceptedId,cil.OriginalPayerId,cil.AcctChkNbrSwitch,cil.StatusFlag,cil.DateActivated
			FROM @ptblDecisionField df
			CROSS APPLY [common].[ufnCustomerItemListDeux] (df.CustomerId,df.ProcessId,df.ProcessMethodology,df.ProcessDateActivated) cil --all inserted values provided by this function
			WHERE df.OrgClientExternalCode <> N'DeluxeClnt' --Deluxe Client receives no History
				AND df.Debug = 0; --Do not load history for debug

			IF @iLogLevel > 1
			BEGIN
				INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
				SELECT TRY_CONVERT(NCHAR(25),ProcessKey),@ncSchemaName,@ncObjectName,N'[common].[ufnCustomerItemListDeux]',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME()
				FROM @ptblDecisionField;
				SET @dtTimerDate = SYSDATETIME();
			END

			--CUSTOMER ATOMIC STATS HERE Need to correctly setup
			INSERT INTO @tblProcessStat(StatName,StatValue)
			SELECT StatName,StatValue
			FROM [stat].[ufnProcessAtomicStat](@tblStatKey)
			ORDER BY StatName;

			IF @iLogLevel > 1
			BEGIN
				INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
				SELECT TRY_CONVERT(NCHAR(25),ProcessKey),@ncSchemaName,@ncObjectName,N'Load ProcessAtomic Stats',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME()
				FROM @ptblDecisionField;
				SET @dtTimerDate = SYSDATETIME();
			END
			--2020-10-15
			INSERT INTO @tblProcessStat(StatName,StatValue)
			SELECT N'ProcessItemCount', ISNULL(TRY_CONVERT(NVARCHAR(100),ItemCount),N'1')
			FROM @ptblDecisionField;
			INSERT INTO @tblProcessStat(StatName,StatValue)
			SELECT N'DisableMultiItemRiskProcessing',MaxItemsExceeded --2020-12-06
			FROM @ptblDecisionField;

			INSERT INTO @tblProcessStat(StatName,StatValue) 
			SELECT 'DLNumber',DLNumber
			FROM @ptblDecisionField 
			WHERE DLNumber IS NOT NULL;
			INSERT INTO @tblProcessStat(StatName,StatValue) 
			SELECT 'DLStateAbbr',DLStateAbbr
			FROM @ptblDecisionField 
			WHERE DLStateAbbr IS NOT NULL;

			IF @iProcessMethodology = 0	--RETAIL
				AND NOT EXISTS (SELECT 'X'
							FROM @tblProcessStat
							WHERE StatName = 'DLNumber')
			BEGIN
				EXECUTE(@ncSQLOpen);		--OPEN SYMMETRIC KEY ValidSymKey DECRYPTION BY ASYMMETRIC KEY [VALIDASYMKEY];
				INSERT INTO @tblDLStat(StatName,StatValue)
				SELECT unpvt.StatName, unpvt.StatValue
				FROM (SELECT TRY_CONVERT(NVARCHAR(100),ISNULL(CONVERT(NVARCHAR(50),DECRYPTBYKEY(cix.IdEncrypted)),'')) AS DLNumber
						,TRY_CONVERT(NVARCHAR(100),ISNULL(s.Code,'')) AS DLStateAbbr
					FROM @ptblDecisionField df
					LEFT OUTER JOIN [customer].[CustomerIdXref] cix on df.CustomerId = cix.CustomerId
																AND cix.IdTypeId = 2 --DL
					LEFT OUTER JOIN [common].[State] s on cix.IdStateId = s.StateId
					) stat
					UNPIVOT
						(StatValue FOR StatName IN 
							(DLNumber,DLStateAbbr
							) 
					) AS unpvt
				EXECUTE(@ncSQLClose);		--CLOSE SYMMETRIC KEY ValidSymKey;
				INSERT INTO @tblProcessStat(StatName,StatValue)
				SELECT StatName,StatValue
				FROM @tblDLStat;
			END

			--LOAD related AutoFraud Records, by KeyIdType 'Customer' 
			INSERT INTO @tblAutoFraud(AutoFraudId,AutoFraudTypeId,AutoFraudTypeCode,OrgId,KeyId,KeyIdType)
			SELECT af.AutoFraudId, af.AutoFraudTypeId, aft.Code, af.OrgId, af.KeyId, aft.KeyIdType
			FROM [ifa].[AutoFraud] af WITH (READUNCOMMITTED) --2021-03-01
			INNER JOIN [ifa].[AutoFraudType] aft ON af.AutoFraudTypeId = aft.AutoFraudTypeId
													AND aft.KeyIdType = 'CustomerId'
			CROSS APPLY @ptblDecisionField df
			WHERE af.KeyId = df.CustomerId
				AND af.OrgId = df.OrgClientId
				AND af.StatusFlag > 0;

			IF @iLogLevel > 1
			BEGIN
				INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
				SELECT TRY_CONVERT(NCHAR(25),ProcessKey),@ncSchemaName,@ncObjectName,N'Load Customer AutoFraud',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME()
				FROM @ptblDecisionField;
				SET @dtTimerDate = SYSDATETIME();
			END

			WHILE @iCurrentRowId <= @iItemCount
			BEGIN
				SET @xTableSet = 0x; --clear the XML variable

				EXECUTE [ifa].[uspItemInsertOut]
						@ptblAvailableCheckTypeCode = @tblAvailableCheckTypeCode
					,@ptblDecisionField = @ptblDecisionField
					,@ptblItemRequest = @tblItemRequest
					,@ptblProcessAutoFraud = @tblAutoFraud
					,@ptblProcessStat = @tblProcessStat
					,@ptblItemList = @tblItemList
					,@ptblLadderRung = @tblLadderRung
					,@ptblMiscStat = @ptblMiscStat
					,@ptblRCLadder = @tblRCLadder
					,@ptblRuleDetail = @tblRuleDetail
					,@ptblStatKey = @tblStatKey
					,@pbiItemId = @pbiItemId OUTPUT
					,@pxTableSet = @xTableSet OUTPUT; --Contains Stats/Item,Items,RuleBreakData,Common

				--COMBINE current XML Sets
				SELECT @pxTableSet = (SELECT @pxTableSet, @xTableSet
										FOR XML PATH(''));

				--Move to next row
				SET @iCurrentRowId += 1; 

				IF @iCurrentRowId > @iItemCount
					BREAK

				--ADD resulting Item data to ItemList
				INSERT INTO @tblItemList(ItemId,ItemTypeId,ProcessId,OrgClientId,OrgId,Latitude,Longitude,OrgDistance,OrgName,OrgIdCode,OrgState,PayerId
					,CustomerId,ItemKey,ClientItemId,RoutingNumber,AccountNumber,CheckNumber,CheckAmount,CheckTypeId,ItemTypeDate
					,Fee,Amount,MICR,Scanned,RuleBreak,RuleBreakResponse,ItemStatusId,ClientAcceptedId,OriginalPayerId,AcctChkNbrSwitch,StatusFlag,DateActivated)
				SELECT i.ItemId,i.ItemTypeId,i.ProcessId,df.OrgClientId,df.OrgId,df.OrgLatitude,df.OrgLongitude,df.OrgDistance,df.OrgCode,df.OrgExternalCode,df.OrgState,i.PayerId
					,df.CustomerId,ir.ItemKey,ir.ClientItemId,p.RoutingNumber,p.AccountNumber,i.CheckNumber,ir.CheckAmount,i.CheckTypeId,i.ItemTypeDate
					,i.Fee,i.Amount,ir.MICR,ir.Scanned,i.RuleBreak,i.RuleBreakResponse,i.ItemStatusId,i.ClientAcceptedId,i.OriginalPayerId,i.AcctChkNbrSwitch,i.StatusFlag,i.DateActivated
				FROM @tblItemRequest ir
				INNER JOIN (SELECT r.a.value('ItemId[1]','bigint') AS ItemId
							,r.a.value('ItemKey[1]','nvarchar(25)') AS ItemKey
							,r.a.value('PayerId[1]','bigint') AS PayerId
							,r.a.value('ItemTypeId[1]','int') AS ItemTypeId
							,r.a.value('ProcessId[1]','bigint') AS ProcessId
							,r.a.value('CheckNumber[1]','nvarchar(50)') AS CheckNumber
							,r.a.value('Amount[1]','money') AS Amount
							,r.a.value('Fee[1]','money') AS Fee
							,r.a.value('CheckTypeId[1]','int') AS CheckTypeId
							,r.a.value('RuleBreak[1]','nvarchar(25)') AS RuleBreak
							,r.a.value('RuleBreakResponse[1]','nvarchar(255)') AS RuleBreakResponse
							,r.a.value('ItemStatusId[1]','int') AS ItemStatusId
							,r.a.value('StatusFlag[1]','int') AS StatusFlag
							,r.a.value('ClientAcceptedId[1]','int') AS ClientAcceptedId
							,r.a.value('OriginalPayerId[1]','int') AS OriginalPayerId
							,r.a.value('AcctChkNbrSwitch[1]','int') AS AcctChkNbrSwitch
							,r.a.value('ItemTypeDate[1]','datetime2(7)') AS ItemTypeDate
							,r.a.value('DateActivated[1]','datetime2(7)') AS DateActivated
						FROM @xTableSet.nodes('Item/.') r(a)) i on ir.ItemKey = i.ItemKey
				INNER JOIN (SELECT p.a.value('PayerId[1]','bigint') AS PayerId
							,p.a.value('RoutingNumber[1]','nchar(9)') AS RoutingNumber
							,p.a.value('AccountNumber[1]','nvarchar(50)') AS AccountNumber
						FROM @xTableSet.nodes('Payer/.') p(a)) p on i.PayerId = p.PayerId
				CROSS APPLY @ptblDecisionField df;

				--Prep for the next Row
				UPDATE ir
				SET ItemTypeCode = irte.ItemTypeCode
					,ClientItemId = irte.ClientItemId
					,ItemKey = irte.ItemKey
					,CheckTypeCode = irte.CheckTypeCode
					,[Date] = irte.[Date]
					,CheckAmount = irte.CheckAmount
					,MICR = irte.MICR
					,RoutingNumber = irte.RoutingNumber
					,AccountNumber = irte.AccountNumber
					,CheckNumber = irte.CheckNumber
					,Scanned = irte.Scanned
				FROM @tblItemRequest ir
				CROSS APPLY @tblItemRequestTypeEnhanced irte
				WHERE irte.RowId = @iCurrentRowId;
			END
		END	--IF @iItemCnt > 0
	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut2] @psSchemaName = @sSchemaName, @pnvProcessKey=@nvProcessKey,@piErrorDetailId=@iErrorDetailId OUTPUT;
		IF @iLogLevel > 0
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			SELECT TRY_CONVERT(NCHAR(25),ProcessKey),@ncSchemaName,@ncObjectName,N'Exit-ErrorDetailId ='+CONVERT(NCHAR(10),@iErrorDetailId),DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME()
			FROM @ptblDecisionField;
		THROW;
	END CATCH;

	--XML Common data for later consumption
	SELECT @xCommon = (SELECT CommonName, CommonValue
							FROM @tblCommon Common
							FOR XML PATH('Common')--element set identifier
						)
	SELECT @pxTableSet = (SELECT @pxTableSet, @xCommon
							FOR XML PATH(''));

	--Last Message uses @dtInitial
	IF @iLogLevel > 0
		INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		SELECT TRY_CONVERT(NCHAR(25),ProcessKey),@ncSchemaName,@ncObjectName,N'Exit' ,DATEDIFF(microsecond,@dtInitial,SYSDATETIME()),SYSDATETIME()
		FROM @ptblDecisionField;

END
