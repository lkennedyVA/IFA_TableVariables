USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspProcessTypeInsert
	CreatedBy: Larry Dugger
	Date: 2016-07-11
	Description: This procedure will insert a new record
	Tables: [common].[ProcessType]
	History:
		2016-07-11 - LBD - Created
*****************************************************************************************/
ALTER PROCEDURE [common].[uspProcessTypeInsert](
	 @pnvCode NVARCHAR(25)
	,@pnvName NVARCHAR(50)
	,@pnvDescr NVARCHAR(255)
	,@piDisplayOrder INT
	,@piStatusFlag INT
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@piProcessTypeId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @ProcessType table (
		ProcessTypeId int
		,Code nvarchar(25)
		,Name nvarchar(50)
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
		INSERT INTO [common].[ProcessType]
			OUTPUT inserted.ProcessTypeId
			,inserted.Code
			,inserted.Name
			,inserted.Descr
			,inserted.DisplayOrder
			,inserted.StatusFlag
			,inserted.DateActivated 
			,inserted.UserName
			INTO @ProcessType
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
		SET @piProcessTypeId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
	BEGIN
		COMMIT TRANSACTION;
		SELECT @piProcessTypeId = ProcessTypeId
		FROM @ProcessType;
	END
END
