USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspCustomerStatusFlagSetOut
	CreatedBy: Larry Dugger
	Date: 2015-05-07
	Descr: This procedure will Activate the Customer (Set StatusFlag)
	Tables: [customer].[Customer]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2015-05-07 - LBD - Created
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [customer].[uspCustomerStatusFlagSetOut](
	 @pnvUserName NVARCHAR(100) = 'N/A'
	,@pbiCustomerId BIGINT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @Customer table (
		 CustomerId bigint
		,OrgId int
		,FirstName nvarchar(50)
		,LastName nvarchar(50)
		,DateOfBirth date
		,WorkPhone nvarchar(10)
		,CellPhone nvarchar(10)
		,Email nvarchar(100)
		,DateEnrolled datetime2(7)
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100) 
	);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName nvarchar(128) = N'customer';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [customer].[Customer]
			SET StatusFlag = 1
				,DateActivated = SYSDATETIME()
				,UserName = @pnvUserName
			OUTPUT deleted.CustomerId
				,deleted.OrgId
				,deleted.FirstName
				,deleted.LastName
				,deleted.DateOfBirth
				,deleted.WorkPhone
				,deleted.CellPhone
				,deleted.Email
				,deleted.DateEnrolled
				,deleted.StatusFlag
				,deleted.DateActivated
				,deleted.UserName
			INTO @Customer
			WHERE CustomerId = @pbiCustomerId;
			----Anytime an update occurs we place an original copy in an archive table
			--INSERT INTO [archive].[Customer](CustomerId
			--	,OrgId
			--,FirstName
			--,LastName
			--,DateOfBirth
			--,WorkPhone
			--,CellPhone
			--,Email
			--	,DateEnrolled
			--,StatusFlag
			--,DateActivated
			--	,UserName
			--,DateArchived
			--) 
			--SELECT CustomerId
			--	,OrgId
			--,FirstName
			--,LastName
			--,DateOfBirth
			--,WorkPhone
			--,CellPhone
			--,Email
			--	,DateEnrolled
			--,StatusFlag
			--,DateActivated
			--	,UserName
			--,SYSDATETIME()
			--FROM @Customer
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @pbiCustomerId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @pbiCustomerId = CustomerId
			FROM @Customer;
		END
	END
END
