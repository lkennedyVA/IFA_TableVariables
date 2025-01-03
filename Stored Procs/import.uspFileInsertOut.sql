USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspFileInsertOut
	CreatedBy: Larry Dugger
	Date: 2017-08-18
	Description: This procedure will insert a new record, or return -1 if it already exists
	Tables: [import].[File]
	History:
		2017-08-18 - LBD - Created
*****************************************************************************************/
ALTER PROCEDURE [import].[uspFileInsertOut](
	 @pnvName NVARCHAR(255)
	,@pnvUserName NVARCHAR(100)
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @tblFile table (
		 FileId bigint
		,[Name] nchar(255)
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @biFileId bigint = 0
		,@iErrorDetailId int
		,@iCurrentTransactionLevel int
		,@sSchemaName nvarchar(128) = N'import';

	SET @iCurrentTransactionLevel = @@TRANCOUNT;

	SELECT @biFileId = FileId
	FROM [import].[File]
	WHERE [Name] = @pnvName;

	IF @biFileId = 0
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			INSERT INTO [import].[File]
				OUTPUT inserted.FileId
				,inserted.[Name]
				,inserted.DateActivated
				,inserted.UserName
				INTO @tblFile
			SELECT @pnvName
				,SYSDATETIME()
				,@pnvUserName;
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
				ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @biFileId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT FileId
			FROM @tblFile;
		END
	END
	ELSE
		SELECT @biFileId AS FileId
END
