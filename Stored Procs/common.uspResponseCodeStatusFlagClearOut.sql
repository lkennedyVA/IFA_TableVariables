USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspResponseCodeStatusFlagClearOut
	CreatedBy: Larry Dugger
	Date: 2017-01-27
	Description: This procedure will Deactivate the ResponseCode record
	Tables: [common].[ResponseCode]

	History:
		2017-01-27 - LBD - Created
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [common].[uspResponseCodeStatusFlagClearOut](
	 @pnvUserName NVARCHAR(100) = 'N/A'
	,@piResponseCodeId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @ResponseCode table(
		 ResponseCodeId int
		,Code nvarchar(25)
		,[Name] nvarchar(50)
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
		UPDATE [common].[ResponseCode]
		SET StatusFlag = 0
			,DateActivated = SYSDATETIME()
			,UserName = @pnvUserName
		OUTPUT deleted.ResponseCodeId
			,deleted.Code
			,deleted.[Name]
			,deleted.Descr
			,deleted.StatusFlag
			,deleted.DateActivated
			,deleted.UserName
		INTO @ResponseCode
		WHERE ResponseCodeId = @piResponseCodeId;
		--INSERT INTO [archive].[ResponseCode](ResponseCodeId
		--	,Code
		--	,Name
		--	,Descr
		--	,StatusFlag
		--	,DateActivated
		--	,UserName
		--	,DateArchived
		--)
		--SELECT ResponseCodeId
		--	,Code
		--	,Name
		--	,Descr
		--	,StatusFlag
		--	,DateActivated
		--	,UserName
		--	,SYSDATETIME()
		--FROM @ResponseCode
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
