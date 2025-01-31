USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
   Name: uspRuleOrgXrefInsertOut
   CreatedBy: Larry Dugger
   Date: 2012-20-03
   Descr: This procedure will insert a new record
   Tables: [rule].[RuleOrgXref]
   
   Functions: [error].[uspLogErrorDetailInsertOut]
   History:
      2012-20-03 - LBD - Created
      06-10-2013 - LBD - Modified, so that if it exists, it will update flags
*****************************************************************************************/
ALTER PROCEDURE [rule].[uspRuleOrgXrefInsertOut](
    @piRuleGroupId INT
   ,@piRuleId INT
   ,@piOrgId INT
   ,@piStatusFlag INT 
   ,@pbOverridableFlag BIT 
	,@pnvUserName NVARCHAR(100) = 'N/A'
   ,@piRuleOrgXrefId INT OUTPUT
)
AS
BEGIN
   SET NOCOUNT ON;
   DECLARE @RuleOrgXref table (
       RuleOrgXrefId int
      ,RuleGroupId int
      ,RuleId int
      ,OrgId int
      ,StatusFlag int
      ,OverridableFlag bit
      ,DateActivated datetime2(7)
		,UserName nvarchar(100));
   DECLARE @iStatusFlag INT 
      ,@bOverridableFlag BIT 
      ,@iErrorDetailId INT
      ,@iCurrentTransactionLevel INT
      ,@sSchemaName SYSNAME;
   SET @sSchemaName =N'rule';
   SET @iCurrentTransactionLevel = @@TRANCOUNT;
   IF NOT EXISTS (SELECT 'X' 
                  FROM [rule].[RuleOrgXref]
                  WHERE RuleId = @piRuleId
                     AND OrgId = @piOrgId)
   BEGIN
      BEGIN TRANSACTION
      BEGIN TRY
         INSERT INTO [rule].[RuleOrgXref]
            OUTPUT inserted.RuleOrgXrefId
               ,inserted.RuleGroupId
               ,inserted.RuleId
               ,inserted.OrgId
               ,inserted.StatusFlag
               ,inserted.OverridableFlag
               ,inserted.DateActivated
					,inserted.UserName
            INTO @RuleOrgXref
         SELECT @piRuleGroupId
            ,@piRuleId
            ,@piOrgId
            ,@piStatusFlag
            ,@pbOverridableFlag
            ,SYSDATETIME()
				,@pnvUserName; 
      END TRY
      BEGIN CATCH
         IF @@TRANCOUNT > @iCurrentTransactionLevel
            ROLLBACK TRANSACTION;
         EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
         SET @piRuleOrgXrefId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
      END CATCH;
      IF @@TRANCOUNT > @iCurrentTransactionLevel
      BEGIN
         COMMIT TRANSACTION;
         SELECT @piRuleOrgXrefId = RuleOrgXrefId
         FROM @RuleOrgXref
      END
   END
   ELSE
   --SO it already Exists, just the a status Is messed-up
   BEGIN
      SELECT @piRuleOrgXrefId = RuleOrgXrefId
               ,@iStatusFlag = StatusFlag
               ,@bOverridableFlag = OverridableFlag
      FROM [rule].[RuleOrgXref]
      WHERE RuleId = @piRuleId
         AND OrgId = @piOrgId;
      IF @piStatusFlag <> @iStatusFlag
      BEGIN
         IF @piStatusFlag = 0
            EXECUTE [rule].[uspRuleOrgXrefStatusFlagClearOut] @pnvUserName=@pnvUserName, @piRuleOrgXrefID=@piRuleOrgXrefId OUTPUT;
         IF @piStatusFlag = 1
            EXECUTE [rule].[uspRuleOrgXrefStatusFlagSetOut] @pnvUserName=@pnvUserName, @piRuleOrgXrefID=@piRuleOrgXrefId OUTPUT;
         IF @piStatusFlag = 2
            EXECUTE [rule].[uspRuleOrgXrefStatusFlagExclusiveOut] @pnvUserName=@pnvUserName, @piRuleOrgXrefID=@piRuleOrgXrefId OUTPUT;
         IF @piStatusFlag = 3
            EXECUTE [rule].[uspRuleOrgXrefStatusFlagNeverActiveOut] @pnvUserName=@pnvUserName, @piRuleOrgXrefID=@piRuleOrgXrefId OUTPUT;
      END
      IF @pbOverridableFlag <> @bOverridableFlag
      BEGIN
         IF @pbOverridableFlag = 0
            EXECUTE [rule].[uspRuleOrgXrefOverridableFlagClearOut] @pnvUserName=@pnvUserName, @piRuleOrgXrefID=@piRuleOrgXrefId OUTPUT;
         IF @pbOverridableFlag = 1
            EXECUTE [rule].[uspRuleOrgXrefOverridableFlagSetOut] @pnvUserName=@pnvUserName, @piRuleOrgXrefID=@piRuleOrgXrefId OUTPUT;
      END   
   END
END
