USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
   Name: uspOrgCipherXrefInsertOut
   CreatedBy: Larry Dugger
   Date: 2015-05-07
   Descr: This procedure will insert a new record
   Tables: [organization].[OrgCipherXref]
   
   Functions: [error].[uspLogErrorDetailInsertOut]
   History:
      2015-05-07 - LBD - Created
*****************************************************************************************/
ALTER PROCEDURE [organization].[uspOrgCipherXrefInsertOut](
    @piOrgId INT
   ,@piCipherTypeId INT
	,@pnvCipher NVARCHAR(255)
   ,@piStatusFlag INT  
	,@pnvUserName NVARCHAR(100) = 'N/A'
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
   BEGIN TRANSACTION
   BEGIN TRY
      INSERT INTO [organization].[OrgCipherXref]
         OUTPUT inserted.OrgCipherXrefId
            ,inserted.OrgId
            ,inserted.CipherTypeId
            ,inserted.Cipher
            ,inserted.StatusFlag
            ,inserted.DateActivated
            ,inserted.UserName
         INTO @OrgCipherXref
      SELECT @piOrgId
         ,@piCipherTypeId
			,@pnvCipher
         ,@piStatusFlag
         ,SYSDATETIME()
			,@pnvUserName; 
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
      FROM @OrgCipherXref
   END
END
