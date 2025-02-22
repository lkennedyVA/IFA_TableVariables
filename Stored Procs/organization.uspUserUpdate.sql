USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspUserUpdate
	CreatedBy: Larry Dugger
	Description: This procedure will insert a new record
	Tables: [organization].[user]

	History:
		2015-05-07 - LBD - Created
		2017-01-25 - LBD - Modified, to operate correctly
		2017-06-03 - LBD - Modified, removed use of archive tables
		2017-11-14 - LBD - Modified, increased the size of the Pwd field 
			from 100 to 255 varbinary
*****************************************************************************************/
ALTER PROCEDURE [organization].[uspUserUpdate](
	 @piOrgId int = -1
	,@pnvFirstName NVARCHAR(50) = N''
	,@pnvLastName NVARCHAR(50) = N''
	,@pnvLoginName NVARCHAR(50) = N''
	,@pnvPwd NVARCHAR(50) = N''
	,@piStatusFlag INT = -1
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@piUserId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	drop table if exists #UserUpdate
	create table #UserUpdate(
		 UserId int
		,OrgId int
		,FirstName nvarchar(50)
		,LastName nvarchar(50)
		,LoginName nvarchar(50)
		,Pwd varbinary(255)
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @vbEncrypted varbinary(255) = 0x 
		,@iErrorDetailId int
		,@iCurrentTransactionLevel int
		,@sSchemaName nvarchar(128) = N'organization';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	IF @pnvPwd <> N''
		--EXECUTE [ifa].[uspEncryptSymAES256] @pnvPwd, @vbEncrypted OUTPUT;
	BEGIN
		OPEN SYMMETRIC KEY VALIDSYMKEY DECRYPTION BY ASYMMETRIC KEY [VALIDASYMKEY]; 
		SET @vbEncrypted = ENCRYPTBYKEY(KEY_GUID('VALIDSYMKEY'),@pnvPwd);
		CLOSE SYMMETRIC KEY VALIDSYMKEY;
	END
	BEGIN TRANSACTION
	BEGIN TRY
		UPDATE [organization].[user]
		SET FirstName =  CASE WHEN @pnvFirstName = N'' THEN FirstName ELSE @pnvFirstName END
			,LastName =  CASE WHEN @pnvLastName = N'' THEN LastName ELSE @pnvLastName END
			,LoginName =  CASE WHEN @pnvLoginName = N'' THEN LoginName ELSE @pnvLoginName END
			,Pwd = CASE WHEN @vbEncrypted <> 0x THEN @vbEncrypted ELSE Pwd END
			,StatusFlag = ISNULL(CASE WHEN @piStatusFlag <> -1 THEN @piStatusFlag ELSE StatusFlag END,StatusFlag)
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
		INTO #UserUpdate
		WHERE OrgId = @piOrgId
			AND UserId = @piUserId;
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
		FROM #UserUpdate;
	END
END
