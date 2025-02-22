USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspOrgCipherXrefStatusFlagClearOut
	CreatedBy: Larry Dugger
	Date: 2015-05-07
	Descr: This procedure will DeActivate the OrgCipherXref (Clear StatusFlag)
	Tables: [organization].[OrgCipherXref]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2015-05-07 - LBD - Created
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [organization].[uspOrgCipherXrefStatusFlagClearOut](
	 @pnvUserName NVARCHAR(100) = 'N/A'
	,@piOrgCipherXrefId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @OrgCipherXref table (
		 OrgCipherXrefId int
		,OrgId int
		,CipherTypeId int
		,Cipher nvarchar(255)
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName nvarchar(128) = N'organization';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [organization].[OrgCipherXref]
			SET StatusFlag = 0
				,DateActivated = SYSDATETIME()
				,UserName = @pnvUserName
			OUTPUT deleted.OrgCipherXrefId
				,deleted.OrgId
				,deleted.CipherTypeId
				,deleted.Cipher
				,deleted.StatusFlag
				,deleted.DateActivated
				,deleted.UserName
			INTO @OrgCipherXref
			WHERE OrgCipherXrefId = @piOrgCipherXrefId;
			----Anytime an update occurs we place an original copy in an archive table
			--INSERT INTO [archive].[OrgCipherXref](OrgCipherXrefId
			--,OrgId
			--,CipherTypeId
			--	,Cipher
			--,StatusFlag
			--,DateActivated
			--	,UserName
			--,DateArchived
			--) 
			--SELECT OrgCipherXrefId
			--,OrgId
			--,CipherTypeId
			--	,Cipher
			--,StatusFlag
			--,DateActivated
			--	,UserName
			--,SYSDATETIME()
			--FROM @OrgCipherXref
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @piOrgCipherXrefId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piOrgCipherXrefId = OrgCipherXrefId
			FROM @OrgCipherXref;
		END
	END
END
