USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspOrgCipherXrefUpdateOut
	CreatedBy: Larry Dugger
	Descr: This procedure will update the OrgCipherXref, it will not update the StatusFlag
	Tables: [organization].[OrgCipherXref]
   
	Functions: [common].[uspLogErrorDetailInsertOut]
	History:
		2015-05-07 - LBD - Created
		2017-06-03 - LBD - Modified, removed use of archive tables
		2017-11-08 - LBD - Modified, added StatusFlag
*****************************************************************************************/
ALTER PROCEDURE [organization].[uspOrgCipherXrefUpdateOut](
	 @piOrgCipherXrefId INT OUTPUT
	,@piOrgId INT = -1
	,@piCipherTypeId INT = -1
	,@piStatusFlag INT = -1
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@pnvCipher NVARCHAR(255) = N''
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
	--Will Not update this xref to an org/Ciphertype already in use
	IF NOT EXISTS(SELECT 'X' 
					FROM [organization].[OrgCipherXref]
					WHERE OrgCipherXrefId <> @piOrgCipherXrefId
						AND OrgId = @piOrgId
						AND CipherTypeId = @piCipherTypeId)
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [organization].[OrgCipherXref]
			SET OrgId = CASE WHEN @piOrgId = -1 THEN OrgId ELSE @piOrgId END
				,CipherTypeId = CASE WHEN @piCipherTypeId = -1 THEN CipherTypeId ELSE @piCipherTypeId END
				,Cipher = CASE WHEN @pnvCipher = N'' THEN Cipher ELSE @pnvCipher END
				,StatusFlag = CASE WHEN @piStatusFlag = -1 THEN StatusFlag ELSE @piStatusFlag END
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
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @piOrgCipherXrefId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
			THROW
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piOrgCipherXrefId = OrgCipherXrefId
			FROM @OrgCipherXref;
		END
	END
	ELSE
		SELECT @piOrgCipherXrefId = -3
END
