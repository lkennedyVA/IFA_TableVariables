USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspCustomerInsertOut
	CreatedBy: Larry Dugger
	Date: 2015-05-26
	Descr: This procedure will insert a new record, Prior to calling we verify this customer
		doesn't exist 
	Tables: [customer].[Customer]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2015-05-26 - LBD - Created
		2020-04-15 - LBD - Filter out dangerous characters from First and Last name
*****************************************************************************************/
ALTER   PROCEDURE [customer].[uspCustomerInsertOut](
	@piOrgId INT
	,@pnvFirstName NVARCHAR(50)
	,@pnvLastName NVARCHAR(50)
	,@pdDateOfBirth DATE
	,@pnvWorkPhone NVARCHAR(10)
	,@pnvCellPhone NVARCHAR(10)
	,@pnvEmail NVARCHAR(100)
	,@piStatusFlag INT 
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@pbiCustomerId BIGINT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @Customer table (
		CustomerId bigint not null
		,OrgId int not null
		,FirstName nvarchar(50) null
		,LastName nvarchar(50) null
		,DateOfBirth date null
		,WorkPhone nvarchar(10) null
		,CellPhone nvarchar(10) null
		,Email nvarchar(100) null
		,DateEnrolled datetime2(7) not null
		,StatusFlag int not null
		,DateActivated datetime2(7) not null
		,UserName nvarchar(100)
		);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName nvarchar(128) = N'customer';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	SET @pbiCustomerId = 0;
	BEGIN TRANSACTION
	BEGIN TRY
		INSERT INTO [customer].[Customer]
			OUTPUT inserted.CustomerId
				,inserted.OrgId
				,inserted.FirstName
				,inserted.LastName
				,inserted.DateOfBirth
				,inserted.WorkPhone
				,inserted.CellPhone
				,inserted.Email
				,inserted.DateEnrolled
				,inserted.StatusFlag
				,inserted.DateActivated
				,inserted.UserName
			INTO @Customer
		SELECT @piOrgId
			,[common].[ufnDeUnicode](@pnvFirstName)
			,[common].[ufnDeUnicode](@pnvLastName)
			,@pdDateOfBirth
			,@pnvWorkPhone
			,@pnvCellPhone
			,@pnvEmail
			,SYSDATETIME()
			,@piStatusFlag
			,SYSDATETIME()
			,@pnvUserName;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @pbiCustomerId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
		THROW
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
	BEGIN
		COMMIT TRANSACTION;
		SELECT @pbiCustomerId = CustomerId
		FROM @Customer;
	END
END
