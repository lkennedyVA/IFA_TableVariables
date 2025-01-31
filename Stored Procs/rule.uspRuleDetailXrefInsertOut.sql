USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
   Name: [rule].[uspRuleDetailXrefInsertOut]
   Created By: Larry Dugger
   Date: 2012-03-20
   Descr: This procedure will insert a new record

   Tables: [rule].[RuleDetailXref]
   
   Functions: [error].[uspLogErrorDetailInsertOut]

   History:
      2012-03-20 - LBD - Created
*****************************************************************************************/
ALTER PROCEDURE [rule].[uspRuleDetailXrefInsertOut](
	 @piRuleId INT
	,@piRuleDetailId INT
	,@piDetailLevelId INT
	,@piStatusFlag INT
	,@pnvUserName NVARCHAR(100) = 'N/A' 
	,@piRuleDetailXrefId INT OUTPUT
)
AS
BEGIN
   SET NOCOUNT ON;
   DECLARE @RuleDetailXref table (
       RuleDetailXrefId int
      ,RuleId int
      ,RuleDetailId int
      ,DetailLevelId int
      ,StatusFlag int
      ,DateActivated datetime
	  ,UserName nvarchar(100));
   DECLARE @iErrorDetailId INT
      ,@iCurrentTransactionLevel INT
      ,@sSchemaName SYSNAME;
   SET @sSchemaName =N'rule';
   SET @iCurrentTransactionLevel = @@TRANCOUNT;

   BEGIN TRANSACTION
   BEGIN TRY
      INSERT INTO [rule].[RuleDetailXref]
         OUTPUT Inserted.RuleDetailXrefId
            ,Inserted.RuleId
            ,Inserted.RuleDetailId
            ,Inserted.DetailLevelId
            ,Inserted.StatusFlag
            ,Inserted.DateActivated
			,Inserted.UserName
         INTO @RuleDetailXref
      SELECT @piRuleId
         ,@piRuleDetailId
         ,@piDetailLevelId
         ,@piStatusFlag
         ,SYSDATETIME()
		 ,@pnvUserName; 
   END TRY
   BEGIN CATCH
      IF @@TRANCOUNT > @iCurrentTransactionLevel
         ROLLBACK TRANSACTION;
      EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
      SET @piRuleDetailXrefId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
   END CATCH;
   IF @@TRANCOUNT > @iCurrentTransactionLevel
   BEGIN
      COMMIT TRANSACTION;
      SELECT @piRuleDetailXrefId = RuleDetailXrefId
      FROM @RuleDetailXref
   END
END
