USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspCustomerIdXrefStatusFlagClearOut
	CreatedBy: Larry Dugger
	Descr: This procedure will DeActivate the CustomerIdXref (Clear StatusFlag)
	Tables: [customer].[CustomerIdXref]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2019-11-13 - LBD - Created, using [common].[uyspCustomerIdXrefStatusFlagClearOut]
			as a template
*****************************************************************************************/
ALTER   PROCEDURE [customer].[uspCustomerIdXrefStatusFlagClearOut](
	 @pnvUserName NVARCHAR(100) = 'N/A'
	,@piCustomerIdXrefId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @CustomerIdXref table(
		 CustomerIdXrefId bigint
		,CustomerId bigint
		,IdTypeId int
		,IdStateId int
		,IdEncrypted varbinary(250)
		,IdMac varbinary(50)
		,Last4 nvarchar(4)
		,OrgId int
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
		,IdMac64 binary(64)
	);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName nvarchar(128);
	SET @sSchemaName = N'common';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [customer].[CustomerIdXref]
			SET StatusFlag = 0
				,DateActivated = SYSDATETIME()
				,UserName = @pnvUserName
			OUTPUT deleted.CustomerIdXrefId
				,deleted.CustomerId
				,deleted.IdTypeId
				,deleted.IdStateId
				,deleted.IdEncrypted
				,deleted.IdMac
				,deleted.Last4
				,deleted.OrgId
				,deleted.StatusFlag
				,deleted.DateActivated
				,deleted.UserName
				,deleted.IdMac64
			INTO @CustomerIdXref
			WHERE CustomerIdXrefId = @piCustomerIdXrefId;
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @piCustomerIdXrefId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piCustomerIdXrefId = CustomerIdXrefId
			FROM @CustomerIdXref;
		END
	END
END
