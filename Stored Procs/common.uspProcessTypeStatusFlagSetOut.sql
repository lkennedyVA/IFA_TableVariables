USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspProcessTypeStatusFlagSetOut
	CreatedBy: Larry Dugger
	Date: 2016-07-11
	Description: This procedure will Activate the ProcessType record
	Tables: [common].[ProcessType]

	History:
		2016-07-11 - LBD - Created
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [common].[uspProcessTypeStatusFlagSetOut](
	 @pnvUserName NVARCHAR(100) = 'N/A'
	,@piProcessTypeId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @ProcessType table(
		 ProcessTypeId int
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
		UPDATE [common].[ProcessType]
		SET StatusFlag = 1
			,DateActivated = SYSDATETIME()
			,UserName = @pnvUserName
		OUTPUT deleted.ProcessTypeId
			,deleted.Code
			,deleted.[Name]
			,deleted.Descr
			,deleted.DisplayOrder
			,deleted.StatusFlag
			,deleted.DateActivated
			,deleted.UserName
		INTO @ProcessType
		WHERE ProcessTypeId = @piProcessTypeId;
		--INSERT INTO [archive].[ProcessType](ProcessTypeId
		--	,Code
		--	,Name
		--	,Descr
		--	,DisplayOrder
		--	,StatusFlag
		--	,DateActivated
		--	,UserName
		--	,DateArchived
		--)
		--SELECT ProcessTypeId
		--	,Code
		--	,Name
		--	,Descr
		--	,DisplayOrder
		--	,StatusFlag
		--	,DateActivated
		--	,UserName
		--	,SYSDATETIME()
		--FROM @ProcessType
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
