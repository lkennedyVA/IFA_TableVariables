USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
   Name: uspOrgInsert2Out
   CreatedBy: Larry Dugger
   Date: 2015-05-07
   Descr: This procedure will insert a new record
   Tables: [organization].[Org]
   
   Functions: [error].[uspLogErrorDetailInsertOut]
   History:
      2015-05-07 - LBD - Created
*****************************************************************************************/
ALTER PROCEDURE [organization].[uspOrgInsert2Out](
    @pnvOrgTypeName NVARCHAR(50)
   ,@pnvCode NVARCHAR(10)
   ,@pnvName NVARCHAR(50)
   ,@pnvDescr NVARCHAR(255)
	,@pnvExternalCode NVARCHAR(50)
   ,@piStatusFlag INT 
	,@pnvUserName NVARCHAR(100) = 'N/A'
   ,@piOrgId INT OUTPUT
)
AS
BEGIN
   SET NOCOUNT ON;
   DECLARE @Org table (
       OrgId int
      ,OrgTypeId int
      ,Code nvarchar(25)
      ,Name nvarchar(50)
      ,Descr nvarchar(255)
      ,ExternalCode nvarchar(50)
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
      INSERT INTO [organization].[Org]
         OUTPUT inserted.OrgId
            ,inserted.OrgTypeId
            ,inserted.Code
            ,inserted.Name
            ,inserted.Descr
				,inserted.ExternalCode
            ,inserted.StatusFlag
            ,inserted.DateActivated
            ,inserted.UserName
         INTO @Org
      SELECT OrgTypeId
         ,@pnvCode
         ,@pnvName
         ,@pnvDescr
			,@pnvExternalCode
         ,@piStatusFlag
         ,SYSDATETIME()
			,@pnvUserName
      FROM [organization].[OrgType] 
      WHERE Name = @pnvOrgTypeName;
   END TRY
   BEGIN CATCH
      IF @@TRANCOUNT > @iCurrentTransactionLevel
         ROLLBACK TRANSACTION;
      EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
      SET @piOrgId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
   END CATCH;
   IF @@TRANCOUNT > @iCurrentTransactionLevel
   BEGIN
      COMMIT TRANSACTION;
      SELECT @piOrgId = OrgId
      FROM @Org
   END
END
