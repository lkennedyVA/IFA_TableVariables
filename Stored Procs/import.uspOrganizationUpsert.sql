USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [import].[uspOrganizationUpsert]
	Created By: Chris Sharp
	Description: This procedure will process all of the unprocessed records
		This will determine if the following exist(s) and will add or link the data
		Organization - Client, Location, SubLocation
		Rule
		RiskControl (Channel Specific)
		Geo
		Channel
		GeoZipLarge
		GeoZipSmall
		GeoZip4
		VaeBrisk 
		VaeRtla

		** DONT TRUNCATE import.Organization ONCE THIS IS LIVE
		** RowId ties the tables together

		--KEEP FOR USE BELOW
		--full set if all 8 variables are floating
		/*REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(@nvMetaDataQuery
			,'{1}',ISNULL(b.[1],'')),'{2}',ISNULL(b.[2],'')),'{3}',ISNULL(b.[3],'')),'{4}',ISNULL(b.[4],''))
			,'{5}',ISNULL(b.[5],'')),'{6}',ISNULL(b.[6],'')),'{7}',ISNULL(b.[7],'')),'{8}',ISNULL(b.[8],''))*/

	Table(s): [import].[OrgCondensed]
		,[import].[Organization] 
		,[organization].[OrgType] 

	Function(s): [orgconfig].[ufnMetadataByOrgTypeILTF]
		,[orgconfig].[ufnParameterSetILTFBSOP]

	Procedure(s): [import].[uspLoadOrgCondensed]
		,[import].[uspFDClientIntoImportOrganization]
		,[import].[uspValidateBusinessRulesInsertOut]
		,[import].[uspOrgUpsertOut]
		,[import].[uspOrgXrefResertOut] 
		,[import].[uspAddressUpsertOut]
		,[import].[uspOrgAddressXrefUpsertOut]
		,[error].[uspLogErrorDetailInsertOut]
		,[condensed].[uspLoadRCCondensedConsolidated]
			
	UDT Type(s): [import].[OrgTemplateType]
		,[ifa].[OrgListType];

	History:
		2020-09-02 - CBS - Created
		2021-02-23 - CBS - Added call to import.uspOrganizationValidateInsertOut, it @iResultId
			is less than 0, we have a problem... Exit the proc
		2021-03-02 - CBS - Added @pnvRecipients as a parameter passed from import.uspOrganizationUpsert
		2021-07-07 - CBS - Added [import].[uspOrgParentOrgChildUpdate] 
		2021-08-24 - CBS - Updated @nvProfileName from 'SQLServerMailProfile' which we used on Dev
			to 'SSDB-PRDTRX01'
		2021-10-21- CBS - Enhanced message output
		2022-04-26 - CBS - VALID:-209- Added the call to [condensed].[uspLoadRCCondensedConsolidated] 
			upon a successful run
*****************************************************************************************/
ALTER PROCEDURE [import].[uspOrganizationUpsert](
	 @pnvSchemaSet NVARCHAR(50)
	,@pnvRecipients NVARCHAR(512) 
	,@pnvUserName NVARCHAR(100) 
	,@piResultId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @sSchemaName nvarchar(128) = OBJECT_SCHEMA_NAME(@@PROCID)
		,@ncObjectName nchar(50) = CONVERT(nchar(50),OBJECT_NAME(@@PROCID))
		,@iErrorDetailId int = 0
		,@iCurrentTransactionLevel int
		,@dt datetime2(7) = SYSDATETIME();
	---Possibly convert to user defined table type after columns are solid
	DROP TABLE IF EXISTS #tblMetaData;
	CREATE TABLE #tblMetaData(
		 Ident int identity(1,1)
		,SchemaSet nvarchar(25)
		,MetaDataCode nvarchar(25)
		,MetaDataParentId int
		,MetaDataId int 
		,MetaDataXrefId int 
		,MetaDataParentContext nvarchar(25) 
		,MetaDataContext nvarchar(25) 
		,MetaDataAction nvarchar(25) 
		,MetaDataActionStep int
		,MetaDataQuery nvarchar(4000) 
		,MetaDataQueryName nvarchar(50)
	);
	DECLARE @tblOrgTemplate [import].[OrgTemplateType]
		,@tblOrgReference [ifa].[OrgListType];
	DECLARE @nvSchemaSet nvarchar(50) = @pnvSchemaSet
		--Template variables
		,@biTemplateRowId bigint
		,@nvTemplateOrgParentName nvarchar(50) 
		,@nvTemplateOrgParentType nvarchar(50) 
		,@nvTemplateOrgName nvarchar(50) 
		,@nvTemplateOrgType nvarchar(50) 
		,@nvTemplateOrgCode nvarchar(25) 
		,@nvTemplateOrgDesc nvarchar(255) 
		,@nvTemplateOrgExternal nvarchar(50) 
		,@iTemplateOrgId int 
		,@nvTemplateChannelName nvarchar(50) 
		,@iTemplateRiskLevel int
		,@nvTemplateAddress1 nvarchar(150) 
		,@nvTemplateAddress2 nvarchar(150) 
		,@nvTemplateCity nvarchar(100) 
		,@nvTemplateState nvarchar(25) 
		,@ncTemplateZip nchar(5) 
		,@fTemplateLatitude float 
		,@fTemplateLongitude float  
		,@iTemplateRowCount int = 0 --Number of records within the Template that we need to step through
		,@iTemplateIdent int = 0	--The Id within the Template that we're currently processing 
		--SchemaSet Variables
		,@nvMetaDataCode nvarchar(25)
		,@iMetaDataParentId int
		,@iMetaDataId int
		,@iMetaDataXrefId int
		,@nvMetaDataParentContext nvarchar(25)
		,@nvMetaDataContext nvarchar(25)
		,@nvMetaDataAction nvarchar(25)
		,@nvMetaDataActionStep int
		,@nvMetaDataQuery nvarchar(4000)
		,@nvMetaDataQueryName nvarchar(50)
		,@iMetaDataRowCount int = 0 --Number of records within the metadata that we need to step through
		,@iMetaDataIdent int = 0		--The Id within the metadata that we're currently processing 
		--Standard Variables
		,@nvSrcTable nvarchar(128) = N'[import].[Organization]'
		,@iStatusFlag int = 1
		,@nvUserName nvarchar(100) = @pnvUserName
		,@nvBody nvarchar(max) = ''
		,@nvProfileName sysname = 'SSDB-PRDTRX01'   --DEV Profile is 'SQLServerMailProfile'   
		,@nvFrom nvarchar(4000) = 'DBSupport@ValidAdvantage.com'
		,@nvSubject nvarchar(4000) = 'OrganizationImport Status'
		,@nvRecipients nvarchar(512) = @pnvRecipients
		,@iOrgId int
		,@iOrgParentId int = -1
		,@iDimensionId int = -1
		,@nvDimName nvarchar(50)
		,@iOrgXrefId int 
		,@biAddressId bigint
		,@iOrgAddressXrefId int
		,@iVaeModelId int = -1
		,@iOrgVaeModelXrefId int 
		,@nvMsg nvarchar(256)
		,@nvCountry nvarchar(50) = 'USA'
		,@bAddressRequired bit = 1
		--Validation Variables
		,@iResultId int = 0
		,@biMaxLogId bigint;

	--Refresh Table Based on current Orgs
	EXECUTE [import].[uspLoadOrgCondensed];

	--Load Current Orgs based on @nvSchemaSet
	INSERT INTO	@tblOrgReference(LevelId,OrgId,OrgCode,OrgName,ExternalCode,OrgTypeId)
	SELECT LevelId,OrgId,OrgCode,OrgName,ExternalCode,OrgTypeId
	FROM [import].[OrgCondensed]
	WHERE @nvSchemaSet <> 'FD'
		AND @nvSchemaSet <> 'FSI'
		AND OrgClientCode = CASE WHEN @nvSchemaSet = 'PNC' THEN N'PNC' 
							WHEN @nvSchemaSet = 'TDB' THEN 'TDB'
							WHEN @nvSchemaSet = 'FTB' THEN 'FTB'
							WHEN @nvSchemaSet = 'HEB' THEN 'HEB' 
							WHEN @nvSchemaSet = 'MTB' THEN 'MTB'
						END;

	INSERT INTO	@tblOrgReference(LevelId,OrgId,OrgCode,OrgName,ExternalCode,OrgTypeId)
	SELECT LevelId,OrgId,OrgCode,OrgName,ExternalCode,OrgTypeId
	FROM [import].[OrgCondensed]
	WHERE @nvSchemaSet = 'FD'
		AND OrgPartnerCode = 'FD';

	INSERT INTO	@tblOrgReference(LevelId,OrgId,OrgCode,OrgName,ExternalCode,OrgTypeId)
	SELECT LevelId,OrgId,OrgCode,OrgName,ExternalCode,OrgTypeId
	FROM [import].[OrgCondensed]
	WHERE @nvSchemaSet = 'FSI'
		AND OrgPartnerCode = 'FiservI';

	--FD Create/reference Casino Clients from the Location records
	IF @nvSchemaSet = N'FD'
		EXECUTE [import].[uspFDClientIntoImportOrganization] @pnvSchemaSet = @nvSchemaSet, @pdtDateActivated=@dt;

	--Read up OrgTemplate information for records that haven't been processed yet
	INSERT INTO @tblOrgTemplate (
		 RowId
		,OrgParentName
		,OrgParentType
		,OrgName
		,OrgType
		,OrgCode
		,OrgDesc
		,OrgExternal
		,OrgId
		,ChannelName
		,RiskLevel
		,Address1
		,Address2
		,City
		,[State]
		,Zip
		,Latitude
		,Longitude
	)
	SELECT RowId 
		,OrgParentName
		,OrgParentType
		,OrgName
		,OrgType
		,OrgCode
		,OrgDesc
		,OrgExternal
		,OrgId
		,ChannelName
		,RiskLevel
		,Address1
		,Address2
		,City
		,[State]
		,Zip
		,Latitude
		,Longitude 
	FROM [import].[Organization] o
	INNER JOIN [organization].[OrgType] ot ON o.OrgParentType = ot.[Name]
	WHERE o.Processed = 0
		AND o.DateActivated < SYSDATETIME()
		AND ot.StatusFlag > 0
		AND ot.DateActivated < SYSDATETIME()
		AND o.SchemaSet = @nvSchemaSet	
	ORDER BY CONVERT(int, ot.Code) ASC, o.OrgName; --Ensure to Load in order of dependency

	SET @iTemplateRowCount += @@ROWCOUNT;
	SET @iTemplateIdent = 1;

	--Checks for errors in the data loaded in import.Organization
	--uspOrganizationValidateInsertOut manages mailing out a notification if an error condition is found.  If @iResultId = -1, we have a problem, EXIT
	EXECUTE [import].[uspValidateBusinessRulesInsertOut] --2021-02-23
		 @ptblOrgTemplate = @tblOrgTemplate
		,@pnvSchemaSet = @nvSchemaSet
		,@pnvUserName = @nvUserName
		,@pnvRecipients = @nvRecipients
		,@piResultId = @iResultId OUTPUT; --2021-03-09	

	SET @iResultId = ISNULL(@iResultId, 0); --2021-02-23
		
	IF @iResultId < 0 --2021-02-23
	BEGIN 
		SET @piResultId = @iResultId;
		RETURN;
	END

	SELECT @biMaxLogId = MAX(LogId)
	FROM [import].[Log];

	IF @iTemplateRowCount < @iTemplateIdent 
		RETURN;

	--Prime the Outer While..
	SELECT @biTemplateRowId = RowId
		,@nvTemplateOrgParentName = OrgParentName
		,@nvTemplateOrgParentType = OrgParentType
		,@nvTemplateOrgName = OrgName
		,@nvTemplateOrgType = OrgType
		,@nvTemplateOrgCode = OrgCode
		,@nvTemplateOrgDesc = OrgDesc
		,@nvTemplateOrgExternal = OrgExternal
		,@iTemplateOrgId = OrgId
		,@nvTemplateChannelName = ChannelName
		,@iTemplateRiskLevel = RiskLevel
		,@nvTemplateAddress1 = Address1
		,@nvTemplateAddress2 = Address2
		,@nvTemplateCity = City
		,@nvTemplateState = [State]
		,@ncTemplateZip = Zip
		,@fTemplateLatitude = Latitude
		,@fTemplateLongitude = Longitude
	FROM @tblOrgTemplate
	WHERE Ident = @iTemplateIdent;
	
	--Grab the first Template Record and walk through it
	WHILE 1 = 1 --We use a BREAK to exit, when we have completed all Template rows
	BEGIN
		BEGIN TRY
		--SELECT N'@tblOrgTemplate', * FROM @tblOrgTemplate WHERE Ident = @iTemplateIdent;

		--Insert SchemaSet Meta Data for the actual template row
		INSERT INTO #tblMetaData( 
			 SchemaSet 
			,MetaDataCode
			,MetaDataParentId
			,MetaDataId
			,MetaDataXrefId
			,MetaDataParentContext
			,MetaDataContext
			,MetaDataAction
			,MetaDataActionStep
			,MetaDataQuery
			,MetaDataQueryName
		)
		SELECT SchemaSet 
			,MetaDataCode
			,MetaDataParentId
			,MetaDataId
			,MetaDataXrefId
			,MetaDataParentContext
			,MetaDataContext
			,MetaDataAction
			,MetaDataActionStep
			,MetaDataQuery
			,MetaDataQueryName
		FROM [orgconfig].[ufnMetadataByOrgTypeILTF](@nvSchemaSet,@nvTemplateOrgType)
		ORDER BY MetaDataParentId, MetaDataId;

		SELECT @iMetaDataRowCount = @@ROWCOUNT
			,@iMetaDataIdent = 1					--Set MetaDataId to start at the beginning
			,@nvMetaDataParentContext = NULL
			,@iMetaDataXrefId = NULL
			,@nvMetaDataContext = NULL
			,@nvMetaDataAction = NULL
			,@nvMetaDataQuery = NULL
			,@nvMetaDataQueryName = NULL;

		IF @iMetaDataRowCount < @iMetaDataIdent		--Nothing to process
			RETURN;

		--SELECT N'#tblMetaData', * from #tblMetaData

		--Prime the Inner While..
		SELECT @nvMetaDataCode = MetaDataCode
			,@iMetaDataParentId = MetaDataParentId
			,@iMetaDataId = MetaDataId
			,@iMetaDataXrefId = MetaDataXrefId
			,@nvMetaDataParentContext = MetaDataParentContext
			,@nvMetaDataContext = MetaDataContext
			,@nvMetaDataAction = MetaDataAction
			,@nvMetaDataActionStep = MetaDataActionStep
			,@nvMetaDataQuery = MetaDataQuery
			,@nvMetaDataQueryName = MetaDataQueryName
		FROM #tblMetaData
		WHERE Ident = @iMetaDataIdent;

		--Next start applying the Schema metadata to our template row
		WHILE 2 = 2 --We use a BREAK to exit, when we have completed all MetaData rows
		BEGIN
			BEGIN TRY

			--SELECT N'#tblMetaData', * from #tblMetaData where ident = @iMetaDataIdent;
			
			IF @nvMetaDataAction = 'EstablishOrg' --No Queries defined for this Action
			BEGIN
				SET @iOrgId = NULL;

				EXECUTE [import].[uspOrgUpsertOut]
					@ptblOrgReference=@tblOrgReference
					,@pbiSrcRowId = @biTemplateRowId
					,@pnvSrcTable = @nvSrcTable
					,@pnvOrgTypeName = @nvTemplateOrgType
					,@pnvCode = @nvTemplateOrgCode
					,@pnvName = @nvTemplateOrgName
					,@pnvDescr = @nvTemplateOrgDesc
					,@pnvExternalCode = @nvTemplateOrgExternal
					,@piStatusFlag = @iStatusFlag
					,@pnvUserName = @nvUserName
					,@piOrgId = @iOrgId OUTPUT;

				--Insert new guys, so we aboid dups and other issues....
				IF NOT EXISTS (SELECT'X' FROM @tblOrgReference WHERE OrgId = @iOrgId)
					INSERT INTO	@tblOrgReference(LevelId,OrgId,OrgCode,OrgName,ExternalCode,OrgTypeId)
					SELECT ot.Code,@iOrgId,@nvTemplateOrgCode,@nvTemplateOrgName,@nvTemplateOrgExternal,ot.OrgTypeId
					FROM [organization].[OrgType] ot
					WHERE ot.[Name] = @nvTemplateOrgType;
			END
			ELSE IF @nvMetaDataAction = 'LinkToDimension'
			BEGIN
				SET @iOrgXrefId = NULL;
				SET @iOrgParentId = NULL;
				SET @iDimensionId = NULL;

				--SQL Query Centric?
				IF @nvMetaDataQuery IS NOT NULL  
				BEGIN
					--Do we neeed to condition it, when establishing Organization Dimension Xref?
					IF @nvMetaDataQueryName = N'ParentOrg' AND @nvMetaDataContext = N'Organization'
						SELECT @nvMetaDataQuery = REPLACE(REPLACE(@nvMetaDataQuery,'{1}',ISNULL(b.[1],'')),'{2}',ISNULL(b.[2],''))
						FROM [orgconfig].[ufnParameterSetILTFBSOP](@nvTemplateOrgParentType,@nvTemplateOrgParentName,NULL,NULL,NULL,NULL) as b;
					ELSE IF @nvMetaDataQueryName = N'ParentOrg' AND @nvMetaDataContext = N'Channel'
						SELECT @nvMetaDataQuery = REPLACE(@nvMetaDataQuery,'{2}',ISNULL(b.[2],''))
						FROM [orgconfig].[ufnParameterSetILTFBSOP](NULL,@nvTemplateChannelName,NULL,NULL,NULL,NULL) as b;
					ELSE IF @nvMetaDataQueryName = N'GeoOrgExclusion'
						SELECT @nvMetaDataQuery = REPLACE(REPLACE(REPLACE(REPLACE(@nvMetaDataQuery,'{1}',ISNULL(b.[1],'')),'{2}',ISNULL(b.[2],'')),'{3}',ISNULL(b.[3],'')),'{5}',ISNULL(b.[5],''))
						FROM [orgconfig].[ufnParameterSetILTFBSOP](@nvTemplateOrgParentType,@nvTemplateState,@ncTemplateZip,NULL,@nvTemplateChannelName,NULL) as b;
					ELSE IF @nvMetaDataQueryName  = N'ParentOrgviaChannel'
						SELECT @nvMetaDataQuery = REPLACE(@nvMetaDataQuery,'{5}',ISNULL(b.[5],''))
						FROM [orgconfig].[ufnParameterSetILTFBSOP](NULL,NULL,NULL,NULL,@nvTemplateChannelName,NULL) as b;
					ELSE IF @nvMetaDataQueryName = N'ParentOrgViaRiskLevel'
						SELECT @nvMetaDataQuery = REPLACE(@nvMetaDataQuery,'{4}',ISNULL(b.[4],''))
						FROM [orgconfig].[ufnParameterSetILTFBSOP](NULL,NULL,NULL,@iTemplateRiskLevel,NULL,NULL) as b;
					
					--Execute the query, porting the info into local variables
					EXEC sp_executesql @nvMetaDataQuery,N'@iOrgParentId int output,@iDimensionId int output',@iOrgParentId output,@iDimensionId output;

					--SELECT @iMetaDataIdent as Ident, @nvMetaDataQueryName as MetaDataQueryName,@iOrgParentId as OrgParentId, @iDimensionId as DimensionId, @nvMetaDataQuery as MetaDataQuery;

				END

				SET @nvMsg = @nvMetaDataContext+' Dim - ' + @nvTemplateOrgName +  '-' + @nvTemplateOrgExternal;

				--If we have populated the necessary variables proceed
				IF ISNULL(@iDimensionId, 0) <> 0			-- -1 when Mobile Channel
					AND ISNULL(@iOrgParentId, 0) <> 0		-- -1 when Mobile Channel
					AND ISNULL(@iOrgId, 0) <> 0				
					EXECUTE [import].[uspOrgXrefResertOut] 
						@pbiSrcRowId = @biTemplateRowId
						,@pnvSrcTable = @nvSrcTable
						,@pnvMsg = @nvMsg
						,@piDimensionId = @iDimensionId
						,@piOrgParentId = @iOrgParentId
						,@piOrgChildId = @iOrgId
						,@piStatusFlag = @iStatusFlag
						,@pnvUserName = @nvUserName
						,@piOrgXrefId = @iOrgXrefId OUTPUT;

			END
			ELSE IF @nvMetaDataAction = 'EstablishOrgAddress'
			BEGIN
				SET @biAddressId = NULL;
				SET @bAddressRequired = 1; --May Change due to Query evaluation
				SET @nvMsg = @nvTemplateOrgName + ';' + @nvTemplateOrgExternal + ';'  + ISNULL(@nvTemplateAddress1,'NULL') + ',' + ISNULL(@nvTemplateCity,'NULL') + ',' + ISNULL(@nvTemplateState,'NULL') + ',' + ISNULL(@ncTemplateZip,'NULL') + ',' + ISNULL(@nvCountry,'NULL');

				--SQL Query Centric?
				IF @nvMetaDataQuery IS NOT NULL  
				BEGIN
					IF @nvMetaDataQueryName = N'AddressExclusion'
						SELECT @nvMetaDataQuery = REPLACE(@nvMetaDataQuery,'{1}',ISNULL(b.[1],''))
						FROM [orgconfig].[ufnParameterSetILTFBSOP](@nvTemplateChannelName,NULL,NULL,NULL,NULL,NULL) as b;
					
					--Execute the query, porting the info into local variables
					EXEC sp_executesql @nvMetaDataQuery,N'@bAddressRequired bit output',@bAddressRequired output;
				END

				IF @bAddressRequired = 1
				BEGIN
					EXECUTE [import].[uspAddressUpsertOut]
						@pbiSrcRowId = @biTemplateRowId
						,@pnvSrcTable = @nvSrcTable
						,@pnvMsg = @nvMsg
						,@piOrgId  = @iOrgid
						,@pnvAddress1 = @nvTemplateAddress1
						,@pnvAddress2 = @nvTemplateAddress2
						,@pnvCity = @nvTemplateCity
						,@pnvStateAbbv = @nvTemplateState
						,@pnvZipCode = @ncTemplateZip
						,@pnvCountry = @nvCountry
						,@pfLatitude = @fTemplateLatitude
						,@pfLongitude = @fTemplateLongitude
						,@piStatusFlag = @iStatusFlag
						,@pnvUserName = @nvUserName
						,@pbiAddressId = @biAddressId OUTPUT;

					SET @iOrgAddressXrefId = NULL;
					SET @nvMsg = @nvTemplateOrgName + ';'
	
					IF ISNULL(@biAddressId,-1) <> -1
						EXECUTE [import].[uspOrgAddressXrefUpsertOut]
							@pbiSrcRowId = @biTemplateRowId
							,@pnvSrcTable = @nvSrcTable
							,@pnvMsg = @nvMsg
							,@piOrgId = @iOrgId
							,@pbiAddressId = @biAddressId
							,@pfLatitude = @fTemplateLatitude
							,@pfLongitude = @fTemplateLongitude
							,@piStatusFlag = @iStatusFlag
							,@pnvUserName = @nvUserName
							,@piOrgAddressXrefId = @iOrgAddressXrefId OUTPUT;	

				END
			END
			ELSE IF @nvMetaDataAction = 'LinkToPluginVaeModel'
			BEGIN
				SET @iVaeModelId = NULL
				SET @iOrgVaeModelXrefId = NULL;
				--Is there a SQL Query?
				IF @nvMetaDataQuery IS NOT NULL
				BEGIN
					--Do we neeed to condition it, when establishing OrgVAEModelXref?
					IF @nvMetaDataQueryName = N'VaePluginExclusion'
						SELECT @nvMetaDataQuery = REPLACE(@nvMetaDataQuery,'{3}',ISNULL(b.[3],''))
						FROM [orgconfig].[ufnParameterSetILTFBSOP](NULL,NULL,@nvTemplateChannelName,NULL,NULL,NULL) as b;
					ELSE IF @nvMetaDataQueryName = N'VAEPluginViaChannel'
						SELECT @nvMetaDataQuery = REPLACE(@nvMetaDataQuery,'{5}',ISNULL(b.[5],''))
						FROM [orgconfig].[ufnParameterSetILTFBSOP](NULL,NULL,NULL,NULL,@nvTemplateChannelName,NULL) as b;

					--Execute the query, porting the info into local variable
					EXEC sp_executesql @nvMetaDataQuery,N'@iVaeModelId int output',@iVaeModelId output;
				END

				SET @nvMsg = @nvTemplateOrgCode + ';' + @nvTemplateOrgExternal + ';' + CONVERT(NVARCHAR(10),@iVaeModelId);

				--If we have populated the necessary variables proceed
				IF ISNULL(@iVaeModelId, 0) > 0	--Would be negative if Model not defined for Channel, 0 for model not found
					AND ISNULL(@iOrgId, 0) > 0				
					EXECUTE [import].[uspOrgVaeModelXrefResertOut]
						 @pbiSrcRowId = @biTemplateRowId
						,@pnvSrcTable = @nvSrcTable
						,@pnvMsg = @nvMsg
						,@piOrgId = @iOrgId
						,@piVaeModelId = @iVaeModelId
						,@pbTestFlag = 0
						,@piStatusFlag = @iStatusFlag
						,@pnvUserName = @nvUserName
						,@piOrgVaeModelXrefId = @iOrgVaeModelXrefId OUTPUT;
					
				--SELECT @iOrgId as OrgId, @iVaeModelId as VaeModelId,@iOrgVaeModelXrefId as OrgVaeModelXrefId

			END
			--Iterating the SchemaSetRowId to get the next applicable record
			SET @iMetaDataIdent += 1; 

			IF @iMetaDataIdent > @iMetaDataRowCount --None left exit
				BREAK;
			--Read Next MetaData Action..
			SELECT @nvMetaDataCode = MetaDataCode
				,@iMetaDataParentId = MetaDataParentId
				,@iMetaDataId = MetaDataId
				,@iMetaDataXrefId = MetaDataXrefId
				,@nvMetaDataParentContext = MetaDataParentContext
				,@nvMetaDataContext = MetaDataContext
				,@nvMetaDataAction = MetaDataAction
				,@nvMetaDataActionStep = MetaDataActionStep
				,@nvMetaDataQuery = MetaDataQuery
				,@nvMetaDataQueryName = MetaDataQueryName
			FROM #tblMetaData
			WHERE Ident = @iMetaDataIdent;

			END TRY
			BEGIN CATCH
				EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
				THROW
			END CATCH
		END --WHILE 2 = 2

		--Truncate data so Identity is intact, removing metadata loaded for last go round, prepping for next
		TRUNCATE TABLE #tblMetaData;

		--Iterating the @iTemplateRowId to get the next applicable record
		SET @iTemplateIdent += 1;
		
		UPDATE o
			SET Processed = 1
				,DateActivated = SYSDATETIME()
		FROM [import].[Organization] o
		WHERE RowId = @biTemplateRowId;

		IF @iTemplateIdent > @iTemplateRowCount --None left exit
			BREAK;

		--Read Next Template Record..
		SELECT @biTemplateRowId = RowId
			,@nvTemplateOrgParentName = OrgParentName
			,@nvTemplateOrgParentType = OrgParentType
			,@nvTemplateOrgName = OrgName
			,@nvTemplateOrgType = OrgType
			,@nvTemplateOrgCode = OrgCode
			,@nvTemplateOrgDesc = OrgDesc
			,@nvTemplateOrgExternal = OrgExternal
			,@iTemplateOrgId = OrgId
			,@nvTemplateChannelName = ChannelName
			,@iTemplateRiskLevel = RiskLevel
			,@nvTemplateAddress1 = Address1
			,@nvTemplateAddress2 = Address2
			,@nvTemplateCity = City
			,@nvTemplateState = [State]
			,@ncTemplateZip = Zip
			,@fTemplateLatitude = Latitude
			,@fTemplateLongitude = Longitude
		FROM @tblOrgTemplate
		WHERE Ident = @iTemplateIdent;

		END TRY
		BEGIN CATCH
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			THROW
		END CATCH
	END --WHILE 1 = 1

	IF @iErrorDetailId >= 0
	BEGIN
		BEGIN TRY 
			--Message being passed back to the calling package
			SET @nvBody = '<table cellpadding="2" cellspacing="2" border="2"> '+'<tr><th>OrganizationImport Success</th></tr>' +
				'<table cellpadding="2" cellspacing="2" border="2">
				<tr><th>TemplateRow</th><th>SchemaSet</th><th>OrgName</th><th>OrgDescr</th><th>OrgType</th><th>OrgExternal</th><th>Msg</th></tr>' + --2021-10-20
			replace(replace((SELECT td = ISNULL(TRY_CONVERT(nvarchar(25),ot.Ident), '') +'</td><td>' +
				ISNULL(o.SchemaSet, '')  +'</td><td>' + --2021-10-20
				ISNULL(o.OrgName, '')  +'</td><td>' +
				ISNULL(o.OrgDesc, '')  +'</td><td>' + --2021-10-20
				ISNULL(o.OrgType, '')  +'</td><td>' +
				ISNULL(o.OrgExternal, '') +'</td><td>' +
				ISNULL('Created ', '') 
			FROM [import].[Organization] o
			INNER JOIN @tblOrgTemplate ot
				ON o.RowId = ot.RowId
			ORDER BY ot.Ident ASC
			FOR XML PATH('tr')), '&lt;', '<'), '&gt;', '>') + '</table></table>' 

			--Sending Mail
			EXEC msdb.dbo.sp_send_dbmail 
				 @profile_name = @nvProfileName
				,@recipients = @nvRecipients
				,@from_address = @nvFrom
				,@body = @nvBody
				,@body_format = 'HTML'
				,@subject = @nvSubject
				,@importance = 'Low';
	
			SET @piResultId = ISNULL(@iResultId, 0);
			EXECUTE [import].[uspLoadOrgCondensed] @pbImportLog = 1;
			EXECUTE [condensed].[uspLoadRCCondensedConsolidated] @pbImportLog = 1; --2022-04-26
		END TRY
		BEGIN CATCH
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			THROW
		END CATCH
	END
END

