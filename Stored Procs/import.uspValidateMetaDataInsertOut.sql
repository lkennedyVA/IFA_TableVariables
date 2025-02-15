USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [import].[uspValidateMetaDataInsertOut]
	Created By: Chris Sharp
	Description: This procedure will validate the metadata that was received in the 
		template and was parsed using ufnBulkOrganizationFormatted

	Functions: [import].[uspValidateMetaDataInsertOut](@piFileId);
	
	History:		
		2021-10-13 - CBS - Created.
		2022-08-02- CBS - OrgId is being imported as NULL.  Added NULLIF(OrgId, N'NULL) to return
			a NULL instead of a literal NULL value
*****************************************************************************************/
ALTER PROCEDURE [import].[uspValidateMetaDataInsertOut](
	 @piFileId BIGINT --= 393
	,@pnvRecipients NVARCHAR(512) --= 'csharp@validsystems.net'
	,@piResultId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @tblValidateMetaData table (
		 Id int 
		,SchemaSet nvarchar(100)			
		,OrgParentName nvarchar(50) 
		,OrgParentType nvarchar(50) 
		,OrgName nvarchar(50) 
		,OrgType nvarchar(50) 
		,Descr nvarchar(255) 
		,ExternalCode nvarchar(50) 
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
		,@iErrorDetailId int
		,@nvBody nvarchar(max) = N'The OrgTemplate has a metadata problem that prevents the process from moving forward. Check the following fields: RiskLevel, Zip, Latitude and Longitude or check the fields for additional commas. The file will be deleted to allow for additional processing.'
		,@nvProfileName sysname = 'SSDB-PRDTRX01'   --DEV Profile is 'SQLServerMailProfile'   
		,@nvFrom nvarchar(4000) = 'DBSupport@ValidAdvantage.com'
		,@nvSubject nvarchar(4000) = 'OrganizationImport Status'
		,@nvRecipients nvarchar(512) = @pnvRecipients;

	BEGIN TRY

		--Read up OrgTemplate information for records that haven't been processed yet
		INSERT INTO @tblValidateMetaData (
			 Id  
			,SchemaSet
			,OrgParentName
			,OrgParentType
			,OrgName
			,OrgType
			,Descr
			,ExternalCode
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
		SELECT Id
			,SchemaSet
			,OrgParentName
			,OrgParentType
			,OrgName
			,OrgType
			,Descr
			,ExternalCode
			,NULLIF(OrgId, N'NULL') AS OrgId --2022-08-02
			,ChannelName
			,RiskLevel
			,Address1
			,Address2
			,City
			,[State]
			,Zip
			,Latitude
			,Longitude
		FROM [import].[ufnBulkOrganizationFormatted](@piFileId)
		ORDER BY Id ASC;

		SET @piResultId = 0;
	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;

		IF ISNULL(@iErrorDetailId, -1) > 0 
		BEGIN
			SET @piResultId = -1;
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
	END CATCH
	SELECT @piResultId;
END
