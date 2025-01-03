USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [ifa].[uspProcessRequestDeux]
	CreatedBy: Larry Dugger
	Description: This procedure will initiate an process request
	Tables: [ifa].[Process]
		,[organization].[Org]
		,[ifa].ItemResponseType
		,[ifa].[RuleBreakDataType]
		,[common].[ufnTransactionType]
		,[common].[ufnIdType]
		,[customer].[Customer]
		,[common].[MiscType]
	Functions: [common].[ufnState]
		,[common].[ufnStatusFlag]
		,[common].[ufnUpDimensionByOrgIdILTF]
		,[common].[ufnDimension]
		,[riskprocessingflow].[ufnRiskProcessingFlow]
		,[ifa].[ufnMaxItemsExceeded]
	Procedures: [customer].[uspCustomerInsertOut]
		,[common].[uspAddressInsertOut]
		,[customer].[uspCustomerAddressXrefInsertOut]
		,[customer].[uspCustomerUpdate]
		,[customer].[uspCustomerIdXrefInsertOut]
		,[ifa].[uspProcessInsertOut]
		,[customer].[uspAccountInsertOut]
		,[ifa].[uspItemMultiInsertOut]
		,[customer].[uspAccountInfoInsertOut]
		,[customer].[uspMiscInfoInsertOut]
	History:
		2015-05-26 - LBD - Created
		2020-02-07 - LBD - Recreated, cleaned-up all prior changes.
			established new methodology that reduces table contention i.e. re-reads of 
			primary tables.
		2020-02-11 - LBD - Modified, Deluxe specific error
		2020-03-11 - LBD - Changed type definition of @tblMiscStat to avoid 
			truncation of data CCF1905
		2020-06-03 - LBD - Adjusted logging so it operates without locking (unless necessary)
		2020-09-13 - LBD - Replace [ifa].[ufnProcessMethodology] with
			[ifa].[ufnProcessMethodologyDeux]
		2020-12-06 - LBD - Incorporated 'PNC' MaxItemsExceed and DisableMultiItemRiskProcessing 
			into the same function and flag 'MaxItemsExceeded'.
			This required adding a record for PNC to [ifa].[ufnMaxItemsExceeded]
		2020-12-17 - LBD - Flip MaxItemsExceed for 
			CustomerId 71923593 CustomerIdentifier 'THIRDPARTY00000000' CCF2318
		2020-12-29 - LBD - Correct default-assignment of DL to @iIdNumberIdTypeId variable
			CCF2329
		2020-02-02 - LBD - Added Query OltpRecordCount Stat CCF2399
		2022-03-10 - CBS - Commented out @iStatUmbrellaOrgTypeId and replaced it with 
			@iStatUmbrellaOrgId. Set @nvIdMac64 for any 'Primary' IdType (based ON the value 
			returned by ifa.ufnProcessMethodologyDeux. 	Add 'PrimaryIdTypeId' to the insert 
			populating @tblDecisionField, also replaced the CASE statement establishing 
			OrgParentId with @iStatUmbrellaOrgId
		2022-04-04 - LBD - VALID-211. Collect additional data for new process methodology 
			(D2C) into MiscType output set. D2C is the prefix for that data.
		2023-03-24 - LBD - VALID-866. Adjust MDMtoCIF
*****************************************************************************************/
ALTER   PROCEDURE [ifa].[uspProcessRequestDeux](
	@piProcessTypeId INT								 
	,@piOrgId INT										--This is the system id for transaction processing
	,@piUserId INT										
	,@pnvProcessKey NVARCHAR(25)						--This is 'TransactionKey' that is passed to the client, you use to link all activity 
	,@pnvClientRequestId NVARCHAR(50)
	,@pnvClientRequestId2 NVARCHAR(50)
	,@pnvCustomerIdentifier NVARCHAR(50)				--Clients identifier for a customer, must be present if other customer info
	,@pnvFirstName NVARCHAR(50)
	,@pnvLastName NVARCHAR(50)
	,@pnvAddressLine1 NVARCHAR(150)
	,@pnvAddressLine2 NVARCHAR(150)
	,@pnvCity NVARCHAR(100)
	,@pnvStateAbbv NCHAR(2)								--TX
	,@pnvZipCode NVARCHAR(9)							--761020234
	,@pnvCountry NVARCHAR(50)
	,@pnvPhoneNumber NVARCHAR(10)						--8176123456
	,@pnvEmailAddress NVARCHAR(100)
	,@pdDateOfBirth DATE								--date
	,@pnvIdTypeCode NVARCHAR(25)						--Currently 2 for DL
	,@pnvIdNumber NVARCHAR(50)							--123456789
	,@pnvIdStateAbbv NCHAR(2)							--TX
	,@pnvSocialSecurityNumber NVARCHAR(9)				--123456789
	,@pnvBankAccountType NVARCHAR(25)					--Code found in [common].[AccountType]
	,@pncBankRoutingNumber NCHAR(9)						--123456789
	,@pnvBankAccountNumber NVARCHAR(50)		
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@ptblItemRequest [ifa].[ItemRequestType] READONLY
	,@ptblAccountInfo [ifa].[AccountInfoType] READONLY	--current TextTypes are 'AccountInfo1','AccountInfo2'
	,@ptblDeviceInfo [ifa].[DeviceInfoType] READONLY	--current DeviceTypes are 'Phone','Pad','PC'
	,@ptblMiscInfo [ifa].[MiscInfoType] READONLY		--current TextTypes are 'MiscInfo1','MiscInfo2'
)
AS
BEGIN
	SET NOCOUNT ON;
	BEGIN TRY
	BEGIN
		DECLARE @iLogLevel int = ISNULL(TRY_CONVERT(INT,[common].[ufnConfigValue](N'LogLevel [ifa].[uspProcessRequestDeux]')),1)
			,@dtTimerDate datetime2(7) = SYSDATETIME()
			,@dtInitial datetime2(7) = SYSDATETIME() --used for complete time in procedure
			,@ncSchemaName nchar(20) = CONVERT(nchar(20),OBJECT_SCHEMA_NAME(@@PROCID))
			,@ncObjectName nchar(50) = CONVERT(nchar(50),OBJECT_NAME(@@PROCID))
			,@ncProcessKey nchar(25) = @pnvProcessKey
			,@bDebug bit = CASE WHEN @@SERVERNAME = N'931519-SQLCLUS6\PRDTRX01' THEN 0 ELSE 1 END --CHECK SERVER FIRST
			,@nvCustomerIdentifier nvarchar(50) = UPPER(RTRIM(LTRIM(@pnvCustomerIdentifier)))
			,@nvSocialSecurityNumber nvarchar(9) = UPPER(RTRIM(LTRIM(@pnvSocialSecurityNumber)))
			,@nvIdNumber nvarchar(50) = UPPER(RTRIM(LTRIM(@pnvIdNumber)))
			,@iOrgId int --used by Id lookup
			,@iOrgDimensionId int = [common].[ufnDimension]('Organization')
			,@iErrorDetailId int
			,@sSchemaName nvarchar(128) = OBJECT_SCHEMA_NAME(@@PROCID)
			,@iIdStateId int = [common].[ufnState](@pnvIdStateAbbv)
			,@iStatusFlag int = [common].[ufnStatusFlag]('Active')
			,@biCustomerId bigint = 0
			,@biAddressId bigint = 0
			,@biCustomerAddressXrefId bigint = 0
			,@iItemCount int = 0
			,@biProcessId bigint = 0
			,@biAccountId bigint
			,@biAccountInfoId bigint
			,@biDeviceInfoId bigint
			,@biMiscInfoId bigint
			,@iProcessMethodology int
			,@iProcessTypeId int = @piProcessTypeId 
			--2022-03-10 ,@iStatUmbrellaOrgTypeId int
			,@iStatUmbrellaOrgId int --2022-03-10
			,@nvStatQueryingField nvarchar(50)
			,@bIncludeMiscFieldInStats bit
			,@biItemId bigint = 0
			,@iIdNumberIdTypeId int --= [common].[ufnIdType](@piOrgId,@pnvIdTypeCode) 2020-09-13
			,@iSocialSecurityNumberIdTypeId int --= [common].[ufnIdType](@piOrgId,'3') 2020-09-13
			,@iClientProvidedIdTypeId int  --= [common].[ufnIdType](@piOrgId,'25') 2020-09-13
			,@iPrimaryIdTypeId int --= [common].[ufnPrimaryIdType](@piOrgId) 2020-09-13
			,@nvIdMac64 nvarchar(256) = TRY_CONVERT(NVARCHAR(256),0x)
			,@nvMsg nvarchar(100)
			,@iTblCnt int
			,@iTypeCnt int
			,@iOrgClientId int = 0
			,@bPNCClient bit = 0 --2023-03-24
			,@nvIdentifier nvarchar(50) = N''
			,@siCnt smallint
			,@siCurrentCnt smallint
			,@biCustomerIdXrefId bigint
			,@iIdTypeId int
			,@xTableSet xml
			,@vbIdEncrypted varbinary(250)
			,@ncSQLOpen nchar(100) = N'OPEN SYMMETRIC KEY VALIDSYMKEY DECRYPTION BY ASYMMETRIC KEY [VALIDASYMKEY]'
			,@ncSQLClose nchar(100) = N'CLOSE SYMMETRIC KEY VALIDSYMKEY';

		IF @iLogLevel > 0
		BEGIN
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Enter' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			SET @dtTimerDate = SYSDATETIME();
		END

		DECLARE @tblDecisionField [ifa].[DecisionFieldType]
			,@tblItem [ifa].[ItemType]
			,@tblMiscStat [ifa].[MiscStatType]
			,@tblItemStat [ifa].[ItemStatType]
			,@tblItemStatRPFlow [ifa].[ItemStatType];
		DECLARE @tblItemStat0 table(
			ItemId bigint
			,StatName nvarchar(128)
			,StatValue nvarchar(100)
			,DR1PO int
			,DR2PO int
		);
		DECLARE @tblIdResult table(
			ResultId smallint identity(1,1)
			,OrgId int
			,Id nvarchar(50) 
			,IdEncrypted varbinary(250)
			,IdTypeId int
			,IdTypeCode nvarchar(25) 
			,IdStateId int
			,IdStateCode nchar(2)
			,PrimaryId int
			,IdMac varbinary(50)
			,IdMac64 binary(64)
			,CustomerId bigint
			,CustomerIdXrefId bigint
		);
		DECLARE @tblIdType table (IdTypeId int
			,IdTypeName nvarchar(50)
			,IdTypeCode nvarchar(25)
		);
		DECLARE @tblRuleBreakData [ifa].[RuleBreakDataType]
			,@tblOL [ifa].[OrgListType]
			,@tblCustomerIdType [ifa].[IdType];

		--2020-09-13 load the acceptable IdTypes
		INSERT INTO @tblIdType(IdTypeId,IdTypeName,IdTypeCode)
		SELECT IdTypeId,IdTypeName,IdTypeCode
		FROM [common].[ufnOrgIdTypeXrefByOrgId](@piOrgId);
		--SET FROM AVAIABLE TO @piOrgId
		SELECT @iIdNumberIdTypeId = IdTypeId FROM @tblIdType WHERE IdTypeCode = @pnvIdTypeCode; --2020-12-29 
		--2020-12-29 SELECT @iIdNumberIdTypeId = IdTypeId FROM @tblIdType WHERE IdTypeName = 'Drivers License or State Id';
		SELECT @iSocialSecurityNumberIdTypeId = IdTypeId FROM @tblIdType WHERE IdTypeName = 'Social Security Number';
		SELECT @iClientProvidedIdTypeId = IdTypeId FROM @tblIdType WHERE IdTypeName = 'Client Provided Identifier';

		INSERT INTO @tblOL (LevelId, RelatedOrgId, OrgId, OrgCode, OrgName, ExternalCode, OrgDescr, OrgTypeId, [Type], StatusFlag)
		SELECT LevelId, ChildId, OrgId, OrgCode, OrgName, ExternalCode, OrgDescr, TypeId, [Type], StatusFlag
		FROM [common].[ufnUpDimensionByOrgIdILTF](@piOrgId,@iOrgDimensionId); 

		SELECT @iOrgClientId = Orgid
			,@bPNCClient = CASE WHEN ExternalCode = 'PNC' THEN 1 ELSE 0 END --2023-03-24
		FROM @tblOL
		WHERE [Type] = 'Client'; 

		--WITH PNC We review the Xref and convert from MDM to CIF, when available, else empty
		IF @bPNCClient = 1 --2023-03-24  Only PNC
			AND TRY_CONVERT(BIGINT,@nvCustomerIdentifier) > 0 --MDM? Reassign MDM to CIF based on what we have
		BEGIN
			--if MDM convert to CIF, run as normal, if no CIF then clean and exit below '@nvCustomerIdentifier' is null
			SELECT @nvCustomerIdentifier = CIF
			FROM [stat].[MDMtoCIFXref]
			WHERE MDM = @nvCustomerIdentifier;
		END

		--Is an OrgClient defined
		IF @iOrgClientId = 0
		BEGIN
			IF @iLogLevel > 0
				INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
				VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Org must have a client parent',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			RAISERROR ('Org must have a client parent', 16, 1);
			RETURN
		END

		--2020-09-13
		SELECT @iProcessMethodology = ProcessMethodologyId
			,@iPrimaryIdTypeId = PrimaryIdTypeId
			,@iStatUmbrellaOrgId = StatUmbrellaOrgId --2022-03-10
			--2022-03-10 ,@iStatUmbrellaOrgTypeId = StatUmbrellaOrgTypeId
			,@nvStatQueryingField = StatQueryingField
			,@bIncludeMiscFieldInStats = IncludeMiscFieldInStats
		FROM [ifa].[ufnProcessMethodologyDeux](@tblOL,@iProcessTypeId);

		IF @iProcessMethodology IS NULL
		BEGIN
			SET @nvMsg = CASE WHEN @iProcessTypeId = 0 THEN N'ProcessIFA Not Availiable For This Location'
							WHEN @iProcessTypeId = 1 THEN N'ProcessIFAMobile Not Availiable For This Location'
							WHEN @iProcessTypeId = 2 THEN N'ProcessCheck Not Availiable For This Location'
							WHEN @iProcessTypeId = 3 THEN N'ProcessCheckMobile Not Availiable For This Location'
						END
			IF @iLogLevel > 0
				INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
				VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,SUBSTRING(@nvMsg,1,50),DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			RAISERROR (@nvMsg, 16, 1);
			RETURN
		END

		--WE need at least one Primary Id to proceed
		IF EXISTS (SELECT 'X' FROM @tblIdType 
					WHERE IdTypeId = @iPrimaryIdTypeId
						AND  @iPrimaryIdTypeId = @iClientProvidedIdTypeId  
						AND ISNULL(@nvCustomerIdentifier,N'') = N'')
		BEGIN
			SET @nvMsg =  N'CustomerIdentifier Not Supplied For This Location';
			IF @iLogLevel > 0
				INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
				VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,SUBSTRING(@nvMsg,1,50),DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			RAISERROR (@nvMsg, 16, 1);
			RETURN
		END
		IF EXISTS (SELECT 'X' FROM @tblIdType 
					WHERE IdTypeId = @iPrimaryIdTypeId
						AND  @iPrimaryIdTypeId = @iSocialSecurityNumberIdTypeId
						AND ISNULL(@nvSocialSecurityNumber,N'') = N'')
		BEGIN
			SET @nvMsg =  N'SocialSecurityNumber Not Supplied For This Location';
			IF @iLogLevel > 0
				INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
				VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,SUBSTRING(@nvMsg,1,50),DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			RAISERROR (@nvMsg, 16, 1);
			RETURN
		END
		IF EXISTS (SELECT 'X' FROM @tblIdType 
					WHERE IdTypeId = @iPrimaryIdTypeId
						AND  @iPrimaryIdTypeId = @iIdNumberIdTypeId
						AND ISNULL(@nvIdNumber,N'') = N'')
		BEGIN
			SET @nvMsg =  N'IdNumber Not Supplied For This Location';
			IF @iLogLevel > 0
				INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
				VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,SUBSTRING(@nvMsg,1,50),DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			RAISERROR (@nvMsg, 16, 1);
			RETURN
		END

		--LOAD the Id(s) into a structure to handle below
		INSERT INTO @tblCustomerIdType ([OrgId], [Id], [IdTypeId], [IdTypeCode], [IdStateId], [IdStateCode], [PrimaryId],[IdMac],[IdMac64])
		SELECT @iOrgClientId,@nvCustomerIdentifier,@iClientProvidedIdTypeId,CONVERT(nvarchar(25),@iClientProvidedIdTypeId),0,N'Un'
			,CASE WHEN @iPrimaryIdTypeId = @iClientProvidedIdTypeId THEN 1 ELSE 0 END		--PrimaryId flag
			,[ifa].[ufnMac](@nvCustomerIdentifier)
			,[ifa].[ufnIdMac64](@iClientProvidedIdTypeId, @iOrgClientId, 0, @nvCustomerIdentifier)
		WHERE ISNULL(@nvCustomerIdentifier,N'') <> N'';

		INSERT INTO @tblCustomerIdType ([OrgId], [Id], [IdTypeId], [IdTypeCode], [IdStateId], [IdStateCode], [PrimaryId],[IdMac],[IdMac64])
		SELECT 0,@nvSocialSecurityNumber,@iSocialSecurityNumberIdTypeId,CONVERT(nvarchar(25),@iSocialSecurityNumberIdTypeId),0,N'Un'
			,CASE WHEN @iPrimaryIdTypeId = @iSocialSecurityNumberIdTypeId THEN 1 ELSE 0 END --PrimaryId flag
			,[ifa].[ufnMac](@nvSocialSecurityNumber)
			,[ifa].[ufnIdMac64](@iSocialSecurityNumberIdTypeId, 0, 0, @nvSocialSecurityNumber)
		WHERE ISNULL(@nvSocialSecurityNumber,N'') <> N'';

		INSERT INTO @tblCustomerIdType ([OrgId], [Id], [IdTypeId], [IdTypeCode], [IdStateId], [IdStateCode], [PrimaryId],[IdMac],[IdMac64])
		SELECT 0,@nvIdNumber,@iIdNumberIdTypeId,@pnvIdTypeCode,@iIdStateId,@pnvIdStateAbbv
			,CASE WHEN @iPrimaryIdTypeId = @iIdNumberIdTypeId THEN 1 ELSE 0 END				--PrimaryId flag
			,[ifa].[ufnMac](@nvIdNumber)
			,[ifa].[ufnIdMac64](@iIdNumberIdTypeId, 0, @iIdStateId, @nvIdNumber)
		WHERE ISNULL(@nvIdNumber,N'') <> N'';

		--SET the IdMac64 (if it is the primary)
		SELECT @nvIdMac64 = TRY_CONVERT(NVARCHAR(256),IdMac64,1)
		FROM @tblCustomerIdType 
		WHERE PrimaryId = 1;
/*2022-03-10 Set @nvIdMac64 for any Primary IdType which is based ON the config value returned by ifa.ufnProcessMethodologyDeux
			AND ((IdTypeId = @iSocialSecurityNumberIdTypeId)
				OR
				(IdTypeId = @iIdNumberIdTypeId)
				);
*/
		--IS there deposit info?
		SELECT @iItemCount = COUNT(*)
		FROM @ptblItemRequest;
		IF @iItemCount = 0
		BEGIN
			IF @iLogLevel > 0
				INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
				VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'At least one deposit is required',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			RAISERROR ('At least one deposit is required', 16, 1);
			RETURN
		END

		IF @iLogLevel > 0
		BEGIN
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Verified Parameters',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			SET @dtTimerDate = SYSDATETIME();
		END

		--RETRIEVE all Ids using the IdMac/IdMac64
		INSERT INTO @tblIdResult(OrgId,Id,IdTypeId,IdTypeCode,IdStateId,IdStateCode,PrimaryId,IdMac,IdMac64,CustomerId,CustomerIdXrefId)
		SELECT OrgId,Id,IdTypeId,IdTypeCode,IdStateId,IdStateCode,PrimaryId,IdMac,IdMac64,CustomerId,CustomerIdXrefId
		FROM [customer].[ufnCustomerIdXref](@tblCustomerIdType);

		IF @iLogLevel > 1
		BEGIN
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Retrieve CIXs',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  		
			SELECT @dtTimerDate = SYSDATETIME();
		END

		--SET CustomerId using the PrimaryId only
		SELECT @biCustomerId = ISNULL(CustomerId,0)
		FROM @tblIdResult
		WHERE PrimaryId = 1;

		---REMOVE id(s) we won't change
		DELETE ir
		FROM @tblIdResult ir
		WHERE CustomerId <> @biCustomerId;

		IF @biCustomerId = 0 --no customer with our OrgId in system
		BEGIN
			EXECUTE [customer].[uspCustomerInsertOut]
				@piOrgId=@piOrgId
				,@pnvFirstName=@pnvFirstName
				,@pnvLastName=@pnvLastName
				,@pdDateOfBirth=@pdDateOfBirth
				,@pnvWorkPhone=@pnvPhoneNumber
				,@pnvCellPhone=NULL
				,@pnvEmail=@pnvEmailAddress
				,@piStatusFlag=@iStatusFlag
				,@pnvUserName = @pnvUserName
				,@pbiCustomerId=@biCustomerId OUTPUT;

			IF @iLogLevel > 1
			BEGIN
				INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
				VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Added Customer',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME()); 
				SET @dtTimerDate = SYSDATETIME();
			END 
		END
		
		--INDICATE our Customer 
		UPDATE @tblIdResult SET CustomerId = @biCustomerId WHERE ISNULL(CustomerId,0) = 0;

		IF ISNULL(@pnvAddressLine1,'') <> ''
			IF NOT EXISTS (SELECT 'X' 
							FROM [customer].[CustomerAddressXref]
							WHERE CustomerId = @biCustomerId)
			BEGIN
				EXECUTE [common].[uspAddressInsertOut]
					@pnvAddress1=@pnvAddressLine1
					,@pnvAddress2=@pnvAddressLine2
					,@pnvCity=@pnvCity
					,@pnvStateAbbv=@pnvStateAbbv
					,@pnvZipCode=@pnvZipCode
					,@pnvCountry=@pnvCountry
					,@pfLatitude=NULL
					,@pfLongitude=NULL
					,@piStatusFlag=@iStatusFlag
					,@pnvUserName = @pnvUserName
					,@pbiAddressId=@biAddressId OUTPUT
				IF @biAddressId > 0
					EXECUTE [customer].[uspCustomerAddressXrefInsertOut]
						@pbiCustomerId=@biCustomerId
						,@pbiAddressId=@biAddressId
						,@piStatusFlag=@iStatusFlag
						,@pnvUserName = @pnvUserName
						,@piCustomerAddressXrefId=@biCustomerAddressXrefId OUTPUT;

				IF @iLogLevel > 1
				BEGIN
					INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
					VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Added Addresses',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME()); 
					SET @dtTimerDate = SYSDATETIME(); 
				END
			END

		IF EXISTS (SELECT 'X' FROM @tblIdResult WHERE ISNULL(CustomerIdXrefId,0) = 0)
		BEGIN
			--HOW Many to process
			SELECT @siCnt = Count(*) FROM @tblIdResult;
			SET @siCurrentCnt = 1;
			WHILE @siCurrentCnt <= @siCnt --until we process all that need it
			BEGIN				
				--CLEAR variables
				SET @nvIdentifier = NULL;
				SET @iIdTypeId = NULL;
				SET @iIdStateId = NULL;
				SET @iOrgId = NULL;
				SELECT @nvIdentifier = Id
					,@iIdTypeId = IdTypeId
					,@iIdStateId = IdStateId
					,@iOrgId = OrgId
				FROM @tblIdResult
				WHERE ResultId = @siCurrentCnt 
					AND ISNULL(CustomerIdXrefId,0) = 0;
				IF ISNULL(@nvIdentifier,N'') <> N'' 
				BEGIN
					EXECUTE(@ncSQLOpen);--Open Symmetric Key
					SET @vbIdEncrypted=ENCRYPTBYKEY(KEY_GUID('VALIDSYMKEY'),@nvIdentifier);
					EXECUTE(@ncSQLClose);--Close Symmetric Key
					EXECUTE [customer].[uspCustomerIdXrefInsertOut]
						@pbiCustomerId=@biCustomerId 
						,@piIdTypeId=@iIdTypeId
						,@piStateId=@iIdStateId
						,@pnvIdDecrypted=@nvIdentifier
						,@pvbIdEncrypted=@vbIdEncrypted
						,@piOrgId=@iOrgId
						,@piStatusFlag=@iStatusFlag
						,@pnvUserName = @pnvUserName
						,@pbiCustomerIdXrefId=@biCustomerIdXrefId OUTPUT;	
					--UPDATE the reference table	
					UPDATE @tblIdResult SET CustomerIdXrefId = @biCustomerIdXrefId WHERE IdTypeId = @iIdTypeId;
					--ADD Timing?
					IF @iLogLevel > 1
					BEGIN
						INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
						VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Added IdTypeId '+CONVERT(nchar(2),@iIdTypeId),DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
						SET @dtTimerDate = SYSDATETIME();
					END 
				END
				SET @siCurrentCnt += 1;
				IF @siCurrentCnt > @siCnt
					BREAK
			END --While
		END --IF Exists

		--CHECK to see if they have sent us the bankaccount info
		IF (ISNULL(@pnvBankAccountType,'') <> '' 
				OR ISNULL(@pncBankRoutingNumber,'') <> '' 
				OR ISNULL(@pnvBankAccountNumber,'') <> '' )
		BEGIN
			--THEN all values must be present
			IF (ISNULL(@pnvBankAccountType,'') = '' 
				OR ISNULL(@pncBankRoutingNumber,'') = '' 
				OR ISNULL(@pnvBankAccountNumber,'') = '' )
			BEGIN
				IF @iLogLevel > 0
					INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
					VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'InComplete BankAccount information',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
				RAISERROR ('InComplete BankAccount information', 16, 1);
				RETURN
			END
			EXECUTE [customer].[uspAccountInsertOut]
				@pbiCustomerId=@biCustomerId
				,@pnvBankAccountType=@pnvBankAccountType
				,@pncBankRoutingNumber=@pncBankRoutingNumber
				,@pnvBankAccountNumber=@pnvBankAccountNumber
				,@piStatusFlag=@iStatusFlag
				,@pnvUserName = @pnvUserName
				,@pbiAccountId=@biAccountId OUTPUT;

			IF @iLogLevel > 1
			BEGIN
				INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
				VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Added Account',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
				SET @dtTimerDate = SYSDATETIME();
			END 
		END
		EXECUTE [ifa].[uspProcessInsertOut]
			@piProcessTypeId=@piProcessTypeId
			,@piOrgId=@piOrgId
			,@pbiCustomerId=@biCustomerId
			,@pnvProcessKey=@pnvProcessKey
			,@pnvClientRequestId=@pnvClientRequestId
			,@pnvClientRequestId2=@pnvClientRequestId2
			,@pbiAccountId=@biAccountId
			,@piItemCount=@iItemCount
			,@piStatusFlag=@iStatusFlag
			,@pnvUserName = @pnvUserName
			,@pbiProcessId=@biProcessId OUTPUT;
		IF @biProcessId = 0 --PROBLEM inserting Process...
		BEGIN
			IF @iLogLevel > 0
				INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
				VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'uspProcessInsert Error',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			RAISERROR ('uspProcessInsertOut, error %I64d', 16, 1,@biProcessId);
			RETURN
		END
		ELSE
		BEGIN --We created a Process so load @tblDecisionField
			
			--2022-03-10 Add PrimaryIdTypeId into the insert for @tblDecisionField and replaced the CASE statement to establish OrgParentId with @iStatUmbrellaOrgId
			--INSERT INTO @tblDecisionField(CustomerId,CustomerIdentifier,Debug,DLNumber,DLStateAbbr,IdMac64,InternalBankAccountNumber,ItemCount
			INSERT INTO @tblDecisionField(CustomerId,CustomerIdentifier,PrimaryIdTypeId,Debug,DLNumber,DLStateAbbr,IdMac64,InternalBankAccountNumber,ItemCount --2022-03-10
				,MaxItemsExceeded,OrgChannelName,OrgClientExternalCode,OrgClientId,OrgCode,OrgDistance,OrgExternalCode,OrgId,OrgLatitude,OrgLongitude
				,OrgName,OrgParentId,OrgState,OrgZipCode,ProcessDateActivated,ProcessId,ProcessKey,ProcessMethodology,StatusFlag,UserName)
			SELECT @biCustomerId
				,CASE WHEN @iPrimaryIdTypeId = @iClientProvidedIdTypeId THEN @nvCustomerIdentifier 
						WHEN @iPrimaryIdTypeId = @iSocialSecurityNumberIdTypeId THEN @nvSocialSecurityNumber 
						WHEN @iPrimaryIdTypeId = @iIdNumberIdTypeId THEN @nvIdNumber --2022-03-10 Just in case
				END --Set based ON PrimaryIdentifier
				,@iPrimaryIdTypeId --2022-03-10
				,CASE WHEN @bDebug = 0 THEN 0 ELSE [common].[ufnDebug](o.OrgId) END AS Debug--IF correct server and Debug is found for this OrgId
				,CASE WHEN @nvIdNumber IS NOT NULL AND @pnvIdTypeCode = N'2' THEN @nvIdNumber ELSE NULL END AS DLNumber
				,CASE WHEN @nvIdNumber IS NOT NULL AND @pnvIdTypeCode = N'2' AND @pnvIdStateAbbv IS NOT NULL THEN @pnvIdStateAbbv ELSE NULL END AS DLStateAbbr
				,@nvIdMac64 as IdMac64
				,[common].[ufnCleanAccountNumber](@pnvBankAccountNumber) AS InternalBankAccountNumber
				,@iItemCount as ItemCount
				,[ifa].[ufnMaxItemsExceeded](co.OrgId,@iItemCount) AS MaxItemsExceeded --2020-12-06
				,ISNULL([common].[ufnOrgChannelName](o.OrgId),'') as ChannelName
				,co.ExternalCode AS OrgClientExternalCode
				,co.OrgId AS OrgClientId
				,o.OrgCode --In some parameter tables this is used for the OrgName
				,-1 as OrgDistance
				,o.ExternalCode as OrgExternalCode
				,o.OrgId
				,ISNULL(a.Latitude,-1) AS OrgLatitude
				,ISNULL(a.Longitude,-1) AS OrgLongitude
				,o.OrgName
				--2022-03-10 ,CASE WHEN @iProcessMethodology <> 0 THEN co.OrgId ELSE 99999 END AS OrgParentId 
				,@iStatUmbrellaOrgId AS OrgParentId--2022-03-10
				,s.Code AS OrgState
				,a.ZipCode AS OrgZipCode
				,SYSDATETIME() AS ProcessDateActivated
				,@biProcessId
				,@pnvProcessKey
				,@iProcessMethodology
				,@iStatusFlag
				,@pnvUserName
			FROM @tblOL o
			LEFT OUTER JOIN [organization].[OrgAddressXref] oax ON o.OrgId = oax.OrgId
			LEFT OUTER JOIN [common].[Address] a ON oax.AddressId = a.AddressId
			LEFT OUTER JOIN [common].[State] s ON a.StateId = s.StateId 
			CROSS APPLY @tblOL co
			WHERE o.OrgId = @piOrgId
				AND co.[Type] = 'Client';
			
			--2020-12-17
			IF  ISNULL(@nvCustomerIdentifier,N'') = N'ThirdParty00000000'
				UPDATE @tblDecisionField set MaxItemsExceeded = 1;
		END
		--ARE all of the misc types passed in defined?
		--BOTH of these tables are consodered MISC types
		SELECT @iTblCnt = count(*) 
		FROM @ptblAccountInfo;
		SELECT @iTypeCnt = count(*) 
		FROM @ptblAccountInfo ai 
		INNER JOIN [common].[MiscType] mt ON ai.TextType = mt.Code;
		IF @iTblCnt = @iTypeCnt
			AND @iTblCnt <> 0
			EXECUTE [ifa].[uspAccountInfoInsertOut]
				@pbiProcessId=@biProcessId
				,@ptblAccountInfo=@ptblAccountInfo
				,@piStatusFlag=@iStatusFlag
				,@pnvUserName = @pnvUserName
				,@pbiAccountInfoId=@biAccountInfoId OUTPUT;
		ELSE IF @iTblCnt <> 0 --SOME missing MiscTypes related to AccountInfo...
		BEGIN
			IF @iLogLevel > 0
				INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
				VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Account/Misc info types not present',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			RAISERROR ('Invalid TextType', 16, 1);
			RETURN
		END								
		SELECT @iTblCnt = count(*) 
		FROM @ptblMiscInfo;
	
		IF @bIncludeMiscFieldInStats = 0	--2020-09-13
			SELECT @iTypeCnt = count(*) 
			FROM @ptblMiscInfo mi 
			INNER JOIN [common].[MiscType] mt ON mi.TextType = mt.Code;
		ELSE --@bIncludeMiscFieldInStats = 1
		BEGIN
			INSERT INTO @tblMiscStat(StatName,StatValue)
			SELECT mi.TextType, mi.[Text]
			FROM @ptblMiscInfo mi 
			INNER JOIN [common].[MiscType] mt ON mi.TextType = mt.Code;
			SELECT @iTypeCnt = @@RowCount;
		END
		IF @iTblCnt = @iTypeCnt
			AND @iTblCnt <> 0
			EXECUTE [ifa].[uspMiscInfoInsertOut]
				@pbiProcessId=@biProcessId
				,@ptblMiscInfo=@ptblMiscInfo
				,@piStatusFlag=@iStatusFlag
				,@pnvUserName = @pnvUserName
				,@pbiMiscInfoId=@biMiscInfoId OUTPUT;
		ELSE IF @iTblCnt <> 0 --SOME missing MiscTypes...
		BEGIN
			IF @iLogLevel > 0
				INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
				VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Misc info types not present',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			RAISERROR ('Invalid TextType', 16, 1);
			RETURN
		END
		--Device Info
		SELECT @iTblCnt = count(*) 
		FROM @ptblDeviceInfo;
		IF @iTblCnt > 0
			EXECUTE [ifa].[uspDeviceInfoInsertOut]
				@pbiProcessId=@biProcessId
				,@ptblDeviceInfo=@ptblDeviceInfo
				,@piStatusFlag=@iStatusFlag 
				,@pnvUserName = @pnvUserName
				,@pbiDeviceInfoId=@biDeviceInfoId OUTPUT;
		--2022-04-04 WE PIGGYBACK ON @tblMiscStats to get the data to uspItemInsertOut
		--The prefix D2C isolates this from what @tblMiscStats is being used for by others
		IF @iProcessMethodology = 4 --Direct to Cash (D2C)
		BEGIN
			INSERT INTO @tblMiscStat(StatName,StatValue)
			VALUES(N'D2CFlag',N'1'),
				(N'D2CCustomerFirstName',@pnvFirstName),
				(N'D2CCustomerLastName',@pnvLastName),
				(N'D2CStateAbbv',@pnvStateAbbv),
				(N'D2CZipCode',@pnvZipCode);
		END
		--NOW Risk Process Item(s) One at a time
		EXECUTE [ifa].[uspItemMultiInsertOut]
			@ptblDecisionField = @tblDecisionField
			,@ptblItemRequest = @ptblItemRequest
			,@ptblMiscStat = @tblMiscStat
			,@pbiItemId = @biItemId OUTPUT
			,@pxTableSet = @xTableSet OUTPUT;--Contains Stats/Item,Items,RuleBreakData,Common
		IF @biItemId < 0 --Item(s) didn't get inserted...
		BEGIN
			IF @iLogLevel > 0
				INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
				VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'uspItemInsertOut Error',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			RAISERROR ('uspItemInsertOut, error %I64d', 16, 1, @biItemId);
			RETURN
		END

		--DECOUPLE XML Data generated within uspItemInsertOut and uspProcessRiskControl
		--STATS
		INSERT INTO @tblItemStat0(ItemId,StatName,StatValue,DR1PO,DR2PO)
		SELECT r.a.value('ItemId[1]','bigint') AS ItemId
			,r.a.value('StatName[1]','nvarchar(128)') AS StatName
			,NULLIF(r.a.value('StatValue[1]','nvarchar(100)'),N'NULL') AS StatValue
			,null
			,null
		FROM @xTableSet.nodes('Stat/.') r(a);

		--ITEMS
		INSERT INTO @tblItem(ItemId,ProcessId,ClientItemId,ItemKey,RuleBreak,RuleBreakResponse,CheckAmount,UserName)
		SELECT r.a.value('ItemId[1]','bigint') AS ItemId
			,r.a.value('ProcessId[1]','bigint') AS ProcessId
			,r.a.value('ClientItemId[1]','nvarchar(50)') AS ClientItemId
			,r.a.value('ItemKey[1]','nvarchar(25)') AS ItemKey
			,r.a.value('RuleBreak[1]','nvarchar(25)') AS RuleBreak
			,r.a.value('RuleBreakResponse[1]','nvarchar(255)') AS RuleBreakResponse
			,r.a.value('CheckAmount[1]','money') AS CheckAmount
			,r.a.value('UserName[1]','nvarchar(100)') AS UserName
		FROM @xTableSet.nodes('Item/.') r(a)

		--RULEBREAKDATA
		INSERT INTO @tblRuleBreakData(ItemId,Code,[Message])
		SELECT r.a.value('ItemId[1]','bigint') AS ItemId
			,r.a.value('Code[1]','nvarchar(25)') AS Code
			,r.a.value('Message[1]','nvarchar(255)') AS [Message]
		FROM @xTableSet.nodes('RuleBreakData/.') r(a);

		IF EXISTS (SELECT 'X' FROM @tblRuleBreakData)
			INSERT INTO @tblItemStat0(ItemId,StatName,StatValue)
			SELECT ItemId,'RuleBreakCode',Code
			FROM @tblRuleBreakData;

		--COMMON --Add these to the Stat table for each item since they are the same for all items
		INSERT INTO @tblItemStat0(ItemId,StatName,StatValue,DR1PO,DR2PO)
		SELECT i.ItemId
			,r.a.value('CommonName[1]','nvarchar(128)') AS CommonName
			,NULLIF(r.a.value('CommonValue[1]','nvarchar(100)'),N'NULL') AS CommonValue
			,null
			,null
		FROM @xTableSet.nodes('Common/.') r(a)
		CROSS APPLY @tblItem i;

		SELECT ClientItemId, ItemKey, RuleBreak, CheckAmount, ItemId
		FROM @tblItem as ItemResponse;

		SELECT i.ItemKey
			,'0' AS GoodCode
			,'Green|Transaction Approved' AS GoodMsg
			,ISNULL(rbd.[Code],'10') AS BadCode
			,ISNULL(rbd.[Message],'General.  Item does not meet defined accelerated availability.') AS BadMsg
			,i.ItemId
		FROM @tblItem i 
		LEFT JOIN @tblRuleBreakData rbd ON i.ItemId = rbd.ItemId
		WHERE i.ProcessId = @biProcessId;

		--DEDUPE Stats
		WITH cte_dedupe(RowId,ItemId, StatName, StatValue)
		AS (SELECT Row_Number() OVER (PARTITION By ItemId, StatName
									ORDER BY ItemId, StatName) as RowId
				,ItemId, StatName, StatValue
			FROM @tblItemStat0
		)
		INSERT INTO @tblItemStat(ItemId, StatName, StatValue)
		SELECT ItemId, StatName, StatValue
		FROM cte_dedupe 
		WHERE RowId = 1;

		--LOAD RiskProcessingFlow (Plugin Flow) structure
		INSERT INTO @tblItemStatRPFlow(ItemId,StatName,StatValue)
		SELECT ItemId, StatName, StatValue
		FROM [riskprocessingflow].[ufnRiskProcessingFlow](@tblItem,@tblItemStat);
		--ADD plugins that were not bypassed
		INSERT INTO @tblItemStatRPFlow(ItemId,StatName,StatValue)
		SELECT ItemId, N'_VaeBriskBypass',N'0'
		FROM @tblItem i0
		WHERE i0.ItemId is NOT NULL 
			AND NOT EXISTS (SELECT 'X' FROM @tblItemStatRPFlow WHERE i0.ItemId = ItemId and StatName = N'_VaeBriskBypass')
		UNION
		SELECT ItemId, N'_VaeRtlaBypass',N'0'
		FROM @tblItem i1
		WHERE i1.ItemId is NOT NULL 
			AND NOT EXISTS (SELECT 'X' FROM @tblItemStatRPFlow WHERE i1.ItemId = ItemId and StatName = N'_VaeRtlaBypass')
		UNION
		SELECT ItemId, N'_VaeFraudBypass',N'0'
		FROM @tblItem i2
		WHERE i2.ItemId is NOT NULL 
			AND NOT EXISTS (SELECT 'X' FROM @tblItemStatRPFlow WHERE i2.ItemId = ItemId and StatName = N'_VaeFraudBypass');

		--Migrate RiskProcessingFlow (Plugin Flow) to Stat
		UPDATE i
		SET StatValue=rpf.StatValue
		FROM @tblItemStat i
		INNER JOIN @tblItemStatRPFlow rpf ON i.ItemId = rpf.ItemId	
										AND i.StatName = rpf.StatName
		WHERE EXISTS (SELECT 'X' FROM @tblItemStat WHERE rpf.ItemId = ItemId
														AND rpf.StatName = StatName);
		INSERT INTO @tblItemStat(ItemId,StatName,StatValue)
		SELECT rpf.ItemId, rpf.StatName, rpf.StatValue
		FROM @tblItemStatRPFlow rpf
		WHERE NOT EXISTS (SELECT 'X' FROM @tblItemStat WHERE rpf.ItemId = ItemId
														AND rpf.StatName = StatName);
		--Log OltpRecordCount
		SET @dtTimerDate = SYSDATETIME();
		IF @iLogLevel > 0
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			SELECT @ncProcessKey, @ncSchemaName, @ncObjectName
				,StatName +'='+TRY_CONVERT(NVARCHAR(100),SUM(TRY_CONVERT(INT,StatValue)))
				,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME()
			FROM @tblItemStat
			WHERE StatName in ('FinancialOltpRecordCount','RetailOltpRecordCount')
			GROUP BY StatName;

		--RETURN stats list 
		SELECT ItemId, StatName, StatValue
		FROM @tblItemStat AS tblStat
		ORDER BY ItemId, StatName;

		--LAST Message uses @dtInitial
		IF @iLogLevel > 0
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Exit' ,DATEDIFF(microsecond,@dtInitial,SYSDATETIME()),SYSDATETIME());
	END 
	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		IF @iLogLevel > 0
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Exit-ErrorDetailId ='+CONVERT(NCHAR(10),@iErrorDetailId),DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
		THROW
	END CATCH
END
