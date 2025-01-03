USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspExceptionTypeInsert
	CreatedBy: Larry Dugger
	Date: 2017-08-18
	Description: This procedure will insert a new record
	Tables: [import].[ExceptionType]
	History:
		2017-08-18 - LBD - Created
*****************************************************************************************/
ALTER PROCEDURE [import].[uspExceptionTypeInsert](
		@pnvCode NVARCHAR(25)
	,@pnvName NVARCHAR(50)
	,@pnvDescr NVARCHAR(255)
	,@piDisplayOrder INT
	,@piStatusFlag INT
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@piExceptionTypeId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @tblExceptionType table (
		ExceptionTypeId int
		,Code nvarchar(25)
		,[Name] nvarchar(50)
		,Descr nvarchar(255)
		,DisplayOrder int
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @iErrorDetailId int
		,@iCurrentTransactionLevel int
		,@sSchemaName nvarchar(128) = N'common';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	BEGIN TRANSACTION
	BEGIN TRY
		INSERT INTO [import].[ExceptionType]
			OUTPUT inserted.ExceptionTypeId
			,inserted.Code
			,inserted.[Name]
			,inserted.Descr
			,inserted.DisplayOrder
			,inserted.StatusFlag
			,inserted.DateActivated 
			,inserted.UserName
			INTO @tblExceptionType
		SELECT @pnvCode
			,@pnvName
			,@pnvDescr
			,@piDisplayOrder
			,@piStatusFlag
			,SYSDATETIME()
			,@pnvUserName;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @piExceptionTypeId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
	BEGIN
		COMMIT TRANSACTION;
		SELECT @piExceptionTypeId = ExceptionTypeId
		FROM @tblExceptionType;
	END
END
