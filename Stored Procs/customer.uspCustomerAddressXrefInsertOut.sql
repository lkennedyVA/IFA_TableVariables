USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspCustomerAddressXrefInsertOut
	CreatedBy: Larry Dugger
	Date: 2015-05-07
	Description: This procedure will insert a new xref record
	Tables: [customer].[CustomerAddressXref]
	History:
		2015-05-07 - LBD - Created
*****************************************************************************************/
ALTER PROCEDURE [customer].[uspCustomerAddressXrefInsertOut](
    @pbiCustomerId BIGINT
	,@pbiAddressId BIGINT
   ,@piStatusFlag INT
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@piCustomerAddressXrefId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
   DECLARE @CustomerAddressXref table (
		 CustomerAddressXrefId int not null
		,CustomerId bigint not null
		,AddressId bigint not null
		,StatusFlag int not null
		,DateActivated datetime2(7) not null
		,UserName nvarchar(100) not null);
   DECLARE @iErrorDetailId int
      ,@iCurrentTransactionLevel int
      ,@sSchemaName nvarchar(128) = N'customer';
   SET @iCurrentTransactionLevel = @@TRANCOUNT;
   BEGIN TRANSACTION
   BEGIN TRY
      INSERT INTO [customer].[CustomerAddressXref]
         OUTPUT inserted.CustomerAddressXrefId
            ,inserted.CustomerId
            ,inserted.AddressId
            ,inserted.StatusFlag
            ,inserted.DateActivated
            ,inserted.UserName
         INTO @CustomerAddressXref
      SELECT @pbiCustomerId
         ,@pbiAddressId
         ,@piStatusFlag
         ,SYSDATETIME()
			,@pnvUserName;
   END TRY
   BEGIN CATCH
      IF @@TRANCOUNT > 0
         ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @piCustomerAddressXrefId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
		THROW;
   END CATCH;
   IF @@TRANCOUNT > 0
   BEGIN
      COMMIT TRANSACTION;
      SELECT @piCustomerAddressXrefId = CustomerAddressXrefId
      FROM @CustomerAddressXref
   END
END
