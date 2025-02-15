USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspAccountInsertOut
	CreatedBy: Larry Dugger
	Date: 2015-05-07
	Descr: This procedure will insert new record(s), update old record(s)
	Tables: [ifa].[Account]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2015-05-07 - LBD - Created
		2017-08-21 - LBD - Modified, adjusted output message to new V106 exceptions
		2018-07-17 - LBD - Modified, will not insert duplicates
*****************************************************************************************/
ALTER PROCEDURE [customer].[uspAccountInsertOut](
	 @pbiCustomerId BIGINT
	,@pnvBankAccountType NVARCHAR(25)
	,@pncBankRoutingNumber NCHAR(9)
	,@pnvBankAccountNumber NVARCHAR(50)
	,@piStatusFlag INT
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@pbiAccountId BIGINT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @Account table (
			AccountId bigint
		,AccountTypeId int
		,CustomerId bigint
		,RoutingNumber nchar(9)
		,AccountNumber nvarchar(50)
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
		);
	DECLARE @iErrorDetailId int
		,@iCurrentTransactionLevel int
		,@sSchemaName nvarchar(128)
		,@iAccountTypeId int = [common].[ufnAccountType](@pnvBankAccountType)--'C','S','Unknown'
		,@nvBankAccountNumber nvarchar(50) = [common].[ufnCleanAccountNumber](@pnvBankAccountNumber)
	SET @sSchemaName = N'customer';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	IF @iAccountTypeId < 0
	BEGIN
		RAISERROR ('Invalid Bank Account Type', 16, 1, @pnvBankAccountType);
		RETURN
	END
	SELECT @pbiAccountId = AccountId
	FROM [customer].[Account]
	WHERE CustomerId = @pbiCustomerId
		AND AccountTypeId = @iAccountTypeId
		AND RoutingNumber = @pncBankRoutingNumber
		AND AccountNumber = @nvBankAccountNumber
		AND StatusFlag = 1;
	IF ISNULL(@pbiAccountId,-1) = -1
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			--INSERT What is new
			INSERT INTO [customer].[Account]
				OUTPUT inserted.AccountId
					,inserted.AccountTypeId
					,inserted.CustomerId
					,inserted.RoutingNumber
					,inserted.AccountNumber
					,inserted.StatusFlag
					,inserted.DateActivated
					,inserted.UserName
				INTO @Account
			SELECT @iAccountTypeId
				,@pbiCustomerId
				,@pncBankRoutingNumber
				,@nvBankAccountNumber
				,@piStatusFlag
				,SYSDATETIME()
				,@pnvUserName;
	 
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
				ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @pbiAccountId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
			THROW;
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @pbiAccountId = AccountId from @Account
		END
	END
END
