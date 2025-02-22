USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspOrgResponseCodeXrefDeActivateOut
	CreatedBy: Larry Dugger
	Date: 2017-01-27
	Description: This procedure will deactivate a xref record
	Tables: [organization].[OrgResponseCodeXref]

	History:
		2017-01-27 - LBD - Created
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [organization].[uspOrgResponseCodeXrefDeactivateOut](
	 @pnvUserName NVARCHAR(100) = 'N/A'
	,@piOrgResponseCodeXrefId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @OrgResponseCodeXref table (
		 OrgResponseCodeXrefId int
		,OrgId int
		,ResponseCodeId int
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
		UPDATE [organization].[OrgResponseCodeXref]
		SET StatusFlag = 0
			,DateActivated = SYSDATETIME()
			,UserName = @pnvUserName
		OUTPUT deleted.OrgResponseCodeXrefId
			,deleted.OrgId
			,deleted.ResponseCodeId
			,deleted.StatusFlag
			,deleted.DateActivated
			,deleted.UserName
		INTO @OrgResponseCodeXref
		WHERE OrgResponseCodeXrefId = @piOrgResponseCodeXrefId;
		--INSERT INTO [archive].[OrgResponseCodeXref](OrgResponseCodeXrefId
		--	,OrgId
		--	,ResponseCodeId
		--	,StatusFlag
		--	,DateActivated
		--	,UserName
		--	,DateArchived
		--)
		--SELECT OrgResponseCodeXrefId
		--	,OrgId
		--	,ResponseCodeId
		--	,StatusFlag
		--	,DateActivated
		--	,UserName
		--	,SYSDATETIME()
		--FROM @OrgResponseCodeXref;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @piOrgResponseCodeXrefId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
	BEGIN
		COMMIT TRANSACTION;
		SELECT @piOrgResponseCodeXrefId = OrgResponseCodeXrefId
		FROM @OrgResponseCodeXref;
	END
END
