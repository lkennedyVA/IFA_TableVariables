USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [import].[uspValidateBusinessRulesInsertOut]
	Created By: Chris Sharp
	Description: This procedure will validate the errors we have seen with the data
		being passed to us from import.Organization.  If an error is encountered, 
		an email will be sent to the recipients list notifying the users of the error.
		The validation rules will be enhanced as we move forward

	Tables: [import].[Log]
		,[import].[Organization]
		,[orgconfig].[MetaData]
		,[organization].[Org]
		,[organization].[OrgType]

	Synonymn: [organization].[ZipCode]  => [PrdBi02].[ZipDemographic].[dbo].[ZipCode]
	
	Procedures: [import].[uspOrganizationLog]
	
	History:		
		2021-02-12 - CBS - Created
		2021-03-02 - CBS - Added @pnvRecipients as a parameter passed from import.uspOrganizationUpsert
		2021-05-11 - CBS - Added debugging code, clearing @nvMsg and @iStepResult prior to entering the 
			BEGIN block
		2021-11-01 - CBS - Added enhanced messaging
		2021-11-30 - CBS - Added a check for a NULL or empty OrgCode in the template prior to processing
			the OrgTemplate
*****************************************************************************************/
ALTER   PROCEDURE [import].[uspValidateBusinessRulesInsertOut](
	 @ptblOrgTemplate [import].[OrgTemplateType] READONLY
	,@pnvSchemaSet NVARCHAR(50)
	,@pnvUserName NVARCHAR(100)
	,@pnvRecipients NVARCHAR(512)
	,@piResultId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DROP TABLE IF EXISTS #tblOrgTemplate;
	CREATE TABLE #tblOrgTemplate(
		 Ident int 
		,RowId bigint
		,OrgParentName nvarchar(50) 
		,OrgParentType nvarchar(50) 
		,OrgName nvarchar(50) 
		,OrgType nvarchar(50) 
		,OrgCode nvarchar(25) 
		,OrgDesc nvarchar(255) 
		,OrgExternal nvarchar(50) 
		,OrgId int 
		,ChannelName nvarchar(50) 
		,RiskLevel int
		,Address1 nvarchar(150) 
		,Address2 nvarchar(150) 
		,City nvarchar(100) 
		,[State] nvarchar(25) 
		,Zip nchar(5) 
		,Latitude decimal(8, 6) 
		,Longitude decimal(9,6)
	);
	DECLARE @sSchemaName nvarchar(128) = OBJECT_SCHEMA_NAME(@@PROCID)
		,@ncObjectName nchar(50) = CONVERT(nchar(50),OBJECT_NAME(@@PROCID))
		,@nvSchemaSet nvarchar(50) = @pnvSchemaSet
		,@nvUserName nvarchar(100) = @pnvUserName
		,@nvSrcTable nvarchar(128) = N'[import].[Organization]'
		,@nvBody nvarchar(max) = ''		
		,@nvProfileName sysname = 'SSDB-PRDTRX01'   --PROD Profile is 'SSDB-PRDTRX01'   --DEV Profile is 'SQLServerMailProfile'  
		,@nvFrom nvarchar(4000) = 'DBSupport@ValidAdvantage.com'
		,@nvSubject nvarchar(4000) = 'OrganizationImport Status'
		,@nvRecipients nvarchar(512) = @pnvRecipients
		--Template variables
		,@biSrcRowId bigint
		,@nvMsg nvarchar(255) = ''
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
		,@iErrorDetailId int
		,@iRowResultId int = 0 --Row result
		,@iStepResultId int = 0 --Validation step result
		,@iTemplateResultId int = 0 --Template result
		,@biMaxErrorLogId bigint = 0;

	--Aquire the MAX LogId prior to validating the template
	SELECT @biMaxErrorLogId = MAX(LogId)
	FROM [import].[Log];

	SET @biMaxErrorLogId = ISNULL(@biMaxErrorLogId, 0);

	--Read up OrgTemplate information for records that haven't been processed yet
	INSERT INTO #tblOrgTemplate (
		 Ident
		,RowId
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
	SELECT Ident
		,RowId 
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
	FROM @ptblOrgTemplate
	ORDER BY Ident ASC;

	--SELECT N'#tblOrgTemplate', * FROM #tblOrgTemplate

	SET @iTemplateRowCount = @@ROWCOUNT;
	SET @iTemplateIdent = 1;

	--Grab the first Template Record and walk through it
	WHILE 1 = 1 --We use a BREAK to exit, when we have completed all Template rows
	BEGIN
		
		IF @iTemplateRowCount < @iTemplateIdent 
			RETURN;

		--Set Variables for comparison
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
		FROM #tblOrgTemplate
		WHERE Ident = @iTemplateIdent;

		--Q: Is the template SchemaSet defined
		SET @nvMsg = '';
		SET @iStepResultId = 0;
		IF NOT EXISTS (SELECT 'X' FROM [orgconfig].[MetaData] WHERE Code = @nvSchemaSet)
		BEGIN
			SET @iStepResultId = -1;
			SET @nvMsg = N'SchemaSet '+ CONVERT(nvarchar(50),@nvSchemaSet)+' Not defined';
			EXECUTE [import].[uspOrganizationLog] 
				 @pbiSrcTableId = @biTemplateRowId
				,@pnvSrcTable = @nvSrcTable
				,@pbiDstTableId = 0
				,@pnvDstTable = N'[orgconfig].[MetaData]'
				,@pnvMsg = @nvMsg
				,@pbiActivityLength = 0 
				,@pnvUserName = @nvUserName;
			
			--We need to retain whether any validation step had an error as we continue processing
			IF @iStepResultId = -1
				SET @iRowResultId = @iStepResultId;
		END

		--SELECT @biTemplateRowId AS N'@biTemplateRowId',@iStepResultId AS N'@iStepResultId1', @nvMsg AS N'@nvMsg';

		--Q: Does the OrgParentType Name exist? 
		SET @nvMsg = '';
		SET @iStepResultId = 0;
		IF NOT EXISTS (SELECT 'X' FROM [organization].[OrgType]	WHERE [Name] = @nvTemplateOrgParentType)
		BEGIN
			SET @iStepResultId = -1;
			SET @nvMsg = N'OrgParentType '+ CONVERT(nvarchar(50),@nvTemplateOrgParentType)+' Not defined';
			EXECUTE [import].[uspOrganizationLog] 
				 @pbiSrcTableId = @biTemplateRowId
				,@pnvSrcTable = @nvSrcTable
				,@pbiDstTableId = @biTemplateRowId
				,@pnvDstTable = N'[organization].[OrgType]'
				,@pnvMsg = @nvMsg
				,@pbiActivityLength = 0 
				,@pnvUserName = @nvUserName;
			
			--We need to retain whether any validation step had an error as we continue processing
			IF @iStepResultId = -1
				SET @iRowResultId = @iStepResultId;
		END
		
		--Q: Are the OrgCodes populated? --2021-11-30
		SET @nvMsg = '';
		SET @iStepResultId = 0;
		IF ISNULL(@nvTemplateOrgCode, '') = ''
		BEGIN
			SET @iStepResultId = -1;
			SET @nvMsg = N'OrgCode Not populated';
			EXECUTE [import].[uspOrganizationLog] 
				 @pbiSrcTableId = @biTemplateRowId
				,@pnvSrcTable = @nvSrcTable
				,@pbiDstTableId = 0
				,@pnvDstTable = N'[organization].[OrgType]'
				,@pnvMsg = @nvMsg
				,@pbiActivityLength = 0 
				,@pnvUserName = @nvUserName;
			
			--We need to retain whether any validation step had an error as we continue processing
			IF @iStepResultId = -1
				SET @iRowResultId = @iStepResultId;
		END

		--Q: Does the OrgType Name exist? 
		SET @nvMsg = '';
		SET @iStepResultId = 0;
		IF NOT EXISTS (SELECT 'X' FROM [organization].[OrgType]	WHERE [Name] = @nvTemplateOrgType)
		BEGIN
			SET @iStepResultId = -1;
			SET @nvMsg = N'OrgType '+ CONVERT(nvarchar(50),@nvTemplateOrgType)+' Not defined';
			EXECUTE [import].[uspOrganizationLog] 
				 @pbiSrcTableId = @biTemplateRowId
				,@pnvSrcTable = @nvSrcTable
				,@pbiDstTableId = 0
				,@pnvDstTable = N'[organization].[OrgType]'
				,@pnvMsg = @nvMsg
				,@pbiActivityLength = 0 
				,@pnvUserName = @nvUserName;
			
			--We need to retain whether any validation step had an error as we continue processing
			IF @iStepResultId = -1
				SET @iRowResultId = @iStepResultId;
		END
	
		--SELECT @biTemplateRowId AS N'@biTemplateRowId', @iStepResultId AS N'@iStepResultId3', @nvMsg AS N'@nvMsg';

		--Both the OrgParentType and OrgType have to exist to evaluate the levels
		SET @nvMsg = '';
		SET @iStepResultId = 0;
		IF EXISTS (SELECT 'X' FROM [organization].[OrgType]	WHERE [Name] = @nvTemplateOrgParentType)
			AND EXISTS (SELECT 'X' FROM [organization].[OrgType] WHERE [Name] = @nvTemplateOrgType)
		BEGIN
			--Q: Is the Parent OrgTypeCode at a lower level the the OrgCode 
			IF NOT EXISTS (SELECT 'X' 
						FROM [organization].[OrgType] otp
						CROSS APPLY [organization].[OrgType] otc
						WHERE otp.[Name] = @nvTemplateOrgParentType
							AND otc.[Name] = @nvTemplateOrgType
							AND CONVERT(int,otp.Code) < CONVERT(int, otc.Code))
			BEGIN
				SET @iStepResultId = -1;
				SET @nvMsg = N'OrgParentType '+ CONVERT(nvarchar(50),@nvTemplateOrgParentType)+' can only be at a lower level than OrgType '+ CONVERT(nvarchar(50),@nvTemplateOrgType);
				EXECUTE [import].[uspOrganizationLog] 
					 @pbiSrcTableId = @biTemplateRowId
					,@pnvSrcTable = @nvSrcTable
					,@pbiDstTableId = 0
					,@pnvDstTable = N'[organization].[OrgType]' --?
					,@pnvMsg = @nvMsg
					,@pbiActivityLength = 0 
					,@pnvUserName = @nvUserName;
			
				--We need to retain whether any validation step had an error as we continue processing
				IF @iStepResultId = -1
					SET @iRowResultId = @iStepResultId;
			END
		END
				
		--SELECT @biTemplateRowId AS N'@biTemplateRowId', @iStepResultId AS N'@iStepResultId4', @nvMsg AS N'@nvMsg';

		--Q: Does the OrgParentName Exist in organization.Org or in import.Organziation with a lower Id
		SET @nvMsg = '';
		SET @iStepResultId = 0;
		IF NOT EXISTS (SELECT 'X' 
						FROM [organization].[Org] o
						INNER JOIN [organization].[OrgType] ot
							ON o.OrgTypeId = ot.OrgTypeId
						WHERE o.[Name] = @nvTemplateOrgParentName
							AND ot.[Name] = @nvTemplateOrgParentType
						UNION ALL 
						SELECT 'X'
						FROM #tblOrgTemplate t 
						WHERE t.OrgName = @nvTemplateOrgParentName
							AND t.OrgType = @nvTemplateOrgParentType
							AND t.Ident < @iTemplateIdent) --2021-05-11 CBS
		BEGIN
			SET @iStepResultId = -1;
			SET @nvMsg = N'OrgParentName '+ CONVERT(nvarchar(50),@nvTemplateOrgParentName)+' and OrgParentType '+CONVERT(nvarchar(50),@nvTemplateOrgParentType)+ ' not found';
			EXECUTE [import].[uspOrganizationLog] 
				 @pbiSrcTableId = @biTemplateRowId
				,@pnvSrcTable = @nvSrcTable
				,@pbiDstTableId = 0
				,@pnvDstTable = N'[organization].[Org]'
				,@pnvMsg = @nvMsg
				,@pbiActivityLength = 0 
				,@pnvUserName = @nvUserName;
			
			--We need to retain whether any validation step had an error as we continue processing
			IF @iStepResultId = -1
				SET @iRowResultId = @iStepResultId;
		END
				
		--SELECT @biTemplateRowId AS N'@biTemplateRowId', @iStepResultId AS N'@iStepResultId5', @nvMsg AS N'@nvMsg';

		--Q: Is the Channel Valid, OrgTypes requiring Channels: Location, SubLocation, ATM --2021-05-11
		SET @nvMsg = '';
		SET @iStepResultId = 0;
		IF (@nvTemplateOrgType IN ('SubLocation','Location','ATM') --2021-05-11
			AND NOT EXISTS (SELECT 'X'
					FROM [organization].[Org] o
					INNER JOIN [organization].[OrgType] ot
						ON o.OrgTypeId = ot.OrgTypeId
					WHERE ot.[Name] = 'Channel' 
						AND o.[Name] = @nvTemplateChannelName))
		BEGIN
			SET @iStepResultId = -1;
			SET @nvMsg = N'Channel Name '+ CONVERT(nvarchar(50),@nvTemplateChannelName)+' not defined';
			EXECUTE [import].[uspOrganizationLog] 
				 @pbiSrcTableId = @biTemplateRowId
				,@pnvSrcTable = @nvSrcTable
				,@pbiDstTableId = 0
				,@pnvDstTable = N'[organization].[Org]'
				,@pnvMsg = @nvMsg
				,@pbiActivityLength = 0 
				,@pnvUserName = @nvUserName;
			
			--We need to retain whether any validation step had an error as we continue processing
			IF @iStepResultId = -1
				SET @iRowResultId = @iStepResultId;
		END

		--SELECT @biTemplateRowId AS N'@biTemplateRowId', @iStepResultId AS N'@iStepResultId6', @nvMsg AS N'@nvMsg';

		--ADDRESS VALIDATION: OrgTypes requiring address: Location, SubLocation, ATM
		SET @nvMsg = '';
		SET @iStepResultId = 0;
		IF (@nvTemplateOrgType IN ('SubLocation','Location','ATM')
			OR @nvTemplateChannelName = 'Mobile')
		BEGIN
			--Is the StateCode Valid
			IF NOT EXISTS (SELECT 'X'
						FROM [organization].[Org] o
						INNER JOIN [organization].[OrgType] ot
							ON o.OrgTypeId = ot.OrgTypeId
						WHERE ot.[Name] = 'State' 
							AND o.[Name] = @nvTemplateState)
			BEGIN
				SET @iStepResultId = -1;
				SET @nvMsg = N'State Abbr '+ CONVERT(nvarchar(50),@nvTemplateState)+' not defined';
				EXECUTE [import].[uspOrganizationLog] 
					 @pbiSrcTableId = @biTemplateRowId
					,@pnvSrcTable = @nvSrcTable
					,@pbiDstTableId = 0
					,@pnvDstTable = N'[organization].[Org]'
					,@pnvMsg = @nvMsg
					,@pbiActivityLength = 0 
					,@pnvUserName = @nvUserName;

				--SELECT @biTemplateRowId AS N'@biTemplateRowId', @iStepResultId AS N'@iStepResultId7', @nvMsg AS N'@nvMsg';
			
			--We need to retain whether any validation step had an error as we continue processing
			IF @iStepResultId = -1
				SET @iRowResultId = @iStepResultId;
			END
			--Check for missing address data
			SET @nvMsg = '';
			SET @iStepResultId = 0;
			IF (ISNULL(@nvTemplateAddress1, '') <> ''
					OR ISNULL(@nvTemplateCity, '') <> ''
					OR ISNULL(@nvTemplateState, '') <> ''
					OR ISNULL(@ncTemplateZip, '') <> '')
				AND  ( -- second check for gaps in the address data
						ISNULL(@nvTemplateAddress1, '') = ''
							OR ISNULL(@nvTemplateCity, '') = ''
							OR ISNULL(@nvTemplateState, '') = ''
							OR ISNULL(@ncTemplateZip, '') = '')
			--For Later, Identify the Template Fields that are missing
			BEGIN
				SET @iStepResultId = -1;
				SET @nvMsg = N'Potentially incomplete address info for '+CONVERT(nvarchar(50), @nvTemplateOrgName);
				EXECUTE [import].[uspOrganizationLog] 
					 @pbiSrcTableId = @biTemplateRowId
					,@pnvSrcTable = @nvSrcTable
					,@pbiDstTableId = 0
					,@pnvDstTable = N'[common].[Address]'
					,@pnvMsg = @nvMsg
					,@pbiActivityLength = 0 
					,@pnvUserName = @nvUserName;

				--SELECT @biTemplateRowId AS N'@biTemplateRowId', @iStepResultId AS N'@iStepResultId8', @nvMsg AS N'@nvMsg';
			
			--We need to retain whether any validation step had an error as we continue processing
			IF @iStepResultId = -1
				SET @iRowResultId = @iStepResultId;
			END
						
			--Testing for Out of Range Lat / Longs
			SET @nvMsg = '';
			SET @iStepResultId = 0;
			IF ABS(@fTemplateLatitude) > 90.0
				OR ABS(@fTemplateLongitude) > 180
			BEGIN
				SET @iStepResultId = -1;
				SET @nvMsg = N'Potentially out of range Latitude '+CONVERT(nvarchar(10),@fTemplateLatitude)+' or Longitude '+CONVERT(nvarchar(10), @fTemplateLongitude)+ ' for '+CONVERT(nvarchar(50), @nvTemplateOrgName);
				EXECUTE [import].[uspOrganizationLog] 
					@pbiSrcTableId = @biTemplateRowId
					,@pnvSrcTable = @nvSrcTable
					,@pbiDstTableId = 0
					,@pnvDstTable = N'[common].[Address]'
					,@pnvMsg = @nvMsg
					,@pbiActivityLength = 0 
					,@pnvUserName = @nvUserName;

				--SELECT @biTemplateRowId AS N'@biTemplateRowId', @iStepResultId AS N'@iStepResultId9', @nvMsg AS N'@nvMsg';
			
			--We need to retain whether any validation step had an error as we continue processing
			IF @iStepResultId = -1
				SET @iRowResultId = @iStepResultId;
			END
			--Does ZipCode exist in the State?
			SET @nvMsg = '';
			SET @iStepResultId = 0;
			IF NOT EXISTS (SELECT 'X'
						FROM [organization].[ZipCode] 
						WHERE ZipCode = @ncTemplateZip 
						AND [State] = @nvTemplateState)
			BEGIN
				SET @iStepResultId = -1;
				SET @nvMsg = N'ZipCode '+CONVERT(nvarchar(25),@ncTemplateZip) + ' is not found in ' +CONVERT(nvarchar(10),@nvTemplateState)+' in [ZipDemographic].[dbo].[ZipCode]';
				EXECUTE [import].[uspOrganizationLog] 
					@pbiSrcTableId = @biTemplateRowId
					,@pnvSrcTable = @nvSrcTable
					,@pbiDstTableId = 0
					,@pnvDstTable = N'[ZipDemographic].[dbo].[ZipCode]'
					,@pnvMsg = @nvMsg
					,@pbiActivityLength = 0 
					,@pnvUserName = @nvUserName;

				--SELECT @biTemplateRowId AS N'@biTemplateRowId', @iStepResultId AS N'@iStepResultId10', @nvMsg AS N'@nvMsg';
			
			--We need to retain whether any validation step had an error as we continue processing
			IF @iStepResultId = -1
				SET @iRowResultId = @iStepResultId;
			END
		END --ADDRESS VALIDATION
					
		--Iterating the @iTemplateRowId to get the next applicable record
		SET @iTemplateIdent += 1;
		
		UPDATE o
		SET o.Processed = 1
			,o.ErrorCodeId = CASE WHEN ISNULL(l.SrcTableId, 0) <> 0 THEN 1 ELSE 0 END
			,o.Validated = CASE WHEN ISNULL(l.SrcTableId, 0) = 0 THEN 1 ELSE 0 END
			,o.DateActivated = SYSDATETIME()
		FROM [import].[Organization] o
		LEFT JOIN [import].[Log] l
			ON o.RowId = l.SrcTableId
		WHERE o.RowId = @biTemplateRowId;

		--If any record has an issue, we flag the template as having an issue and set @iTemplateResult to -1
		IF ISNULL(@iRowResultId, -1) = -1
			AND @iTemplateResultId <> -1 
			SET @iTemplateResultId = -1;
		
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
		FROM #tblOrgTemplate
		WHERE Ident = @iTemplateIdent;
	
	END 

	--SELECT @iTemplateResultId AS N'@iTemplateResultId';

	IF @iTemplateResultId = -1
	BEGIN
		SET @piResultId = @iTemplateResultId;
		SET @nvBody = '<table cellpadding="2" cellspacing="2" border="2"> '+'<tr><th>OrganizationImport Error</th></tr>' +
				'<table cellpadding="2" cellspacing="2" border="2">
				<tr><th>TemplateRow</th><th>SchemaSet</th><th>OrgName</th><th>OrgDescr</th><th>OrgType</th><th>OrgExternal</th><th>Msg</th></tr>' + --2021-10-20
			replace(replace((SELECT td = ISNULL(TRY_CONVERT(nvarchar(25),ot.Ident), '') +'</td><td>' +
				ISNULL(o.SchemaSet, '')  +'</td><td>' + --2021-10-20
				ISNULL(o.OrgName, '')  +'</td><td>' +
				ISNULL(o.OrgDesc, '')  +'</td><td>' + --2021-10-20
				ISNULL(o.OrgType, '')  +'</td><td>' +
				ISNULL(o.OrgExternal, '') +'</td><td>' +
				ISNULL(Msg, '') 
			FROM [import].[Organization] o
			INNER JOIN [import].[Log] il
				ON o.RowId = il.SrcTableId
			INNER JOIN @ptblOrgTemplate ot
				ON o.RowId = ot.RowId
			WHERE il.LogId > @biMaxErrorLogId
			ORDER BY il.LogId ASC
			FOR XML PATH('tr')), '&lt;', '<'), '&gt;', '>') + '</table></table>' 

		--Sending Mail
		EXEC msdb.dbo.sp_send_dbmail 
			 @profile_name = @nvProfileName
			,@recipients = @nvRecipients
			,@from_address = @nvFrom
			,@body = @nvBody
			,@body_format = 'HTML'
			,@subject = @nvSubject
			,@importance = 'High';
	END
END

