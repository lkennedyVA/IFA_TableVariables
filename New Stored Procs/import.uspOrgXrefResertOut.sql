USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [import].[uspOrgXrefResertOut]
	CreatedBy: Larry Dugger
	Descr: This procedure will Insert/Delete-Insert a new record
	Tables: [organization].[OrgXref]
   
	Procedures: [error].[uspLogErrorDetailInsertOut]
	History:
		2020-02-01 - LBD - Created
*****************************************************************************************/
ALTER PROCEDURE [import].[uspOrgXrefResertOut](
	 @pbiSrcRowId BIGINT
	,@pnvSrcTable NVARCHAR(128)
	,@pnvMsg NVARCHAR(255)
	,@piDimensionid INT
	,@piOrgParentId INT
	,@piOrgChildId INT
	,@piStatusFlag INT 
	,@pnvUserName NVARCHAR(100)
	,@piOrgXrefId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @dtStart datetime2(7) = SYSDATETIME()
		,@biActivityTime bigint = 0;
	DECLARE @tblOrgXref table (
		OrgXrefId int
		,DimensionId int
		,OrgParentId int
		,OrgChildId int
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
		);
	DECLARE @biSrcRowId bigint = @pbiSrcRowId 
		,@nvSrcTable nvarchar(128) = @pnvSrcTable
		,@nvMsg nvarchar(255) = @pnvMsg
		,@iOrgXrefId int = NULL
		,@iDimensionid int = @piDimensionid
		,@iCurrentOrgParentId int
		,@iOrgParentId int = @piOrgParentId
		,@iOrgChildId int = @piOrgChildId
		,@iStatusFlag int = @piStatusFlag
		,@nvUserName nvarchar(100) = @pnvUserName
		,@sSchemaName nvarchar(128) = OBJECT_SCHEMA_NAME(@@PROCID)
		,@sObjectName nvarchar(128) = OBJECT_NAME(@@PROCID)
		,@iErrorDetailId int
		,@iCurrentTransactionLevel int = @@TRANCOUNT;

	--Already exists? 
	--Must be restricted to a universal key fields (DimensionId, OrgChildId)
	SELECT @iOrgXrefId = OrgXrefId
		,@iCurrentOrgParentId = ox.OrgParentId	--If this exists what is it?
	FROM [organization].[OrgXref] ox
	WHERE ox.DimensionId = @iDimensionid
		AND ox.OrgChildId = @iOrgChildId;

	BEGIN TRANSACTION
	BEGIN TRY
		--Did we find one for this child-dimension with a different parent?
		IF ISNULL(@iOrgXrefId,-1) <> -1
			AND @iCurrentOrgParentId <> @iOrgParentId
		BEGIN
			SET @nvMsg = 'Delete ' + @nvMsg;
			UPDATE [organization].[OrgXref]
				SET StatusFlag = 0
					,DateActivated = SYSDATETIME()
					,UserName = @nvUserName
			WHERE OrgXrefId = @iOrgXrefId;
			SET @iOrgXrefId = NULL;
		END
		--Create new we didn't find one for this child-dimension
		IF ISNULL(@iOrgXrefId,-1) = -1
		BEGIN
			SET @nvMsg = 'Insert ' + @nvMsg;
			INSERT INTO [organization].[OrgXref]
				OUTPUT inserted.OrgXrefId
				,inserted.DimensionId
				,inserted.OrgParentId
				,inserted.OrgChildId
				,inserted.StatusFlag
				,inserted.DateActivated
				,inserted.UserName
				INTO @tblOrgXref
			SELECT @iDimensionid 
				,@iOrgParentId
				,@iOrgChildId
				,@iStatusFlag
				,SYSDATETIME()
				,@nvUserName; 
		END
		ELSE
		BEGIN
			SET @nvMsg = 'Exists ' + @nvMsg;
			INSERT INTO @tblOrgXref(OrgXrefId) VALUES(@iOrgXrefId);
		END
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @piOrgXrefId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
	BEGIN
		COMMIT TRANSACTION;
		SELECT @piOrgXrefId = OrgXrefId
			,@iOrgXrefId = OrgXrefId
		FROM @tblOrgXref
	END

	SET @biActivityTime = DATEDIFF(microsecond,@dtStart,sysdatetime());
	--Log the Activity						
	EXECUTE [import].[uspOrganizationLog] 
		 @pbiSrcTableId = @biSrcRowId
		,@pnvSrcTable = @nvSrcTable
		,@pbiDstTableId = @iOrgXrefId
		,@pnvDstTable = N'[organization].[OrgXref]'
		,@pnvMsg = @nvMsg
		,@pbiActivityLength = @biActivityTime
		,@pnvUserName = @nvUserName;
END
