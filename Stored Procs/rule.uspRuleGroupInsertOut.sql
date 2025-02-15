USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
   Name: uspRuleGroupInsertOut
   CreatedBy: Larry Dugger
   Date: 2012-03-20
   Descr: This procedure will insert a new record

   Tables: [rule].[RuleGroup]
   
   Functions: [error].[uspLogErrorDetailInsertOut]

   History:
      2012-03-20 - LBD - Created, migrated from Validbank
*****************************************************************************************/
ALTER PROCEDURE [rule].[uspRuleGroupInsertOut](
    @pnvCode NVARCHAR(10)
   ,@pnvName NVARCHAR(50)
   ,@pnvDescr NVARCHAR(255)
   ,@pbOverridableFlag BIT
   ,@piStatusFlag INT
   ,@pnvUserName NVARCHAR(100) = 'N/A'
   ,@piRuleGroupId INT OUTPUT
)
AS
BEGIN
   SET NOCOUNT ON;
   DECLARE @RuleGroup table (
       RuleGroupId int
      ,Code nvarchar(25)
      ,Name nvarchar(50)
      ,Descr nvarchar(255)
      ,OverridableFlag bit
      ,StatusFlag int
      ,DateActivated datetime
	  ,UserName nvarchar(100));
   DECLARE @iErrorDetailId INT
      ,@iCurrentTransactionLevel INT
      ,@sSchemaName SYSNAME;
   SET @sSchemaName = N'rule';
   SET @iCurrentTransactionLevel = @@TRANCOUNT;

   BEGIN TRANSACTION
   BEGIN TRY
      INSERT INTO [rule].[RuleGroup]
         OUTPUT Inserted.RuleGroupId
            ,Inserted.Code
            ,Inserted.Name
            ,Inserted.Descr
            ,Inserted.OverridableFlag
            ,Inserted.StatusFlag
            ,Inserted.DateActivated
			,Inserted.UserName
         INTO @RuleGroup
      SELECT @pnvCode
         ,@pnvName
         ,@pnvDescr
         ,@pbOverridableFlag
         ,@piStatusFlag
         ,SYSDATETIME()
		 ,@pnvUserName; 
   END TRY
   BEGIN CATCH
      IF @@TRANCOUNT > @iCurrentTransactionLevel
         ROLLBACK TRANSACTION;
      EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
      SET @piRuleGroupId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
   END CATCH;
   IF @@TRANCOUNT > @iCurrentTransactionLevel
   BEGIN
      COMMIT TRANSACTION;
      SELECT @piRuleGroupId = RuleGroupId
      FROM @RuleGroup
   END
END
