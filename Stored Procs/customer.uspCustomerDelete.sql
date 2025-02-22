USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspCustomerDelete
	CreatedBy: Larry Dugger
	Date: 2015-05-07
	Description: This procedure will delete a new record
	Tables: [customer].[Customer]

	History:
		2015-05-07 - LBD - Created
		2017-06-03 - LBD - Modified, removed use of archive tables
		2025-01-13 - LXK - Replaced table variables with local temp tables
*****************************************************************************************/
ALTER PROCEDURE [customer].[uspCustomerDelete](
	 @pnvUserName NVARCHAR(100) = 'N/A'
	,@piCustomerId BIGINT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	drop table if exists #CustomerDelete
	DECLARE #CustomerDelete table (
		 CustomerId bigint
		,FirstName nvarchar(50)
		,LastName nvarchar(50)
		,DateOfBirth date
		,WorkPhone nvarchar(10)
		,CellPhone nvarchar(10)
		,Email nvarchar(100)
		,DateEnrolled date
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @nvNumber nvarchar(50) 
		,@iErrorDetailId int
		,@iCurrentTransactionLevel int
		,@sSchemaName nvarchar(128) = N'customer';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	BEGIN TRANSACTION
	BEGIN TRY
		UPDATE [customer].[Customer]
		SET StatusFlag = 0
			,DateActivated = SYSDATETIME()
			,UserName = @pnvUserName
		OUTPUT deleted.CustomerId
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
		INTO #CustomerDelete
		WHERE CustomerId = @piCustomerId;
		----Anytime an update occurs we place a copy in an archive table
		--INSERT INTO [archive].[Customer](CustomerId
		--	,FirstName
		--	,LastName
		--	,DateOfBirth
		--	,WorkPhone
		--	,CellPhone
		--	,Email
		--	,DateEnrolled
		--	,StatusFlag
		--	,DateActivated
		--	,UserName
		--	,DateArchived)
		--SELECT CustomerId
		--	,FirstName
		--	,LastName
		--	,DateOfBirth
		--	,WorkPhone
		--	,CellPhone
		--	,Email
		--	,DateEnrolled
		--	,StatusFlag
		--	,DateActivated
		--	,UserName
		--	,SYSDATETIME()
		--FROM #CustomerDelete
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @piCustomerId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
	BEGIN
		COMMIT TRANSACTION;
		SELECT @piCustomerId = CustomerId
		FROM #CustomerDelete;
	END
END
