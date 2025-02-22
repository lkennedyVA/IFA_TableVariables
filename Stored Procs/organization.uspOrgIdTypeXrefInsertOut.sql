USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspOrgIdTypeXrefInsertOut
	CreatedBy: Larry Dugger
	Date: 2015-05-07
	Description: This procedure will insert a new xref record
	Tables: [organization].[OrgIdTypeXref]
	History:
		2015-05-07 - LBD - Created
		2019-10-24 - LBD - Modified, added PrimaryId field
		2020-09-13 - LBD - Removed PrimaryId
*****************************************************************************************/
ALTER   PROCEDURE [organization].[uspOrgIdTypeXrefInsertOut](
	@piOrgId INT
	,@piIdTypeId INT
	--,@piPrimaryId BIT = 0
	,@piStatusFlag INT
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@piOrgIdTypeXrefId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @OrgIdTypeXref table (
		OrgIdTypeXrefId int
		,OrgId int
		,IdTypeId int
		,PrimaryId bit	
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
		);
	DECLARE @iOrgId int = @piOrgId
		,@iIdTypeId int = @piIdTypeId
		--,@iPrimaryId bit = @piPrimaryId
		,@iStatusFlag int = @piStatusFlag
		,@nvUserName nvarchar(100) = @pnvUserName
		,@iErrorDetailId int
		,@iCurrentTransactionLevel int
		,@sSchemaName nvarchar(128) = N'organization';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	BEGIN TRANSACTION
	BEGIN TRY
		INSERT INTO [organization].[OrgIdTypeXref]
			OUTPUT inserted.OrgIdTypeXrefId
			,inserted.OrgId
			,inserted.IdTypeId
			,inserted.PrimaryId	
			,inserted.StatusFlag
			,inserted.DateActivated
			,inserted.UserName
			INTO @OrgIdTypeXref
		SELECT @iOrgId
			,@iIdTypeId
			,0 --@iPrimaryId		2020-09-13
			,@iStatusFlag
			,SYSDATETIME()
			,@nvUserName;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @piOrgIdTypeXrefId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
	END CATCH;
	IF @@TRANCOUNT > 0
	BEGIN
		COMMIT TRANSACTION;
		SELECT @piOrgIdTypeXrefId = OrgIdTypeXrefId
		FROM @OrgIdTypeXref
	END
END
