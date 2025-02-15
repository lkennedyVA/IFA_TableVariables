USE [IFA]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspMiscTypeStatusFlagSetOut
	CreatedBy: Larry Dugger
	Date: 2015-05-07
	Description: This procedure will Activate the MiscType record
	Tables: [common].[MiscType]

	History:
		2015-05-07 - LBD - Created
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [common].[uspMiscTypeStatusFlagSetOut](
	 @pnvUserName NVARCHAR(100) = 'N/A' 
	,@piMiscTypeId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @MiscType table(
		 MiscTypeId int
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
		UPDATE [common].[MiscType]
		SET StatusFlag = 1
			,DateActivated = SYSDATETIME()
			,UserName = @pnvUserName
		OUTPUT deleted.MiscTypeId
			,deleted.Code
			,deleted.[Name]
			,deleted.Descr
			,deleted.DisplayOrder
			,deleted.StatusFlag
			,deleted.DateActivated
			,deleted.UserName
		INTO @MiscType
		WHERE MiscTypeId = @piMiscTypeId;
		--INSERT INTO [archive].[MiscType](MiscTypeId
		--	,Code
		--	,Name
		--	,Descr
		--	,DisplayOrder
		--	,StatusFlag
		--	,DateActivated
		--	,UserName
		--	,DateArchived
		--)
		--SELECT MiscTypeId
		--	,Code
		--	,Name
		--	,Descr
		--	,DisplayOrder
		--	,StatusFlag
		--	,DateActivated
		--	,UserName
		--	,SYSDATETIME()
		--FROM @MiscType
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @piMiscTypeId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
	BEGIN
		COMMIT TRANSACTION;
		SELECT @piMiscTypeId = MiscTypeId
		FROM @MiscType;
	END
END
