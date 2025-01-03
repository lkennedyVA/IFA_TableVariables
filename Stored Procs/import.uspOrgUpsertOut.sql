USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [import].[uspOrgUpsertOut]
	CreatedBy: Larry Dugger
	Descr: This procedure will upsert a new record
	Tables: [import].[Organization] 
		,[organization].[Org]
	Functions: [error].[uspLogErrorDetailInsertOut]

	History:
		2021-01-29 - LBD - Created
*****************************************************************************************/
ALTER PROCEDURE [import].[uspOrgUpsertOut](
	@ptblOrgReference [ifa].[OrgListType] READONLY
	,@pbiSrcRowId BIGINT
	,@pnvSrcTable NVARCHAR(128)
	,@pnvOrgTypeName NVARCHAR(50)
	,@pnvCode NVARCHAR(25)
	,@pnvName NVARCHAR(50)
	,@pnvDescr NVARCHAR(255)
	,@pnvExternalCode NVARCHAR(50)
	,@piStatusFlag INT 
	,@pnvUserName NVARCHAR(100)
	,@piOrgId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @dtStart datetime2(7) = SYSDATETIME()
		,@biActivityTime bigint = 0;
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
	DECLARE @biSrcRowId bigint = @pbiSrcRowId 
		,@nvSrcTable nvarchar(128) = @pnvSrcTable
		,@nvMsg nvarchar(255) = ''
		,@iOrgId int = NULL
		,@nvCode nvarchar(25) = @pnvCode
		,@nvName nvarchar(50) = @pnvName
		,@nvDescr nvarchar(255) = @pnvDescr
		,@nvExternalCode nvarchar(50) = @pnvExternalCode
		,@iStatusFlag int = @piStatusFlag
		,@nvUserName nvarchar(100) = @pnvUserName
		,@iOrgTypeId int = [common].[ufnOrgType](@pnvOrgTypeName)
		,@iCurrentOrgTypeId int
		,@sSchemaName nvarchar(128) = OBJECT_SCHEMA_NAME(@@PROCID)
		,@iErrorDetailId int
		,@iCurrentTransactionLevel int = @@TRANCOUNT;

	--Already exists? 
	--Must be restricted to a universal key field under the Client or Partner for FD/FIS (FiservI)
	SELECT @iOrgId = OrgId
		,@iCurrentOrgTypeId = OrgTypeId
	FROM @ptblOrgReference o	--pre-loaded with orgs in this family
	WHERE o.[ExternalCode] = @nvExternalCode;

	BEGIN TRANSACTION
	BEGIN TRY
		IF @iCurrentOrgTypeId = @iOrgTypeId
		BEGIN
			SET @nvMsg = 'Update ';
			UPDATE [organization].[Org]
			SET Code = @nvCode
				,[Name] = @nvName
				,Descr = @nvDescr
				,StatusFlag = @iStatusFlag
				,DateActivated = SYSDATETIME()
				,UserName = @pnvUserName
				OUTPUT inserted.OrgId 
					,inserted.Code
					,inserted.[Name]		
					,inserted.Descr
					--,inserted.ExternalCode	This process can't update ExternalCode
					,inserted.StatusFlag
					,inserted.DateActivated
					,inserted.UserName
				INTO @tblOrg (OrgId,Code,[Name],Descr,StatusFlag,DateActivated,UserName)
			WHERE OrgId = @iOrgId;
		END
		ELSE IF ISNULL(@iOrgId,-1) = -1		--Doesn't already exist
		BEGIN
			SET @nvMsg = 'Insert ';
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
				INTO @tblOrg (OrgId,OrgTypeId,Code,[Name],Descr,ExternalCode,StatusFlag,DateActivated,UserName)
			SELECT @iOrgTypeId
				,@nvCode
				,@nvName
				,@nvDescr
				,@nvExternalCode
				,@iStatusFlag
				,SYSDATETIME()
				,@nvUserName;
		END
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @piOrgId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
	BEGIN
		COMMIT TRANSACTION;
		SELECT @piOrgId = OrgId
			,@iOrgId = OrgId
			,@nvMsg = @nvMsg+'OrgId:'+ CONVERT(nvarchar(10),OrgId)+ '-' + @nvName + '-' + ISNULL(@nvExternalCode,'')
		FROM @tblOrg
	END

	SET @biActivityTime = DATEDIFF(microsecond,@dtStart,sysdatetime());
	--Log the Activity						
	EXECUTE [import].[uspOrganizationLog] 
		 @pbiSrcTableId = @biSrcRowId
		,@pnvSrcTable = @nvSrcTable
		,@pbiDstTableId = @iOrgId
		,@pnvDstTable = N'[organization].[Org]'
		,@pnvMsg = @nvMsg
		,@pbiActivityLength = @biActivityTime
		,@pnvUserName = @nvUserName;
END
