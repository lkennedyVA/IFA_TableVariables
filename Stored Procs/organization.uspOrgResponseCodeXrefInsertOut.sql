USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspOrgResponseCodeXrefInsertOut
	CreatedBy: Larry Dugger
	Date: 2017-01-27
	Description: This procedure will insert a new xref record
	Tables: [organization].[OrgResponseCodeXref]
	History:
		2017-01-27 - LBD - Created
*****************************************************************************************/
ALTER PROCEDURE [organization].[uspOrgResponseCodeXrefInsertOut](
	 @piOrgId INT
	,@piResponseCodeId INT
	,@piStatusFlag INT
	,@pnvUserName NVARCHAR(100) = 'N/A'
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
	DECLARE @iErrorDetailId int
		,@iCurrentTransactionLevel int
		,@sSchemaName nvarchar(128) = N'organization';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	BEGIN TRANSACTION
	BEGIN TRY
		INSERT INTO [organization].[OrgResponseCodeXref]
			OUTPUT inserted.OrgResponseCodeXrefId
			,inserted.OrgId
			,inserted.ResponseCodeId
			,inserted.StatusFlag
			,inserted.DateActivated
			,inserted.UserName
			INTO @OrgResponseCodeXref
		SELECT @piOrgId
			,@piResponseCodeId
			,@piStatusFlag
			,SYSDATETIME()
			,@pnvUserName;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @piOrgResponseCodeXrefId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
	END CATCH;
	IF @@TRANCOUNT > 0
	BEGIN
		COMMIT TRANSACTION;
		SELECT @piOrgResponseCodeXrefId = OrgResponseCodeXrefId
		FROM @OrgResponseCodeXref
	END
END

