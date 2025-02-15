USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
   Name: [rule].[uspRuleInsertOut]
   Created By: Larry Dugger
   Date: 2012-03-20
   Descr: This procedure will insert a new record

   Tables: [rule].[Rule]
   
   Functions: [error].[uspLogErrorDetailInsertOut]

   History:
      2012-03-20 - LBD - Created
      2014-05-06 - LBD - Modified, will not insert if code already exists...
*****************************************************************************************/
ALTER PROCEDURE [rule].[uspRuleInsertOut](
    @pnvCode NVARCHAR(25)
   ,@pnvName NVARCHAR(50)
   ,@pnvDescr NVARCHAR(255)
   ,@pnvDescr2 NVARCHAR(255)
   ,@piATMResponseCodeId INT
   ,@piStatusFlag INT 
   ,@pnvUserName NVARCHAR(100) = 'N/A'
   ,@piRuleId INT OUTPUT
)
AS
BEGIN
   SET NOCOUNT ON;
   DECLARE @Rule table (
       RuleId int
      ,Code nvarchar(25)
      ,Name nvarchar(50)
      ,Descr nvarchar(255)
      ,Descr2 nvarchar(255)
      ,ATMResponseCodeId int
      ,StatusFlag int
      ,DateActivated datetime
	  ,UserName NVARCHAR(100));
   DECLARE @iErrorDetailId INT
      ,@iCurrentTransactionLevel INT
      ,@sSchemaName SYSNAME;
   SET @sSchemaName = N'rule';
   SET @iCurrentTransactionLevel = @@TRANCOUNT;

   SET @piRuleId = NULL;

   SELECT @piRuleId = RuleId
   FROM [rule].[Rule]
   WHERE Code = @pnvCode;
   
   IF ISNULL(@piRuleId,-1) = -1
   BEGIN
      BEGIN TRANSACTION
      BEGIN TRY
         INSERT INTO [rule].[Rule]
            OUTPUT Inserted.RuleId
               ,Inserted.Code
               ,Inserted.Name
               ,Inserted.Descr
               ,Inserted.Descr2
               ,Inserted.ATMResponseCodeId
               ,Inserted.StatusFlag
               ,Inserted.DateActivated
			   ,Inserted.Username
            INTO @Rule
         SELECT @pnvCode
            ,@pnvName
            ,@pnvDescr
            ,@pnvDescr2
            ,@piATMResponseCodeId
            ,@piStatusFlag
            ,SYSDATETIME()
			,@pnvUserName; 
      END TRY
      BEGIN CATCH
         IF @@TRANCOUNT > @iCurrentTransactionLevel
            ROLLBACK TRANSACTION;
         EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
         SET @piRuleId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
      END CATCH;
      IF @@TRANCOUNT > @iCurrentTransactionLevel
      BEGIN
         COMMIT TRANSACTION;
         SELECT @piRuleId = RuleId
         FROM @Rule
      END
   END
END
