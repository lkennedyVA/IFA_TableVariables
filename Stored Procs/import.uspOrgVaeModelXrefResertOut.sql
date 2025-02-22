USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [import].[uspOrgVaeModelXrefResertOut]
	Created by: Larry Dugger
	Description: Inserts a record into riskprocessingflow.OrgVaeModelXref associating 
		an organization with an existing VaeModelId

	Table: [organization].[Org]
		,[riskprocessingflow].[OrgVaeModelXrefInsertOut]

	History:
		2021-02-01 - LBD - Created, used [riskprocessingflow].[uspOrgVaeModelXrefInsertOut]
			as template
*****************************************************************************************/
ALTER   PROCEDURE [import].[uspOrgVaeModelXrefResertOut](
	@pbiSrcRowId BIGINT
	,@pnvSrcTable NVARCHAR(128)
	,@pnvMsg NVARCHAR(255)
	,@piOrgId INT
	,@piVaeModelId INT
	,@pbTestFlag BIT = 0
	,@piStatusFlag INT  
	,@pnvUserName NVARCHAR(100)
	,@piOrgVaeModelXrefId INT OUTPUT
) 
AS 
BEGIN
	SET NOCOUNT ON;
	DECLARE @dtStart datetime2(7) = SYSDATETIME()
		,@biActivityTime bigint = 0;
	DECLARE @tblOrgVaeModelXref table(
		OrgVaeModelXrefId int
		,OrgId int
		,VaeModelId int
		,TestFlag int
		,StatusFlag int 
		,DateActivated datetime2(7) 
		,UserName nvarchar(100) 
	);				
	DECLARE  @biSrcRowId bigint = @pbiSrcRowId 
		,@nvSrcTable nvarchar(128) = @pnvSrcTable
		,@nvMsg nvarchar(255) = @pnvMsg
		,@iOrgId int = @piOrgId
		,@iVaeModelId int = @piVaeModelId
		,@bTestFlag bit = @pbTestFlag
		,@iStatusFlag int = @piStatusFlag
		,@nvUserName nvarchar(100) = @pnvUserName
		,@iOrgVaeModelXrefId int = -1
		,@iBriskPluginId int = -1
		,@iCurrentVaeModelId int = -1
		,@sSchemaName nvarchar(128) = OBJECT_SCHEMA_NAME(@@PROCID)
		,@iErrorDetailId int
		,@iCurrentTransactionLevel int = @@TRANCOUNT;

	--What Plugin?
	SELECT @iBriskPluginId = BriskPluginId
	FROM [riskprocessingflow].[VaeModel]
	WHERE VaeModelId = @iVaeModelId;

	SELECT @iOrgVaeModelXrefId = OrgVaeModelXrefId
		,@iCurrentVaeModelId = x.VaeModelId
	FROM [riskprocessingflow].[OrgVaeModelXref] x
	INNER JOIN [riskprocessingflow].[VaeModel] vm on x.VaeModelId = vm.VaeModelId
	WHERE x.OrgId = @iOrgId
		AND vm.BriskPluginId = @iBriskPluginId  --Critical requirement
		AND x.StatusFlag = 1
		AND x.DateActivated <= SYSDATETIME();

	BEGIN TRANSACTION
	BEGIN TRY
		--Did we find one for this org-briskplugin with a different model?
		IF ISNULL(@iOrgVaeModelXrefId, -1) <> -1
			AND @iCurrentVaeModelId <> @iVaeModelId
		BEGIN
			SET @nvMsg = 'Delete ' + @nvMsg;
			UPDATE [riskprocessingflow].[OrgVaeModelXref]
				SET StatusFlag = 0
					,DateActivated = SYSDATETIME()
					,UserName = @nvUserName
			WHERE OrgVaeModelXrefId = @iOrgVaeModelXrefId;
			SET @iOrgVaeModelXrefId = NULL;
		END
		--Create new we didn't find one for this org-briskplugin
		IF ISNULL(@iOrgVaeModelXrefId, -1) = -1
		BEGIN
			SET @nvMsg = 'Insert ' + @nvMsg;
			INSERT INTO [riskprocessingflow].[OrgVaeModelXref](
				 OrgId
				,VaeModelId
				,TestFlag
				,StatusFlag
				,DateActivated
				,UserName
			)
			OUTPUT inserted.OrgVaeModelXrefId
				,inserted.OrgId
				,inserted.VaeModelId
				,inserted.TestFlag
				,inserted.StatusFlag
				,inserted.DateActivated
				,inserted.UserName
			INTO @tblOrgVaeModelXref
			SELECT @iOrgId AS OrgId
				,@iVaeModelId AS VaeModelId
				,@bTestFlag AS TestFlag
				,@iStatusFlag AS StatusFlag
				,SYSDATETIME()
				,@nvUserName AS UserName;
		END
		ELSE
		BEGIN
			SET @nvMsg = 'Exists ' + @nvMsg;
			INSERT INTO @tblOrgVaeModelXref(OrgVaeModelXrefId) VALUES(@iOrgVaeModelXrefId);
		END

	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		THROW
	END CATCH
	IF @@TRANCOUNT > @iCurrentTransactionLevel
	BEGIN
		COMMIT TRANSACTION;
		SELECT @piOrgVaeModelXrefId = OrgVaeModelXrefId
			,@iOrgVaeModelXrefId = OrgVaeModelXrefId 
		FROM @tblOrgVaeModelXref;
	END

	SET @biActivityTime = DATEDIFF(microsecond,@dtStart,sysdatetime());
	--Log the Activity						
	EXECUTE [import].[uspOrganizationLog] 
		 @pbiSrcTableId = @biSrcRowId
		,@pnvSrcTable = @nvSrcTable
		,@pbiDstTableId = @iOrgVaeModelXrefId
		,@pnvDstTable = N'[riskprocessingflow].[OrgVaeModelXref]'
		,@pnvMsg = @nvMsg
		,@pbiActivityLength = @biActivityTime
		,@pnvUserName = @nvUserName;
END
