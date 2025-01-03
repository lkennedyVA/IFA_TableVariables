USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspResponseCodeInsert
	CreatedBy: Larry Dugger
	Date: 2017-01-27
	Description: This procedure will insert a new record
	Tables: [common].[ResponseCode]
	History:
		2017-01-27 - LBD - Created
*****************************************************************************************/
ALTER PROCEDURE [common].[uspResponseCodeInsert](
	 @pnvCode NVARCHAR(25)
	,@pnvName NVARCHAR(50)
	,@pnvDescr NVARCHAR(255)
	,@piStatusFlag INT
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@piResponseCodeId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @ResponseCode table (
			ResponseCodeId int
		,Code nvarchar(25)
		,Name nvarchar(50)
		,Descr nvarchar(255)
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
		INSERT INTO [common].[ResponseCode]
			OUTPUT inserted.ResponseCodeId
			,inserted.Code
			,inserted.Name
			,inserted.Descr
			,inserted.StatusFlag
			,inserted.DateActivated 
			,inserted.UserName
			INTO @ResponseCode
		SELECT @pnvCode
			,@pnvName
			,@pnvDescr
			,@piStatusFlag
			,SYSDATETIME()
			,@pnvUserName;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @piResponseCodeId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
	BEGIN
		COMMIT TRANSACTION;
		SELECT @piResponseCodeId = ResponseCodeId
		FROM @ResponseCode;
	END
END
