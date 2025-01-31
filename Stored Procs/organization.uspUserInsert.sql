USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspUserInsert
	CreatedBy: Larry Dugger
	Description: This procedure will insert a new record
	Tables: [organization].[user]
	History:
		2015-05-07 - LBD - Created
		2017-11-14 - LBD - Modified, increased the size of the Pwd field 
			from 100 to 255 varbinary
		2019-11-25 - LBD - Added EmailAddress field
*****************************************************************************************/
ALTER PROCEDURE [organization].[uspUserInsert](
	 @piOrgId INT
	,@pnvFirstName NVARCHAR(50)
	,@pnvLastName NVARCHAR(50)
	,@pnvLoginName NVARCHAR(50)
	,@pnvPwd NVARCHAR(50)
	,@piStatusFlag INT
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@pnvEmailAddress NVARCHAR(100) = NULL
	,@piUserId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	drop table if exists #UserInsert
	create table #UserInsert(
		 UserId int
		,OrgId int
		,FirstName nvarchar(50)
		,LastName nvarchar(50)
		,LoginName nvarchar(50)
		,Pwd varbinary(255)
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
		,EmailAddress nvarchar(100)
	);
	DECLARE @vbEncrypted varbinary(100) 
		,@iErrorDetailId int
		,@iCurrentTransactionLevel int
		,@sSchemaName nvarchar(128) = N'organization';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	BEGIN TRANSACTION
	BEGIN TRY
		OPEN SYMMETRIC KEY VALIDSYMKEY DECRYPTION BY ASYMMETRIC KEY [VALIDASYMKEY]; 

		INSERT INTO [organization].[user]
			OUTPUT inserted.UserId
				,inserted.OrgId 
				,inserted.FirstName
				,inserted.LastName
				,inserted.LoginName
				,inserted.Pwd
				,inserted.StatusFlag
				,inserted.DateActivated
				,inserted.UserName
				,inserted.EmailAddress
			INTO #UserInsert
		SELECT @piOrgId
			,@pnvFirstName
			,@pnvLastName
			,@pnvLoginName
			,ENCRYPTBYKEY(KEY_GUID('VALIDSYMKEY'),@pnvPwd)--@vbEncrypted
			,@piStatusFlag
			,SYSDATETIME()
			,@pnvUserName
			,@pnvEmailAddress;
		CLOSE SYMMETRIC KEY VALIDSYMKEY;
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
		FROM #UserInsert;
	END
END

