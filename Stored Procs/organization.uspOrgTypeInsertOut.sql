USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
   Name: uspOrgTypeInsertOut
   CreatedBy: Larry Dugger
   Date: 2015-05-07
   Descr: This procedure will insert a new record
   Tables: [organization].[OrgType]
   
   Functions: [error].[uspLogErrorDetailInsertOut]
   History:
      2015-05-07 - LBD - Created
*****************************************************************************************/
ALTER PROCEDURE [organization].[uspOrgTypeInsertOut](
    @pnvCode NVARCHAR(10)
   ,@pnvName NVARCHAR(50)
   ,@pnvDescr NVARCHAR(255)
   ,@piStatusFlag INT 
	,@pnvUserName NVARCHAR(100) = 'N/A'
   ,@piOrgTypeId INT OUTPUT
)
AS
BEGIN
   SET NOCOUNT ON;
   DECLARE @OrgType table (
       OrgTypeId int
      ,Code nvarchar(25)
      ,Name nvarchar(50)
      ,Descr nvarchar(255)
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
      INSERT INTO [organization].[OrgType]
         OUTPUT inserted.OrgTypeId
            ,inserted.Code
            ,inserted.Name
            ,inserted.Descr
            ,inserted.StatusFlag
            ,inserted.DateActivated
            ,inserted.UserName
         INTO @OrgType
      SELECT @pnvCode
         ,@pnvName
         ,@pnvDescr
         ,@piStatusFlag
         ,SYSDATETIME()
			,@pnvUserName; 
   END TRY
   BEGIN CATCH
      IF @@TRANCOUNT > @iCurrentTransactionLevel
         ROLLBACK TRANSACTION;
      EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
      SET @piOrgTypeId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
   END CATCH;
   IF @@TRANCOUNT > @iCurrentTransactionLevel
   BEGIN
      COMMIT TRANSACTION;
      SELECT @piOrgTypeId = OrgTypeId
      FROM @OrgType
   END
END
