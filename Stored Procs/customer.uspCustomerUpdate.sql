USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspCustomerUpdate
	CreatedBy: Larry Dugger
	Date: 2015-05-07
	Description: This procedure will insert a new record
	Tables: [customer].[Customer]

	History:
		2015-05-07 - LBD - Created
		2017-06-03 - LBD - Modified, removed use of archive tables
		2025-01-13 - LXK - Replaced table variables with local temp tables
*****************************************************************************************/
ALTER PROCEDURE [customer].[uspCustomerUpdate](
	 @pnvFirstName NVARCHAR(50) = N''
	,@pnvLastName NVARCHAR(50) = N''
	,@pdDateOfBirth DATE = NULL
	,@pnvWorkPhone NVARCHAR(10) = N''
	,@pnvCellPhone NVARCHAR(10) = N''
	,@pnvEmail NVARCHAR(100) = N''
	,@piStatusFlag INT = -1
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@pbiCustomerId BIGINT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	drop table if exists #CustomerUpdate
	DECLARE #CustomerUpdate table (
		 CustomerId bigint not null
		,OrgId int not null
		,FirstName nvarchar(50) null
		,LastName nvarchar(50) null
		,DateOfBirth date null
		,WorkPhone nvarchar(10) null
		,CellPhone nvarchar(10) null
		,Email nvarchar(100) null
		,DateEnrolled date null
		,StatusFlag int not null
		,DateActivated datetime2(7) not null
		,UserName nvarchar(100)  not null);
	DECLARE @nvNumber nvarchar(50) 
		,@iErrorDetailId int
		,@iCurrentTransactionLevel int 
		,@sSchemaName nvarchar(128) = N'customer';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	BEGIN TRANSACTION
	BEGIN TRY
		UPDATE [customer].[Customer]
		SET FirstName =  CASE WHEN @pnvFirstName = N'' THEN FirstName ELSE @pnvFirstName END
			,LastName =  CASE WHEN @pnvLastName = N'' THEN LastName ELSE @pnvLastName END
			,DateOfBirth =  CASE WHEN @pdDateOfBirth IS NULL THEN DateOfBirth ELSE @pdDateOfBirth END
			,WorkPhone =  CASE WHEN @pnvWorkPhone = N'' THEN WorkPhone ELSE @pnvWorkPhone END
			,CellPhone =  CASE WHEN @pnvCellPhone = N'' THEN CellPhone ELSE @pnvCellPhone END
			,Email =  CASE WHEN @pnvEmail = N'' THEN Email ELSE @pnvEmail END
			,StatusFlag = ISNULL(CASE WHEN @piStatusFlag <> -1 THEN @piStatusFlag ELSE StatusFlag END,StatusFlag)
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
		INTO #CustomerUpdate
		WHERE CustomerId = @pbiCustomerId;
		----Anytime an update occurs we place a copy in an archive table
		--INSERT INTO [archive].[Customer](CustomerId
		--	,OrgId
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
		--	,OrgId
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
		--FROM #CustomerUpdate
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
		FROM #CustomerUpdate;
	END
END
