USE [IFA]
GO
/****** Object:  StoredProcedure [common].[uspCipherTypeStatusFlagClearOut]    Script Date: 1/2/2025 7:42:06 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspCipherTypeStatusFlagClearOut
	CreatedBy: Larry Dugger
	Date: 2015-05-07
	Description: This procedure will Deactivate the CipherType record
	Tables: [common].[CipherType]

	History:
		2015-05-07 - LBD - Created
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [common].[uspCipherTypeStatusFlagClearOut](
	 @pnvUserName NVARCHAR(100) = 'N/A'
	,@piCipherTypeId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @CipherType table(
		 CipherTypeId int
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
		UPDATE [common].[CipherType]
		SET StatusFlag = 0
			,DateActivated = SYSDATETIME()
			,UserName = @pnvUserName
		OUTPUT deleted.CipherTypeId
			,deleted.Code
			,deleted.[Name]
			,deleted.Descr
			,deleted.DisplayOrder
			,deleted.StatusFlag
			,deleted.DateActivated
			,deleted.UserName
		INTO @CipherType
		WHERE CipherTypeId = @piCipherTypeId;
		--INSERT INTO [archive].[CipherType](CipherTypeId
		--	,Code
		--	,Name
		--	,Descr
		--	,DisplayOrder
		--	,StatusFlag
		--	,DateActivated
		--	,UserName
		--	,DateArchived
		--)
		--SELECT CipherTypeId
		--	,Code
		--	,Name
		--	,Descr
		--	,DisplayOrder
		--	,StatusFlag
		--	,DateActivated
		--	,UserName
		--	,SYSDATETIME()
		--FROM @CipherType
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @piCipherTypeId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
	BEGIN
		COMMIT TRANSACTION;
		SELECT @piCipherTypeId = CipherTypeId
		FROM @CipherType;
	END
END
