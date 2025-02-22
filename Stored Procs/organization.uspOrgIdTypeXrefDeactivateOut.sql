USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspOrgIdTypeXrefDeActivateOut
	CreatedBy: Larry Dugger
	Description: This procedure will deactivate a xref record
	Tables: [organization].[OrgIdTypeXref]

	History:
		2015-05-07 - LBD - Created
		2017-06-03 - LBD - Modified, removed use of archive tables
		2019-10-24 - LBD - Modified, added PrimaryId field
		2020-09-13 - LBD - Removed PrimaryId
*****************************************************************************************/
ALTER   PROCEDURE [organization].[uspOrgIdTypeXrefDeactivateOut](
	@pnvUserName NVARCHAR(100) = 'N/A'
	,@piOrgIdTypeXrefId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @OrgIdTypeXref table (
		OrgIdTypeXrefId int
		,OrgId int
		,IdTypeId int
		--,PrimaryId bit
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName nvarchar(128) = N'organization';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	BEGIN TRANSACTION
	BEGIN TRY
		UPDATE [organization].[OrgIdTypeXref]
		SET StatusFlag = 0
			,DateActivated = SYSDATETIME()
			,UserName = @pnvUserName
		OUTPUT deleted.OrgIdTypeXrefId
			,deleted.OrgId
			,deleted.IdTypeId
			--,deleted.PrimaryId
			,deleted.StatusFlag
			,deleted.DateActivated
			,deleted.UserName
		INTO @OrgIdTypeXref
		WHERE OrgIdTypeXrefId = @piOrgIdTypeXrefId;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @piOrgIdTypeXrefId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
	BEGIN
		COMMIT TRANSACTION;
		SELECT @piOrgIdTypeXrefId = OrgIdTypeXrefId
		FROM @OrgIdTypeXref;
	END
END
