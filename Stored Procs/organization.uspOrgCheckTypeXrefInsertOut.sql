USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
   Name: uspOrgCheckTypeXrefInsertOut
   CreatedBy: Larry Dugger
   Date: 2015-05-07
   Descr: This procedure will insert a new record
   Tables: [organization].[OrgCheckTypeXref]
   
   Functions: [error].[uspLogErrorDetailInsertOut]
   History:
      2015-05-07 - LBD - Created
*****************************************************************************************/
ALTER PROCEDURE [organization].[uspOrgCheckTypeXrefInsertOut](
    @piOrgId INT
   ,@piCheckTypeId INT
   ,@piStatusFlag INT  
	,@pnvUserName NVARCHAR(100) = 'N/A'
   ,@piOrgCheckTypeXrefId INT OUTPUT
)
AS
BEGIN
   SET NOCOUNT ON;
   DECLARE @OrgCheckTypeXref table (
       OrgCheckTypeXrefId int
      ,OrgId int
      ,CheckTypeId int
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
      INSERT INTO [organization].[OrgCheckTypeXref]
         OUTPUT inserted.OrgCheckTypeXrefId
            ,inserted.OrgId
            ,inserted.CheckTypeId
            ,inserted.StatusFlag
            ,inserted.DateActivated
            ,inserted.UserName
         INTO @OrgCheckTypeXref
      SELECT @piOrgId
         ,@piCheckTypeId
         ,@piStatusFlag
         ,SYSDATETIME()
			,@pnvUserName; 
   END TRY
   BEGIN CATCH
      IF @@TRANCOUNT > @iCurrentTransactionLevel
         ROLLBACK TRANSACTION;
      EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
      SET @piOrgCheckTypeXrefId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
   END CATCH;
   IF @@TRANCOUNT > @iCurrentTransactionLevel
   BEGIN
      COMMIT TRANSACTION;
      SELECT @piOrgCheckTypeXrefId = OrgCheckTypeXrefId
      FROM @OrgCheckTypeXref
   END
END
