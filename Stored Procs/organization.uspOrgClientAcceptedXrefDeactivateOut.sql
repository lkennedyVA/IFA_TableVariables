USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspOrgClientAcceptedXrefDeActivateOut
	CreatedBy: Larry Dugger
	Date: 2015-08-04
	Description: This procedure will deactivate a xref record
	Tables: [organization].[OrgClientAcceptedXref]

	History:
		2015-08-04 - LBD - Created
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [organization].[uspOrgClientAcceptedXrefDeactivateOut](
	 @pnvUserName NVARCHAR(100) = 'N/A'
	,@piOrgClientAcceptedXrefId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @OrgClientAcceptedXref table (
		 OrgClientAcceptedXrefId int
		,OrgId int
		,ClientAcceptedId int
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
		UPDATE [organization].[OrgClientAcceptedXref]
		SET StatusFlag = 0
			,DateActivated = SYSDATETIME()
			,UserName = @pnvUserName
		OUTPUT deleted.OrgClientAcceptedXrefId
			,deleted.OrgId
			,deleted.ClientAcceptedId
			,deleted.StatusFlag
			,deleted.DateActivated
			,deleted.UserName
		INTO @OrgClientAcceptedXref
		WHERE OrgClientAcceptedXrefId = @piOrgClientAcceptedXrefId;
		--INSERT INTO [archive].[OrgClientAcceptedXref](OrgClientAcceptedXrefId
		--	,OrgId
		--	,ClientAcceptedId
		--	,StatusFlag
		--	,DateActivated
		--	,UserName
		--	,DateArchived
		--)
		--SELECT OrgClientAcceptedXrefId
		--	,OrgId
		--	,ClientAcceptedId
		--	,StatusFlag
		--	,DateActivated
		--	,UserName
		--	,SYSDATETIME()
		--FROM @OrgClientAcceptedXref;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @piOrgClientAcceptedXrefId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
	BEGIN
		COMMIT TRANSACTION;
		SELECT @piOrgClientAcceptedXrefId = OrgClientAcceptedXrefId
		FROM @OrgClientAcceptedXref;
	END
END
