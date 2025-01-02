USE [IFA]
GO
/****** Object:  StoredProcedure [common].[uspAccountTypeStatusFlagSetOut]    Script Date: 1/2/2025 6:10:46 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspAccountTypeStatusFlagSetOut
	CreatedBy: Larry Dugger
	Date: 2015-05-07
	Description: This procedure will Activate the AccountType record
	Tables: [common].[AccountType]

	History:
		2015-05-07 - LBD - Created
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [common].[uspAccountTypeStatusFlagSetOut](
	 @pnvUserName NVARCHAR(100) = 'N/A'
	,@piAccountTypeId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @AccountType table(
		 AccountTypeId int
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
		UPDATE [common].[AccountType]
		SET StatusFlag = 1
			,DateActivated = SYSDATETIME()
			,UserName = @pnvUserName  
		OUTPUT deleted.AccountTypeId
			,deleted.Code
			,deleted.[Name]
			,deleted.Descr
			,deleted.DisplayOrder
			,deleted.StatusFlag
			,deleted.DateActivated
			,deleted.UserName
		INTO @AccountType
		WHERE AccountTypeId = @piAccountTypeId;
		--INSERT INTO [archive].[AccountType](AccountTypeId
		--	,Code
		--	,Name
		--	,Descr
		--	,DisplayOrder
		--	,StatusFlag
		--	,DateActivated
		--	,UserName
		--	,DateArchived
		--)
		--SELECT AccountTypeId
		--	,Code
		--	,Name
		--	,Descr
		--	,DisplayOrder
		--	,StatusFlag
		--	,DateActivated
		--	,UserName
		--	,SYSDATETIME()
		--FROM @AccountType
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @piAccountTypeId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
	BEGIN
		COMMIT TRANSACTION;
		SELECT @piAccountTypeId = AccountTypeId
		FROM @AccountType;
	END
END
