USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspValidCodeStatusFlagSetOut
	CreatedBy: Larry Dugger
	Date: 2015-05-07
	Description: This procedure will Activate the ValidCode record
	Tables: [common].[ValidCode]

	History:
		2015-05-07 - LBD - Created
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [common].[uspValidCodeStatusFlagSetOut](
	 @pnvUserName NVARCHAR(100) = 'N/A'
	,@piValidCodeId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @ValidCode table(
		 ValidCodeId int
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
		UPDATE [common].[ValidCode]
		SET StatusFlag = 1
			,DateActivated = SYSDATETIME()
			,UserName = @pnvUserName
		OUTPUT deleted.ValidCodeId
			,deleted.Code
			,deleted.[Name]
			,deleted.Descr
			,deleted.DisplayOrder
			,deleted.StatusFlag
			,deleted.DateActivated
			,deleted.UserName
		INTO @ValidCode
		WHERE ValidCodeId = @piValidCodeId;
		--INSERT INTO [archive].[ValidCode](ValidCodeId
		--	,Code
		--	,Name
		--	,Descr
		--	,DisplayOrder
		--	,StatusFlag
		--	,DateActivated
		--	,UserName
		--	,DateArchived
		--)
		--SELECT ValidCodeId
		--	,Code
		--	,Name
		--	,Descr
		--	,DisplayOrder
		--	,StatusFlag
		--	,DateActivated
		--	,UserName
		--	,SYSDATETIME()
		--FROM @ValidCode
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @piValidCodeId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
	BEGIN
		COMMIT TRANSACTION;
		SELECT @piValidCodeId = ValidCodeId
		FROM @ValidCode;
	END
END
