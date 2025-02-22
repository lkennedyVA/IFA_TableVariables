USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspVerifyAndImportOfac
	CreatedBy: Larry Dugger
	Date: 2017-08-25
	Description: This procedure will verify each of the utility tables and then 
		replace the destination tables, if there are any verification issues, it will
		exit with an error.

	Procedures: [dbo].[uspVerifyOfacSdn]
		,[dbo].[uspVerifyOfacSdnAdd]
		,[dbo].[uspVerifyOfacSdnAlt]
		,[dbo].[uspVerifyOfacPrime]
		,[dbo].[uspVerifyOfacConsAdd]
		,[dbo].[uspVerifyOfacConsAlt]
		,[dbo].[uspImportOfac] 

	History:
		2017-08-25 - LBD - Created
*****************************************************************************************/
ALTER PROCEDURE [dbo].[uspVerifyAndImportOfac]
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @iErrorDetailId int = 0
		,@sSchemaName sysname= N'utility';

	BEGIN TRY
		--Verify 6 tables
		EXECUTE [dbo].[uspVerifyOfacSdn];
		IF @iErrorDetailId = 0
			EXECUTE [dbo].[uspVerifyOfacSdnAdd];
		IF @iErrorDetailId = 0
			EXECUTE [dbo].[uspVerifyOfacSdnAlt];
		IF @iErrorDetailId = 0
			EXECUTE [dbo].[uspVerifyOfacPrim];
		IF @iErrorDetailId = 0
			EXECUTE [dbo].[uspVerifyOfacConsAdd];
		IF @iErrorDetailId = 0
			EXECUTE [dbo].[uspVerifyOfacConsAlt];
		IF @iErrorDetailId = 0
			EXECUTE [dbo].[uspImportOfac];
		IF @iErrorDetailId <> 0
		BEGIN
			RAISERROR ('OFAC Verify or Import Error, Import halted', 16, 1);
			RETURN
		END
	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		THROW 
	END CATCH
END
