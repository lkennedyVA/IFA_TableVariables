USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspCustomerAddressXrefDeActivateOut
	CreatedBy: Larry Dugger
	Date: 2015-05-07
	Description: This procedure will deactivate a xref record
	Tables: [customer].[CustomerAddressXref]

	History:
		2015-05-07 - LBD - Created
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [customer].[uspCustomerAddressXrefDeactivateOut](
	 @pnvUserName NVARCHAR(100) = 'N/A'
	,@piCustomerAddressXrefId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @CustomerAddressXref table (
		 CustomerAddressXrefId int
		,CustomerId bigint
		,AddressId bigint
		,StatusFlag int
		,DateActivated datetime
		,UserName nvarchar(100)
	);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName nvarchar(128);
	SET @sSchemaName = N'customer';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	BEGIN TRANSACTION
	BEGIN TRY
		UPDATE [customer].[CustomerAddressXref]
		SET StatusFlag = 0
			,DateActivated = SYSDATETIME()
			,UserName = @pnvUserName
		OUTPUT deleted.CustomerAddressXrefId
			,deleted.CustomerId
			,deleted.AddressId
			,deleted.StatusFlag
			,deleted.DateActivated
			,deleted.UserName
		INTO @CustomerAddressXref
		WHERE CustomerAddressXrefId = @piCustomerAddressXrefId;
		--INSERT INTO [archive].[CustomerAddressXref](CustomerAddressXrefId
		--	,CustomerId
		--	,AddressId
		--	,StatusFlag
		--	,DateActivated
		--	,UserName
		--	,DateArchived
		--)
		--SELECT CustomerAddressXrefId
		--	,CustomerId
		--	,AddressId
		--	,StatusFlag
		--	,DateActivated
		--	,UserName
		--	,SYSDATETIME()
		--FROM @CustomerAddressXref;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @piCustomerAddressXrefId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
	BEGIN
		COMMIT TRANSACTION;
		SELECT @piCustomerAddressXrefId = CustomerAddressXrefId
		FROM @CustomerAddressXref;
	END
END
