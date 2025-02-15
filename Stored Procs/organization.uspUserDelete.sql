USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspUserDelete
	CreatedBy: Larry Dugger
	Description: This procedure will delete a new record
	Tables: [organization].[User]

	History:
		2015-05-07 - LBD - Created
		2017-06-03 - LBD - Modified, removed use of archive tables
		2017-11-14 - LBD - Modified, increased the size of the Pwd field 
			from 100 to 255 varbinary
*****************************************************************************************/
ALTER PROCEDURE [organization].[uspUserDelete](
	 @pnvUserName NVARCHAR(100) = 'N/A'
	,@piUserId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	drop table if exists #UserDelete
	create table #UserDelete(
		 UserId bigint
		,OrgId int
		,FirstName nvarchar(50)
		,LastName nvarchar(50)
		,LoginName nchar(10)
		,Pwd varbinary(255)
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @nvNumber nvarchar(50) 
		,@iErrorDetailId int
		,@iCurrentTransactionLevel int
		,@sSchemaName nvarchar(128) = N'user';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	BEGIN TRANSACTION
	BEGIN TRY
		UPDATE [organization].[User]
		SET StatusFlag = 0
			,DateActivated = SYSDATETIME()
			,UserName = @pnvUserName
		OUTPUT deleted.UserId
			,deleted.OrgId
			,deleted.FirstName
			,deleted.LastName
			,deleted.LoginName
			,deleted.Pwd
			,deleted.StatusFlag
			,deleted.DateActivated
			,deleted.UserName
		INTO #UserDelete
		WHERE UserId = @piUserId;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @piUserId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
	BEGIN
		COMMIT TRANSACTION;
		SELECT @piUserId = UserId
		FROM #UserDelete;
	END
END
