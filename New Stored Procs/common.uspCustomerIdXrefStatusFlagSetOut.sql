USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspCustomerIdXrefStatusFlagSetOut
	CreatedBy: Larry Dugger
	Date: 2015-01-07
	Descr: This procedure will Activate the CustomerIdXref (Set StatusFlag)
	Tables: [common].[CustomerIdXref]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2015-01-07 - LBD - Created
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [common].[uspCustomerIdXrefStatusFlagSetOut](
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
			SET StatusFlag = 1
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
			INTO @CustomerIdXref
			WHERE CustomerIdXrefId = @piCustomerIdXrefId;
			----Anytime an update occurs we place an original copy in an archive table
			--INSERT INTO [archive].[CustomerIdXref](CustomerIdXrefId
			--	,CustomerId
			--	,IdTypeId
			--	,IdStateId
			--	,IdEncrypted
			--	,IdMac
			--	,Last4
			--	,OrgId
			--	,StatusFlag
			--	,DateActivated
			--	,UserName
			--,DateArchived
			--) 
			--SELECT CustomerIdXrefId
			--	,CustomerId
			--	,IdTypeId
			--	,IdStateId
			--	,IdEncrypted
			--	,IdMac
			--	,Last4
			--	,OrgId
			--	,StatusFlag
			--	,DateActivated
			--	,UserName
			--,SYSDATETIME()
			--FROM @CustomerIdXref
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
