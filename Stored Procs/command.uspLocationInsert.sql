USE [IFA]
GO
/****** Object:  StoredProcedure [command].[uspLocationInsert]    Script Date: 1/2/2025 6:05:42 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspLocationInsert
	Created By: Chris Sharp
	Descr: This procedure will insert a new record into the Org Table.
		We also insert an OrgXref record into the Organization dimension and 
		Channel Dimensions.  If the address fields are passed in, we also insert an 
		Address and an OrgAddressXref record
		
	Note(s): To insert an address we need the following:
		 @pnvAddress1
		,@pnvCity
		,@pnvStateAbbv
		,@pnvZipCode

	Also, before we enter the main logic, we perform a validation using the following
		IF (@piOrgTypeId = @iLocationOrgTypeId
			AND @iLocationLevelId > @iParentOrgLevelId)
			OR (@piOrgTypeId = @iSubLocationOrgTypeId
				AND @iSubLocationLevelId > @iParentOrgLevelId)...
		Do some work...
			
	Tables: [organization].[Org]
		,[organization].[OrgType] 

	Functions: [command].[ufnOrgType]
		,[command].[ufnOrgTypeLevelId]
		,[common].[ufnDimension]

   
	Procedures: [common].[uspLogErrorDetailInsertOut]
		,[common].[uspAddressInsertOut]
		,[organization].[uspOrgAddressXrefInsertOut]
		,[organization].[uspOrgXrefInsertOut]
		,[command].[uspLocationSelect]

	History:
		2018-02-05 - CBS - Created
*****************************************************************************************/
ALTER PROCEDURE [command].[uspLocationInsert](
	 @pnvOrgCode NVARCHAR(25)
	,@pnvOrgName NVARCHAR(50)
	,@pnvOrgDescr NVARCHAR(255)
	,@pnvExternalCode NVARCHAR(50)
	,@piOrgTypeId INT
	,@piStatusFlag INT
	,@piParentOrgId INT
	,@pnvUserName NVARCHAR(100)
	,@piChannelId INT
	,@pnvAddress1 NVARCHAR(150) 
	,@pnvAddress2 NVARCHAR(150) = N''
	,@pnvCity NVARCHAR(150) 
	,@pnvStateAbbv NVARCHAR(2) 
	,@pnvZipCode NCHAR(9)
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @tblOrg table (
		 OrgId int
		,OrgTypeId int
		,Code nvarchar(25)
		,[Name] nvarchar(50)
		,Descr nvarchar(255)
		,ExternalCode nvarchar(50)
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @iLocationOrgTypeId int = [command].[ufnOrgType]('Location')
		,@iSubLocationOrgTypeId int = [command].[ufnOrgType]('SubLocation')
		,@iLocationLevelId int = [command].[ufnOrgTypeLevelId]('Location')
		,@iSubLocationLevelId int = [command].[ufnOrgTypeLevelId]('SubLocation')
		,@iOrgDimensionId int = [common].[ufnDimension]('Organization')
		,@iChannelDimensionId int = [common].[ufnDimension]('Channel')
		,@biAddressId bigint 
		,@iOrgId int 
		,@iOrgXrefId int 
		,@iOrgAddressXrefId int
		,@iParentOrgLevelId int 
		,@iChannelParentOrgId int
		,@nvDesiredChannel nvarchar(50)
		,@nvCountry nvarchar(100) = N'USA'
		,@fLatitude float = -1
		,@fLongitude float = -1
		,@iErrorDetailId int
		,@iCurrentTransactionLevel int
		,@sSchemaName nvarchar(128) = N'command';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	--Check for mandatory fields prior to inserting an Organization
	IF ISNULL(@pnvOrgCode, '') = '' 
		OR ISNULL(@pnvOrgName, '') = '' 
		OR ISNULL(@pnvExternalCode, '') = ''  
	BEGIN
		RAISERROR ('Missing information create org', 16, 1);
		RETURN
	END
	IF EXISTS(SELECT 'X' 
			FROM [organization].[Org]
			WHERE Code = @pnvOrgCode)
	BEGIN
		RAISERROR ('Org exists for OrgCode', 16, 1);
		RETURN
	END
	ELSE IF EXISTS(SELECT 'X' 
				FROM [organization].[Org]
				WHERE [Name] = @pnvOrgName)
	BEGIN
		RAISERROR ('Org exists for OrgName', 16, 1);
		RETURN
	END
	ELSE IF EXISTS(SELECT 'X' 
				FROM [organization].[Org]
				WHERE ExternalCode = @pnvExternalCode)
	BEGIN
		RAISERROR ('Org exists for ExternalCode', 16, 1);
		RETURN
	END
	ELSE IF NOT EXISTS (SELECT 'X'
					FROM [organization].[Org]
					WHERE OrgId = @piParentOrgId)
	BEGIN
		RAISERROR ('ParentOrg doesn''t exist', 16, 1);
		RETURN
	END
	--WHATS the Parent OrgType and LevelId?
	SELECT @iParentOrgLevelId = TRY_CONVERT(INT,ot.Code)
	FROM [organization].[Org] o
	INNER JOIN [organization].[OrgType] ot on o.OrgTypeId = ot.OrgTypeId
	WHERE o.OrgId = @piParentOrgId;
	--WHATS the channel?
	SELECT @nvDesiredChannel = o.[Name] 
		,@iChannelParentOrgId = o.OrgId 
	FROM [organization].[Org] o
	INNER JOIN [organization].[OrgType] ot ON o.OrgTypeId = ot.OrgTypeId
	WHERE ot.[Name] = 'Channel'
		AND CASE o.[Name] WHEN 'Teller' THEN 1
							WHEN 'ATM' THEN 2
							WHEN 'Mobile' THEN 3
							ELSE 0
						END = @piChannelId;
	
	IF (@piOrgTypeId = @iLocationOrgTypeId
		AND @iLocationLevelId > @iParentOrgLevelId)
		OR (@piOrgTypeId = @iSubLocationOrgTypeId
			AND @iSubLocationLevelId > @iParentOrgLevelId)
	BEGIN
	BEGIN TRANSACTION
	BEGIN TRY
		INSERT INTO [organization].[Org]
			OUTPUT inserted.OrgId
				,inserted.OrgTypeId
				,inserted.Code
				,inserted.[Name]
				,inserted.Descr
				,inserted.ExternalCode
				,inserted.StatusFlag
				,inserted.DateActivated
				,inserted.UserName
			INTO @tblOrg
		SELECT @piOrgTypeId
			,@pnvOrgCode
			,@pnvOrgName
			,@pnvOrgDescr
			,@pnvExternalCode
			,@piStatusFlag
			,SYSDATETIME()
			,@pnvUserName; 
		SELECT @iOrgId = OrgId
		FROM @tblOrg;
				
		--INSERT 'OrgXref for 'Organization' dim
		EXECUTE [organization].[uspOrgXrefInsertOut]
			 @piDimensionid = @iOrgDimensionId
			,@piOrgParentId = @piParentOrgId
			,@piOrgChildId = @iOrgId
			,@piStatusFlag = @piStatusFlag
			,@pnvUserName = @pnvUserName
			,@piOrgXrefId = @iOrgXrefId OUTPUT;

		--INSERT 'OrgXref for 'Channel' dim
		SET @iOrgXrefId = NULL;
		EXECUTE [organization].[uspOrgXrefInsertOut]
			 @piDimensionid = @iChannelDimensionId
			,@piOrgParentId = @iChannelParentOrgId
			,@piOrgChildId = @iOrgId
			,@piStatusFlag = @piStatusFlag
			,@pnvUserName = @pnvUserName
			,@piOrgXrefId = @iOrgXrefId OUTPUT;
		
		IF ISNULL(@pnvAddress1, '') <> ''
			AND ISNULL(@pnvCity, '') <> ''
			AND ISNULL(@pnvStateAbbv, '') <> ''
			AND ISNULL(@pnvZipCode, '') <> ''
		BEGIN
			--Insert address information passed into procedure
			--Using table variable to return fields to calling proc
			EXECUTE [common].[uspAddressInsertOut]
				 @pnvAddress1 = @pnvAddress1
				,@pnvAddress2 = @pnvAddress2
				,@pnvCity = @pnvCity
				,@pnvStateAbbv = @pnvStateAbbv
				,@pnvZipCode = @pnvZipCode
				,@pnvCountry = @nvCountry
				,@pfLatitude = @fLatitude
				,@pfLongitude = @fLongitude
				,@piStatusFlag = @piStatusFlag
				,@pnvUserName = @pnvUserName
				,@pbiAddressId = @biAddressId OUTPUT;

			EXECUTE [organization].[uspOrgAddressXrefInsertOut]		
				 @piOrgId = @iOrgId
				,@pbiAddressId = @biAddressId
				,@pfLatitude = @fLatitude
				,@pfLongitude = @fLongitude
				,@piStatusFlag = @piStatusFlag
				,@pnvUserName = @pnvUserName
 				,@piOrgAddressXrefId = @iOrgAddressXrefId OUTPUT;
		END
	END TRY
	BEGIN CATCH
	IF @@TRANCOUNT > @iCurrentTransactionLevel
		ROLLBACK TRANSACTION;
	EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
	THROW;
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
	BEGIN
		COMMIT TRANSACTION;	
		EXECUTE [command].[uspLocationSelect] @piOrgId = @iOrgId;			
	END
	ELSE
		RAISERROR ('Location/SubLocations can only have a parent with a lower org type Code', 16, 1);
	END
END
